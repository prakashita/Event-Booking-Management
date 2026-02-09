from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from models import User
from auth import REQUIRED_GOOGLE_SCOPES, ensure_google_access_token, verify_google_token, create_access_token, is_admin_email
from routers.deps import get_current_user
import requests

router = APIRouter(prefix="/auth", tags=["Auth"])


class TokenRequest(BaseModel):
    token: str


@router.post("/google")
async def google_login(payload: TokenRequest):
    google_data = verify_google_token(payload.token)

    google_id = google_data["sub"]
    email = google_data["email"]
    name = google_data.get("name", "")

    # Find user by google_id
    user = await User.find_one(User.google_id == google_id)

    if not user:
        # Create new user if doesn't exist
        user = User(
            name=name,
            email=email,
            google_id=google_id
        )
        await user.insert()

    if is_admin_email(email) and (user.role or "").strip().lower() != "admin":
        user.role = "admin"
        await user.save()

    jwt_token = create_access_token({"user_id": str(user.id)})

    return {
        "access_token": jwt_token,
        "user": {
            "id": str(user.id),
            "name": user.name,
            "email": user.email,
            "role": user.role
        }
    }


@router.get("/google/status")
async def google_oauth_status(user: User = Depends(get_current_user)):
    if not user.google_refresh_token:
        return {"connected": False, "missing_scopes": REQUIRED_GOOGLE_SCOPES}

    try:
        access_token = await ensure_google_access_token(user)
    except HTTPException as exc:
        if exc.status_code in {status.HTTP_403_FORBIDDEN, status.HTTP_401_UNAUTHORIZED}:
            return {"connected": False, "missing_scopes": REQUIRED_GOOGLE_SCOPES}
        raise

    response = requests.get(
        "https://oauth2.googleapis.com/tokeninfo",
        params={"access_token": access_token},
        timeout=10,
    )
    if response.status_code != 200:
        return {"connected": False, "missing_scopes": REQUIRED_GOOGLE_SCOPES}

    data = response.json()
    granted_scopes = set((data.get("scope") or "").split())
    missing = [scope for scope in REQUIRED_GOOGLE_SCOPES if scope not in granted_scopes]
    return {"connected": len(missing) == 0, "missing_scopes": missing}
