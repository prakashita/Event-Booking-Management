import base64
import logging
import re
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
import requests

from auth import ensure_google_access_token
from models import ApprovalRequest, Event, FacilityManagerRequest, ItRequest, MarketingRequest, User
from event_status import combine_datetime, compute_event_status, event_has_started
from routers.deps import get_current_user
from routers.events import sync_event_to_google_calendar
from schemas import ApprovalDecision, ApprovalRequestResponse

router = APIRouter(prefix="/approvals", tags=["Approvals"])
logger = logging.getLogger("event-booking.approvals")


def _build_raw_email(to_email: str, subject: str, body: str) -> str:
    headers = [
        f"To: {to_email}",
        f"Subject: {subject}",
        "Content-Type: text/plain; charset=\"UTF-8\"",
    ]
    return "\r\n".join(headers) + "\r\n\r\n" + body


async def notify_requester_on_approval(
    approver: User,
    requester_email: str,
    event_name: str,
    event_id: str,
) -> None:
    """Send email to requester when registrar approves their event."""
    try:
        access_token = await ensure_google_access_token(approver)
    except HTTPException:
        logger.warning("Cannot notify requester: approver Google token not available")
        return
    subject = f"Event Approved: {event_name}"
    body = (
        f"Your event \"{event_name}\" has been approved by the registrar.\n\n"
        "The event is now active. Please log in to the Event Booking portal and "
        "submit your requirements to the Facility Manager, IT, and Marketing teams."
    )
    raw_message = _build_raw_email(requester_email, subject, body)
    encoded_message = base64.urlsafe_b64encode(raw_message.encode("utf-8")).decode("utf-8")
    response = requests.post(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        headers={"Authorization": f"Bearer {access_token}"},
        json={"raw": encoded_message},
        timeout=15,
    )
    if response.status_code not in {200, 202}:
        logger.warning("Failed to notify requester of approval: %s", response.text)


def normalize_time(value: str | None) -> str:
    if not value:
        return ""
    parts = value.split(":")
    return ":".join(parts[:2])


@router.get("/me", response_model=list[ApprovalRequestResponse])
async def list_my_requests(user: User = Depends(get_current_user)):
    requests = await ApprovalRequest.find(
        ApprovalRequest.requester_id == str(user.id)
    ).sort("-created_at").to_list()
    return [
        ApprovalRequestResponse(
            id=str(item.id),
            status=item.status,
            requester_id=item.requester_id,
            requester_email=item.requester_email,
            requested_to=item.requested_to,
            event_name=item.event_name,
            facilitator=item.facilitator,
            budget=getattr(item, "budget", None),
            description=item.description,
            venue_name=item.venue_name,
            start_date=item.start_date,
            start_time=item.start_time,
            end_date=item.end_date,
            end_time=item.end_time,
            requirements=item.requirements,
            other_notes=item.other_notes,
            event_id=item.event_id,
            decided_at=item.decided_at,
            decided_by=item.decided_by,
            created_at=item.created_at,
        )
        for item in requests
    ]


@router.get("/inbox", response_model=list[ApprovalRequestResponse])
async def list_inbox(user: User = Depends(get_current_user)):
    email = (user.email or "").strip()
    regex = re.compile(f"^{re.escape(email)}$", re.IGNORECASE)
    requests = await ApprovalRequest.find(
        {"requested_to": {"$regex": regex}}
    ).sort("-created_at").to_list()
    return [
        ApprovalRequestResponse(
            id=str(item.id),
            status=item.status,
            requester_id=item.requester_id,
            requester_email=item.requester_email,
            requested_to=item.requested_to,
            event_name=item.event_name,
            facilitator=item.facilitator,
            budget=getattr(item, "budget", None),
            description=item.description,
            venue_name=item.venue_name,
            start_date=item.start_date,
            start_time=item.start_time,
            end_date=item.end_date,
            end_time=item.end_time,
            requirements=item.requirements,
            other_notes=item.other_notes,
            event_id=item.event_id,
            decided_at=item.decided_at,
            decided_by=item.decided_by,
            created_at=item.created_at,
        )
        for item in requests
    ]


@router.patch("/{request_id}", response_model=ApprovalRequestResponse)
async def decide_request(
    request_id: str,
    payload: ApprovalDecision,
    user: User = Depends(get_current_user),
):
    normalized_status = payload.status.strip().lower()
    if normalized_status not in {"approved", "rejected"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Status must be approved or rejected",
        )

    approval = await ApprovalRequest.get(request_id)
    if not approval:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    if event_has_started(approval.start_date, approval.start_time):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Event has already started; approval or rejection is no longer allowed.",
        )

    approver_email = (user.email or "").strip().lower()
    if approval.requested_to and approval.requested_to.strip().lower() != approver_email:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    if approval.status == "pending":
        if normalized_status == "approved":
            if not approval.event_id:
                start_dt = combine_datetime(approval.start_date, approval.start_time)
                end_dt = combine_datetime(approval.end_date, approval.end_time)
                if end_dt < start_dt:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="End datetime must be after start datetime",
                    )
                if not getattr(approval, "override_conflict", False):
                    existing_events = await Event.find_all().to_list()
                    for existing in existing_events:
                        existing_start = combine_datetime(existing.start_date, existing.start_time)
                        existing_end = combine_datetime(existing.end_date, existing.end_time)
                        if start_dt < existing_end and end_dt > existing_start and existing.venue_name == approval.venue_name:
                            raise HTTPException(
                                status_code=status.HTTP_409_CONFLICT,
                                detail="Schedule conflict detected for the venue",
                            )
                event = Event(
                    name=approval.event_name,
                    facilitator=approval.facilitator,
                    description=approval.description,
                    venue_name=approval.venue_name,
                    budget=getattr(approval, "budget", None),
                    start_date=approval.start_date,
                    start_time=approval.start_time,
                    end_date=approval.end_date,
                    end_time=approval.end_time,
                    created_by=approval.requester_id,
                    status=compute_event_status(start_dt, end_dt),
                )
                await event.insert()
                requester = await User.get(approval.requester_id)
                if not requester:
                    await event.delete()
                    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Requester not found")
                try:
                    await sync_event_to_google_calendar(event, requester)
                except (HTTPException, Exception) as exc:
                    logger.warning(
                        "Google Calendar sync skipped for approved event %s: %s",
                        event.name,
                        exc,
                    )
                    # Proceed without calendar sync; event is created, requester can sync later

                approval.event_id = str(event.id)
                matching_query = {
                    "requester_id": approval.requester_id,
                    "event_name": approval.event_name,
                    "start_date": approval.start_date,
                    "end_date": approval.end_date,
                    "event_id": None,
                }
                approval_start = normalize_time(approval.start_time)
                approval_end = normalize_time(approval.end_time)

                facility_requests = await FacilityManagerRequest.find(matching_query).to_list()
                for request_item in facility_requests:
                    if (
                        normalize_time(request_item.start_time) == approval_start
                        and normalize_time(request_item.end_time) == approval_end
                    ):
                        request_item.event_id = approval.event_id
                        await request_item.save()

                marketing_requests = await MarketingRequest.find(matching_query).to_list()
                for request_item in marketing_requests:
                    if (
                        normalize_time(request_item.start_time) == approval_start
                        and normalize_time(request_item.end_time) == approval_end
                    ):
                        request_item.event_id = approval.event_id
                        await request_item.save()

                it_requests = await ItRequest.find(matching_query).to_list()
                for request_item in it_requests:
                    if (
                        normalize_time(request_item.start_time) == approval_start
                        and normalize_time(request_item.end_time) == approval_end
                    ):
                        request_item.event_id = approval.event_id
                        await request_item.save()

                try:
                    await notify_requester_on_approval(
                        user, requester.email, event.name, str(event.id)
                    )
                except Exception as exc:
                    logger.warning("Requester approval notification failed: %s", exc)
            approval.status = "approved"
        else:
            approval.status = "rejected"
        approval.decided_by = user.email
        approval.decided_at = datetime.utcnow()
        await approval.save()

    return ApprovalRequestResponse(
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
    )
