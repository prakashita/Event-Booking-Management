from __future__ import annotations

from datetime import date as DateType, time, datetime
from typing import Any, Dict, Generic, List, Literal, Optional, TypeVar, Union

from pydantic import BaseModel, Field, field_validator, model_validator

T = TypeVar("T")


class PaginatedResponse(BaseModel, Generic[T]):
    """Standard paginated list response."""
    items: List[T]
    total: int
    limit: int
    offset: int
    next_offset: Optional[int] = None  # None if no more items


InstitutionCalendarEntryType = Literal["holiday", "academic"]
InstitutionCalendarSemesterType = Literal["Even Semester", "Odd Semester", "Summer Term"]


class InstitutionCalendarEntryCreate(BaseModel):
    entry_type: InstitutionCalendarEntryType
    academic_year: str = Field(..., min_length=1, max_length=40)
    calendar_year: Optional[int] = Field(default=None, ge=1900, le=3000)
    date: Optional[DateType] = None
    holiday_name: Optional[str] = Field(default=None, max_length=200)
    title: Optional[str] = Field(default=None, max_length=200)
    semester_type: Optional[InstitutionCalendarSemesterType] = None
    semester: Optional[str] = Field(default=None, max_length=60)
    category: Optional[str] = Field(default=None, max_length=80)
    start_date: Optional[DateType] = None
    end_date: Optional[DateType] = None
    all_day: bool = True
    description: Optional[str] = Field(default=None, max_length=2000)
    color: Optional[str] = Field(default=None, max_length=20)
    visible_to_all: bool = True
    google_sync_enabled: bool = False
    is_active: bool = True

    @field_validator("academic_year", "semester", "holiday_name", "title", "category", "description", "color", mode="before")
    @classmethod
    def strip_text(cls, value):
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value

    @model_validator(mode="after")
    def validate_payload(self):
        if self.entry_type == "holiday":
            if not self.date:
                raise ValueError("Holiday date is required")
            if not self.holiday_name:
                raise ValueError("Holiday name is required")
            self.title = self.holiday_name
            self.category = "Holiday"
            self.start_date = self.date
            self.end_date = self.date
            self.all_day = True
            if not self.calendar_year:
                self.calendar_year = self.date.year
            return self

        if not self.title:
            raise ValueError("Academic event title is required")
        if not self.category:
            raise ValueError("Academic event category is required")
        if not self.semester_type:
            raise ValueError("Semester type is required")
        if not self.start_date:
            raise ValueError("Start date is required")
        if self.end_date and self.end_date < self.start_date:
            raise ValueError("End date cannot be before start date")
        if self.end_date is None:
            self.end_date = self.start_date
        if not self.calendar_year:
            self.calendar_year = self.start_date.year
        return self


class InstitutionCalendarEntryUpdate(BaseModel):
    academic_year: Optional[str] = Field(default=None, min_length=1, max_length=40)
    calendar_year: Optional[int] = Field(default=None, ge=1900, le=3000)
    date: Optional[DateType] = None
    holiday_name: Optional[str] = Field(default=None, max_length=200)
    title: Optional[str] = Field(default=None, max_length=200)
    semester_type: Optional[InstitutionCalendarSemesterType] = None
    semester: Optional[str] = Field(default=None, max_length=60)
    category: Optional[str] = Field(default=None, max_length=80)
    start_date: Optional[DateType] = None
    end_date: Optional[DateType] = None
    all_day: Optional[bool] = None
    description: Optional[str] = Field(default=None, max_length=2000)
    color: Optional[str] = Field(default=None, max_length=20)
    visible_to_all: Optional[bool] = None
    google_sync_enabled: Optional[bool] = None
    is_active: Optional[bool] = None

    @field_validator("academic_year", "semester", "holiday_name", "title", "category", "description", "color", mode="before")
    @classmethod
    def strip_optional_text(cls, value):
        if isinstance(value, str):
            value = value.strip()
            return value or None
        return value


class InstitutionCalendarSyncResponse(BaseModel):
    success: bool
    detail: str
    google_event_id: Optional[str] = None
    google_event_link: Optional[str] = None
    sync_error: Optional[str] = None


class InstitutionCalendarEntryResponse(BaseModel):
    id: str
    title: str
    holiday_name: Optional[str] = None
    category: str
    entry_type: InstitutionCalendarEntryType
    academic_year: str
    calendar_year: Optional[int] = None
    semester_type: Optional[str] = None
    semester: Optional[str] = None
    date: Optional[str] = None
    start_date: str
    end_date: str
    all_day: bool
    day_label: Optional[str] = None
    description: Optional[str] = None
    color: Optional[str] = None
    visible_to_all: bool
    google_sync_enabled: bool
    google_event_id: Optional[str] = None
    google_event_link: Optional[str] = None
    google_sync_error: Optional[str] = None
    sync_status: str
    is_active: bool
    created_by: str
    updated_by: str
    created_at: datetime
    updated_at: datetime


class InstitutionCalendarMutationResponse(BaseModel):
    entry: InstitutionCalendarEntryResponse
    sync: Optional[InstitutionCalendarSyncResponse] = None


class UserAdminResponse(BaseModel):
    id: str
    name: str
    email: str
    role: str
    approval_status: Optional[str] = "approved"
    approved_by: Optional[str] = None
    approved_at: Optional[datetime] = None
    rejected_by: Optional[str] = None
    rejected_at: Optional[datetime] = None
    rejection_reason: Optional[str] = None
    requested_role: Optional[str] = None
    created_at: datetime
    last_seen: Optional[datetime] = None


IQACSSRSectionKey = Literal["executive_summary", "university_profile", "extended_profile", "qif"]


class IQACSSRSectionUpdate(BaseModel):
    data: Dict[str, Any] = Field(default_factory=dict)


class IQACSSRSectionResponse(BaseModel):
    id: Optional[str] = None
    section_key: IQACSSRSectionKey
    data: Dict[str, Any] = Field(default_factory=dict)
    no_changes: bool = False
    message: Optional[str] = None
    created_by: Optional[str] = None
    created_by_name: Optional[str] = None
    updated_by: Optional[str] = None
    updated_by_name: Optional[str] = None
    updated_by_email: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class IQACSSRHistoryResponse(BaseModel):
    id: str
    section_key: str
    previous_data: Dict[str, Any] = Field(default_factory=dict)
    new_data: Dict[str, Any] = Field(default_factory=dict)
    changed_fields: List[str] = Field(default_factory=list)
    field_diffs: Dict[str, Any] = Field(default_factory=dict)
    change_summary: Optional[str] = None
    edited_by: str
    edited_by_user_id: Optional[str] = None
    edited_by_name: Optional[str] = None
    edited_by_email: Optional[str] = None
    edited_at: datetime
    expires_at: Optional[datetime] = None


class UserRoleUpdate(BaseModel):
    role: str


class UserApprovalAction(BaseModel):
    """Admin action to approve or reject a pending user."""
    action: Literal["approve", "reject"]
    role: Optional[str] = None  # final role when approving
    rejection_reason: Optional[str] = Field(default=None, max_length=1000)


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
    intendedAudience: Optional[List[str]] = None
    intendedAudienceOther: Optional[str] = Field(default=None, max_length=500)
    discussedWithProgrammingChair: bool = False
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

    start_date: DateType
    start_time: time
    end_date: DateType
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
    intendedAudience: Optional[Union[List[str], str]] = None
    intendedAudienceOther: Optional[str] = None
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
    attendance_file_id: Optional[str] = None
    attendance_file_name: Optional[str] = None
    attendance_web_view_link: Optional[str] = None
    created_at: datetime


class ApprovalRequestResponse(BaseModel):
    id: str
    status: str
    discussion_status: Optional[str] = None
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
    intendedAudience: Optional[Union[List[str], str]] = None
    intendedAudienceOther: Optional[str] = None
    discussedWithProgrammingChair: bool = False
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
    approval_cc: List[str] = Field(default_factory=list)
    pipeline_stage: Optional[str] = None
    # Enriched fields for frontend display
    current_stage_label: Optional[str] = None
    approved_by_role: Optional[str] = None
    completed: bool = False
    # Stage-history: who decided at each gate
    deputy_decided_by: Optional[str] = None
    deputy_decided_at: Optional[datetime] = None
    finance_decided_by: Optional[str] = None
    finance_decided_at: Optional[datetime] = None
    # Whether this item is still actionable (vs read-only history)
    is_actionable: bool = True


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


class MarketingRequesterAttachmentResponse(BaseModel):
    file_id: str
    file_name: str
    web_view_link: Optional[str] = None
    uploaded_at: datetime


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
    requester_attachments: List[MarketingRequesterAttachmentResponse] = Field(default_factory=list)
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
    parent_id: Optional[str] = None
    thread_id: Optional[str] = None
    is_deleted: bool = False


class WorkflowActionThreadNode(BaseModel):
    """Nested approval discussion (registrar ↔ requester); mirrors WorkflowActionLogEntry + replies."""

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
    parent_id: Optional[str] = None
    thread_id: Optional[str] = None
    is_deleted: bool = False
    replies: List["WorkflowActionThreadNode"] = Field(default_factory=list)


class ApprovalDiscussionReply(BaseModel):
    """Reply to an approval discussion — either via legacy parent_id or via thread_id."""
    parent_id: Optional[str] = Field(default=None, max_length=64)
    thread_id: Optional[str] = Field(default=None, max_length=64)
    message: str = Field(..., min_length=1, max_length=4000)
    reply_to_message_id: Optional[str] = Field(default=None, max_length=64)


class ApprovalThreadEnsureRequest(BaseModel):
    """Create or retrieve a department thread for an approval request."""
    department: str = Field(..., min_length=1, max_length=50)
    message: Optional[str] = Field(default=None, max_length=4000)


class ApprovalThreadParticipant(BaseModel):
    id: str
    name: str
    email: str
    role: str


class ApprovalThreadMessage(BaseModel):
    id: str
    sender_id: str
    sender_name: str
    content: Optional[str] = None
    created_at: datetime
    is_legacy: bool = False  # True for WorkflowActionLog-sourced messages
    reply_to_message_id: Optional[str] = None
    reply_to_snapshot: Optional[dict] = None


class ApprovalThreadInfo(BaseModel):
    """A department-isolated approval discussion thread backed by a ChatConversation."""
    id: str  # conversation id
    department: str
    department_label: str
    related_request_id: Optional[str] = None
    related_kind: Optional[str] = None
    thread_status: str = "active"
    # Workflow status of the related dept request (pending/approved/rejected/clarification_requested).
    # Populated for facility/it/marketing/transport threads; None for registrar/approval threads.
    dept_request_status: Optional[str] = None
    participants: list[ApprovalThreadParticipant] = Field(default_factory=list)
    created_at: datetime
    messages: list[ApprovalThreadMessage] = Field(default_factory=list)
    closed_at: Optional[datetime] = None
    closed_reason: Optional[str] = None


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
    approval_discussion_threads: List[WorkflowActionThreadNode] = Field(default_factory=list)
    # Per-dept-request discussion threads (facility/IT/marketing/transport clarifications).
    # Each entry is keyed by related_request_id matching the resp. dept request's id.
    dept_request_threads: List[ApprovalThreadInfo] = Field(default_factory=list)


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
    reply_to_message_id: Optional[str] = None


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
    reply_to_message_id: Optional[str] = None
    reply_to_snapshot: Optional[dict] = None  # {sender_name, content_preview, is_deleted}


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
    # Workflow thread fields (approval_thread kind)
    thread_status: Optional[str] = None
    department: Optional[str] = None
    department_label: Optional[str] = None
    related_kind: Optional[str] = None
    approval_request_id: Optional[str] = None
    closed_at: Optional[datetime] = None
    closed_reason: Optional[str] = None
    event_title: Optional[str] = None  # resolved event name for approval_thread rows


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
    source_type: Optional[str] = None
    citation_format: Optional[str] = None
    details: Dict[str, Any] = Field(default_factory=dict)
    others: Optional[str] = None
    file_id: Optional[str] = None
    file_name: Optional[str] = None
    web_view_link: Optional[str] = None
    uploaded_at: Optional[datetime] = None
    created_at: datetime
    created_by: Optional[str] = None
    created_by_name: Optional[str] = None
    created_by_email: Optional[str] = None
    updated_by: Optional[str] = None
    updated_by_name: Optional[str] = None
    updated_by_email: Optional[str] = None
    updated_at: Optional[datetime] = None
    # Shared
    author: Optional[str] = None
    author_first_name: Optional[str] = None
    author_last_name: Optional[str] = None
    publication_date: Optional[str] = None
    issued_date: Optional[str] = None
    accessed_date: Optional[str] = None
    composed_date: Optional[str] = None
    submitted_date: Optional[str] = None
    content: Optional[str] = None
    contributors: Optional[str] = None
    container_title: Optional[str] = None
    collection_title: Optional[str] = None
    note: Optional[str] = None
    source: Optional[str] = None
    url: Optional[str] = None
    pdf_url: Optional[str] = None
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


class StudentAchievementStudentPayload(BaseModel):
    student_name: str = Field(default="", max_length=200)
    batch: Optional[str] = Field(default=None, max_length=120)
    course: Optional[str] = Field(default=None, max_length=200)
    # Legacy input/response aliases retained for older records and clients.
    name: Optional[str] = Field(default=None, max_length=200)
    registration_number: Optional[str] = Field(default=None, max_length=120)


class StudentAchievementFileResponse(BaseModel):
    file_id: str
    file_name: str
    web_view_link: Optional[str] = None
    content_type: Optional[str] = None
    size: Optional[int] = None
    uploaded_at: datetime


class StudentAchievementPatch(BaseModel):
    achievement_title: Optional[str] = Field(default=None, max_length=240)
    achievement_type: Optional[str] = Field(default=None, max_length=40)
    students: Optional[List[StudentAchievementStudentPayload]] = None
    activity_description: Optional[str] = Field(default=None, max_length=6000)
    additional_context_objective: Optional[str] = Field(default=None, max_length=6000)
    social_media_writeup: Optional[str] = Field(default=None, max_length=6000)
    department_programme: Optional[str] = Field(default=None, max_length=200)
    year_semester: Optional[str] = Field(default=None, max_length=120)
    faculty_mentor: Optional[str] = Field(default=None, max_length=200)
    achievement_category: Optional[str] = Field(default=None, max_length=80)
    achievement_date: Optional[str] = Field(default=None, max_length=40)
    activity_name: Optional[str] = Field(default=None, max_length=240)
    organising_institution: Optional[str] = Field(default=None, max_length=240)
    level: Optional[str] = Field(default=None, max_length=80)
    award_recognition: Optional[str] = Field(default=None, max_length=240)
    brief_context: Optional[str] = Field(default=None, max_length=2000)
    detailed_writeup: Optional[str] = Field(default=None, max_length=6000)
    suggested_platforms: Optional[List[str]] = None
    iqac_criterion_id: Optional[str] = Field(default=None, max_length=40)
    iqac_subfolder_id: Optional[str] = Field(default=None, max_length=40)
    iqac_item_id: Optional[str] = Field(default=None, max_length=40)
    iqac_description: Optional[str] = Field(default=None, max_length=500)
    preferred_posting_date: Optional[str] = Field(default=None, max_length=40)
    consent_confirmed: Optional[bool] = None
    additional_notes: Optional[str] = Field(default=None, max_length=3000)
    status: Optional[Literal["submitted", "reviewed", "posted"]] = None


class StudentAchievementResponse(BaseModel):
    id: str
    achievement_title: str
    achievement_type: Optional[str] = None
    students: List[StudentAchievementStudentPayload] = Field(default_factory=list)
    activity_description: Optional[str] = None
    additional_context_objective: Optional[str] = None
    social_media_writeup: Optional[str] = None
    attachments: List[StudentAchievementFileResponse] = Field(default_factory=list)
    iqac_criterion_id: Optional[str] = None
    iqac_subfolder_id: Optional[str] = None
    iqac_item_id: Optional[str] = None
    iqac_description: Optional[str] = None
    department_programme: Optional[str] = None
    year_semester: Optional[str] = None
    faculty_mentor: Optional[str] = None
    achievement_category: Optional[str] = None
    achievement_date: Optional[str] = None
    activity_name: Optional[str] = None
    organising_institution: Optional[str] = None
    level: Optional[str] = None
    award_recognition: Optional[str] = None
    brief_context: Optional[str] = None
    detailed_writeup: Optional[str] = None
    suggested_platforms: List[str] = Field(default_factory=list)
    preferred_posting_date: Optional[str] = None
    assets: List[StudentAchievementFileResponse] = Field(default_factory=list)
    proofs: List[StudentAchievementFileResponse] = Field(default_factory=list)
    consent_confirmed: bool
    additional_notes: Optional[str] = None
    status: str
    created_by: str
    created_by_name: Optional[str] = None
    created_by_email: Optional[str] = None
    created_at: datetime
    updated_by: Optional[str] = None
    updated_by_name: Optional[str] = None
    updated_by_email: Optional[str] = None
    updated_at: datetime
    audit_log: List[dict] = Field(default_factory=list)


WorkflowActionThreadNode.model_rebuild()
