from datetime import datetime, timedelta
from jose import jwt
import requests
from fastapi import HTTPException

SECRET_KEY = "CHANGE_ME_LATER"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24

GOOGLE_TOKEN_INFO_URL = "https://oauth2.googleapis.com/tokeninfo"
ALLOWED_DOMAIN = "@srmap.edu.in"


def verify_google_token(token: str):
    response = requests.get(GOOGLE_TOKEN_INFO_URL, params={"id_token": token})

    if response.status_code != 200:
        raise HTTPException(status_code=401, detail="Invalid Google token")

    data = response.json()

    email = data.get("email")
    if not email.endswith(ALLOWED_DOMAIN):
        raise HTTPException(
            status_code=403,
            detail="Only SRM AP accounts allowed"
        )

    return data


def create_access_token(data: dict):
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    data["exp"] = expire
    return jwt.encode(data, SECRET_KEY, algorithm=ALGORITHM)
