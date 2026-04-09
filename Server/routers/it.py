import re

from fastapi import APIRouter, Depends, HTTPException, status

from auth import get_primary_email_by_role
from event_status import event_has_started
from models import ApprovalRequest, Event, ItRequest, User
from notifications import send_notification_email
from routers.deps import get_current_user
from decision_helpers import parse_requirement_decision_status, requirement_decision_comment
from requirement_decision_service import apply_requirement_decision
from schemas import ItDecision, ItRequestCreate, ItRequestResponse

router = APIRouter(prefix="/it", tags=["IT"])


@router.post("/requests", response_model=ItRequestResponse, status_code=status.HTTP_201_CREATED)
async def create_it_request(
    payload: ItRequestCreate,
    user: User = Depends(get_current_user),
):
    if not payload.event_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="IT request requires an approved event",
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
            detail="Event has already started; cannot send IT request.",
        )

    approval = await ApprovalRequest.find_one(ApprovalRequest.event_id == str(event.id))
    if not approval or approval.status != "approved":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registrar must approve the event before sending IT request",
        )

    requested_to = (payload.requested_to or "").strip().lower() or await get_primary_email_by_role("it")
    if not requested_to:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="IT email is required",
        )

    request_item = ItRequest(
        requester_id=str(user.id),
        requester_email=user.email,
        requested_to=requested_to,
        event_id=payload.event_id,
        event_name=payload.event_name,
        start_date=payload.start_date,
        start_time=payload.start_time,
        end_date=payload.end_date,
        end_time=payload.end_time,
        event_mode=payload.event_mode,
        pa_system=payload.pa_system,
        projection=payload.projection,
        other_notes=payload.other_notes,
    )
    await request_item.insert()

    # Ensure a discussion thread exists between faculty and IT
    try:
        ar_for_event = await ApprovalRequest.find_one(ApprovalRequest.event_id == payload.event_id)
        if ar_for_event:
            from event_chat_service import ensure_dept_request_thread
            await ensure_dept_request_thread(
                approval_request_id=str(ar_for_event.id),
                department="it",
                faculty_user_id=str(user.id),
                dept_email=requested_to,
                related_request_id=str(request_item.id),
                related_kind="it_request",
                event_name=request_item.event_name,
            )
    except Exception:
        pass

    subject = f"IT Request: {request_item.event_name}"
    event_mode_line = f"Event mode: {request_item.event_mode}\n" if request_item.event_mode else ""
    body = (
        f"A new IT request has been submitted for your approval.\n\n"
        f"Requester: {user.email}\n"
        f"Event: {request_item.event_name}\n"
        f"Date: {request_item.start_date} {request_item.start_time} - {request_item.end_date} {request_item.end_time}\n"
        f"{event_mode_line}"
        f"PA system: {'Yes' if request_item.pa_system else 'No'}\n"
        f"Projection: {'Yes' if request_item.projection else 'No'}\n"
    )
    if request_item.other_notes:
        body += f"\nAdditional notes: {request_item.other_notes}\n"
    body += "\nPlease approve or reject this request from your dashboard."
    await send_notification_email(
        recipient_email=requested_to,
        subject=subject,
        body=body,
        requester=user,
        fallback_role="it",
    )

    return ItRequestResponse(
        id=str(request_item.id),
        requester_id=request_item.requester_id,
        requester_email=request_item.requester_email,
        requested_to=request_item.requested_to,
        event_id=request_item.event_id,
        event_name=request_item.event_name,
        start_date=request_item.start_date,
        start_time=request_item.start_time,
        end_date=request_item.end_date,
        end_time=request_item.end_time,
        event_mode=getattr(request_item, "event_mode", None),
        pa_system=request_item.pa_system,
        projection=request_item.projection,
        other_notes=request_item.other_notes,
        status=request_item.status,
        decided_at=request_item.decided_at,
        decided_by=request_item.decided_by,
        created_at=request_item.created_at,
    )


@router.get("/inbox", response_model=list[ItRequestResponse])
async def list_it_inbox(user: User = Depends(get_current_user)):
    requested_to = (user.email or "").strip().lower()
    regex = re.compile(f"^{re.escape(requested_to)}$", re.IGNORECASE)
    requests = await ItRequest.find(
        {"requested_to": {"$regex": regex}}
    ).sort("-created_at").to_list()
    return [
        ItRequestResponse(
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
            event_mode=getattr(item, "event_mode", None),
            pa_system=item.pa_system,
            projection=item.projection,
            other_notes=item.other_notes,
            status=item.status,
            decided_at=item.decided_at,
            decided_by=item.decided_by,
            created_at=item.created_at,
        )
        for item in requests
    ]


@router.patch("/requests/{request_id}", response_model=ItRequestResponse)
async def decide_it_request(
    request_id: str,
    payload: ItDecision,
    user: User = Depends(get_current_user),
):
    normalized_status = parse_requirement_decision_status(payload.status)
    comment = requirement_decision_comment(normalized_status, payload.comment)

    request_item = await ItRequest.get(request_id)
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
        related_kind="it_request",
        role="it",
    )

    return ItRequestResponse(
        id=str(request_item.id),
        requester_id=request_item.requester_id,
        requester_email=request_item.requester_email,
        requested_to=request_item.requested_to,
        event_id=request_item.event_id,
        event_name=request_item.event_name,
        start_date=request_item.start_date,
        start_time=request_item.start_time,
        end_date=request_item.end_date,
        end_time=request_item.end_time,
        event_mode=getattr(request_item, "event_mode", None),
        pa_system=request_item.pa_system,
        projection=request_item.projection,
        other_notes=request_item.other_notes,
        status=request_item.status,
        decided_at=request_item.decided_at,
        decided_by=request_item.decided_by,
        created_at=request_item.created_at,
    )


@router.get("/requests/me", response_model=list[ItRequestResponse])
async def list_my_it_requests(user: User = Depends(get_current_user)):
    requests = await ItRequest.find(
        ItRequest.requester_id == str(user.id)
    ).sort("-created_at").to_list()
    return [
        ItRequestResponse(
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
            event_mode=getattr(item, "event_mode", None),
            pa_system=item.pa_system,
            projection=item.projection,
            other_notes=item.other_notes,
            status=item.status,
            decided_at=item.decided_at,
            decided_by=item.decided_by,
            created_at=item.created_at,
        )
        for item in requests
    ]
