import os
from datetime import datetime

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import JSONResponse
import requests

from auth import ensure_google_access_token
from drive import upload_report_file
from event_status import compute_event_status, sync_event_status
from models import ApprovalRequest, Event, User
from routers.deps import get_current_user
from schemas import ApprovalRequestResponse, EventCreate, EventCreateResponse, EventResponse, EventStatusUpdate

router = APIRouter(prefix="/events", tags=["Events"])


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

def combine_datetime(date_value: str, time_value: str) -> datetime:
    return datetime.fromisoformat(f"{date_value}T{time_value}")


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

@router.get("", response_model=list[EventResponse])
async def list_events(user: User = Depends(get_current_user)):
    events = await Event.find(Event.created_by == str(user.id)).sort("-created_at").to_list()
    for event in events:
        await sync_event_status(event)
    return [
    EventResponse(
        id=str(event.id),
        name=event.name,
        facilitator=event.facilitator,
        description=event.description,
        venue_name=event.venue_name,
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
]


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
        if start_dt < existing_end and end_dt > existing_start:
            conflicts.append(serialize_conflict(existing))

    return {"conflicts": conflicts}


@router.post("", response_model=EventCreateResponse, status_code=status.HTTP_201_CREATED)
async def create_event(payload: EventCreate, user: User = Depends(get_current_user)):
    start_dt = datetime.combine(payload.start_date, payload.start_time)
    end_dt = datetime.combine(payload.end_date, payload.end_time)
    if end_dt < start_dt:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="End datetime must be after start datetime",
        )

    if payload.submit_for_approval:
        approval_to = (payload.approval_to or "").strip().lower()
        if not approval_to:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Approval recipient is required",
            )
        approval = ApprovalRequest(
            requester_id=str(user.id),
            requester_email=user.email,
            requested_to=approval_to,
            event_name=payload.name,
            facilitator=payload.facilitator,
            description=payload.description,
            venue_name=payload.venue_name,
            start_date=payload.start_date.isoformat(),
            start_time=payload.start_time.isoformat(),
            end_date=payload.end_date.isoformat(),
            end_time=payload.end_time.isoformat(),
            requirements=payload.requirements,
            other_notes=payload.other_notes,
        )
        await approval.insert()
        return EventCreateResponse(
            status="pending_approval",
            approval_request=ApprovalRequestResponse(
                id=str(approval.id),
                status=approval.status,
                requester_id=approval.requester_id,
                requester_email=approval.requester_email,
                requested_to=approval.requested_to,
                event_name=approval.event_name,
                facilitator=approval.facilitator,
                description=approval.description,
                venue_name=approval.venue_name,
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

    if not payload.override_conflict:
        existing_events = await Event.find_all().to_list()
        conflicts = []
        for existing in existing_events:
            existing_start = combine_datetime(existing.start_date, existing.start_time)
            existing_end = combine_datetime(existing.end_date, existing.end_time)
            if start_dt < existing_end and end_dt > existing_start:
                conflicts.append(serialize_conflict(existing))

        if conflicts:
            return JSONResponse(
                status_code=status.HTTP_409_CONFLICT,
                content={
                    "detail": "Schedule conflict detected",
                    "conflicts": conflicts,
                },
            )

    event = Event(
        name=payload.name,
        facilitator=payload.facilitator,
        description=payload.description,
        venue_name=payload.venue_name,
        start_date=payload.start_date.isoformat(),
        start_time=payload.start_time.isoformat(),
        end_date=payload.end_date.isoformat(),
        end_time=payload.end_time.isoformat(),
        created_by=str(user.id),
        status=compute_event_status(start_dt, end_dt),
    )
    await event.insert()

    try:
        await sync_event_to_google_calendar(event, user)
    except HTTPException:
        await event.delete()
        raise
    except Exception as exc:
        await event.delete()
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Unable to sync event to Google Calendar: {exc}",
        )

    return EventCreateResponse(
        status="created",
        event=EventResponse(
            id=str(event.id),
            name=event.name,
            facilitator=event.facilitator,
            description=event.description,
            venue_name=event.venue_name,
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
        ),
    )


@router.post("/{event_id}/report", response_model=EventResponse)
async def upload_event_report(
    event_id: str,
    file: UploadFile = File(...),
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

    contents = await file.read()
    max_size = 10 * 1024 * 1024
    if len(contents) > max_size:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="File too large (max 10MB)")

    folder_id = os.getenv("GOOGLE_DRIVE_FOLDER_ID", "")
    if not folder_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Google Drive folder not configured",
        )

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
