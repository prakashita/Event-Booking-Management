import os
import re
import base64
import logging
from pathlib import Path
from datetime import datetime
from typing import Optional, Tuple

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile, status

from rate_limit import limiter
from fastapi.responses import JSONResponse
import requests

from auth import (
    ensure_google_access_token,
    get_primary_email_by_role,
    get_staff_emails_for_calendar_invites,
    get_user_by_role,
    is_admin_email,
)
from drive import delete_drive_file, upload_report_file
from errors import error_payload
from idempotency import get_cached_response, get_idempotency_key, store_response
from event_status import combine_datetime, sync_event_status
from models import ApprovalRequest, ChatConversation, ChatMessage, Event, FacilityManagerRequest, ItRequest, MarketingRequest, TransportRequest, User
from routers.admin import (
    serialize_approval,
    serialize_event,
    serialize_facility,
    serialize_it,
    serialize_marketing,
    serialize_transport,
)
from routers.deps import IQAC_ALLOWED_ROLES, get_current_user
from routers.iqac import persist_iqac_upload, validate_iqac_path
from schemas import (
    ApprovalThreadInfo,
    ApprovalThreadMessage,
    ApprovalThreadParticipant,
    EventCreate,
    EventCreateResponse,
    EventDetailsResponse,
    EventResponse,
    EventStatusUpdate,
    FacilityManagerRequestResponse,
    ItRequestResponse,
    MarketingRequestResponse,
    PaginatedResponse,
    TransportRequestResponse,
    WorkflowActionLogEntry,
    WorkflowActionThreadNode,
)
from workflow_action_service import (
    filter_logs_for_approval_discussion,
    list_workflow_actions_for_scope,
    nest_workflow_logs_as_trees,
)

router = APIRouter(prefix="/events", tags=["Events"])
logger = logging.getLogger("event-booking.events")

# Above this budget (Rs), the vice chancellor is the primary approver; registrar is CC only.
BUDGET_VC_PRIMARY_THRESHOLD = 30000.0


def _requested_to_matches_user_email(email: str) -> dict:
    """Case-insensitive exact match on requested_to (handles legacy casing in DB)."""
    return {"$regex": f"^{re.escape((email or '').strip())}$", "$options": "i"}


async def user_may_view_event_details(user: User, event: Event) -> bool:
    """Creator, admin/registrar, or staff who received a requirement for this event."""
    if event.created_by == str(user.id):
        return True
    role = (user.role or "").strip().lower()
    if role in ("admin", "registrar", "vice_chancellor", "deputy_registrar", "finance_team"):
        return True
    if is_admin_email(user.email or ""):
        return True
    email = (user.email or "").strip()
    if not email:
        return False
    eid = str(event.id)
    to_query = _requested_to_matches_user_email(email)
    if await MarketingRequest.find_one({"event_id": eid, "requested_to": to_query}):
        return True
    if await FacilityManagerRequest.find_one({"event_id": eid, "requested_to": to_query}):
        return True
    if await ItRequest.find_one({"event_id": eid, "requested_to": to_query}):
        return True
    if await TransportRequest.find_one({"event_id": eid, "requested_to": to_query}):
        return True
    return False


def serialize_workflow_log_entry(entry) -> WorkflowActionLogEntry:
    deleted = bool(getattr(entry, "is_deleted", False))
    text = "[Deleted]" if deleted else (entry.comment or "")
    return WorkflowActionLogEntry(
        id=str(entry.id),
        event_id=entry.event_id,
        approval_request_id=entry.approval_request_id,
        related_kind=entry.related_kind,
        related_id=entry.related_id,
        role=entry.role,
        action_type=entry.action_type,
        comment=text,
        action_by=entry.action_by,
        action_by_user_id=entry.action_by_user_id,
        created_at=entry.created_at,
        parent_id=getattr(entry, "parent_id", None),
        thread_id=getattr(entry, "thread_id", None),
        is_deleted=deleted,
    )


def _serialize_workflow_logs(entries) -> list[WorkflowActionLogEntry]:
    return [serialize_workflow_log_entry(entry) for entry in entries]


def _build_approval_discussion_threads(wf_logs, approval_request_id: str) -> list[WorkflowActionThreadNode]:
    scoped = filter_logs_for_approval_discussion(wf_logs, approval_request_id)
    trees = nest_workflow_logs_as_trees(scoped)
    return [WorkflowActionThreadNode.model_validate(t) for t in trees]


# Dept-request thread kinds the event details view should expose inline.
_DEPT_REQUEST_THREAD_KINDS = frozenset({
    "facility_request", "it_request", "marketing_request", "transport_request",
})


async def _build_dept_request_threads(
    approval_request_id: str,
    user: User,
    event_created_by: str,
) -> list[ApprovalThreadInfo]:
    """Return per-dept-request discussion threads for the event details view.

    Visibility rules:
    - Admin: all dept-request threads.
    - Event creator (requester/faculty): all dept threads for their event.
    - Dept user: only threads they participate in.
    All other roles get threads they participate in directly.
    """
    from event_chat_service import DEPARTMENT_LABELS, list_approval_threads

    all_threads = await list_approval_threads(approval_request_id)
    dept_threads = [t for t in all_threads if (t.related_kind or "") in _DEPT_REQUEST_THREAD_KINDS]

    uid = str(user.id)
    role = (user.role or "").strip().lower()
    is_admin_user = role == "admin" or is_admin_email(user.email or "")
    is_requester = uid == str(event_created_by)

    result: list[ApprovalThreadInfo] = []
    for conv in dept_threads:
        user_is_participant = uid in (conv.participants or [])
        # Visibility check: admin or requester sees all; others only their threads
        if not (is_admin_user or is_requester or user_is_participant):
            continue

        participants: list[ApprovalThreadParticipant] = []
        for pid in conv.participants:
            u = await User.get(pid)
            if u:
                participants.append(ApprovalThreadParticipant(
                    id=str(u.id), name=u.name, email=u.email, role=u.role or "",
                ))

        raw_messages = await ChatMessage.find(
            {"conversation_id": str(conv.id), "is_deleted": {"$ne": True}},
        ).sort("created_at").to_list()
        messages = [
            ApprovalThreadMessage(
                id=str(m.id),
                sender_id=m.sender_id,
                sender_name=m.sender_name,
                content=m.content,
                created_at=m.created_at,
                reply_to_message_id=getattr(m, "reply_to_message_id", None),
                reply_to_snapshot=getattr(m, "reply_to_snapshot", None),
            )
            for m in raw_messages
        ]
        result.append(ApprovalThreadInfo(
            id=str(conv.id),
            department=conv.department or "",
            department_label=DEPARTMENT_LABELS.get(conv.department or "", conv.department or ""),
            related_request_id=conv.related_request_id,
            related_kind=conv.related_kind,
            thread_status=conv.thread_status or "active",
            participants=participants,
            created_at=conv.created_at,
            messages=messages,
            closed_at=getattr(conv, "closed_at", None),
            closed_reason=getattr(conv, "closed_reason", None),
        ))
    return result


def _requirement_status_for_event_details(
    row: FacilityManagerRequestResponse | MarketingRequestResponse | ItRequestResponse | TransportRequestResponse,
) -> FacilityManagerRequestResponse | MarketingRequestResponse | ItRequestResponse | TransportRequestResponse:
    """Event details UI shows 'accepted' for facility/marketing/IT; registrar stays 'approved'."""
    if (row.status or "").strip() == "approved":
        return row.model_copy(update={"status": "accepted"})
    return row


# Report filename format: {SanitizedEventName}_{StartDate}_Report.pdf
REPORT_FILENAME_SUFFIX = "_Report.pdf"
BUDGET_BREAKDOWN_FILENAME_SUFFIX = "_BudgetBreakdown.pdf"


def _sanitize_for_report_filename(name: str) -> str:
    """Sanitize event name for report filename: alphanumeric, spaces, hyphens only; spaces -> underscores."""
    if not name or not name.strip():
        return "Event"
    # Keep letters, digits, spaces, hyphens; replace other chars with space
    cleaned = re.sub(r"[^\w\s-]", "", name, flags=re.IGNORECASE)
    cleaned = re.sub(r"[\s]+", "_", cleaned.strip())
    return cleaned or "Event"


def get_expected_report_filename(event_name: str, start_date: str) -> str:
    """Return the required report filename for an event: EventName_YYYY-MM-DD_Report.pdf"""
    sanitized = _sanitize_for_report_filename(event_name or "Event")
    date_part = (start_date or "").strip() or "0000-00-00"
    return f"{sanitized}_{date_part}{REPORT_FILENAME_SUFFIX}"


def get_expected_budget_breakdown_filename(event_name: str, start_date: str) -> str:
    """Required budget breakdown PDF name: EventName_YYYY-MM-DD_BudgetBreakdown.pdf"""
    sanitized = _sanitize_for_report_filename(event_name or "Event")
    date_part = (start_date or "").strip() or "0000-00-00"
    return f"{sanitized}_{date_part}{BUDGET_BREAKDOWN_FILENAME_SUFFIX}"


ATTENDANCE_ALLOWED_EXT = {".pdf", ".doc", ".docx", ".xls", ".xlsx"}
ATTENDANCE_EXT_TO_MIME = {
    ".pdf": "application/pdf",
    ".doc": "application/msword",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xls": "application/vnd.ms-excel",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
}
ATTENDANCE_ALLOWED_MIMES = set(ATTENDANCE_EXT_TO_MIME.values())


async def _read_validated_attendance_attachment(file: UploadFile) -> Tuple[bytes, str, str]:
    """Return (bytes, safe_filename, mime_type) or raise HTTPException."""
    raw_name = (file.filename or "").strip()
    if not raw_name:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Attendance attachment has no filename")
    safe_name = Path(raw_name.replace("\\", "/")).name
    if not safe_name:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid attendance attachment filename")
    ext = Path(safe_name).suffix.lower()
    if ext not in ATTENDANCE_ALLOWED_EXT:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Attendance attachment must be PDF, Word (.doc, .docx), or Excel (.xls, .xlsx)",
        )
    declared = (file.content_type or "").split(";")[0].strip().lower()
    if declared and declared not in ATTENDANCE_ALLOWED_MIMES and declared != "application/octet-stream":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Attendance attachment must be PDF, Word (.doc, .docx), or Excel (.xls, .xlsx)",
        )
    contents = await file.read()
    max_size = 10 * 1024 * 1024
    if len(contents) > max_size:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Attendance attachment too large (max 10MB)")
    mime = ATTENDANCE_EXT_TO_MIME[ext]
    return contents, safe_name, mime


async def sync_event_to_google_calendar(event: Event, user: User) -> None:
    if not user.google_refresh_token:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Connect Google Calendar to create events",
        )

    access_token = await ensure_google_access_token(user)
    time_zone = os.getenv("DEFAULT_TIMEZONE", "Asia/Kolkata")
    organizer_email = (user.email or "").strip().lower()
    staff_emails = await get_staff_emails_for_calendar_invites(
        exclude_emails={organizer_email} if organizer_email else None,
    )
    payload = {
        "summary": event.name,
        "description": event.description or "",
        "location": event.venue_name,
        "start": {"dateTime": f"{event.start_date}T{event.start_time}", "timeZone": time_zone},
        "end": {"dateTime": f"{event.end_date}T{event.end_time}", "timeZone": time_zone},
    }
    if staff_emails:
        payload["attendees"] = [{"email": email} for email in staff_emails]

    send_updates = "all" if staff_emails else "none"
    response = requests.post(
        "https://www.googleapis.com/calendar/v3/calendars/primary/events",
        headers={"Authorization": f"Bearer {access_token}"},
        params={"sendUpdates": send_updates},
        json=payload,
        timeout=15,
    )
    if response.status_code not in {200, 201}:
        detail = "Unable to create Google Calendar event"
        try:
            error_payload = response.json()
            error_message = error_payload.get("error", {}).get("message")
            if error_message:
                detail = f"{detail}: {error_message}"
        except Exception:
            pass
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=detail,
        )

    data = response.json()
    google_event_id = data.get("id")
    if not google_event_id:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Google Calendar event created without an event id",
        )

    event.google_event_id = google_event_id
    event.google_event_link = data.get("htmlLink")
    await event.save()

def serialize_conflict(event: Event) -> dict:
    return {
        "id": str(event.id),
        "name": event.name,
        "venue_name": event.venue_name,
        "start_date": event.start_date,
        "start_time": event.start_time,
        "end_date": event.end_date,
        "end_time": event.end_time,
    }


def _serialize_conflict_doc(doc: dict) -> dict:
    return {
        "id": str(doc.get("_id", "")),
        "name": str(doc.get("name", "") or ""),
        "venue_name": str(doc.get("venue_name", "") or ""),
        "start_date": doc.get("start_date"),
        "start_time": doc.get("start_time"),
        "end_date": doc.get("end_date"),
        "end_time": doc.get("end_time"),
    }


async def _fetch_event_conflict_docs(venue_name: str) -> list[dict]:
    # Read raw Mongo documents so malformed legacy rows do not fail Beanie model parsing.
    # Restrict to one venue to avoid scanning the full events collection on each request.
    collection = Event.get_motor_collection()
    cursor = collection.find(
        {"venue_name": venue_name},
        {
            "_id": 1,
            "name": 1,
            "venue_name": 1,
            "start_date": 1,
            "start_time": 1,
            "end_date": 1,
            "end_time": 1,
        },
    )
    return await cursor.to_list(length=None)


def _build_raw_email(
    to_email: str,
    subject: str,
    body: str,
    cc_emails: Optional[list[str]] = None,
) -> str:
    cc_clean = [e.strip() for e in (cc_emails or []) if e and str(e).strip()]
    headers = [
        f"To: {to_email}",
    ]
    if cc_clean:
        headers.append(f"Cc: {', '.join(cc_clean)}")
    headers.extend(
        [
            f"Subject: {subject}",
            "Content-Type: text/plain; charset=\"UTF-8\"",
        ]
    )
    return "\r\n".join(headers) + "\r\n\r\n" + body


async def notify_registrar_for_approval(
    requester: User,
    primary_approver_email: str,
    approval: ApprovalRequest,
    cc_emails: Optional[list[str]] = None,
) -> None:
    """Notify primary approver (To) and CC others. Uses VC/registrar/requester Gmail in that order."""
    subject = f"Event Approval Request: {approval.event_name}"
    budget_line = f"Budget: Rs {approval.budget:,.0f}\n" if getattr(approval, "budget", None) is not None else ""
    body = (
        f"A new event requires your approval.\n\n"
        f"Requester: {approval.requester_email}\n"
        f"Event: {approval.event_name}\n"
        f"Facilitator: {approval.facilitator}\n"
        f"Venue: {approval.venue_name}\n"
        f"{budget_line}"
        f"Start: {approval.start_date} {approval.start_time}\n"
        f"End: {approval.end_date} {approval.end_time}\n"
        f"\nPlease approve or reject this event from your dashboard."
    )
    raw_message = _build_raw_email(primary_approver_email, subject, body, cc_emails)
    encoded_message = base64.urlsafe_b64encode(raw_message.encode("utf-8")).decode("utf-8")

    access_token = None
    for sender_user in [
        await get_user_by_role("deputy_registrar"),
        await get_user_by_role("finance_team"),
        await get_user_by_role("vice_chancellor"),
        await get_user_by_role("registrar"),
        requester,
    ]:
        if not sender_user:
            continue
        try:
            access_token = await ensure_google_access_token(sender_user)
            break
        except Exception:
            continue

    if not access_token:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Unable to send approval notification: connect Google on deputy registrar, finance, vice chancellor, registrar, or your account.",
        )

    response = requests.post(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"raw": encoded_message},
        timeout=15,
    )
    if response.status_code not in {200, 202}:
        detail = "Unable to send approval notification email"
        try:
            payload = response.json()
            detail = payload.get("error", {}).get("message", detail)
        except Exception:
            pass
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=detail)

DEFAULT_LIMIT = 50
MAX_LIMIT = 100


@router.get("", response_model=PaginatedResponse[EventResponse])
async def list_events(
    user: User = Depends(get_current_user),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    query = Event.find(Event.created_by == str(user.id)).sort("-created_at")
    total = await query.count()
    events = await query.skip(offset).limit(limit).to_list()
    for event in events:
        await sync_event_status(event)
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[EventResponse](
        items=[serialize_event(event) for event in events],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/{event_id}/details", response_model=EventDetailsResponse)
async def get_event_details(event_id: str, user: User = Depends(get_current_user)):
    """Return full event details for the details modal: event, registrar approval, facility/marketing/IT requests and who approved, marketing deliverables."""
    if event_id.startswith("approval-"):
        approval_id = event_id[len("approval-") :].strip()
        try:
            approval_object_id = PydanticObjectId(approval_id)
        except Exception:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

        approval = await ApprovalRequest.get(approval_object_id)
        if not approval:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
        role = (user.role or "").strip().lower()
        is_requester = approval.requester_id == str(user.id)
        is_assigned_approver = (
            approval.requested_to
            and approval.requested_to.strip().lower() == (user.email or "").strip().lower()
        )
        is_privileged = role in (
            "registrar",
            "vice_chancellor",
            "deputy_registrar",
            "finance_team",
            "admin",
        ) or is_admin_email(user.email or "")
        if not (is_requester or is_assigned_approver or is_privileged):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to view this event")

        if not approval.event_id:
            wf_logs = await list_workflow_actions_for_scope(
                event_id=None,
                approval_request_id=str(approval.id),
            )
            approval_threads = _build_approval_discussion_threads(wf_logs, str(approval.id))
            return EventDetailsResponse(
                event=EventResponse(
                    id=event_id,
                    name=approval.event_name,
                    facilitator=approval.facilitator,
                    description=approval.description,
                    venue_name=approval.venue_name,
                    intendedAudience=getattr(approval, "intendedAudience", None),
                    budget=getattr(approval, "budget", None),
                    budget_breakdown_file_id=getattr(approval, "budget_breakdown_file_id", None),
                    budget_breakdown_file_name=getattr(approval, "budget_breakdown_file_name", None),
                    budget_breakdown_web_view_link=getattr(approval, "budget_breakdown_web_view_link", None),
                    budget_breakdown_uploaded_at=getattr(approval, "budget_breakdown_uploaded_at", None),
                    start_date=approval.start_date,
                    start_time=approval.start_time,
                    end_date=approval.end_date,
                    end_time=approval.end_time,
                    created_by=approval.requester_id,
                    status=approval.status,
                    google_event_id=None,
                    google_event_link=None,
                    report_file_id=None,
                    report_file_name=None,
                    report_web_view_link=None,
                    report_uploaded_at=None,
                    attendance_file_id=None,
                    attendance_file_name=None,
                    attendance_web_view_link=None,
                    created_at=approval.created_at,
                ),
                approval_request=serialize_approval(approval),
                facility_requests=[],
                marketing_requests=[],
                it_requests=[],
                transport_requests=[],
                workflow_action_logs=_serialize_workflow_logs(wf_logs),
                approval_discussion_threads=approval_threads,
                dept_request_threads=[],
            )

        event_id = approval.event_id

    try:
        event_object_id = PydanticObjectId(event_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

    event = await Event.get(event_object_id)
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    if not await user_may_view_event_details(user, event):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to view this event")

    event_id_str = str(event.id)
    await sync_event_status(event)
    approval_request = await ApprovalRequest.find_one(ApprovalRequest.event_id == event_id_str)
    facility_requests = await FacilityManagerRequest.find(
        FacilityManagerRequest.event_id == event_id_str
    ).sort("-created_at").to_list()
    marketing_requests = await MarketingRequest.find(
        MarketingRequest.event_id == event_id_str
    ).sort("-created_at").to_list()
    it_requests = await ItRequest.find(ItRequest.event_id == event_id_str).sort("-created_at").to_list()
    transport_requests = await TransportRequest.find(TransportRequest.event_id == event_id_str).sort(
        "-created_at"
    ).to_list()

    wf_logs = await list_workflow_actions_for_scope(
        event_id=event_id_str,
        approval_request_id=str(approval_request.id) if approval_request else None,
    )
    approval_threads = (
        _build_approval_discussion_threads(wf_logs, str(approval_request.id))
        if approval_request
        else []
    )
    dept_request_threads = (
        await _build_dept_request_threads(
            str(approval_request.id), user, str(event.created_by)
        )
        if approval_request
        else []
    )

    return EventDetailsResponse(
        event=serialize_event(event),
        approval_request=serialize_approval(approval_request) if approval_request else None,
        facility_requests=[
            _requirement_status_for_event_details(serialize_facility(r)) for r in facility_requests
        ],
        marketing_requests=[
            _requirement_status_for_event_details(serialize_marketing(r)) for r in marketing_requests
        ],
        it_requests=[_requirement_status_for_event_details(serialize_it(r)) for r in it_requests],
        transport_requests=[
            _requirement_status_for_event_details(serialize_transport(r)) for r in transport_requests
        ],
        workflow_action_logs=_serialize_workflow_logs(wf_logs),
        approval_discussion_threads=approval_threads,
        dept_request_threads=dept_request_threads,
    )


@router.post("/conflicts")
async def check_conflicts(payload: EventCreate, user: User = Depends(get_current_user)):
    start_dt = datetime.combine(payload.start_date, payload.start_time)
    end_dt = datetime.combine(payload.end_date, payload.end_time)
    if end_dt < start_dt:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="End datetime must be after start datetime",
        )

    logger.info("Checking conflicts venue=%s", payload.venue_name)
    existing_events = await _fetch_event_conflict_docs(payload.venue_name)
    logger.info("Conflict candidate count venue=%s count=%s", payload.venue_name, len(existing_events))
    conflicts = []
    for existing in existing_events:
        try:
            existing_start = combine_datetime(existing.get("start_date"), existing.get("start_time"))
            existing_end = combine_datetime(existing.get("end_date"), existing.get("end_time"))
        except (TypeError, ValueError):
            logger.warning(
                "Skipping event with invalid date/time while checking conflicts",
                extra={"event_id": str(existing.get("_id", ""))},
            )
            continue
        if (
            str(existing.get("venue_name", "") or "") == payload.venue_name
            and start_dt < existing_end
            and end_dt > existing_start
        ):
            conflicts.append(_serialize_conflict_doc(existing))

    return {"conflicts": conflicts}


@router.post("", response_model=EventCreateResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
async def create_event(request: Request, payload: EventCreate, user: User = Depends(get_current_user)):
    idem_key = get_idempotency_key(request)
    if idem_key:
        cached = await get_cached_response(idem_key)
        if cached:
            return JSONResponse(status_code=cached[0], content=cached[1])

    start_dt = datetime.combine(payload.start_date, payload.start_time)
    end_dt = datetime.combine(payload.end_date, payload.end_time)
    if end_dt < start_dt:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="End datetime must be after start datetime",
        )

    if not payload.override_conflict:
        existing_events = await _fetch_event_conflict_docs(payload.venue_name)
        conflicts = []
        for existing in existing_events:
            try:
                existing_start = combine_datetime(existing.get("start_date"), existing.get("start_time"))
                existing_end = combine_datetime(existing.get("end_date"), existing.get("end_time"))
            except (TypeError, ValueError):
                logger.warning(
                    "Skipping event with invalid date/time while creating event",
                    extra={"event_id": str(existing.get("_id", ""))},
                )
                continue
            if (
                str(existing.get("venue_name", "") or "") == payload.venue_name
                and start_dt < existing_end
                and end_dt > existing_start
            ):
                conflicts.append(_serialize_conflict_doc(existing))

        if conflicts:
            request_id = getattr(request.state, "request_id", "")
            return JSONResponse(
                status_code=status.HTTP_409_CONFLICT,
                content=error_payload(
                    detail="Schedule conflict detected",
                    code="CONFLICT",
                    request_id=request_id,
                    conflicts=conflicts,
                ),
            )

    # Block creation if 5+ completed events have report upload pending
    user_completed = await Event.find(
        Event.created_by == str(user.id),
        Event.status == "completed",
    ).to_list()
    completed_without_report = sum(1 for e in user_completed if not e.report_file_id)
    if completed_without_report >= 5:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Upload reports for at least some completed events (5 or more have report pending) before creating a new one.",
        )

    registrar_email = (await get_primary_email_by_role("registrar") or "").strip()
    if not registrar_email:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Registrar email is not configured",
        )

    deputy_email = (await get_primary_email_by_role("deputy_registrar") or "").strip()
    if not deputy_email:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Deputy Registrar email is not configured",
        )

    finance_email = (await get_primary_email_by_role("finance_team") or "").strip()
    if not finance_email:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Finance Team email is not configured",
        )

    vc_email = (await get_primary_email_by_role("vice_chancellor") or "").strip()
    # First stage: Deputy Registrar only. VC/registrar routing applies at the final stage after finance.
    primary_approver_email = deputy_email
    cc_list = [e for e in [registrar_email, vc_email, finance_email] if e]
    pending_status = "pending_deputy_registrar_approval"

    # Primary addressee approves in-app; CC list is notification-only on this email.
    approval = ApprovalRequest(
        requester_id=str(user.id),
        requester_email=user.email,
        requested_to=primary_approver_email,
        event_name=payload.name,
        facilitator=payload.facilitator,
        description=payload.description,
        venue_name=payload.venue_name,
        intendedAudience=payload.intendedAudience,
        intendedAudienceOther=payload.intendedAudienceOther,
        discussedWithProgrammingChair=payload.discussedWithProgrammingChair,
        budget=payload.budget,
        start_date=payload.start_date.isoformat(),
        start_time=payload.start_time.isoformat(),
        end_date=payload.end_date.isoformat(),
        end_time=payload.end_time.isoformat(),
        requirements=[],
        other_notes=None,
        override_conflict=payload.override_conflict,
        approval_cc=cc_list,
        pipeline_stage="deputy",
    )
    await approval.insert()

    status_label = pending_status
    try:
        await notify_registrar_for_approval(user, primary_approver_email, approval, cc_emails=cc_list)
    except Exception as exc:
        logger.warning("Approval email notification failed approval_id=%s error=%s", str(approval.id), exc)
        status_label = f"{pending_status}_email_failed"

    response_body = EventCreateResponse(
        status=status_label,
        approval_request=serialize_approval(approval),
    )
    if idem_key:
        await store_response(idem_key, status.HTTP_201_CREATED, response_body.model_dump(mode="json"))
    return response_body


@router.post("/{event_id}/report", response_model=EventResponse)
@limiter.limit("30/minute")
async def upload_event_report(
    request: Request,
    event_id: str,
    file: UploadFile = File(...),
    attendance_file: Optional[UploadFile] = File(None),
    attendance_not_applicable: Optional[str] = Form(None),
    iqac_criterion: Optional[int] = Form(None),
    iqac_sub_folder: Optional[str] = Form(None),
    iqac_item: Optional[str] = Form(None),
    iqac_description: Optional[str] = Form(None),
    user: User = Depends(get_current_user),
):
    event = await Event.get(event_id)
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    if event.created_by != str(user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    await sync_event_status(event)
    if event.status != "completed":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Report can be uploaded only after the event is completed",
        )

    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only PDF files are allowed")
    if file.content_type not in {"application/pdf"}:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only PDF files are allowed")

    expected_name = get_expected_report_filename(event.name, event.start_date)
    if file.filename.strip() != expected_name:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Report filename must be exactly: {expected_name}",
        )

    contents = await file.read()
    max_size = 10 * 1024 * 1024
    if len(contents) > max_size:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File too large (max 10MB)")

    attendance_bytes: Optional[bytes] = None
    attendance_name: Optional[str] = None
    attendance_mime: Optional[str] = None
    if attendance_file is not None and (attendance_file.filename or "").strip():
        attendance_bytes, attendance_name, attendance_mime = await _read_validated_attendance_attachment(
            attendance_file
        )

    def _form_flag_truthy(value: Optional[str]) -> bool:
        return (value or "").strip().lower() in ("1", "true", "yes", "on")

    attendance_na = _form_flag_truthy(attendance_not_applicable)
    if attendance_na and attendance_bytes is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Remove the attendance file when 'Not applicable' is selected, or untick Not applicable.",
        )
    if not attendance_na:
        has_new_attendance = attendance_bytes is not None
        has_existing_attendance = bool(getattr(event, "attendance_file_id", None))
        if not has_new_attendance and not has_existing_attendance:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Upload an attendance file (PDF, Word, or Excel), or tick Not applicable.",
            )

    sub_s = (iqac_sub_folder or "").strip()
    item_s = (iqac_item or "").strip()
    iqac_requested = iqac_criterion is not None or bool(sub_s) or bool(item_s)
    iqac_sub_norm: Optional[str] = None
    iqac_item_norm: Optional[str] = None
    if iqac_requested:
        if iqac_criterion is None or not sub_s or not item_s:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="IQAC filing requires criterion, sub-criterion, and item together, or leave IQAC fields empty.",
            )
        role = (user.role or "").strip().lower()
        if role not in IQAC_ALLOWED_ROLES:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Your role cannot file documents under IQAC Data Collection.",
            )
        iqac_sub_norm, iqac_item_norm = validate_iqac_path(iqac_criterion, sub_s, item_s)

    folder_id = os.getenv("GOOGLE_DRIVE_FOLDER_ID", "")
    if not folder_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Google Drive folder not configured",
        )

    access_token = None
    drive_file = None
    drive_attendance = None
    try:
        access_token = await ensure_google_access_token(user)
        drive_file = upload_report_file(
            access_token=access_token,
            file_name=file.filename,
            file_bytes=contents,
            mime_type=file.content_type,
            folder_id=folder_id,
            replace_file_id=event.report_file_id,
        )
        if not attendance_na and attendance_bytes is not None and attendance_name and attendance_mime:
            drive_attendance = upload_report_file(
                access_token=access_token,
                file_name=attendance_name,
                file_bytes=attendance_bytes,
                mime_type=attendance_mime,
                folder_id=folder_id,
                replace_file_id=getattr(event, "attendance_file_id", None),
            )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(exc),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Unable to upload report: {exc}",
        )

    if iqac_requested and iqac_criterion is not None and iqac_sub_norm and iqac_item_norm:
        desc_bits = [f"Event report: {event.name} (event id {event.id})"]
        extra = (iqac_description or "").strip()
        if extra:
            desc_bits.append(extra)
        iqac_full_desc = " · ".join(desc_bits)
        try:
            await persist_iqac_upload(
                user,
                iqac_criterion,
                iqac_sub_norm,
                iqac_item_norm,
                file.filename or "Report.pdf",
                contents,
                iqac_full_desc,
            )
        except Exception as exc:
            if drive_file and drive_file.get("id") and access_token:
                delete_drive_file(access_token, drive_file.get("id"))
            if drive_attendance and drive_attendance.get("id") and access_token:
                delete_drive_file(access_token, drive_attendance.get("id"))
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Report was not saved: could not add a copy to IQAC Data Collection ({exc}).",
            ) from exc

    event.report_file_id = drive_file.get("id")
    event.report_file_name = drive_file.get("name")
    event.report_web_view_link = drive_file.get("webViewLink")
    event.report_uploaded_at = datetime.utcnow()
    if attendance_na:
        old_att_id = getattr(event, "attendance_file_id", None)
        if old_att_id and access_token:
            delete_drive_file(access_token, old_att_id)
        event.attendance_file_id = None
        event.attendance_file_name = None
        event.attendance_web_view_link = None
    elif drive_attendance:
        event.attendance_file_id = drive_attendance.get("id")
        event.attendance_file_name = drive_attendance.get("name")
        event.attendance_web_view_link = drive_attendance.get("webViewLink")
    await event.save()

    return serialize_event(event)


@router.patch("/{event_id}/status", response_model=EventResponse)
async def update_event_status(
    event_id: str,
    payload: EventStatusUpdate,
    user: User = Depends(get_current_user),
):
    event = await Event.get(event_id)
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    if event.created_by != str(user.id):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    normalized_status = (payload.status or "").strip().lower()
    if normalized_status != "closed":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid status")
    if event.status != "completed":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Event must be completed before closing",
        )
    if not event.report_file_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Upload a report before closing",
        )

    event.status = "closed"
    await event.save()

    # Close all workflow discussion threads tied to this event's approval
    try:
        from event_chat_service import close_all_threads_for_approval
        from models import ApprovalRequest as _AR
        _approval = await _AR.find_one({"event_id": str(event.id)})
        if _approval:
            await close_all_threads_for_approval(str(_approval.id), reason="event_closed")
    except Exception as _exc:
        logger.warning("close_all_threads_for_approval on event close failed: %s", _exc)

    return serialize_event(event)
