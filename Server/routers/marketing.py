from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status

from models import MarketingRequest, User
from routers.deps import get_current_user
from schemas import MarketingDecision, MarketingRequestCreate, MarketingRequestResponse

router = APIRouter(prefix="/marketing", tags=["Marketing"])


@router.post("/requests", response_model=MarketingRequestResponse, status_code=status.HTTP_201_CREATED)
async def create_marketing_request(
    payload: MarketingRequestCreate,
    user: User = Depends(get_current_user),
):
    requested_to = (payload.requested_to or "").strip().lower()
    if not requested_to:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Marketing recipient is required",
        )

    request_item = MarketingRequest(
        requester_id=str(user.id),
        requester_email=user.email,
        requested_to=requested_to,
        event_name=payload.event_name,
        start_date=payload.start_date,
        start_time=payload.start_time,
        end_date=payload.end_date,
        end_time=payload.end_time,
        poster_required=payload.poster_required,
        poster_dimension=payload.poster_dimension,
        video_required=payload.video_required,
        video_dimension=payload.video_dimension,
        linkedin_post=payload.linkedin_post,
        photography=payload.photography,
        recording=payload.recording,
        other_notes=payload.other_notes,
    )
    await request_item.insert()

    return MarketingRequestResponse(
        id=str(request_item.id),
        requester_id=request_item.requester_id,
        requester_email=request_item.requester_email,
        requested_to=request_item.requested_to,
        event_name=request_item.event_name,
        start_date=request_item.start_date,
        start_time=request_item.start_time,
        end_date=request_item.end_date,
        end_time=request_item.end_time,
        poster_required=request_item.poster_required,
        poster_dimension=request_item.poster_dimension,
        video_required=request_item.video_required,
        video_dimension=request_item.video_dimension,
        linkedin_post=request_item.linkedin_post,
        photography=request_item.photography,
        recording=request_item.recording,
        other_notes=request_item.other_notes,
        status=request_item.status,
        decided_at=request_item.decided_at,
        decided_by=request_item.decided_by,
        created_at=request_item.created_at,
    )


@router.get("/inbox", response_model=list[MarketingRequestResponse])
async def list_marketing_inbox(user: User = Depends(get_current_user)):
    requested_to = (user.email or "").strip().lower()
    requests = await MarketingRequest.find(
        MarketingRequest.requested_to == requested_to
    ).sort("-created_at").to_list()
    return [
        MarketingRequestResponse(
            id=str(item.id),
            requester_id=item.requester_id,
            requester_email=item.requester_email,
            requested_to=item.requested_to,
            event_name=item.event_name,
            start_date=item.start_date,
            start_time=item.start_time,
            end_date=item.end_date,
            end_time=item.end_time,
            poster_required=item.poster_required,
            poster_dimension=item.poster_dimension,
            video_required=item.video_required,
            video_dimension=item.video_dimension,
            linkedin_post=item.linkedin_post,
            photography=item.photography,
            recording=item.recording,
            other_notes=item.other_notes,
            status=item.status,
            decided_at=item.decided_at,
            decided_by=item.decided_by,
            created_at=item.created_at,
        )
        for item in requests
    ]


@router.patch("/requests/{request_id}", response_model=MarketingRequestResponse)
async def decide_marketing_request(
    request_id: str,
    payload: MarketingDecision,
    user: User = Depends(get_current_user),
):
    normalized_status = payload.status.strip().lower()
    if normalized_status not in {"approved", "rejected"}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Status must be approved or rejected",
        )

    request_item = await MarketingRequest.get(request_id)
    if not request_item:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Request not found")

    if request_item.requested_to and request_item.requested_to != (user.email or "").strip().lower():
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not allowed")

    if request_item.status == "pending":
        request_item.status = normalized_status
        request_item.decided_by = user.email
        request_item.decided_at = datetime.utcnow()
        await request_item.save()

    return MarketingRequestResponse(
        id=str(request_item.id),
        requester_id=request_item.requester_id,
        requester_email=request_item.requester_email,
        requested_to=request_item.requested_to,
        event_name=request_item.event_name,
        start_date=request_item.start_date,
        start_time=request_item.start_time,
        end_date=request_item.end_date,
        end_time=request_item.end_time,
        poster_required=request_item.poster_required,
        poster_dimension=request_item.poster_dimension,
        video_required=request_item.video_required,
        video_dimension=request_item.video_dimension,
        linkedin_post=request_item.linkedin_post,
        photography=request_item.photography,
        recording=request_item.recording,
        other_notes=request_item.other_notes,
        status=request_item.status,
        decided_at=request_item.decided_at,
        decided_by=request_item.decided_by,
        created_at=request_item.created_at,
    )
