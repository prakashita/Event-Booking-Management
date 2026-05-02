import os
import logging
import time
import uuid
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from slowapi.errors import RateLimitExceeded

from errors import STATUS_TO_CODE, error_payload
from rate_limit import limiter
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from database import init_db, close_db
from event_status import update_event_statuses
from routers import admin, approvals, auth, calendar, chat, events, facility, institution_calendar, invites, iqac, it, marketing, publications, student_achievements, transport, users, venues
from routers.calendar import oauth_callback as google_calendar_oauth_callback
from dotenv import load_dotenv
from settings import load_settings

# Load environment variables from Server/.env explicitly
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))
settings = load_settings()

logging.basicConfig(
    level=getattr(logging, settings.log_level, logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("event-booking.api")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Initialize MongoDB connection
    logger.info("Starting API in %s environment", settings.app_env)
    await init_db()
    scheduler = None
    if os.getenv("VERCEL") == "1":
        logger.info("Skipping startup status sweep and scheduler on Vercel")
    else:
        await update_event_statuses()
        scheduler = AsyncIOScheduler()
        scheduler.add_job(update_event_statuses, "interval", minutes=5)
        scheduler.start()
        app.state.scheduler = scheduler
    yield
    if scheduler:
        scheduler.shutdown(wait=False)
    # Shutdown: Close MongoDB connection
    await close_db()
    logger.info("API shutdown complete")


app = FastAPI(title="Event Booking Management API", version="1.0.0", lifespan=lifespan)
app.state.limiter = limiter

def handle_rate_limit_exceeded(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=429,
        content=error_payload(
            detail=getattr(exc, "detail", "Rate limit exceeded"),
            code="RATE_LIMIT_EXCEEDED",
            request_id=_request_id(request),
        ),
    )


app.add_exception_handler(RateLimitExceeded, handle_rate_limit_exceeded)

def resolve_uploads_dir() -> str:
    env_dir = os.getenv("UPLOADS_DIR")
    if env_dir:
        return os.path.abspath(env_dir)
    if os.getenv("VERCEL") == "1":
        return "/tmp/uploads"
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "uploads"))


uploads_dir = resolve_uploads_dir()
try:
    os.makedirs(uploads_dir, exist_ok=True)
except OSError:
    uploads_dir = "/tmp/uploads"
    os.makedirs(uploads_dir, exist_ok=True)

try:
    app.mount("/uploads", StaticFiles(directory=uploads_dir), name="uploads")
except OSError:
    # On read-only filesystems, skip mounting uploads.
    pass

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_origin_regex=settings.cors_origin_regex,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["*"],
)


def _request_id(request: Request) -> str:
    return getattr(request.state, "request_id", "")


@app.middleware("http")
async def security_headers_middleware(request: Request, call_next):
    response = await call_next(request)
    # Content-Security-Policy: restrict script sources to mitigate XSS
    csp = "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://accounts.google.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: https: blob:; font-src 'self' data:; connect-src 'self' https://accounts.google.com https://oauth2.googleapis.com https://www.googleapis.com; frame-src https://accounts.google.com"
    response.headers["Content-Security-Policy"] = csp
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@app.middleware("http")
async def request_context_middleware(request: Request, call_next):
    request_id = request.headers.get(settings.request_id_header) or uuid.uuid4().hex
    request.state.request_id = request_id
    started = time.perf_counter()

    try:
        response = await call_next(request)
    except Exception as exc:
        if isinstance(exc, BaseExceptionGroup):
            for idx, sub_exc in enumerate(exc.exceptions, start=1):
                logger.error(
                    "Unhandled request sub-exception rid=%s method=%s path=%s index=%s type=%s message=%s",
                    request_id,
                    request.method,
                    request.url.path,
                    idx,
                    type(sub_exc).__name__,
                    sub_exc,
                    exc_info=(type(sub_exc), sub_exc, sub_exc.__traceback__),
                )
        logger.exception(
            "Unhandled request error rid=%s method=%s path=%s",
            request_id,
            request.method,
            request.url.path,
        )
        raise

    elapsed_ms = (time.perf_counter() - started) * 1000
    response.headers[settings.request_id_header] = request_id
    logger.info(
        "Request rid=%s method=%s path=%s status=%s duration_ms=%.2f",
        request_id,
        request.method,
        request.url.path,
        response.status_code,
        elapsed_ms,
    )
    return response


@app.exception_handler(HTTPException)
async def handle_http_exception(request: Request, exc: HTTPException):
    code = STATUS_TO_CODE.get(exc.status_code, "ERROR")
    return JSONResponse(
        status_code=exc.status_code,
        content=error_payload(
            detail=exc.detail,
            code=code,
            request_id=_request_id(request),
        ),
    )


@app.exception_handler(RequestValidationError)
async def handle_validation_exception(request: Request, exc: RequestValidationError):
    body = None
    try:
        body = await request.body()
        if isinstance(body, (bytes, bytearray)):
            body = body.decode(errors="replace")
    except Exception:
        body = "<unavailable>"
    logger.error(
        "Request validation failed rid=%s path=%s body=%s errors=%s",
        _request_id(request),
        request.url.path,
        body,
        exc.errors(),
    )
    return JSONResponse(
        status_code=422,
        content=error_payload(
            detail="Validation error",
            code="VALIDATION_ERROR",
            request_id=_request_id(request),
            errors=exc.errors(),
        ),
    )


@app.exception_handler(Exception)
async def handle_unexpected_exception(request: Request, exc: Exception):
    logger.exception("Unhandled exception rid=%s", _request_id(request))
    return JSONResponse(
        status_code=500,
        content=error_payload(
            detail="Internal server error",
            code="INTERNAL_ERROR",
            request_id=_request_id(request),
        ),
    )

# API v1 prefix for versioned, stable endpoints
API_PREFIX = "/api/v1"
app.include_router(auth.router, prefix=API_PREFIX)
app.include_router(users.router, prefix=API_PREFIX)
app.include_router(admin.router, prefix=API_PREFIX)
app.include_router(calendar.router, prefix=API_PREFIX)
app.include_router(institution_calendar.router, prefix=API_PREFIX)
app.include_router(venues.router, prefix=API_PREFIX)
app.include_router(events.router, prefix=API_PREFIX)
app.include_router(approvals.router, prefix=API_PREFIX)
app.include_router(facility.router, prefix=API_PREFIX)
app.include_router(marketing.router, prefix=API_PREFIX)
app.include_router(it.router, prefix=API_PREFIX)
app.include_router(transport.router, prefix=API_PREFIX)
app.include_router(invites.router, prefix=API_PREFIX)
app.include_router(chat.router, prefix=API_PREFIX)
app.include_router(publications.router, prefix=API_PREFIX)
app.include_router(student_achievements.router, prefix=API_PREFIX)
app.include_router(iqac.router, prefix=API_PREFIX)


@app.get("/calendar/oauth/callback")
async def google_oauth_callback_legacy(code: str, state: str):
    """
    Google OAuth redirect without the /api/v1 prefix.

    GOOGLE_REDIRECT_URI and Google Cloud "Authorized redirect URIs" often use
    https://<host>/calendar/oauth/callback while versioned APIs live under /api/v1.
    """
    return await google_calendar_oauth_callback(code, state)


@app.get("/")
def home():
    return {"message": "Backend running"}


@app.get("/health")
def health():
    return {"status": "ok"}
