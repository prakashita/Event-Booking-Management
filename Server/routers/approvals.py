from datetime import datetime
import re

from fastapi import APIRouter, Depends, HTTPException, status

from models import ApprovalRequest, Event, User
from routers.deps import get_current_user
from schemas import ApprovalDecision, ApprovalRequestResponse

router = APIRouter(prefix="/approvals", tags=["Approvals"])


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

    if approval.requested_to and approval.requested_to != user.email:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    if approval.status == "pending":
        if normalized_status == "approved":
            if not approval.event_id:
                event = Event(
                    name=approval.event_name,
                    facilitator=approval.facilitator,
                    description=approval.description,
                    venue_name=approval.venue_name,
                    start_date=approval.start_date,
                    start_time=approval.start_time,
                    end_date=approval.end_date,
                    end_time=approval.end_time,
                    created_by=approval.requester_id,
                )
                await event.insert()
                approval.event_id = str(event.id)
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
