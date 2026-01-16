import os
from datetime import datetime, timedelta
from jose import jwt
import requests
from fastapi import HTTPException
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

SECRET_KEY = os.getenv("SECRET_KEY", "CHANGE_ME_LATER")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24

GOOGLE_TOKEN_INFO_URL = "https://oauth2.googleapis.com/tokeninfo"
ALLOWED_DOMAIN = ["@srmap.edu.in", "@vidyashilp.edu.in"]



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
