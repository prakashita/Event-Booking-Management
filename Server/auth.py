import os
from datetime import datetime, timedelta, timezone
from jose import jwt, JWTError
import requests
from fastapi import HTTPException, status
from dotenv import load_dotenv

# Load environment variables from Server/.env explicitly
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

SECRET_KEY = os.getenv("SECRET_KEY", "CHANGE_ME_LATER")
ALGORITHM = "HS256"
# Default 7 days; set ACCESS_TOKEN_EXPIRE_MINUTES in .env to override
_access_minutes = os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "")
ACCESS_TOKEN_EXPIRE_MINUTES = int(_access_minutes) if _access_minutes.isdigit() else (60 * 24 * 7)

GOOGLE_TOKEN_INFO_URL = "https://oauth2.googleapis.com/tokeninfo"
# Comma-separated allowed email domains (e.g. srmap.edu.in,vidyashilp.edu.in,gmail.com)
# Emails must end with @<domain> (e.g. user@vidyashilp.edu.in)
_allowed = os.getenv("ALLOWED_EMAIL_DOMAINS", "srmap.edu.in,vidyashilp.edu.in,gmail.com")
ALLOWED_DOMAIN = [f"@{d.strip()}" if d.strip() and not d.strip().startswith("@") else d.strip() for d in _allowed.split(",") if d.strip()]

GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
GOOGLE_REDIRECT_URI = os.getenv("GOOGLE_REDIRECT_URI", "http://localhost:8000/calendar/oauth/callback")
GOOGLE_OAUTH_SCOPE = "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/drive.file"
REQUIRED_GOOGLE_SCOPES = GOOGLE_OAUTH_SCOPE.split()

ADMIN_EMAILS = [
    email.strip().lower()
    for email in os.getenv("ADMIN_EMAILS", "").split(",")
    if email.strip()
]


def is_admin_email(email: str) -> bool:
    return (email or "").strip().lower() in ADMIN_EMAILS


async def get_primary_email_by_role(role: str) -> str:
    """Get primary email for a role from User collection. Used for registrar, facility_manager, marketing, it."""
    from models import User
    user = await User.find_one(User.role == role.lower())
    return (user.email or "").strip().lower() if user else ""


async def get_user_by_role(role: str):
    """Get the User with the given role, or None."""
    from models import User
    return await User.find_one(User.role == role.lower())


# Roles that receive Google Calendar invitations when an event is approved (organizer excluded).
CALENDAR_INVITE_STAFF_ROLES = (
    "registrar",
    "facility_manager",
    "marketing",
    "it",
    "admin",
)


async def get_staff_emails_for_calendar_invites(
    exclude_emails: set[str] | None = None,
) -> list[str]:
    """Primary emails for staff roles that should see approved bookings on Google Calendar."""
    from models import User

    exclude = {e.strip().lower() for e in exclude_emails if e and e.strip()} if exclude_emails else set()
    seen: set[str] = set()
    out: list[str] = []
    for role in CALENDAR_INVITE_STAFF_ROLES:
        users = await User.find(User.role == role).to_list()
        for u in users:
            em = (u.email or "").strip().lower()
            if not em or em in exclude or em in seen:
                continue
            seen.add(em)
            out.append(em)
    return out


def verify_google_token(token: str):
    response = requests.get(GOOGLE_TOKEN_INFO_URL, params={"id_token": token})

    if response.status_code != 200:
        raise HTTPException(status_code=401, detail="Invalid Google token")

    data = response.json()

    email = data.get("email")
    if not ALLOWED_DOMAIN or not any(email.endswith(d) for d in ALLOWED_DOMAIN):
        raise HTTPException(
            status_code=403,
            detail="Only Vidyashilp accounts allowed"
        )

    return data


def create_access_token(data: dict):
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    data["exp"] = expire
    return jwt.encode(data, SECRET_KEY, algorithm=ALGORITHM)


def decode_access_token(token: str) -> dict:
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token"
        )


def create_oauth_state(user_id: str) -> str:
    payload = {
        "user_id": user_id,
        "exp": datetime.utcnow() + timedelta(minutes=10)
    }
    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def decode_oauth_state(state: str) -> dict:
    try:
        return jwt.decode(state, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid OAuth state"
        )


async def ensure_google_access_token(user):
    if user.google_access_token and user.google_token_expiry:
        expiry = user.google_token_expiry
        if expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=timezone.utc)
        if expiry > datetime.now(timezone.utc) + timedelta(minutes=1):
            return user.google_access_token

    if not user.google_refresh_token:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Google not connected"
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
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Unable to refresh Google token. Please reconnect Google.",
        )

    data = response.json()
    access_token = data.get("access_token")
    expires_in = data.get("expires_in", 3600)
    if not access_token:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Google token missing. Please reconnect Google.",
        )

    user.google_access_token = access_token
    user.google_token_expiry = datetime.now(timezone.utc) + timedelta(seconds=expires_in)
    await user.save()
    return access_token
