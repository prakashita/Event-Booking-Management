from datetime import date, time, datetime
from typing import Optional

from pydantic import BaseModel, Field


class UserAdminResponse(BaseModel):
    id: str
    name: str
    email: str
    role: str
    created_at: datetime
    last_seen: Optional[datetime] = None


class UserRoleUpdate(BaseModel):
    role: str


class VenueCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)


class VenueResponse(BaseModel):
    id: str
    name: str


class EventCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=160)
    facilitator: str = Field(..., min_length=1, max_length=120)
    description: Optional[str] = Field(default=None, max_length=2000)
    venue_name: str = Field(..., min_length=1, max_length=120)
    start_date: date
    start_time: time
    end_date: date
    end_time: time
    override_conflict: bool = False
    submit_for_approval: bool = False
    approval_to: Optional[str] = Field(default=None, max_length=200)
    requirements: list[str] = Field(default_factory=list)
    other_notes: Optional[str] = Field(default=None, max_length=2000)


class EventResponse(BaseModel):
    id: str
    name: str
    facilitator: str
    description: Optional[str] = None
    venue_name: str
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    created_by: str
    status: str
    google_event_id: Optional[str] = None
    google_event_link: Optional[str] = None
    report_file_id: Optional[str] = None
    report_file_name: Optional[str] = None
    report_web_view_link: Optional[str] = None
    report_uploaded_at: Optional[datetime] = None
    created_at: datetime


class ApprovalRequestResponse(BaseModel):
    id: str
    status: str
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
    requirements: list[str]
    other_notes: Optional[str] = None
    event_id: Optional[str] = None
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime


class ApprovalDecision(BaseModel):
    status: str


class MarketingRequestCreate(BaseModel):
    requested_to: Optional[str] = Field(default=None, max_length=200)
    event_id: Optional[str] = None
    event_name: str = Field(..., min_length=1, max_length=160)
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    poster_required: bool = False
    poster_dimension: Optional[str] = Field(default=None, max_length=120)
    video_required: bool = False
    video_dimension: Optional[str] = Field(default=None, max_length=120)
    linkedin_post: bool = False
    photography: bool = False
    recording: bool = False
    other_notes: Optional[str] = Field(default=None, max_length=2000)


class MarketingRequestResponse(BaseModel):
    id: str
    requester_id: str
    requester_email: str
    requested_to: Optional[str] = None
    event_id: Optional[str] = None
    event_name: str
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    poster_required: bool
    poster_dimension: Optional[str] = None
    video_required: bool
    video_dimension: Optional[str] = None
    linkedin_post: bool
    photography: bool
    recording: bool
    other_notes: Optional[str] = None
    status: str
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime


class MarketingDecision(BaseModel):
    status: str


class ItRequestCreate(BaseModel):
    requested_to: Optional[str] = Field(default=None, max_length=200)
    event_id: Optional[str] = None
    event_name: str = Field(..., min_length=1, max_length=160)
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    pa_system: bool = False
    projection: bool = False
    other_notes: Optional[str] = Field(default=None, max_length=2000)


class ItRequestResponse(BaseModel):
    id: str
    requester_id: str
    requester_email: str
    requested_to: Optional[str] = None
    event_id: Optional[str] = None
    event_name: str
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    pa_system: bool
    projection: bool
    other_notes: Optional[str] = None
    status: str
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime


class ItDecision(BaseModel):
    status: str


class EventCreateResponse(BaseModel):
    status: str
    event: Optional[EventResponse] = None
    approval_request: Optional[ApprovalRequestResponse] = None


class EventStatusUpdate(BaseModel):
    status: str


class InviteCreate(BaseModel):
    event_id: str
    to_email: str
    subject: str
    body: str


class InviteResponse(BaseModel):
    id: str
    event_id: str
    created_by: str
    to_email: str
    subject: str
    body: str
    status: str
    sent_at: datetime
    created_at: datetime


class ChatAttachment(BaseModel):
    name: str
    url: str
    content_type: str
    size: int


class ChatMessageCreate(BaseModel):
    conversation_id: str
    content: Optional[str] = Field(default=None, max_length=4000)
    attachments: list[ChatAttachment] = Field(default_factory=list)


class ChatMessageResponse(BaseModel):
    id: str
    conversation_id: str
    sender_id: str
    sender_name: str
    sender_email: str
    content: Optional[str] = None
    attachments: list[ChatAttachment]
    read_by: list[str]
    created_at: datetime


class ChatReadReceipt(BaseModel):
    message_ids: list[str] = Field(default_factory=list)


class ChatUserResponse(BaseModel):
    id: str
    name: str
    email: str
    role: str
    online: bool
    last_seen: Optional[datetime] = None


class ChatConversationCreate(BaseModel):
    user_id: str


class ChatConversationResponse(BaseModel):
    id: str
    participants: list[str]
    updated_at: datetime


class ChatUploadResponse(BaseModel):
    attachment: ChatAttachment


class PublicationResponse(BaseModel):
    id: str
    name: str
    title: str
    others: Optional[str] = None
    file_id: str
    file_name: str
    web_view_link: Optional[str] = None
    uploaded_at: datetime
    created_at: datetime
