import os
from datetime import datetime, timedelta
from jose import jwt, JWTError
import requests
from fastapi import HTTPException, status
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

SECRET_KEY = os.getenv("SECRET_KEY", "CHANGE_ME_LATER")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24

GOOGLE_TOKEN_INFO_URL = "https://oauth2.googleapis.com/tokeninfo"
ALLOWED_DOMAIN = ["@srmap.edu.in", "@vidyashilp.edu.in"]

GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.getenv("GOOGLE_CLIENT_SECRET", "")
GOOGLE_REDIRECT_URI = os.getenv("GOOGLE_REDIRECT_URI", "http://localhost:8000/calendar/oauth/callback")
GOOGLE_CALENDAR_SCOPE = "https://www.googleapis.com/auth/calendar.readonly"



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
