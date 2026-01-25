from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status

from models import ItRequest, User
from routers.deps import get_current_user
from schemas import ItDecision, ItRequestCreate, ItRequestResponse

router = APIRouter(prefix="/it", tags=["IT"])


@router.post("/requests", response_model=ItRequestResponse, status_code=status.HTTP_201_CREATED)
async def create_it_request(
    payload: ItRequestCreate,
    user: User = Depends(get_current_user),
):
    requested_to = (payload.requested_to or "").strip().lower()
    if not requested_to:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="IT recipient is required",
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
        pa_system=payload.pa_system,
        projection=payload.projection,
        other_notes=payload.other_notes,
    )
    await request_item.insert()

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
    requests = await ItRequest.find(
        ItRequest.requested_to == requested_to
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
    normalized_status = payload.status.strip().lower()
    if normalized_status not in {"approved", "rejected"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Status must be approved or rejected",
        )

    request_item = await ItRequest.get(request_id)
    if not request_item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    if request_item.requested_to and request_item.requested_to != (user.email or "").strip().lower():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    if request_item.status == "pending":
        request_item.status = normalized_status
        request_item.decided_by = user.email
        request_item.decided_at = datetime.utcnow()
        await request_item.save()

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
