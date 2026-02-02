from datetime import datetime
import os
import re

from fastapi import APIRouter, Depends, HTTPException, status

import requests

from auth import ensure_google_access_token
from models import ApprovalRequest, Event, ItRequest, MarketingRequest, User
from routers.deps import get_current_user
from schemas import ApprovalDecision, ApprovalRequestResponse

router = APIRouter(prefix="/approvals", tags=["Approvals"])

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
                matching_query = {
                    "requester_id": approval.requester_id,
                    "event_name": approval.event_name,
                    "start_date": approval.start_date,
                    "end_date": approval.end_date,
                    "event_id": None,
                }
                approval_start = normalize_time(approval.start_time)
                approval_end = normalize_time(approval.end_time)

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

                requester = await User.get(approval.requester_id)
                if requester and requester.google_refresh_token:
                    try:
                        access_token = await ensure_google_access_token(requester)
                        time_zone = os.getenv("DEFAULT_TIMEZONE", "UTC")
                        start_dt = f"{approval.start_date}T{approval.start_time}"
                        end_dt = f"{approval.end_date}T{approval.end_time}"
                        payload = {
                            "summary": approval.event_name,
                            "description": approval.description or "",
                            "location": approval.venue_name,
                            "start": {"dateTime": start_dt, "timeZone": time_zone},
                            "end": {"dateTime": end_dt, "timeZone": time_zone},
                        }
                        response = requests.post(
                            "https://www.googleapis.com/calendar/v3/calendars/primary/events",
                            headers={"Authorization": f"Bearer {access_token}"},
                            json=payload,
                            timeout=15,
                        )
                        if response.status_code in {200, 201}:
                            data = response.json()
                            event.google_event_id = data.get("id")
                            event.google_event_link = data.get("htmlLink")
                            await event.save()
                    except Exception:
                        pass
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
