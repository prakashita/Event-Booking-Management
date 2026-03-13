from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import HTMLResponse
import requests

from auth import (
    GOOGLE_CLIENT_ID,
    GOOGLE_CLIENT_SECRET,
    GOOGLE_OAUTH_SCOPE,
    GOOGLE_REDIRECT_URI,
    create_oauth_state,
    decode_oauth_state,
    ensure_google_access_token,
)
from event_status import combine_datetime
from models import Event, User
from routers.deps import get_current_user

router = APIRouter(prefix="/calendar", tags=["Calendar"])


def build_google_oauth_url(state: str) -> str:
    if not GOOGLE_CLIENT_ID or not GOOGLE_REDIRECT_URI:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Google OAuth not configured"
        )

    params = {
        "client_id": GOOGLE_CLIENT_ID,
        "redirect_uri": GOOGLE_REDIRECT_URI,
        "response_type": "code",
        "scope": GOOGLE_OAUTH_SCOPE,
        "access_type": "offline",
        "prompt": "consent",
        "include_granted_scopes": "true",
        "state": state,
    }
    query = "&".join([f"{key}={requests.utils.quote(str(value))}" for key, value in params.items()])
    return f"https://accounts.google.com/o/oauth2/v2/auth?{query}"



@router.get("/connect-url")
async def get_connect_url(user: User = Depends(get_current_user)):
    state = create_oauth_state(str(user.id))
    return {"url": build_google_oauth_url(state)}


@router.get("/oauth/callback")
async def oauth_callback(code: str, state: str):
    payload = decode_oauth_state(state)
    user_id = payload.get("user_id")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid state")

    if not GOOGLE_CLIENT_ID or not GOOGLE_CLIENT_SECRET:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Google OAuth not configured"
        )

    token_response = requests.post(
        "https://oauth2.googleapis.com/token",
        data={
            "client_id": GOOGLE_CLIENT_ID,
            "client_secret": GOOGLE_CLIENT_SECRET,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": GOOGLE_REDIRECT_URI,
        },
        timeout=15,
    )

    if token_response.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Failed to exchange code",
        )

    tokens = token_response.json()
    refresh_token = tokens.get("refresh_token")
    access_token = tokens.get("access_token")
    expires_in = tokens.get("expires_in", 3600)

    user = await User.get(user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    if refresh_token:
        user.google_refresh_token = refresh_token
    if access_token:
        user.google_access_token = access_token
        user.google_token_expiry = datetime.now(timezone.utc) + timedelta(seconds=expires_in)

    await user.save()

    return HTMLResponse(
        """
        <html>
          <head><title>Calendar Connected</title></head>
          <body style="font-family: Arial, sans-serif; padding: 32px;">
            <h2>Google Calendar connected.</h2>
            <p>You can close this tab and return to the app.</p>
          </body>
        </html>
        """
    )


def _event_to_calendar_item(event: Event) -> dict | None:
    """Convert an Event to a FullCalendar-friendly dict. Returns None if date/time invalid."""
    try:
        start_dt = combine_datetime(event.start_date, event.start_time)
        end_dt = combine_datetime(event.end_date, event.end_time)
    except (ValueError, TypeError):
        return None
    return {
        "id": str(event.id),
        "summary": event.name or "Untitled event",
        "start": start_dt.isoformat(),
        "end": end_dt.isoformat(),
        "location": event.venue_name,
        "htmlLink": event.google_event_link,
    }


@router.get("/app-events")
async def get_app_calendar_events(
    start: str | None = Query(None, description="ISO datetime for calendar range start"),
    end: str | None = Query(None, description="ISO datetime for calendar range end"),
    user: User = Depends(get_current_user),
):
    """
    Return all approved events from the app (Event collection) in calendar format.
    All events in the DB are approved (created only after registrar approval).
    Optional start/end filter by visible calendar range.
    """
    all_events = await Event.find_all().sort("start_date", "start_time").to_list()
    events_payload = []

    try:
        range_start = datetime.fromisoformat(start.replace("Z", "+00:00")) if start else None
    except (ValueError, AttributeError):
        range_start = None
    try:
        range_end = datetime.fromisoformat(end.replace("Z", "+00:00")) if end else None
    except (ValueError, AttributeError):
        range_end = None

    for event in all_events:
        item = _event_to_calendar_item(event)
        if not item:
            continue
        if range_start is not None or range_end is not None:
            try:
                ev_start = combine_datetime(event.start_date, event.start_time)
                ev_end = combine_datetime(event.end_date, event.end_time)
            except (ValueError, TypeError):
                continue
            if range_start is not None and ev_end < range_start:
                continue
            if range_end is not None and ev_start > range_end:
                continue
        events_payload.append(item)

    return {"events": events_payload}


@router.get("/events")
async def get_calendar_events(
    start: str | None = None,
    end: str | None = None,
    user: User = Depends(get_current_user),
):
    """Fetch from Google Calendar API (user's personal calendar). Use /app-events for all approved app events."""
    access_token = await ensure_google_access_token(user)
    time_min = start or datetime.now(timezone.utc).isoformat()
    time_max = end or (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()

    response = requests.get(
        "https://www.googleapis.com/calendar/v3/calendars/primary/events",
        headers={"Authorization": f"Bearer {access_token}"},
        params={
            "singleEvents": "true",
            "orderBy": "startTime",
            "timeMin": time_min,
            "timeMax": time_max,
            "maxResults": 250,
        },
        timeout=15,
    )

    if response.status_code != 200:
        raise HTTPException(
            status_code=response.status_code,
            detail="Unable to fetch calendar events",
        )

    items = response.json().get("items", [])
    events = []
    for item in items:
        start_val = item.get("start", {}).get("dateTime") or item.get("start", {}).get("date")
        end_val = item.get("end", {}).get("dateTime") or item.get("end", {}).get("date")
        events.append(
            {
                "id": item.get("id"),
                "summary": item.get("summary"),
                "start": start_val,
                "end": end_val,
                "location": item.get("location"),
                "htmlLink": item.get("htmlLink"),
            }
        )

    return {"events": events}
