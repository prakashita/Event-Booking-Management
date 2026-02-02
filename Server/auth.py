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
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24

GOOGLE_TOKEN_INFO_URL = "https://oauth2.googleapis.com/tokeninfo"
ALLOWED_DOMAIN = ["@srmap.edu.in", "@vidyashilp.edu.in"]

GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
GOOGLE_REDIRECT_URI = os.getenv("GOOGLE_REDIRECT_URI", "http://localhost:8000/calendar/oauth/callback")
GOOGLE_OAUTH_SCOPE = "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/gmail.send https://www.googleapis.com/auth/drive.file"
REQUIRED_GOOGLE_SCOPES = GOOGLE_OAUTH_SCOPE.split()



def verify_google_token(token: str):
    response = requests.get(GOOGLE_TOKEN_INFO_URL, params={"id_token": token})

    if response.status_code != 200:
        raise HTTPException(status_code=401, detail="Invalid Google token")

    data = response.json()

    email = data.get("email")
    if not any(email.endswith(domain) for domain in ALLOWED_DOMAIN):
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
