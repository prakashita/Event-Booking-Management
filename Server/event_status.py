from __future__ import annotations

import re
from datetime import datetime

from models import Event


def _normalize_time_for_iso(time_value: str | None) -> str:
    """Return time as HH:MM:SS so fromisoformat parses reliably. Handles HH:MM and HH:MM:SS."""
    if not time_value:
        return "00:00:00"
    s = str(time_value).strip()
    if not s:
        return "00:00:00"
    # Match H?H:MM or H?H:MM:SS (optional seconds)
    m = re.match(r"^(\d{1,2}):(\d{2})(?::(\d{2}))?$", s)
    if m:
        h, mi, sec = m.group(1), m.group(2), m.group(3) or "00"
        return f"{int(h):02d}:{mi}:{sec}"
    return "00:00:00"


def _normalize_date_for_iso(date_value: str | None) -> str | None:
    """Return date as YYYY-MM-DD, or None if unparseable."""
    if not date_value:
        return None
    s = str(date_value).strip()
    if not s:
        return None
    # Already ISO-like (YYYY-MM-DD or YYYY-M-D)
    if re.match(r"^\d{4}-\d{1,2}-\d{1,2}$", s):
        try:
            dt = datetime.fromisoformat(s + "T00:00:00")
            return dt.strftime("%Y-%m-%d")
        except ValueError:
            pass
    # DD-MM-YYYY or DD/MM/YYYY
    for fmt in ("%d-%m-%Y", "%d/%m/%Y", "%Y/%m/%d"):
        try:
            dt = datetime.strptime(s, fmt)
            return dt.strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def combine_datetime(date_value: str, time_value: str) -> datetime:
    """Parse date and time into a datetime. Uses normalized time (HH:MM:SS) and optional date normalization."""
    time_str = _normalize_time_for_iso(time_value)
    date_str = _normalize_date_for_iso(date_value)
    if not date_str:
        raise ValueError(f"Invalid date format: {date_value!r}")
    return datetime.fromisoformat(f"{date_str}T{time_str}")


def event_has_started(start_date: str, start_time: str, now: datetime | None = None) -> bool:
    """True if the event start datetime is in the past. Use to block actions on started events."""
    if not start_date:
        return False
    if now is None:
        now = datetime.now()
    try:
        time_str = (start_time or "00:00:00").strip()
        if len(time_str) <= 5:  # HH:MM
            time_str = f"{time_str}:00"
        start_dt = combine_datetime(start_date, time_str)
        return now >= start_dt
    except (ValueError, TypeError):
        return False


def compute_event_status(start_dt: datetime, end_dt: datetime, now: datetime | None = None) -> str:
    if now is None:
        now = datetime.now()
    if now < start_dt:
        return "upcoming"
    if now <= end_dt:
        return "ongoing"
    return "completed"


async def sync_event_status(event: Event, now: datetime | None = None) -> str:
    if event.status == "closed":
        return event.status
    try:
        start_dt = combine_datetime(event.start_date, event.start_time)
        end_dt = combine_datetime(event.end_date, event.end_time)
    except (ValueError, TypeError):
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
        if event.status == "closed":
            continue
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
