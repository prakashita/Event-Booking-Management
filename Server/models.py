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


class ApprovalRequest(Document):
    requester_id: str
    requester_email: str
    requested_to: Optional[str] = None
    event_name: str
    facilitator: str
    description: Optional[str] = None
    venue_name: str
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    requirements: list[str] = Field(default_factory=list)
    other_notes: Optional[str] = None
    status: str = Field(default="pending")
    event_id: Optional[str] = None
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "approval_requests"


class MarketingRequest(Document):
    requester_id: str
    requester_email: str
    requested_to: Optional[str] = None
    event_name: str
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    poster_required: bool = False
    poster_dimension: Optional[str] = None
    video_required: bool = False
    video_dimension: Optional[str] = None
    linkedin_post: bool = False
    photography: bool = False
    recording: bool = False
    other_notes: Optional[str] = None
    status: str = Field(default="pending")
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "marketing_requests"


class ItRequest(Document):
    requester_id: str
    requester_email: str
    requested_to: Optional[str] = None
    event_name: str
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    pa_system: bool = False
    projection: bool = False
    other_notes: Optional[str] = None
    status: str = Field(default="pending")
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "it_requests"
