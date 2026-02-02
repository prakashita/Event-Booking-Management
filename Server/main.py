import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from database import init_db, close_db
from event_status import update_event_statuses
from routers import approvals, auth, calendar, events, invites, it, marketing, venues
from dotenv import load_dotenv

# Load environment variables from Server/.env explicitly
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Initialize MongoDB connection
    await init_db()
    await update_event_statuses()
    scheduler = AsyncIOScheduler()
    scheduler.add_job(update_event_statuses, "interval", minutes=5)
    scheduler.start()
    app.state.scheduler = scheduler
    yield
    scheduler.shutdown()
    # Shutdown: Close MongoDB connection
    await close_db()


app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "https://event-booking-management.netlify.app",
        "https://delicate-rolypoly-9e3ca2.netlify.app",
        "https://*.netlify.app",  # Allow all Netlify subdomains
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["*"],
)

app.include_router(auth.router)
app.include_router(calendar.router)
app.include_router(venues.router)
app.include_router(events.router)
app.include_router(approvals.router)
app.include_router(marketing.router)
app.include_router(it.router)
app.include_router(invites.router)

@app.get("/")
def home():
    return {"message": "Backend running"}
