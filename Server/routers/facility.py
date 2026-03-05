from datetime import datetime
import re

from fastapi import APIRouter, Depends, HTTPException, status

from auth import get_primary_email_by_role
from models import ApprovalRequest, Event, FacilityManagerRequest, User
from routers.deps import get_current_user
from schemas import (
    FacilityManagerDecision,
    FacilityManagerRequestCreate,
    FacilityManagerRequestResponse,
)

router = APIRouter(prefix="/facility", tags=["Facility Manager"])


def normalize_time(value: str | None) -> str:
    if not value:
        return ""
    parts = value.split(":")
    return ":".join(parts[:2])


@router.post("/requests", response_model=FacilityManagerRequestResponse, status_code=status.HTTP_201_CREATED)
async def create_facility_request(
    payload: FacilityManagerRequestCreate,
    user: User = Depends(get_current_user),
):
    if not payload.event_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Facility request requires an approved event",
        )

    event = await Event.get(payload.event_id)
    if not event or event.created_by != str(user.id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Event not found",
        )

    approval = await ApprovalRequest.find_one(ApprovalRequest.event_id == str(event.id))
    if not approval or approval.status != "approved":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Registrar must approve the event before sending facility manager request",
        )

    requested_to = (payload.requested_to or "").strip().lower() or await get_primary_email_by_role("facility_manager")
    if not requested_to:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Facility manager email is required",
        )

    request_item = FacilityManagerRequest(
        requester_id=str(user.id),
        requester_email=user.email,
        requested_to=requested_to,
        event_id=payload.event_id,
        event_name=payload.event_name,
        start_date=payload.start_date,
        start_time=payload.start_time,
        end_date=payload.end_date,
        end_time=payload.end_time,
        venue_required=payload.venue_required,
        refreshments=payload.refreshments,
        other_notes=payload.other_notes,
    )
    await request_item.insert()

    return FacilityManagerRequestResponse(
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
        venue_required=request_item.venue_required,
        refreshments=request_item.refreshments,
        other_notes=request_item.other_notes,
        status=request_item.status,
        decided_at=request_item.decided_at,
        decided_by=request_item.decided_by,
        created_at=request_item.created_at,
    )


@router.get("/inbox", response_model=list[FacilityManagerRequestResponse])
async def list_facility_inbox(user: User = Depends(get_current_user)):
    requested_to = (user.email or "").strip().lower()
    regex = re.compile(f"^{re.escape(requested_to)}$", re.IGNORECASE)
    requests = await FacilityManagerRequest.find(
        {"requested_to": {"$regex": regex}}
    ).sort("-created_at").to_list()
    return [
        FacilityManagerRequestResponse(
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
            venue_required=item.venue_required,
            refreshments=item.refreshments,
            other_notes=item.other_notes,
            status=item.status,
            decided_at=item.decided_at,
            decided_by=item.decided_by,
            created_at=item.created_at,
        )
        for item in requests
    ]


@router.patch("/requests/{request_id}", response_model=FacilityManagerRequestResponse)
async def decide_facility_request(
    request_id: str,
    payload: FacilityManagerDecision,
    user: User = Depends(get_current_user),
):
    normalized_status = payload.status.strip().lower()
    if normalized_status not in {"approved", "rejected"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Status must be approved or rejected",
        )

    request_item = await FacilityManagerRequest.get(request_id)
    if not request_item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    approver_email = (user.email or "").strip().lower()
    if request_item.requested_to and request_item.requested_to.strip().lower() != approver_email:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    if request_item.status == "pending":
        request_item.status = normalized_status
        request_item.decided_by = user.email
        request_item.decided_at = datetime.utcnow()
        await request_item.save()

    return FacilityManagerRequestResponse(
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
        venue_required=request_item.venue_required,
        refreshments=request_item.refreshments,
        other_notes=request_item.other_notes,
        status=request_item.status,
        decided_at=request_item.decided_at,
        decided_by=request_item.decided_by,
        created_at=request_item.created_at,
    )


@router.get("/requests/me", response_model=list[FacilityManagerRequestResponse])
async def list_my_facility_requests(user: User = Depends(get_current_user)):
    requests = await FacilityManagerRequest.find(
        FacilityManagerRequest.requester_id == str(user.id)
    ).sort("-created_at").to_list()
    return [
        FacilityManagerRequestResponse(
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
            venue_required=item.venue_required,
            refreshments=item.refreshments,
            other_notes=item.other_notes,
            status=item.status,
            decided_at=item.decided_at,
            decided_by=item.decided_by,
            created_at=item.created_at,
        )
        for item in requests
    ]
