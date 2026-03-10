from beanie import Document, Indexed
from pydantic import Field
from datetime import datetime, date, time
from typing import Optional, List
from pydantic import BaseModel

class User(Document):
    name: str
    email: str = Field(unique=True)
    google_id: str = Field(unique=True)
    role: str = Field(default="faculty")
    created_at: datetime = Field(default_factory=datetime.utcnow)
    last_seen: Optional[datetime] = None
    google_refresh_token: Optional[str] = None
    google_access_token: Optional[str] = None
    google_token_expiry: Optional[datetime] = None
    
    class Settings:
        name = "users"  # Collection name in MongoDB
        indexes = [
            "email",
            "google_id"
        ]


class PendingRoleAssignment(Document):
    """Pre-assigned role for an email before first login. Applied when user signs in with Google."""
    email: str = Field(unique=True)
    role: str  # registrar, facility_manager, marketing, it
    created_at: datetime = Field(default_factory=datetime.utcnow)
    created_by: Optional[str] = None  # admin user id who added

    class Settings:
        name = "pending_role_assignments"
        indexes = ["email"]


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
    status: str = Field(default="upcoming")
    google_event_id: Optional[str] = None
    google_event_link: Optional[str] = None
    report_file_id: Optional[str] = None
    report_file_name: Optional[str] = None
    report_web_view_link: Optional[str] = None
    report_uploaded_at: Optional[datetime] = None
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


class MarketingDeliverable(BaseModel):
    """A file uploaded by marketing for a request (poster, photo, video, etc.), or marked NA."""
    deliverable_type: str  # poster, photography, video, recording, linkedin, other
    file_id: str  # "na" when is_na=True
    file_name: str  # "N/A" when is_na=True
    web_view_link: Optional[str] = None
    uploaded_at: datetime = Field(default_factory=datetime.utcnow)
    is_na: bool = False


class MarketingRequest(Document):
    requester_id: str
    requester_email: str
    requested_to: Optional[str] = None
    event_id: Optional[str] = None
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
    deliverables: List[MarketingDeliverable] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "marketing_requests"


class FacilityManagerRequest(Document):
    requester_id: str
    requester_email: str
    requested_to: Optional[str] = None
    event_id: Optional[str] = None
    event_name: str
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    venue_required: bool = False
    refreshments: bool = False
    other_notes: Optional[str] = None
    status: str = Field(default="pending")
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "facility_manager_requests"


class ItRequest(Document):
    requester_id: str
    requester_email: str
    requested_to: Optional[str] = None
    event_id: Optional[str] = None
    event_name: str
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    event_mode: Optional[str] = None  # "online" | "offline"
    pa_system: bool = False
    projection: bool = False
    other_notes: Optional[str] = None
    status: str = Field(default="pending")
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "it_requests"


class Invite(Document):
    event_id: str
    created_by: str
    to_email: str
    subject: str
    body: str
    status: str = Field(default="sent")
    sent_at: datetime = Field(default_factory=datetime.utcnow)
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "invites"


class Publication(Document):
    name: str
    title: str
    pub_type: Optional[str] = None  # webpage, journal_article, book, report, video, online_newspaper
    others: Optional[str] = None
    file_id: Optional[str] = None
    file_name: Optional[str] = None
    web_view_link: Optional[str] = None
    uploaded_at: Optional[datetime] = None
    created_by: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    # Shared / common fields
    author: Optional[str] = None
    publication_date: Optional[str] = None
    url: Optional[str] = None
    # Journal Article
    article_title: Optional[str] = None
    journal_name: Optional[str] = None
    volume: Optional[str] = None
    issue: Optional[str] = None
    pages: Optional[str] = None
    doi: Optional[str] = None
    year: Optional[str] = None
    # Book
    book_title: Optional[str] = None
    publisher: Optional[str] = None
    edition: Optional[str] = None
    page_number: Optional[str] = None
    # Report
    organization: Optional[str] = None
    report_title: Optional[str] = None
    # Video
    creator: Optional[str] = None
    video_title: Optional[str] = None
    platform: Optional[str] = None
    # Online Newspaper / Webpage
    newspaper_name: Optional[str] = None
    website_name: Optional[str] = None
    page_title: Optional[str] = None

    class Settings:
        name = "publications"


class ChatAttachment(BaseModel):
    name: str
    url: str
    content_type: str
    size: int


class ChatConversation(Document):
    participants: List[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "chat_conversations"


class ChatMessage(Document):
    conversation_id: str
    sender_id: str
    sender_name: str
    sender_email: str
    content: Optional[str] = None
    attachments: List[ChatAttachment] = Field(default_factory=list)
    read_by: List[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "chat_messages"
