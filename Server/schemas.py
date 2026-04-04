from datetime import date, time, datetime
from typing import Generic, List, Literal, Optional, TypeVar

from pydantic import BaseModel, Field, field_validator, model_validator

T = TypeVar("T")


class PaginatedResponse(BaseModel, Generic[T]):
    """Standard paginated list response."""
    items: List[T]
    total: int
    limit: int
    offset: int
    next_offset: Optional[int] = None  # None if no more items


class UserAdminResponse(BaseModel):
    id: str
    name: str
    email: str
    role: str
    created_at: datetime
    last_seen: Optional[datetime] = None


class UserRoleUpdate(BaseModel):
    role: str


class AddUserRequest(BaseModel):
    email: str = Field(..., min_length=1)
    role: str = Field(..., min_length=1)


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
    intendedAudience: Optional[Literal["Students", "Faculty", "PhD Scholars", "Staffs", "Everyone at VU"]] = None
    budget: Optional[float] = Field(default=None, ge=0)  # Event budget in Rs

    @field_validator("budget", mode="before")
    @classmethod
    def coerce_budget(cls, v):
        if v is None or v == "":
            return None
        if isinstance(v, str):
            try:
                return float(v) if v.strip() else None
            except ValueError:
                return None
        return v

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
    intendedAudience: Optional[str] = None
    budget: Optional[float] = None
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    created_by: str
    status: str
    google_event_id: Optional[str] = None
    google_event_link: Optional[str] = None
    budget_breakdown_file_id: Optional[str] = None
    budget_breakdown_file_name: Optional[str] = None
    budget_breakdown_web_view_link: Optional[str] = None
    budget_breakdown_uploaded_at: Optional[datetime] = None
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
    budget: Optional[float] = None
    budget_breakdown_file_id: Optional[str] = None
    budget_breakdown_file_name: Optional[str] = None
    budget_breakdown_web_view_link: Optional[str] = None
    budget_breakdown_uploaded_at: Optional[datetime] = None
    description: Optional[str] = None
    venue_name: str
    intendedAudience: Optional[str] = None
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
    comment: Optional[str] = Field(default=None, max_length=4000)


class FacilityManagerRequestCreate(BaseModel):
    requested_to: Optional[str] = Field(default=None, max_length=200)
    event_id: Optional[str] = None
    event_name: str = Field(..., min_length=1, max_length=160)
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    venue_required: bool = False
    refreshments: bool = False
    other_notes: Optional[str] = Field(default=None, max_length=2000)


class FacilityManagerRequestResponse(BaseModel):
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
    venue_required: bool
    refreshments: bool
    other_notes: Optional[str] = None
    status: str
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime


class FacilityManagerDecision(BaseModel):
    status: str
    comment: Optional[str] = Field(default=None, max_length=4000)


class MarketingRequirementsPreEvent(BaseModel):
    poster: bool = False
    social_media: bool = False


class MarketingRequirementsDuringEvent(BaseModel):
    photo: bool = False
    video: bool = False


class MarketingRequirementsPostEvent(BaseModel):
    social_media: bool = False
    photo_upload: bool = False
    video: bool = False


class MarketingRequirements(BaseModel):
    pre_event: MarketingRequirementsPreEvent = Field(default_factory=MarketingRequirementsPreEvent)
    during_event: MarketingRequirementsDuringEvent = Field(default_factory=MarketingRequirementsDuringEvent)
    post_event: MarketingRequirementsPostEvent = Field(default_factory=MarketingRequirementsPostEvent)


class MarketingRequestCreate(BaseModel):
    requested_to: Optional[str] = Field(default=None, max_length=200)
    event_id: Optional[str] = None
    event_name: str = Field(..., min_length=1, max_length=160)
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    marketing_requirements: Optional[MarketingRequirements] = None
    poster_required: bool = False
    poster_dimension: Optional[str] = Field(default=None, max_length=120)
    video_required: bool = False
    video_dimension: Optional[str] = Field(default=None, max_length=120)
    linkedin_post: bool = False
    photography: bool = False
    recording: bool = False
    other_notes: Optional[str] = Field(default=None, max_length=2000)


class MarketingDeliverableResponse(BaseModel):
    deliverable_type: str
    file_id: str
    file_name: str
    web_view_link: Optional[str] = None
    uploaded_at: datetime
    is_na: bool = False


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
    marketing_requirements: MarketingRequirements = Field(default_factory=MarketingRequirements)
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
    deliverables: List[MarketingDeliverableResponse] = Field(default_factory=list)
    created_at: datetime


class MarketingDecision(BaseModel):
    status: str
    comment: Optional[str] = Field(default=None, max_length=4000)


class ItRequestCreate(BaseModel):
    requested_to: Optional[str] = Field(default=None, max_length=200)
    event_id: Optional[str] = None
    event_name: str = Field(..., min_length=1, max_length=160)
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    event_mode: Optional[Literal["online", "offline"]] = None
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
    event_mode: Optional[str] = None
    pa_system: bool
    projection: bool
    other_notes: Optional[str] = None
    status: str
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime


class ItDecision(BaseModel):
    status: str
    comment: Optional[str] = Field(default=None, max_length=4000)


TransportTypeLiteral = Literal["guest_cab", "students_off_campus", "both"]


class TransportRequestCreate(BaseModel):
    requested_to: Optional[str] = Field(default=None, max_length=200)
    event_id: Optional[str] = None
    event_name: str = Field(..., min_length=1, max_length=160)
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    transport_type: TransportTypeLiteral
    guest_pickup_location: Optional[str] = Field(default=None, max_length=500)
    guest_pickup_date: Optional[str] = Field(default=None, max_length=32)
    guest_pickup_time: Optional[str] = Field(default=None, max_length=32)
    guest_dropoff_location: Optional[str] = Field(default=None, max_length=500)
    guest_dropoff_date: Optional[str] = Field(default=None, max_length=32)
    guest_dropoff_time: Optional[str] = Field(default=None, max_length=32)
    student_count: Optional[int] = Field(default=None, ge=1)
    student_transport_kind: Optional[str] = Field(default=None, max_length=200)
    student_date: Optional[str] = Field(default=None, max_length=32)
    student_time: Optional[str] = Field(default=None, max_length=32)
    student_pickup_point: Optional[str] = Field(default=None, max_length=500)
    other_notes: Optional[str] = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def validate_by_transport_type(self):
        def nz(s: Optional[str]) -> str:
            return (s or "").strip()

        def require_guest_cab_fields() -> None:
            missing = []
            if not nz(self.guest_pickup_location):
                missing.append("guest_pickup_location")
            if not nz(self.guest_pickup_date):
                missing.append("guest_pickup_date")
            if not nz(self.guest_pickup_time):
                missing.append("guest_pickup_time")
            if not nz(self.guest_dropoff_location):
                missing.append("guest_dropoff_location")
            if not nz(self.guest_dropoff_time):
                missing.append("guest_dropoff_time")
            if missing:
                raise ValueError(
                    "Guest cab requires pickup location, pickup date, pickup time, drop-off location, and drop-off time"
                )

        def require_student_fields() -> None:
            if self.student_count is None or self.student_count < 1:
                raise ValueError("Student transport requires number of students (at least 1)")
            if not nz(self.student_transport_kind):
                raise ValueError("Student transport requires kind of transport")
            if not nz(self.student_date):
                raise ValueError("Student transport requires date")
            if not nz(self.student_time):
                raise ValueError("Student transport requires time")
            if not nz(self.student_pickup_point):
                raise ValueError("Student transport requires pickup point")

        if self.transport_type == "guest_cab":
            require_guest_cab_fields()
        elif self.transport_type == "students_off_campus":
            require_student_fields()
        else:
            require_guest_cab_fields()
            require_student_fields()
        return self


class TransportRequestResponse(BaseModel):
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
    transport_type: str
    guest_pickup_location: Optional[str] = None
    guest_pickup_date: Optional[str] = None
    guest_pickup_time: Optional[str] = None
    guest_dropoff_location: Optional[str] = None
    guest_dropoff_date: Optional[str] = None
    guest_dropoff_time: Optional[str] = None
    student_count: Optional[int] = None
    student_transport_kind: Optional[str] = None
    student_date: Optional[str] = None
    student_time: Optional[str] = None
    student_pickup_point: Optional[str] = None
    other_notes: Optional[str] = None
    status: str
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime


class TransportDecision(BaseModel):
    status: str
    comment: Optional[str] = Field(default=None, max_length=4000)


class WorkflowActionLogEntry(BaseModel):
    id: str
    event_id: Optional[str] = None
    approval_request_id: Optional[str] = None
    related_kind: str
    related_id: str
    role: str
    action_type: str
    comment: str
    action_by: str
    action_by_user_id: str
    created_at: datetime


class EventCreateResponse(BaseModel):
    status: str
    event: Optional[EventResponse] = None
    approval_request: Optional[ApprovalRequestResponse] = None


class EventDetailsResponse(BaseModel):
    """Full event details for the details modal: event + approval, facility, transport, marketing (with deliverables), IT."""
    event: EventResponse
    approval_request: Optional[ApprovalRequestResponse] = None
    facility_requests: List[FacilityManagerRequestResponse] = Field(default_factory=list)
    marketing_requests: List[MarketingRequestResponse] = Field(default_factory=list)
    it_requests: List[ItRequestResponse] = Field(default_factory=list)
    transport_requests: List[TransportRequestResponse] = Field(default_factory=list)
    workflow_action_logs: List[WorkflowActionLogEntry] = Field(default_factory=list)


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


class ChatMessageEdit(BaseModel):
    content: str = Field(..., min_length=1, max_length=4000)


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
    conversation_thread_kind: Optional[str] = None
    is_deleted: bool = False
    deleted_for_everyone: bool = False
    edited: bool = False
    edited_at: Optional[datetime] = None


class ChatReadReceipt(BaseModel):
    message_ids: list[str] = Field(default_factory=list)


class ChatUserResponse(BaseModel):
    id: str
    name: str
    email: str
    role: str
    online: bool
    last_seen: Optional[datetime] = None


class ChatParticipantSummary(BaseModel):
    id: str
    name: str


class ChatConversationCreate(BaseModel):
    user_id: str


class ChatConversationResponse(BaseModel):
    id: str
    participants: list[str]
    updated_at: datetime
    thread_kind: str = "direct"
    event_id: Optional[str] = None
    title: Optional[str] = None


class ChatConversationListItem(BaseModel):
    """Row for GET /chat/conversations/me — direct threads and event group chats."""

    id: str
    thread_kind: str
    participants: list[str]
    updated_at: datetime
    title: Optional[str] = None
    event_id: Optional[str] = None
    other_user: Optional[ChatUserResponse] = None
    unread_count: int = 0
    last_message: Optional[dict] = None  # {text, sender_id, sender_name, created_at, message_id?}
    participant_count: int = 0
    participants_preview: list[ChatParticipantSummary] = Field(default_factory=list)


class ChatSendMessage(BaseModel):
    """Unified send-message payload: provide conversation_id OR recipient_id."""
    conversation_id: Optional[str] = None
    recipient_id: Optional[str] = None
    content: Optional[str] = Field(default=None, max_length=4000)
    attachments: list[ChatAttachment] = Field(default_factory=list)


class ChatUploadResponse(BaseModel):
    attachment: ChatAttachment


class PublicationResponse(BaseModel):
    id: str
    name: str
    title: str
    pub_type: Optional[str] = None
    others: Optional[str] = None
    file_id: Optional[str] = None
    file_name: Optional[str] = None
    web_view_link: Optional[str] = None
    uploaded_at: Optional[datetime] = None
    created_at: datetime
    # Shared
    author: Optional[str] = None
    author_first_name: Optional[str] = None
    author_last_name: Optional[str] = None
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
