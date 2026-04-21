from beanie import Document, Indexed
from pydantic import Field
from datetime import datetime, date, time
from typing import Optional, List, Union
from pydantic import BaseModel

class User(Document):
    name: str
    email: str = Field(unique=True)
    google_id: str = Field(unique=True)
    role: str = Field(default="faculty")
    # Approval workflow: "approved" | "pending" | "rejected"
    # Existing users without this field are treated as approved (see backfill in auth).
    approval_status: str = Field(default="approved")
    approved_by: Optional[str] = None
    approved_at: Optional[datetime] = None
    rejected_by: Optional[str] = None
    rejected_at: Optional[datetime] = None
    rejection_reason: Optional[str] = None
    requested_role: Optional[str] = None  # role requested at sign-up before approval
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
    intendedAudience: Optional[Union[List[str], str]] = None
    intendedAudienceOther: Optional[str] = None
    budget: Optional[float] = None  # Event budget in Rs
    budget_breakdown_file_id: Optional[str] = None
    budget_breakdown_file_name: Optional[str] = None
    budget_breakdown_web_view_link: Optional[str] = None
    budget_breakdown_uploaded_at: Optional[datetime] = None
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
    attendance_file_id: Optional[str] = None
    attendance_file_name: Optional[str] = None
    attendance_web_view_link: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "events"


class InstitutionCalendarEntry(Document):
    title: str
    category: str
    entry_type: str = Field(default="academic")  # holiday | academic
    academic_year: str
    calendar_year: Optional[int] = None
    semester_type: Optional[str] = None
    semester: Optional[str] = None
    start_date: str
    end_date: str
    all_day: bool = True
    day_label: Optional[str] = None
    description: Optional[str] = None
    color: Optional[str] = None
    visible_to_all: bool = True
    google_sync_enabled: bool = False
    google_event_id: Optional[str] = None
    google_event_link: Optional[str] = None
    google_sync_error: Optional[str] = None
    is_active: bool = True
    created_by: str
    updated_by: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "institution_calendar_entries"
        indexes = [
            "entry_type",
            "academic_year",
            "semester",
            "category",
            "start_date",
            "end_date",
            "is_active",
            "visible_to_all",
        ]


class ApprovalRequest(Document):
    requester_id: str
    requester_email: str
    requested_to: Optional[str] = None
    event_name: str
    facilitator: str
    budget: Optional[float] = None  # Event budget in Rs
    budget_breakdown_file_id: Optional[str] = None
    budget_breakdown_file_name: Optional[str] = None
    budget_breakdown_web_view_link: Optional[str] = None
    budget_breakdown_uploaded_at: Optional[datetime] = None
    description: Optional[str] = None
    venue_name: str
    intendedAudience: Optional[Union[List[str], str]] = None
    intendedAudienceOther: Optional[str] = None
    discussedWithProgrammingChair: bool = Field(default=False)
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    requirements: list[str] = Field(default_factory=list)
    other_notes: Optional[str] = None
    status: str = Field(default="pending")
    discussion_status: Optional[str] = None  # active | waiting_for_faculty | waiting_for_department
    event_id: Optional[str] = None
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    override_conflict: bool = Field(default=False)
    # Emails copied on the initial approval notification (not approvers on the request).
    approval_cc: List[str] = Field(default_factory=list)
    # Multi-stage routing: deputy → finance → registrar/VC (final). Legacy rows omit this (treated as registrar-only).
    pipeline_stage: Optional[str] = Field(default=None)
    # Stage-history: who decided at the deputy / finance gates (for post-approval visibility).
    deputy_decided_by: Optional[str] = None
    deputy_decided_at: Optional[datetime] = None
    finance_decided_by: Optional[str] = None
    finance_decided_at: Optional[datetime] = None

    class Settings:
        name = "approval_requests"


class MarketingRequesterAttachment(BaseModel):
    """Reference files supplied by the faculty requester for marketing (briefs, brand assets, etc.)."""
    file_id: str
    file_name: str
    web_view_link: Optional[str] = None
    uploaded_at: datetime = Field(default_factory=datetime.utcnow)


class MarketingDeliverable(BaseModel):
    """A file uploaded by marketing for a request (poster, photo, video, etc.), or marked NA."""
    deliverable_type: str  # poster, photography, video, recording, linkedin, other
    file_id: str  # "na" when is_na=True
    file_name: str  # "N/A" when is_na=True
    web_view_link: Optional[str] = None
    uploaded_at: datetime = Field(default_factory=datetime.utcnow)
    is_na: bool = False


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
    marketing_requirements: Optional[MarketingRequirements] = None
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
    requester_attachments: List[MarketingRequesterAttachment] = Field(default_factory=list)
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


class TransportRequest(Document):
    """Guest cab, off-campus student transport, or both; created after registrar approves the event."""

    requester_id: str
    requester_email: str
    requested_to: Optional[str] = None
    event_id: Optional[str] = None
    event_name: str
    start_date: str
    start_time: str
    end_date: str
    end_time: str
    transport_type: str  # guest_cab | students_off_campus | both
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
    status: str = Field(default="pending")
    decided_at: Optional[datetime] = None
    decided_by: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Settings:
        name = "transport_requests"


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
    # "direct" = 1:1; "event" = group for one event; "approval_thread" = dept ↔ faculty
    thread_kind: str = Field(default="direct")
    event_id: Optional[str] = None
    title: Optional[str] = None
    # Messaging enhancements
    last_message: Optional[dict] = None  # {text, sender_id, sender_name, created_at}
    deleted_for: List[str] = Field(default_factory=list)  # user_ids who soft-deleted
    participant_unreads: dict = Field(default_factory=dict)  # {user_id: unread_count}
    # Approval-thread fields (thread_kind="approval_thread")
    approval_request_id: Optional[str] = None
    # department key encodes BOTH the dept-request channel (facility_manager,
    # it, marketing, transport, iqac) AND the approval pipeline stage:
    #   "deputy_registrar"  — Deputy Registrar clarification stage
    #   "finance_team"      — Finance Team clarification stage
    #   "registrar"         — Registrar / VC final-approval stage
    # Each pipeline stage uses a distinct key so conversations are NEVER shared
    # across stages even for the same approval_request_id.
    department: Optional[str] = None
    related_request_id: Optional[str] = None  # dept request id (or approval id for pipeline-stage threads)
    related_kind: Optional[str] = None  # approval_request | facility_request | ...
    thread_status: Optional[str] = None  # active | waiting_for_faculty | waiting_for_department | resolved | closed
    closed_at: Optional[datetime] = None
    closed_reason: Optional[str] = None  # "approved" | "rejected" | "event_closed" | "manual"
    # Migration audit trail — set when a legacy "registrar" thread is reclassified
    migrated_from_dept: Optional[str] = None
    migrated_at: Optional[datetime] = None

    class Settings:
        name = "chat_conversations"
        indexes = [
            "event_id",
            "participants",
            "updated_at",
            "approval_request_id",
        ]


class ChatMessage(Document):
    conversation_id: str
    sender_id: str
    sender_name: str
    sender_email: str
    content: Optional[str] = None
    attachments: List[ChatAttachment] = Field(default_factory=list)
    read_by: List[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    # Deletion support
    is_deleted: bool = Field(default=False)
    deleted_for_everyone: bool = Field(default=False)
    deleted_for: List[str] = Field(default_factory=list)  # user_ids — hidden for these users only
    edited: bool = Field(default=False)
    edited_at: Optional[datetime] = None
    # Reply threading
    reply_to_message_id: Optional[str] = None
    reply_to_snapshot: Optional[dict] = None  # frozen at write time: {sender_name, content_preview, is_deleted}

    class Settings:
        name = "chat_messages"
        indexes = [
            "conversation_id",
            "created_at",
        ]


class IQACFile(Document):
    """File uploaded under IQAC data collection (criterion / subfolder / item)."""
    criterion: int  # 1-7
    sub_folder: str  # e.g. "1.1", "1.2"
    item: str  # e.g. "1.1.1", "1.1.2"
    file_name: str
    file_path: str  # path relative to uploads root or absolute
    uploaded_by: str  # user id
    uploaded_at: datetime = Field(default_factory=datetime.utcnow)
    description: Optional[str] = None
    size: int = 0  # bytes

    class Settings:
        name = "iqac_files"
        indexes = [
            "criterion",
            "sub_folder",
            "item",
            ("criterion", "sub_folder", "item"),
        ]


class WorkflowActionLog(Document):
    """Audit trail for registrar and department decisions (approve / reject / need clarification)."""

    event_id: Optional[str] = None
    approval_request_id: Optional[str] = None
    related_kind: str  # approval_request | facility_request | marketing_request | it_request | transport_request
    related_id: str
    role: str  # registrar | facility_manager | marketing | it | transport | requester
    action_type: str  # approve | reject | clarification | reply
    comment: str
    action_by: str
    action_by_user_id: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
    parent_id: Optional[str] = None
    thread_id: Optional[str] = None
    is_deleted: bool = Field(default=False)

    class Settings:
        name = "workflow_action_logs"
        indexes = ["event_id", "approval_request_id", "related_id", "created_at", "parent_id", "thread_id"]
