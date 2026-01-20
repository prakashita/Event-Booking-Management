from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import JSONResponse

from models import Event, User
from routers.deps import get_current_user
from schemas import EventCreate, EventResponse

router = APIRouter(prefix="/events", tags=["Events"])

def combine_datetime(date_value: str, time_value: str) -> datetime:
    return datetime.fromisoformat(f"{date_value}T{time_value}")


def serialize_conflict(event: Event) -> dict:
    return {
        "id": str(event.id),
        "name": event.name,
        "venue_name": event.venue_name,
        "start_date": event.start_date,
        "start_time": event.start_time,
        "end_date": event.end_date,
        "end_time": event.end_time,
    }

@router.get("", response_model=list[EventResponse])
async def list_events(user: User = Depends(get_current_user)):
    events = await Event.find(Event.created_by == str(user.id)).sort("-created_at").to_list()
    return [
        EventResponse(
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
            created_at=event.created_at,
        )
        for event in events
    ]


@router.post("", response_model=EventResponse, status_code=status.HTTP_201_CREATED)
async def create_event(payload: EventCreate, user: User = Depends(get_current_user)):
    start_dt = datetime.combine(payload.start_date, payload.start_time)
    end_dt = datetime.combine(payload.end_date, payload.end_time)
    if end_dt < start_dt:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="End datetime must be after start datetime",
        )

    if not payload.override_conflict:
        existing_events = await Event.find_all().to_list()
        conflicts = []
        for existing in existing_events:
            existing_start = combine_datetime(existing.start_date, existing.start_time)
            existing_end = combine_datetime(existing.end_date, existing.end_time)
            if start_dt < existing_end and end_dt > existing_start:
                conflicts.append(serialize_conflict(existing))

        if conflicts:
            return JSONResponse(
                status_code=status.HTTP_409_CONFLICT,
                content={
                    "detail": "Schedule conflict detected",
                    "conflicts": conflicts,
                },
            )

    event = Event(
        name=payload.name,
        facilitator=payload.facilitator,
        description=payload.description,
        venue_name=payload.venue_name,
        start_date=payload.start_date.isoformat(),
        start_time=payload.start_time.isoformat(),
        end_date=payload.end_date.isoformat(),
        end_time=payload.end_time.isoformat(),
        created_by=str(user.id),
    )
    await event.insert()
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
        created_at=event.created_at,
    )
