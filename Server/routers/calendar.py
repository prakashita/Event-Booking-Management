from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
import requests

from auth import (
    GOOGLE_CALENDAR_SCOPE,
    GOOGLE_CLIENT_ID,
    GOOGLE_CLIENT_SECRET,
    GOOGLE_REDIRECT_URI,
    create_oauth_state,
    decode_access_token,
    decode_oauth_state,
)
from models import User

router = APIRouter(prefix="/calendar", tags=["Calendar"])
security = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> User:
    if not credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing token")

    payload = decode_access_token(credentials.credentials)
    user_id = payload.get("user_id")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    user = await User.get(user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


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
        "scope": GOOGLE_CALENDAR_SCOPE,
        "access_type": "offline",
        "prompt": "consent",
        "include_granted_scopes": "true",
        "state": state,
    }
    query = "&".join([f"{key}={requests.utils.quote(str(value))}" for key, value in params.items()])
    return f"https://accounts.google.com/o/oauth2/v2/auth?{query}"


async def ensure_access_token(user: User) -> str:
    if user.google_access_token and user.google_token_expiry:
        expiry = user.google_token_expiry
        if expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=timezone.utc)
        if expiry > datetime.now(timezone.utc) + timedelta(minutes=1):
            return user.google_access_token

    if not user.google_refresh_token:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Google Calendar not connected"
        )

    if not GOOGLE_CLIENT_ID or not GOOGLE_CLIENT_SECRET:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Google OAuth not configured"
        )

    response = requests.post(
        "https://oauth2.googleapis.com/token",
        data={
            "client_id": GOOGLE_CLIENT_ID,
            "client_secret": GOOGLE_CLIENT_SECRET,
            "refresh_token": user.google_refresh_token,
            "grant_type": "refresh_token",
        },
        timeout=15,
    )

    if response.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unable to refresh Google token",
        )

    data = response.json()
    access_token = data.get("access_token")
    expires_in = data.get("expires_in", 3600)
    if not access_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Google token missing",
        )

    user.google_access_token = access_token
    user.google_token_expiry = datetime.now(timezone.utc) + timedelta(seconds=expires_in)
    await user.save()
    return access_token


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


@router.get("/events")
async def get_calendar_events(
    start: str | None = None,
    end: str | None = None,
    user: User = Depends(get_current_user),
):
    access_token = await ensure_access_token(user)
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
        start = item.get("start", {}).get("dateTime") or item.get("start", {}).get("date")
        end = item.get("end", {}).get("dateTime") or item.get("end", {}).get("date")
        events.append(
            {
                "id": item.get("id"),
                "summary": item.get("summary"),
                "start": start,
                "end": end,
                "location": item.get("location"),
                "htmlLink": item.get("htmlLink"),
            }
        )

    return {"events": events}
