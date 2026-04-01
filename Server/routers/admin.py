from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query

from models import ApprovalRequest, Event, FacilityManagerRequest, Invite, ItRequest, MarketingRequest, Publication, TransportRequest, User, Venue
from routers.deps import require_admin
from schemas import (
    ApprovalRequestResponse,
    EventResponse,
    FacilityManagerRequestResponse,
    InviteResponse,
    ItRequestResponse,
    MarketingDeliverableResponse,
    MarketingRequestResponse,
    PaginatedResponse,
    PublicationResponse,
    TransportRequestResponse,
    VenueResponse,
)

router = APIRouter(prefix="/admin", tags=["Admin"])

DEFAULT_LIMIT = 50
MAX_LIMIT = 100


def serialize_event(event: Event) -> EventResponse:
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
        budget_breakdown_file_id=getattr(event, "budget_breakdown_file_id", None),
        budget_breakdown_file_name=getattr(event, "budget_breakdown_file_name", None),
        budget_breakdown_web_view_link=getattr(event, "budget_breakdown_web_view_link", None),
        budget_breakdown_uploaded_at=getattr(event, "budget_breakdown_uploaded_at", None),
        report_file_id=event.report_file_id,
        report_file_name=event.report_file_name,
        report_web_view_link=event.report_web_view_link,
        report_uploaded_at=event.report_uploaded_at,
        created_at=event.created_at,
    )


def serialize_approval(item: ApprovalRequest) -> ApprovalRequestResponse:
    return ApprovalRequestResponse(
        id=str(item.id),
        status=item.status,
        requester_id=item.requester_id,
        requester_email=item.requester_email,
        requested_to=item.requested_to,
        event_name=item.event_name,
        facilitator=item.facilitator,
        budget=getattr(item, "budget", None),
        budget_breakdown_file_id=getattr(item, "budget_breakdown_file_id", None),
        budget_breakdown_file_name=getattr(item, "budget_breakdown_file_name", None),
        budget_breakdown_web_view_link=getattr(item, "budget_breakdown_web_view_link", None),
        budget_breakdown_uploaded_at=getattr(item, "budget_breakdown_uploaded_at", None),
        description=item.description,
        venue_name=item.venue_name,
        intendedAudience=getattr(item, "intendedAudience", None),
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


def _deliverable_to_response(d):
    if isinstance(d, dict):
        file_id = d.get("file_id")
        is_na = d.get("is_na", False)
        if not file_id and not is_na:
            return None
        file_id = file_id or "na"
        return MarketingDeliverableResponse(
            deliverable_type=d.get("deliverable_type", "other"),
            file_id=file_id,
            file_name=d.get("file_name", "N/A" if is_na else ""),
            web_view_link=d.get("web_view_link"),
            uploaded_at=d.get("uploaded_at") or datetime.utcnow(),
            is_na=is_na,
        )
    file_id = getattr(d, "file_id", None)
    is_na = getattr(d, "is_na", False)
    if not file_id and not is_na:
        return None
    file_id = file_id or "na"
    return MarketingDeliverableResponse(
        deliverable_type=getattr(d, "deliverable_type", "other"),
        file_id=file_id,
        file_name=getattr(d, "file_name", "N/A" if is_na else ""),
        web_view_link=getattr(d, "web_view_link", None),
        uploaded_at=getattr(d, "uploaded_at", None) or datetime.utcnow(),
        is_na=is_na,
    )


def _as_bool(value) -> bool:
    return bool(value) if value is not None else False


def _nested_flag(raw, section: str, key: str) -> bool:
    if raw is None:
        return False
    section_obj = raw.get(section) if isinstance(raw, dict) else getattr(raw, section, None)
    if section_obj is None:
        return False
    return _as_bool(section_obj.get(key) if isinstance(section_obj, dict) else getattr(section_obj, key, False))


def _normalize_marketing_requirements(item: MarketingRequest):
    raw = getattr(item, "marketing_requirements", None)
    normalized = {
        "pre_event": {
            "poster": _nested_flag(raw, "pre_event", "poster") or _as_bool(getattr(item, "poster_required", False)),
            "social_media": _nested_flag(raw, "pre_event", "social_media") or _as_bool(getattr(item, "linkedin_post", False)),
        },
        "during_event": {
            "photo": _nested_flag(raw, "during_event", "photo") or _as_bool(getattr(item, "photography", False)),
            "video": _nested_flag(raw, "during_event", "video") or _as_bool(getattr(item, "video_required", False)),
        },
        "post_event": {
            "social_media": _nested_flag(raw, "post_event", "social_media"),
            "photo_upload": _nested_flag(raw, "post_event", "photo_upload"),
            "video": _nested_flag(raw, "post_event", "video") or _as_bool(getattr(item, "recording", False)),
        },
    }
    flags = {
        "poster_required": normalized["pre_event"]["poster"],
        "video_required": normalized["during_event"]["video"],
        "linkedin_post": normalized["pre_event"]["social_media"] or normalized["post_event"]["social_media"],
        "photography": normalized["during_event"]["photo"] or normalized["post_event"]["photo_upload"],
        "recording": normalized["post_event"]["video"],
    }
    return normalized, flags


def serialize_marketing(item: MarketingRequest) -> MarketingRequestResponse:
    raw = getattr(item, "deliverables", None) or []
    deliverables = [x for d in raw if (x := _deliverable_to_response(d))]
    normalized_requirements, flags = _normalize_marketing_requirements(item)

    return MarketingRequestResponse(
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
        marketing_requirements=normalized_requirements,
        poster_required=flags["poster_required"],
        poster_dimension=item.poster_dimension,
        video_required=flags["video_required"],
        video_dimension=item.video_dimension,
        linkedin_post=flags["linkedin_post"],
        photography=flags["photography"],
        recording=flags["recording"],
        other_notes=item.other_notes,
        status=item.status,
        decided_at=item.decided_at,
        decided_by=item.decided_by,
        deliverables=deliverables,
        created_at=item.created_at,
    )


def serialize_facility(item: FacilityManagerRequest) -> FacilityManagerRequestResponse:
    return FacilityManagerRequestResponse(
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


def serialize_transport(item: TransportRequest) -> TransportRequestResponse:
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


def serialize_it(item: ItRequest) -> ItRequestResponse:
    return ItRequestResponse(
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


def serialize_invite(item: Invite) -> InviteResponse:
    return InviteResponse(
        id=str(item.id),
        event_id=item.event_id,
        created_by=item.created_by,
        to_email=item.to_email,
        subject=item.subject,
        body=item.body,
        status=item.status,
        sent_at=item.sent_at,
        created_at=item.created_at,
    )


def serialize_publication(item: Publication) -> PublicationResponse:
    return PublicationResponse(
        id=str(item.id),
        name=item.name,
        title=item.title,
        others=item.others,
        file_id=item.file_id,
        file_name=item.file_name,
        web_view_link=item.web_view_link,
        uploaded_at=item.uploaded_at,
        created_at=item.created_at,
    )


@router.get("/overview")
async def admin_overview(admin: User = Depends(require_admin)):
    return {
        "users": await User.find_all().count(),
        "venues": await Venue.find_all().count(),
        "events": await Event.find_all().count(),
        "approvals": await ApprovalRequest.find_all().count(),
        "facility": await FacilityManagerRequest.find_all().count(),
        "marketing": await MarketingRequest.find_all().count(),
        "it": await ItRequest.find_all().count(),
        "transport": await TransportRequest.find_all().count(),
        "invites": await Invite.find_all().count(),
        "publications": await Publication.find_all().count(),
    }


@router.get("/events", response_model=PaginatedResponse[EventResponse])
async def list_all_events(
    admin: User = Depends(require_admin),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    query = Event.find_all().sort("-created_at")
    total = await query.count()
    items = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[EventResponse](
        items=[serialize_event(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/event-reports", response_model=PaginatedResponse[EventResponse])
async def list_event_reports(
    admin: User = Depends(require_admin),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    """All closed events with uploaded reports (admin and registrar only)."""
    query = Event.find(Event.status == "closed").sort("-created_at")
    total = await query.count()
    items = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[EventResponse](
        items=[serialize_event(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/approvals", response_model=PaginatedResponse[ApprovalRequestResponse])
async def list_all_approvals(
    admin: User = Depends(require_admin),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    query = ApprovalRequest.find_all().sort("-created_at")
    total = await query.count()
    items = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[ApprovalRequestResponse](
        items=[serialize_approval(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/facility", response_model=PaginatedResponse[FacilityManagerRequestResponse])
async def list_all_facility(
    admin: User = Depends(require_admin),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    query = FacilityManagerRequest.find_all().sort("-created_at")
    total = await query.count()
    items = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[FacilityManagerRequestResponse](
        items=[serialize_facility(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/marketing", response_model=PaginatedResponse[MarketingRequestResponse])
async def list_all_marketing(
    admin: User = Depends(require_admin),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    query = MarketingRequest.find_all().sort("-created_at")
    total = await query.count()
    items = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[MarketingRequestResponse](
        items=[serialize_marketing(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/it", response_model=PaginatedResponse[ItRequestResponse])
async def list_all_it(
    admin: User = Depends(require_admin),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    query = ItRequest.find_all().sort("-created_at")
    total = await query.count()
    items = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[ItRequestResponse](
        items=[serialize_it(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/transport", response_model=PaginatedResponse[TransportRequestResponse])
async def list_all_transport(
    admin: User = Depends(require_admin),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    query = TransportRequest.find_all().sort("-created_at")
    total = await query.count()
    items = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[TransportRequestResponse](
        items=[serialize_transport(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/invites", response_model=PaginatedResponse[InviteResponse])
async def list_all_invites(
    admin: User = Depends(require_admin),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    query = Invite.find_all().sort("-created_at")
    total = await query.count()
    items = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[InviteResponse](
        items=[serialize_invite(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/publications", response_model=PaginatedResponse[PublicationResponse])
async def list_all_publications(
    admin: User = Depends(require_admin),
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    offset: int = Query(0, ge=0),
):
    query = Publication.find_all().sort("-created_at")
    total = await query.count()
    items = await query.skip(offset).limit(limit).to_list()
    next_offset = offset + limit if offset + limit < total else None
    return PaginatedResponse[PublicationResponse](
        items=[serialize_publication(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
        next_offset=next_offset,
    )


@router.get("/venues", response_model=list[VenueResponse])
async def list_all_venues(admin: User = Depends(require_admin)):
    items = await Venue.find_all().sort("name").to_list()
    return [VenueResponse(id=str(item.id), name=item.name) for item in items]

@router.delete("/events/{event_id}")
async def delete_event(event_id: str, admin: User = Depends(require_admin)):
    item = await Event.get(event_id)
    if not item:
        raise HTTPException(status_code=404, detail="Event not found")
    # Remove related approval requests if they point to this event
    await ApprovalRequest.find(ApprovalRequest.event_id == event_id).delete()
    # Also remove pending approvals that match the event details (no event_id yet)
    await ApprovalRequest.find(
        {
            "event_id": None,
            "requester_id": item.created_by,
            "event_name": item.name,
            "start_date": item.start_date,
            "start_time": item.start_time,
            "end_date": item.end_date,
            "end_time": item.end_time,
        }
    ).delete()
    # Remove related marketing requests (by event_id or matching pending details)
    await FacilityManagerRequest.find(FacilityManagerRequest.event_id == event_id).delete()
    await MarketingRequest.find(MarketingRequest.event_id == event_id).delete()
    await FacilityManagerRequest.find(
        {
            "event_id": None,
            "requester_id": item.created_by,
            "event_name": item.name,
            "start_date": item.start_date,
            "start_time": item.start_time,
            "end_date": item.end_date,
            "end_time": item.end_time,
        }
    ).delete()
    await MarketingRequest.find(
        {
            "event_id": None,
            "requester_id": item.created_by,
            "event_name": item.name,
            "start_date": item.start_date,
            "start_time": item.start_time,
            "end_date": item.end_date,
            "end_time": item.end_time,
        }
    ).delete()
    # Remove related IT requests (by event_id or matching pending details)
    await ItRequest.find(ItRequest.event_id == event_id).delete()
    await ItRequest.find(
        {
            "event_id": None,
            "requester_id": item.created_by,
            "event_name": item.name,
            "start_date": item.start_date,
            "start_time": item.start_time,
            "end_date": item.end_date,
            "end_time": item.end_time,
        }
    ).delete()
    await TransportRequest.find(TransportRequest.event_id == event_id).delete()
    await TransportRequest.find(
        {
            "event_id": None,
            "requester_id": item.created_by,
            "event_name": item.name,
            "start_date": item.start_date,
            "start_time": item.start_time,
            "end_date": item.end_date,
            "end_time": item.end_time,
        }
    ).delete()
    # Remove related invites
    await Invite.find(Invite.event_id == event_id).delete()
    await item.delete()
    return {"status": "deleted", "id": event_id}


@router.delete("/approvals/{request_id}")
async def delete_approval(request_id: str, admin: User = Depends(require_admin)):
    item = await ApprovalRequest.get(request_id)
    if not item:
        raise HTTPException(status_code=404, detail="Approval request not found")
    # If this approval created an event, remove the event and its related records
    if item.event_id:
        event = await Event.get(item.event_id)
        if event:
            await ApprovalRequest.find(ApprovalRequest.event_id == item.event_id).delete()
            await MarketingRequest.find(MarketingRequest.event_id == item.event_id).delete()
            await ItRequest.find(ItRequest.event_id == item.event_id).delete()
            await Invite.find(Invite.event_id == item.event_id).delete()
            await event.delete()
    # Remove related pending requests that match this approval details
    await FacilityManagerRequest.find(
        {
            "event_id": None,
            "requester_id": item.requester_id,
            "event_name": item.event_name,
            "start_date": item.start_date,
            "start_time": item.start_time,
            "end_date": item.end_date,
            "end_time": item.end_time,
        }
    ).delete()
    await MarketingRequest.find(
        {
            "event_id": None,
            "requester_id": item.requester_id,
            "event_name": item.event_name,
            "start_date": item.start_date,
            "start_time": item.start_time,
            "end_date": item.end_date,
            "end_time": item.end_time,
        }
    ).delete()
    await ItRequest.find(
        {
            "event_id": None,
            "requester_id": item.requester_id,
            "event_name": item.event_name,
            "start_date": item.start_date,
            "start_time": item.start_time,
            "end_date": item.end_date,
            "end_time": item.end_time,
        }
    ).delete()
    await TransportRequest.find(
        {
            "event_id": None,
            "requester_id": item.requester_id,
            "event_name": item.event_name,
            "start_date": item.start_date,
            "start_time": item.start_time,
            "end_date": item.end_date,
            "end_time": item.end_time,
        }
    ).delete()
    await item.delete()
    return {"status": "deleted", "id": request_id}


@router.delete("/facility/{request_id}")
async def delete_facility(request_id: str, admin: User = Depends(require_admin)):
    item = await FacilityManagerRequest.get(request_id)
    if not item:
        raise HTTPException(status_code=404, detail="Facility request not found")
    await item.delete()
    return {"status": "deleted", "id": request_id}


@router.delete("/marketing/{request_id}")
async def delete_marketing(request_id: str, admin: User = Depends(require_admin)):
    item = await MarketingRequest.get(request_id)
    if not item:
        raise HTTPException(status_code=404, detail="Marketing request not found")
    await item.delete()
    return {"status": "deleted", "id": request_id}


@router.delete("/it/{request_id}")
async def delete_it(request_id: str, admin: User = Depends(require_admin)):
    item = await ItRequest.get(request_id)
    if not item:
        raise HTTPException(status_code=404, detail="IT request not found")
    await item.delete()
    return {"status": "deleted", "id": request_id}


@router.delete("/transport/{request_id}")
async def delete_transport(request_id: str, admin: User = Depends(require_admin)):
    item = await TransportRequest.get(request_id)
    if not item:
        raise HTTPException(status_code=404, detail="Transport request not found")
    await item.delete()
    return {"status": "deleted", "id": request_id}


@router.delete("/invites/{invite_id}")
async def delete_invite(invite_id: str, admin: User = Depends(require_admin)):
    item = await Invite.get(invite_id)
    if not item:
        raise HTTPException(status_code=404, detail="Invite not found")
    await item.delete()
    return {"status": "deleted", "id": invite_id}


@router.delete("/publications/{publication_id}")
async def delete_publication(publication_id: str, admin: User = Depends(require_admin)):
    item = await Publication.get(publication_id)
    if not item:
        raise HTTPException(status_code=404, detail="Publication not found")
    await item.delete()
    return {"status": "deleted", "id": publication_id}

