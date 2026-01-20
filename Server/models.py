from beanie import Document, Indexed
from pydantic import Field
from datetime import datetime, date, time
from typing import Optional

class User(Document):
    name: str
    email: str = Field(unique=True)
    google_id: str = Field(unique=True)
    role: str = Field(default="faculty")
    created_at: datetime = Field(default_factory=datetime.utcnow)
    google_refresh_token: Optional[str] = None
    google_access_token: Optional[str] = None
    google_token_expiry: Optional[datetime] = None
    
    class Settings:
        name = "users"  # Collection name in MongoDB
        indexes = [
            "email",
            "google_id"
        ]


class Venue(Document):
    name: Indexed(str, unique=True)

    class Settings:
        name = "venues"
        indexes = [
            "name"
        ]


class Event(Document):
    name: str
    facilitator: str
    description: Optional[str] = None
    venue_name: str
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    created_by: str
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "events"
