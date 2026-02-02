from __future__ import annotations

from datetime import datetime

from models import Event


def combine_datetime(date_value: str, time_value: str) -> datetime:
    return datetime.fromisoformat(f"{date_value}T{time_value}")


def compute_event_status(start_dt: datetime, end_dt: datetime, now: datetime | None = None) -> str:
    if now is None:
        now = datetime.now()
    if now < start_dt:
        return "upcoming"
    if now <= end_dt:
        return "ongoing"
    return "completed"


async def sync_event_status(event: Event, now: datetime | None = None) -> str:
    try:
        start_dt = combine_datetime(event.start_date, event.start_time)
        end_dt = combine_datetime(event.end_date, event.end_time)
    except ValueError:
        return event.status
    status = compute_event_status(start_dt, end_dt, now=now)
    if event.status != status:
        event.status = status
        await event.save()
    return status


async def update_event_statuses() -> int:
    now = datetime.now()
    events = await Event.find_all().to_list()
    updates = 0
    for event in events:
        try:
            start_dt = combine_datetime(event.start_date, event.start_time)
            end_dt = combine_datetime(event.end_date, event.end_time)
        except ValueError:
            continue
        status = compute_event_status(start_dt, end_dt, now=now)
        if event.status != status:
            event.status = status
            await event.save()
            updates += 1
    return updates
