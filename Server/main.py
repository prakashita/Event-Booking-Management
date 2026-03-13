import os
import logging
import time
import uuid
from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from database import init_db, close_db
from event_status import update_event_statuses
from routers import admin, approvals, auth, calendar, chat, events, facility, invites, it, marketing, publications, users, venues
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
    await update_event_statuses()
    scheduler = AsyncIOScheduler()
    scheduler.add_job(update_event_statuses, "interval", minutes=5)
    scheduler.start()
    app.state.scheduler = scheduler
    yield
    scheduler.shutdown(wait=False)
    # Shutdown: Close MongoDB connection
    await close_db()
    logger.info("API shutdown complete")


app = FastAPI(title="Event Booking Management API", version="1.0.0", lifespan=lifespan)

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
async def request_context_middleware(request: Request, call_next):
    request_id = request.headers.get(settings.request_id_header) or uuid.uuid4().hex
    request.state.request_id = request_id
    started = time.perf_counter()

    try:
        response = await call_next(request)
    except Exception:
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
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "detail": exc.detail,
            "request_id": _request_id(request),
        },
    )


@app.exception_handler(RequestValidationError)
async def handle_validation_exception(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content={
            "detail": "Validation error",
            "errors": exc.errors(),
            "request_id": _request_id(request),
        },
    )


@app.exception_handler(Exception)
async def handle_unexpected_exception(request: Request, exc: Exception):
    logger.exception("Unhandled exception rid=%s", _request_id(request))
    return JSONResponse(
        status_code=500,
        content={
            "detail": "Internal server error",
            "request_id": _request_id(request),
        },
    )

# API v1 prefix for versioned, stable endpoints
API_PREFIX = "/api/v1"
app.include_router(auth.router, prefix=API_PREFIX)
app.include_router(users.router, prefix=API_PREFIX)
app.include_router(admin.router, prefix=API_PREFIX)
app.include_router(calendar.router, prefix=API_PREFIX)
app.include_router(venues.router, prefix=API_PREFIX)
app.include_router(events.router, prefix=API_PREFIX)
app.include_router(approvals.router, prefix=API_PREFIX)
app.include_router(facility.router, prefix=API_PREFIX)
app.include_router(marketing.router, prefix=API_PREFIX)
app.include_router(it.router, prefix=API_PREFIX)
app.include_router(invites.router, prefix=API_PREFIX)
app.include_router(chat.router, prefix=API_PREFIX)
app.include_router(publications.router, prefix=API_PREFIX)

@app.get("/")
def home():
    return {"message": "Backend running"}


@app.get("/health")
def health():
    return {"status": "ok"}
