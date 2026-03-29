import os
import re
import base64
import logging
from datetime import datetime
from typing import Optional

from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Request, UploadFile, status

from rate_limit import limiter
from fastapi.responses import JSONResponse
import requests

from auth import ensure_google_access_token, get_primary_email_by_role, get_user_by_role
from drive import delete_drive_file, upload_report_file
from errors import error_payload
from idempotency import get_cached_response, get_idempotency_key, store_response
from event_status import combine_datetime, sync_event_status
from models import ApprovalRequest, Event, FacilityManagerRequest, ItRequest, MarketingRequest, User
from routers.admin import serialize_approval, serialize_event, serialize_facility, serialize_it, serialize_marketing
from routers.deps import IQAC_ALLOWED_ROLES, get_current_user
from routers.iqac import persist_iqac_upload, validate_iqac_path
from schemas import (
    ApprovalRequestResponse,
    EventCreate,
    EventCreateResponse,
    EventDetailsResponse,
    EventResponse,
    EventStatusUpdate,
    FacilityManagerRequestResponse,
    ItRequestResponse,
    MarketingRequestResponse,
    PaginatedResponse,
)

router = APIRouter(prefix="/events", tags=["Events"])
logger = logging.getLogger("event-booking.events")


def _requirement_status_for_event_details(
    row: FacilityManagerRequestResponse | MarketingRequestResponse | ItRequestResponse,
) -> FacilityManagerRequestResponse | MarketingRequestResponse | ItRequestResponse:
    """Event details UI shows 'accepted' for facility/marketing/IT; registrar stays 'approved'."""
    if (row.status or "").strip() == "approved":
        return row.model_copy(update={"status": "accepted"})
    return row


# Report filename format: {SanitizedEventName}_{StartDate}_Report.pdf
REPORT_FILENAME_SUFFIX = "_Report.pdf"


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


async def sync_event_to_google_calendar(event: Event, user: User) -> None:
    if not user.google_refresh_token:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Connect Google Calendar to create events",
        )

    access_token = await ensure_google_access_token(user)
    time_zone = os.getenv("DEFAULT_TIMEZONE", "Asia/Kolkata")
    payload = {
        "summary": event.name,
        "description": event.description or "",
        "location": event.venue_name,
        "start": {"dateTime": f"{event.start_date}T{event.start_time}", "timeZone": time_zone},
        "end": {"dateTime": f"{event.end_date}T{event.end_time}", "timeZone": time_zone},
    }
    response = requests.post(
        "https://www.googleapis.com/calendar/v3/calendars/primary/events",
        headers={"Authorization": f"Bearer {access_token}"},
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


def _build_raw_email(to_email: str, subject: str, body: str) -> str:
    headers = [
        f"To: {to_email}",
        f"Subject: {subject}",
        "Content-Type: text/plain; charset=\"UTF-8\"",
    ]
    return "\r\n".join(headers) + "\r\n\r\n" + body


async def notify_registrar_for_approval(
    requester: User,
    registrar_email: str,
    approval: ApprovalRequest,
) -> None:
    """Send email to registrar when a new event requires approval. Uses registrar's Gmail first, then requester's."""
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
    raw_message = _build_raw_email(registrar_email, subject, body)
    encoded_message = base64.urlsafe_b64encode(raw_message.encode("utf-8")).decode("utf-8")

    # Try registrar's Gmail first (they usually have it connected for approvals), then requester's
    access_token = None
    for sender_user in [await get_user_by_role("registrar"), requester]:
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
            detail="Unable to send registrar notification: registrar or requester must connect Google.",
        )

    response = requests.post(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"raw": encoded_message},
        timeout=15,
    )
    if response.status_code not in {200, 202}:
        detail = "Unable to send registrar notification email"
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
        items=[
    EventResponse(
        id=str(event.id),
        name=event.name,
        facilitator=event.facilitator,
        description=event.description,
        venue_name=event.venue_name,
        intendedAudience=getattr(event, "intendedAudience", None),
        budget=getattr(event, "budget", None),
        start_date=event.start_date,
        start_time=event.start_time,
        end_date=event.end_date,
        end_time=event.end_time,
        created_by=event.created_by,
        status=event.status,
        google_event_id=event.google_event_id,
        google_event_link=event.google_event_link,
        report_file_id=event.report_file_id,
        report_file_name=event.report_file_name,
        report_web_view_link=event.report_web_view_link,
        report_uploaded_at=event.report_uploaded_at,
        created_at=event.created_at,
    )
    for event in events
],
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
        if approval.requester_id != str(user.id):
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed to view this event")

        if not approval.event_id:
            return EventDetailsResponse(
                event=EventResponse(
                    id=event_id,
                    name=approval.event_name,
                    facilitator=approval.facilitator,
                    description=approval.description,
                    venue_name=approval.venue_name,
                    intendedAudience=getattr(approval, "intendedAudience", None),
                    budget=getattr(approval, "budget", None),
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
                    created_at=approval.created_at,
                ),
                approval_request=serialize_approval(approval),
                facility_requests=[],
                marketing_requests=[],
                it_requests=[],
            )

        event_id = approval.event_id

    try:
        event_object_id = PydanticObjectId(event_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")

    event = await Event.get(event_object_id)
    if not event:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Event not found")
    if event.created_by != str(user.id):
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

    existing_events = await Event.find_all().to_list()
    conflicts = []
    for existing in existing_events:
        existing_start = combine_datetime(existing.start_date, existing.start_time)
        existing_end = combine_datetime(existing.end_date, existing.end_time)
        if (
            existing.venue_name == payload.venue_name
            and start_dt < existing_end
            and end_dt > existing_start
        ):
            conflicts.append(serialize_conflict(existing))

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
        existing_events = await Event.find_all().to_list()
        conflicts = []
        for existing in existing_events:
            existing_start = combine_datetime(existing.start_date, existing.start_time)
            existing_end = combine_datetime(existing.end_date, existing.end_time)
            if (
                existing.venue_name == payload.venue_name
                and start_dt < existing_end
                and end_dt > existing_start
            ):
                conflicts.append(serialize_conflict(existing))

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

    registrar_email = await get_primary_email_by_role("registrar")
    if not registrar_email:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Registrar email is not configured",
        )

    # Registrar receives only event details for approve/reject. Requirements (venue, refreshments)
    # go to Facility Manager after approval.
    approval = ApprovalRequest(
        requester_id=str(user.id),
        requester_email=user.email,
        requested_to=registrar_email,
        event_name=payload.name,
        facilitator=payload.facilitator,
        description=payload.description,
        venue_name=payload.venue_name,
        intendedAudience=payload.intendedAudience,
        budget=payload.budget,
        start_date=payload.start_date.isoformat(),
        start_time=payload.start_time.isoformat(),
        end_date=payload.end_date.isoformat(),
        end_time=payload.end_time.isoformat(),
        requirements=[],
        other_notes=None,
        override_conflict=payload.override_conflict,
    )
    await approval.insert()

    status_label = "pending_registrar_approval"
    try:
        await notify_registrar_for_approval(user, registrar_email, approval)
    except Exception as exc:
        logger.warning("Registrar email notification failed approval_id=%s error=%s", str(approval.id), exc)
        status_label = "pending_registrar_approval_email_failed"

    response_body = EventCreateResponse(
        status=status_label,
        approval_request=ApprovalRequestResponse(
            id=str(approval.id),
            status=approval.status,
            requester_id=approval.requester_id,
            requester_email=approval.requester_email,
            requested_to=approval.requested_to,
            event_name=approval.event_name,
            facilitator=approval.facilitator,
            budget=getattr(approval, "budget", None),
            description=approval.description,
            venue_name=approval.venue_name,
            intendedAudience=getattr(approval, "intendedAudience", None),
            start_date=approval.start_date,
            start_time=approval.start_time,
            end_date=approval.end_date,
            end_time=approval.end_time,
            requirements=approval.requirements,
            other_notes=approval.other_notes,
            event_id=approval.event_id,
            decided_at=approval.decided_at,
            decided_by=approval.decided_by,
            created_at=approval.created_at,
        ),
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
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Report was not saved: could not add a copy to IQAC Data Collection ({exc}).",
            ) from exc

    event.report_file_id = drive_file.get("id")
    event.report_file_name = drive_file.get("name")
    event.report_web_view_link = drive_file.get("webViewLink")
    event.report_uploaded_at = datetime.utcnow()
    await event.save()

    return EventResponse(
        id=str(event.id),
        name=event.name,
        facilitator=event.facilitator,
        description=event.description,
        venue_name=event.venue_name,
        intendedAudience=getattr(event, "intendedAudience", None),
        budget=getattr(event, "budget", None),
        start_date=event.start_date,
        start_time=event.start_time,
        end_date=event.end_date,
        end_time=event.end_time,
        created_by=event.created_by,
        status=event.status,
        google_event_id=event.google_event_id,
        google_event_link=event.google_event_link,
        report_file_id=event.report_file_id,
        report_file_name=event.report_file_name,
        report_web_view_link=event.report_web_view_link,
        report_uploaded_at=event.report_uploaded_at,
        created_at=event.created_at,
    )


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
    return EventResponse(
        id=str(event.id),
        name=event.name,
        facilitator=event.facilitator,
        description=event.description,
        venue_name=event.venue_name,
        intendedAudience=getattr(event, "intendedAudience", None),
        budget=getattr(event, "budget", None),
        start_date=event.start_date,
        start_time=event.start_time,
        end_date=event.end_date,
        end_time=event.end_time,
        created_by=event.created_by,
        status=event.status,
        google_event_id=event.google_event_id,
        google_event_link=event.google_event_link,
        report_file_id=event.report_file_id,
        report_file_name=event.report_file_name,
        report_web_view_link=event.report_web_view_link,
        report_uploaded_at=event.report_uploaded_at,
        created_at=event.created_at,
    )
