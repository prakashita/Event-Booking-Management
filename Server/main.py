import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from database import init_db, close_db
from routers import approvals, auth, calendar, events, it, marketing, venues
from dotenv import load_dotenv

# Load environment variables
load_dotenv()


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: Initialize MongoDB connection
    await init_db()
    yield
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
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
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

@app.get("/")
def home():
    return {"message": "Backend running"}
