import logging
import re

from fastapi import APIRouter, Depends, HTTPException, status

from auth import get_primary_email_by_role
from decision_helpers import parse_requirement_decision_status, require_decision_comment
from event_status import event_has_started
from models import ApprovalRequest, Event, TransportRequest, User
from notifications import send_notification_email
from requirement_decision_service import apply_requirement_decision
from routers.deps import get_current_user
from schemas import TransportDecision, TransportRequestCreate, TransportRequestResponse

router = APIRouter(prefix="/transport", tags=["Transport"])
logger = logging.getLogger("event-booking.transport")


def _response(item: TransportRequest) -> TransportRequestResponse:
    return TransportRequestResponse(
        id=str(item.id),
        requester_id=item.requester_id,
        requester_email=item.requester_email,
        requested_to=item.requested_to,
        event_id=item.event_id,
        event_name=item.event_name,
        start_date=item.start_date,
        start_time=item.start_time,
        end_date=item.end_date,
        end_time=item.end_time,
        transport_type=item.transport_type,
        guest_pickup_location=item.guest_pickup_location,
        guest_pickup_date=item.guest_pickup_date,
        guest_pickup_time=item.guest_pickup_time,
        guest_dropoff_location=item.guest_dropoff_location,
        guest_dropoff_date=item.guest_dropoff_date,
        guest_dropoff_time=item.guest_dropoff_time,
        student_count=item.student_count,
        student_transport_kind=item.student_transport_kind,
        student_date=item.student_date,
        student_time=item.student_time,
        student_pickup_point=item.student_pickup_point,
        other_notes=item.other_notes,
        status=item.status,
        decided_at=item.decided_at,
        decided_by=item.decided_by,
        created_at=item.created_at,
    )


@router.post("/requests", response_model=TransportRequestResponse, status_code=status.HTTP_201_CREATED)
async def create_transport_request(
    payload: TransportRequestCreate,
    user: User = Depends(get_current_user),
):
    if not payload.event_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Transport request requires an approved event",
        )

    event = await Event.get(payload.event_id)
    if not event or event.created_by != str(user.id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found",
        )

    if event_has_started(event.start_date, event.start_time):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Event has already started; cannot send transport request.",
        )

    approval = await ApprovalRequest.find_one(ApprovalRequest.event_id == str(event.id))
    if not approval or approval.status != "approved":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registrar must approve the event before sending transport request",
        )

    requested_to = (payload.requested_to or "").strip().lower() or await get_primary_email_by_role("transport")
    if not requested_to:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Transport coordinator email is required",
        )

    request_item = TransportRequest(
        requester_id=str(user.id),
        requester_email=user.email,
        requested_to=requested_to,
        event_id=payload.event_id,
        event_name=payload.event_name,
        start_date=payload.start_date,
        start_time=payload.start_time,
        end_date=payload.end_date,
        end_time=payload.end_time,
        transport_type=payload.transport_type,
        guest_pickup_location=(payload.guest_pickup_location or "").strip() or None,
        guest_pickup_date=(payload.guest_pickup_date or "").strip() or None,
        guest_pickup_time=(payload.guest_pickup_time or "").strip() or None,
        guest_dropoff_location=(payload.guest_dropoff_location or "").strip() or None,
        guest_dropoff_date=(payload.guest_dropoff_date or "").strip() or None,
        guest_dropoff_time=(payload.guest_dropoff_time or "").strip() or None,
        student_count=payload.student_count,
        student_transport_kind=(payload.student_transport_kind or "").strip() or None,
        student_date=(payload.student_date or "").strip() or None,
        student_time=(payload.student_time or "").strip() or None,
        student_pickup_point=(payload.student_pickup_point or "").strip() or None,
        other_notes=(payload.other_notes or "").strip() or None,
    )
    await request_item.insert()

    subject = f"Transport Request: {request_item.event_name}"
    common_head = (
        f"Requester: {user.email}\n"
        f"Event: {request_item.event_name}\n"
        f"Event window: {request_item.start_date} {request_item.start_time} - "
        f"{request_item.end_date} {request_item.end_time}\n\n"
    )
    tt = request_item.transport_type
    if tt == "both":
        intro = "A new combined transport request (guest cab and student transport) has been submitted.\n\n"
    elif tt == "guest_cab":
        intro = "A new guest cab / transport request has been submitted.\n\n"
    else:
        intro = "A new student (off-campus) transport request has been submitted.\n\n"

    body = intro + common_head
    if tt in ("guest_cab", "both"):
        body += (
            "--- Guest cab ---\n"
            f"Pickup location: {request_item.guest_pickup_location}\n"
            f"Pickup: {request_item.guest_pickup_date} {request_item.guest_pickup_time}\n"
            f"Drop-off location: {request_item.guest_dropoff_location}\n"
            f"Drop-off: {request_item.guest_dropoff_date or '(same day)'} {request_item.guest_dropoff_time}\n"
        )
        if tt == "both":
            body += "\n"
    if tt in ("students_off_campus", "both"):
        body += (
            "--- Student transport ---\n"
            f"Number of students: {request_item.student_count}\n"
            f"Kind of transport: {request_item.student_transport_kind}\n"
            f"Date & time: {request_item.student_date} {request_item.student_time}\n"
            f"Pickup point: {request_item.student_pickup_point}\n"
        )
    if request_item.other_notes:
        body += f"\nAdditional notes: {request_item.other_notes}\n"
    body += "\nPlease approve or reject this request from your dashboard."
    await send_notification_email(
        recipient_email=requested_to,
        subject=subject,
        body=body,
        requester=user,
        fallback_role="transport",
    )

    return _response(request_item)


@router.get("/inbox", response_model=list[TransportRequestResponse])
async def list_transport_inbox(user: User = Depends(get_current_user)):
    requested_to = (user.email or "").strip().lower()
    regex = re.compile(f"^{re.escape(requested_to)}$", re.IGNORECASE)
    requests = await TransportRequest.find({"requested_to": {"$regex": regex}}).sort("-created_at").to_list()
    return [_response(item) for item in requests]


@router.patch("/requests/{request_id}", response_model=TransportRequestResponse)
async def decide_transport_request(
    request_id: str,
    payload: TransportDecision,
    user: User = Depends(get_current_user),
):
    comment = require_decision_comment(payload.comment)
    normalized_status = parse_requirement_decision_status(payload.status)

    request_item = await TransportRequest.get(request_id)
    if not request_item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    if event_has_started(request_item.start_date, request_item.start_time):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Event has already started; approval or rejection is no longer allowed.",
        )

    approver_email = (user.email or "").strip().lower()
    if request_item.requested_to and request_item.requested_to.strip().lower() != approver_email:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    await apply_requirement_decision(
        request_item,
        user=user,
        normalized_status=normalized_status,
        comment=comment,
        related_kind="transport_request",
        role="transport",
    )

    return _response(request_item)


@router.get("/requests/me", response_model=list[TransportRequestResponse])
async def list_my_transport_requests(user: User = Depends(get_current_user)):
    requests = await TransportRequest.find(TransportRequest.requester_id == str(user.id)).sort("-created_at").to_list()
    return [_response(item) for item in requests]
