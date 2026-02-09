from fastapi import APIRouter, Depends, HTTPException

from models import ApprovalRequest, Event, Invite, ItRequest, MarketingRequest, Publication, User, Venue
from routers.deps import require_admin
from schemas import (
    ApprovalRequestResponse,
    EventResponse,
    InviteResponse,
    ItRequestResponse,
    MarketingRequestResponse,
    PublicationResponse,
    VenueResponse,
)

router = APIRouter(prefix="/admin", tags=["Admin"])


def serialize_event(event: Event) -> EventResponse:
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


def serialize_approval(item: ApprovalRequest) -> ApprovalRequestResponse:
    return ApprovalRequestResponse(
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


def serialize_marketing(item: MarketingRequest) -> MarketingRequestResponse:
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
        "marketing": await MarketingRequest.find_all().count(),
        "it": await ItRequest.find_all().count(),
        "invites": await Invite.find_all().count(),
        "publications": await Publication.find_all().count(),
    }


@router.get("/events", response_model=list[EventResponse])
async def list_all_events(admin: User = Depends(require_admin)):
    items = await Event.find_all().sort("-created_at").to_list()
    return [serialize_event(item) for item in items]


@router.get("/approvals", response_model=list[ApprovalRequestResponse])
async def list_all_approvals(admin: User = Depends(require_admin)):
    items = await ApprovalRequest.find_all().sort("-created_at").to_list()
    return [serialize_approval(item) for item in items]


@router.get("/marketing", response_model=list[MarketingRequestResponse])
async def list_all_marketing(admin: User = Depends(require_admin)):
    items = await MarketingRequest.find_all().sort("-created_at").to_list()
    return [serialize_marketing(item) for item in items]


@router.get("/it", response_model=list[ItRequestResponse])
async def list_all_it(admin: User = Depends(require_admin)):
    items = await ItRequest.find_all().sort("-created_at").to_list()
    return [serialize_it(item) for item in items]


@router.get("/invites", response_model=list[InviteResponse])
async def list_all_invites(admin: User = Depends(require_admin)):
    items = await Invite.find_all().sort("-created_at").to_list()
    return [serialize_invite(item) for item in items]


@router.get("/publications", response_model=list[PublicationResponse])
async def list_all_publications(admin: User = Depends(require_admin)):
    items = await Publication.find_all().sort("-created_at").to_list()
    return [serialize_publication(item) for item in items]


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
    await MarketingRequest.find(MarketingRequest.event_id == event_id).delete()
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

