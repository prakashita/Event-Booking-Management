from __future__ import annotations

from datetime import date, datetime, timedelta
import os
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
import requests

from auth import ensure_google_access_token
from models import InstitutionCalendarEntry, User
from routers.deps import require_admin_or_registrar
from schemas import (
    InstitutionCalendarEntryCreate,
    InstitutionCalendarEntryResponse,
    InstitutionCalendarEntryUpdate,
    InstitutionCalendarMutationResponse,
    InstitutionCalendarSyncResponse,
)

router = APIRouter(prefix="/institution-calendar", tags=["Institution Calendar"])

ENTRY_TYPE_COLORS = {
    "holiday": "#f59e0b",
}

CATEGORY_COLORS = {
    "registration": "#2563eb",
    "instruction": "#16a34a",
    "examination": "#dc2626",
    "assessment": "#dc2626",
    "committee meeting": "#7c3aed",
    "committee": "#7c3aed",
    "review": "#7c3aed",
    "result": "#0f766e",
    "application": "#0f766e",
    "eligibility list": "#0f766e",
    "commencement": "#4f46e5",
    "semester closure": "#4f46e5",
    "semester start": "#4f46e5",
    "semester end": "#4f46e5",
}


def _normalized_text(value: Optional[str]) -> str:
    return (value or "").strip()


def resolve_entry_color(entry_type: str, category: Optional[str], explicit_color: Optional[str] = None) -> str:
    if explicit_color:
        return explicit_color
    if entry_type == "holiday":
        return ENTRY_TYPE_COLORS["holiday"]
    normalized = _normalized_text(category).lower()
    return CATEGORY_COLORS.get(normalized, "#475569")


def _day_label_from_iso(iso_date: str) -> str:
    return datetime.strptime(iso_date, "%Y-%m-%d").strftime("%A")


def _sync_status(entry: InstitutionCalendarEntry) -> str:
    if getattr(entry, "google_event_id", None):
        return "synced"
    if getattr(entry, "google_sync_error", None):
        return "sync_failed"
    if getattr(entry, "google_sync_enabled", False):
        return "pending"
    return "disabled"


def serialize_institution_calendar_entry(entry: InstitutionCalendarEntry) -> InstitutionCalendarEntryResponse:
    is_holiday = entry.entry_type == "holiday"
    return InstitutionCalendarEntryResponse(
        id=str(entry.id),
        title=entry.title,
        holiday_name=entry.title if is_holiday else None,
        category=entry.category,
        entry_type=entry.entry_type,
        academic_year=entry.academic_year,
        calendar_year=getattr(entry, "calendar_year", None),
        semester_type=getattr(entry, "semester_type", None),
        semester=getattr(entry, "semester", None),
        date=entry.start_date if is_holiday else None,
        start_date=entry.start_date,
        end_date=entry.end_date,
        all_day=entry.all_day,
        day_label=getattr(entry, "day_label", None),
        description=getattr(entry, "description", None),
        color=resolve_entry_color(entry.entry_type, entry.category, getattr(entry, "color", None)),
        visible_to_all=entry.visible_to_all,
        google_sync_enabled=entry.google_sync_enabled,
        google_event_id=getattr(entry, "google_event_id", None),
        google_event_link=getattr(entry, "google_event_link", None),
        google_sync_error=getattr(entry, "google_sync_error", None),
        sync_status=_sync_status(entry),
        is_active=entry.is_active,
        created_by=entry.created_by,
        updated_by=entry.updated_by,
        created_at=entry.created_at,
        updated_at=entry.updated_at,
    )


def _build_entry_query(
    *,
    entry_type: Optional[str] = None,
    academic_year: Optional[str] = None,
    semester: Optional[str] = None,
    category: Optional[str] = None,
    visible_only: bool = False,
):
    filters: dict = {}
    if entry_type:
        filters["entry_type"] = entry_type
    if academic_year:
        filters["academic_year"] = academic_year
    if semester:
        filters["semester"] = semester
    if category:
        filters["category"] = category
    if visible_only:
        filters["visible_to_all"] = True
        filters["is_active"] = True
    return filters


def institution_entry_to_calendar_item(entry: InstitutionCalendarEntry) -> dict:
    color = resolve_entry_color(entry.entry_type, entry.category, getattr(entry, "color", None))
    end_exclusive = (
        datetime.strptime(entry.end_date, "%Y-%m-%d").date() + timedelta(days=1)
    ).isoformat()
    title = f"Holiday: {entry.title}" if entry.entry_type == "holiday" else f"{entry.category} • {entry.title}"
    return {
        "id": f"institution-{entry.id}",
        "summary": title,
        "start": entry.start_date,
        "end": end_exclusive,
        "allDay": True,
        "htmlLink": getattr(entry, "google_event_link", None),
        "color": color,
        "sourceType": "institution_calendar",
        "entryType": entry.entry_type,
        "category": entry.category,
        "academicYear": entry.academic_year,
        "semesterType": getattr(entry, "semester_type", None),
        "semester": getattr(entry, "semester", None),
        "description": getattr(entry, "description", None),
        "dayLabel": getattr(entry, "day_label", None),
        "dateRangeLabel": entry.start_date if entry.start_date == entry.end_date else f"{entry.start_date} to {entry.end_date}",
    }


async def list_visible_institution_calendar_entries() -> list[InstitutionCalendarEntry]:
    return await InstitutionCalendarEntry.find(
        {"visible_to_all": True, "is_active": True}
    ).sort("start_date", "title").to_list()


def _build_google_payload(entry: InstitutionCalendarEntry) -> dict:
    time_zone = os.getenv("DEFAULT_TIMEZONE", "Asia/Kolkata")
    description_lines = [
        f"Category: {entry.category}",
        f"Academic Year: {entry.academic_year}",
    ]
    if getattr(entry, "semester_type", None):
        description_lines.append(f"Semester Type: {entry.semester_type}")
    if getattr(entry, "semester", None):
        description_lines.append(f"Semester: {entry.semester}")
    if getattr(entry, "description", None):
        description_lines.extend(["", entry.description])

    payload = {
        "summary": entry.title,
        "description": "\n".join(description_lines),
    }
    if entry.all_day:
        start_day = datetime.strptime(entry.start_date, "%Y-%m-%d").date()
        end_day = datetime.strptime(entry.end_date, "%Y-%m-%d").date() + timedelta(days=1)
        payload["start"] = {"date": start_day.isoformat(), "timeZone": time_zone}
        payload["end"] = {"date": end_day.isoformat(), "timeZone": time_zone}
    else:
        payload["start"] = {"dateTime": f"{entry.start_date}T00:00:00", "timeZone": time_zone}
        payload["end"] = {"dateTime": f"{entry.end_date}T23:59:00", "timeZone": time_zone}
    return payload


async def sync_institution_entry_to_google_calendar(
    entry: InstitutionCalendarEntry,
    user: User,
) -> InstitutionCalendarSyncResponse:
    if not user.google_refresh_token:
        detail = "Connect Google Calendar to sync calendar updates."
        entry.google_sync_error = detail
        await entry.save()
        return InstitutionCalendarSyncResponse(success=False, detail=detail, sync_error=detail)

    access_token = await ensure_google_access_token(user)
    payload = _build_google_payload(entry)
    method = requests.patch if getattr(entry, "google_event_id", None) else requests.post
    url = (
        f"https://www.googleapis.com/calendar/v3/calendars/primary/events/{entry.google_event_id}"
        if getattr(entry, "google_event_id", None)
        else "https://www.googleapis.com/calendar/v3/calendars/primary/events"
    )
    response = method(
        url,
        headers={"Authorization": f"Bearer {access_token}"},
        json=payload,
        timeout=15,
    )
    if response.status_code not in {200, 201}:
        detail = "Unable to sync institution calendar entry to Google Calendar"
        try:
            error_payload = response.json()
            message = error_payload.get("error", {}).get("message")
            if message:
                detail = f"{detail}: {message}"
        except Exception:
            pass
        entry.google_sync_error = detail
        await entry.save()
        return InstitutionCalendarSyncResponse(success=False, detail=detail, sync_error=detail)

    data = response.json()
    entry.google_event_id = data.get("id")
    entry.google_event_link = data.get("htmlLink")
    entry.google_sync_error = None
    await entry.save()
    return InstitutionCalendarSyncResponse(
        success=True,
        detail="Synced to Google Calendar.",
        google_event_id=entry.google_event_id,
        google_event_link=entry.google_event_link,
    )


async def unsync_institution_entry_from_google_calendar(
    entry: InstitutionCalendarEntry,
    user: User,
) -> InstitutionCalendarSyncResponse:
    if not getattr(entry, "google_event_id", None):
        entry.google_sync_error = None
        await entry.save()
        return InstitutionCalendarSyncResponse(success=True, detail="Entry is not currently synced.")

    if not user.google_refresh_token:
        detail = "Connect Google Calendar to remove synced calendar updates."
        entry.google_sync_error = detail
        await entry.save()
        return InstitutionCalendarSyncResponse(success=False, detail=detail, sync_error=detail)

    access_token = await ensure_google_access_token(user)
    response = requests.delete(
        f"https://www.googleapis.com/calendar/v3/calendars/primary/events/{entry.google_event_id}",
        headers={"Authorization": f"Bearer {access_token}"},
        timeout=15,
    )
    if response.status_code not in {200, 204, 404}:
        detail = "Unable to remove Google Calendar event"
        try:
            error_payload = response.json()
            message = error_payload.get("error", {}).get("message")
            if message:
                detail = f"{detail}: {message}"
        except Exception:
            pass
        entry.google_sync_error = detail
        await entry.save()
        return InstitutionCalendarSyncResponse(success=False, detail=detail, sync_error=detail)

    entry.google_event_id = None
    entry.google_event_link = None
    entry.google_sync_error = None
    await entry.save()
    return InstitutionCalendarSyncResponse(success=True, detail="Google Calendar sync removed.")


def _apply_payload_to_entry(
    entry: InstitutionCalendarEntry,
    payload: InstitutionCalendarEntryCreate | InstitutionCalendarEntryUpdate,
    *,
    entry_type: str,
    current_user: User,
):
    data = payload.model_dump(exclude_unset=True)
    if entry_type == "holiday":
        holiday_date = data.get("date") or datetime.strptime(entry.start_date, "%Y-%m-%d").date()
        holiday_name = data.get("holiday_name") or data.get("title") or entry.title
        entry.title = holiday_name
        entry.category = "Holiday"
        entry.calendar_year = data.get("calendar_year", holiday_date.year)
        entry.start_date = holiday_date.isoformat()
        entry.end_date = holiday_date.isoformat()
        entry.all_day = True
        entry.semester_type = None
        entry.semester = None
    else:
        if "title" in data and data["title"] is not None:
            entry.title = data["title"]
        if "category" in data and data["category"] is not None:
            entry.category = data["category"]
        if "calendar_year" in data:
            entry.calendar_year = data["calendar_year"]
        if "semester_type" in data:
            entry.semester_type = data["semester_type"]
        if "semester" in data:
            entry.semester = data["semester"]
        if "start_date" in data and data["start_date"] is not None:
            entry.start_date = data["start_date"].isoformat()
        if "end_date" in data and data["end_date"] is not None:
            entry.end_date = data["end_date"].isoformat()
        elif not getattr(entry, "end_date", None):
            entry.end_date = entry.start_date
        if data.get("all_day") is not None:
            entry.all_day = data["all_day"]

    if "academic_year" in data and data["academic_year"] is not None:
        entry.academic_year = data["academic_year"]
    if "description" in data:
        entry.description = data["description"]
    if "color" in data:
        entry.color = data["color"]
    if "visible_to_all" in data and data["visible_to_all"] is not None:
        entry.visible_to_all = data["visible_to_all"]
    if "google_sync_enabled" in data and data["google_sync_enabled"] is not None:
        entry.google_sync_enabled = data["google_sync_enabled"]
    if "is_active" in data and data["is_active"] is not None:
        entry.is_active = data["is_active"]

    if entry.end_date < entry.start_date:
        raise HTTPException(status_code=422, detail="End date cannot be before start date")

    entry.day_label = _day_label_from_iso(entry.start_date)
    entry.color = resolve_entry_color(entry.entry_type, entry.category, entry.color)
    entry.updated_by = str(current_user.id)
    entry.updated_at = datetime.utcnow()


async def _get_entry_or_404(entry_id: str) -> InstitutionCalendarEntry:
    entry = await InstitutionCalendarEntry.get(entry_id)
    if not entry:
        raise HTTPException(status_code=404, detail="Institution calendar entry not found")
    return entry


@router.get("", response_model=list[InstitutionCalendarEntryResponse])
async def list_institution_calendar_entries(
    entry_type: Optional[str] = Query(None),
    academic_year: Optional[str] = Query(None),
    semester: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
    current_user: User = Depends(require_admin_or_registrar),
):
    items = await InstitutionCalendarEntry.find(
        _build_entry_query(
            entry_type=entry_type,
            academic_year=academic_year,
            semester=semester,
            category=category,
        )
    ).sort("start_date", "title").to_list()
    return [serialize_institution_calendar_entry(item) for item in items]


@router.get("/public", response_model=list[InstitutionCalendarEntryResponse])
async def list_public_institution_calendar_entries(
    entry_type: Optional[str] = Query(None),
    academic_year: Optional[str] = Query(None),
    semester: Optional[str] = Query(None),
    category: Optional[str] = Query(None),
):
    items = await InstitutionCalendarEntry.find(
        _build_entry_query(
            entry_type=entry_type,
            academic_year=academic_year,
            semester=semester,
            category=category,
            visible_only=True,
        )
    ).sort("start_date", "title").to_list()
    return [serialize_institution_calendar_entry(item) for item in items]


@router.post("", response_model=InstitutionCalendarMutationResponse, status_code=201)
async def create_institution_calendar_entry(
    payload: InstitutionCalendarEntryCreate,
    current_user: User = Depends(require_admin_or_registrar),
):
    now = datetime.utcnow()
    entry_type = payload.entry_type
    if entry_type == "holiday":
        holiday_date = payload.date.isoformat()
        category = "Holiday"
        title = payload.holiday_name
        start_date = holiday_date
        end_date = holiday_date
        semester_type = None
        semester = None
        all_day = True
        calendar_year = payload.calendar_year or payload.date.year
    else:
        title = payload.title
        category = payload.category
        start_date = payload.start_date.isoformat()
        end_date = (payload.end_date or payload.start_date).isoformat()
        semester_type = payload.semester_type
        semester = payload.semester
        all_day = payload.all_day
        calendar_year = payload.calendar_year or payload.start_date.year

    entry = InstitutionCalendarEntry(
        title=title,
        category=category,
        entry_type=entry_type,
        academic_year=payload.academic_year,
        calendar_year=calendar_year,
        semester_type=semester_type,
        semester=semester,
        start_date=start_date,
        end_date=end_date,
        all_day=all_day,
        day_label=_day_label_from_iso(start_date),
        description=payload.description,
        color=resolve_entry_color(entry_type, category, payload.color),
        visible_to_all=payload.visible_to_all,
        google_sync_enabled=payload.google_sync_enabled,
        is_active=payload.is_active,
        created_by=str(current_user.id),
        updated_by=str(current_user.id),
        created_at=now,
        updated_at=now,
    )
    await entry.insert()

    sync_result = None
    if entry.google_sync_enabled:
        sync_result = await sync_institution_entry_to_google_calendar(entry, current_user)
        entry = await _get_entry_or_404(str(entry.id))

    return InstitutionCalendarMutationResponse(
        entry=serialize_institution_calendar_entry(entry),
        sync=sync_result,
    )


@router.patch("/{entry_id}", response_model=InstitutionCalendarMutationResponse)
async def update_institution_calendar_entry(
    entry_id: str,
    payload: InstitutionCalendarEntryUpdate,
    current_user: User = Depends(require_admin_or_registrar),
):
    entry = await _get_entry_or_404(entry_id)
    _apply_payload_to_entry(entry, payload, entry_type=entry.entry_type, current_user=current_user)
    await entry.save()

    sync_result = None
    if entry.google_sync_enabled:
        sync_result = await sync_institution_entry_to_google_calendar(entry, current_user)
        entry = await _get_entry_or_404(entry_id)

    return InstitutionCalendarMutationResponse(
        entry=serialize_institution_calendar_entry(entry),
        sync=sync_result,
    )


@router.delete("/{entry_id}")
async def delete_institution_calendar_entry(
    entry_id: str,
    current_user: User = Depends(require_admin_or_registrar),
):
    entry = await _get_entry_or_404(entry_id)
    await entry.delete()
    return {"status": "deleted", "id": entry_id}


@router.post("/{entry_id}/sync-google", response_model=InstitutionCalendarMutationResponse)
async def sync_institution_calendar_entry_google(
    entry_id: str,
    current_user: User = Depends(require_admin_or_registrar),
):
    entry = await _get_entry_or_404(entry_id)
    entry.google_sync_enabled = True
    entry.updated_by = str(current_user.id)
    entry.updated_at = datetime.utcnow()
    await entry.save()
    sync_result = await sync_institution_entry_to_google_calendar(entry, current_user)
    entry = await _get_entry_or_404(entry_id)
    return InstitutionCalendarMutationResponse(
        entry=serialize_institution_calendar_entry(entry),
        sync=sync_result,
    )


@router.delete("/{entry_id}/unsync-google", response_model=InstitutionCalendarMutationResponse)
async def unsync_institution_calendar_entry_google(
    entry_id: str,
    current_user: User = Depends(require_admin_or_registrar),
):
    entry = await _get_entry_or_404(entry_id)
    sync_result = await unsync_institution_entry_from_google_calendar(entry, current_user)
    if sync_result.success:
        entry.google_sync_enabled = False
    entry.updated_by = str(current_user.id)
    entry.updated_at = datetime.utcnow()
    await entry.save()
    entry = await _get_entry_or_404(entry_id)
    return InstitutionCalendarMutationResponse(
        entry=serialize_institution_calendar_entry(entry),
        sync=sync_result,
    )
