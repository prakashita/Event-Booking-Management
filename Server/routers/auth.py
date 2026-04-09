from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel

from rate_limit import limiter
from models import PendingRoleAssignment, User
from auth import (
    REQUIRED_GOOGLE_SCOPES,
    ensure_google_access_token,
    get_primary_email_by_role,
    verify_google_token,
    create_access_token,
    is_admin_email,
)
from routers.deps import get_current_user
import requests

router = APIRouter(prefix="/auth", tags=["Auth"])


class TokenRequest(BaseModel):
    token: str


@router.post("/google")
@limiter.limit("10/minute")
async def google_login(request: Request, payload: TokenRequest):
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
        # Apply pre-assigned role from Add User (pending role assignment)
        pending = await PendingRoleAssignment.find_one(PendingRoleAssignment.email == email.lower().strip())
        if pending and pending.role:
            user.role = (pending.role or "").strip().lower()
            await user.save()
            await pending.delete()

    normalized_role = (user.role or "").strip().lower()
    if is_admin_email(email) and normalized_role != "admin":
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
        if exc.status_code in {
            status.HTTP_403_FORBIDDEN,
            status.HTTP_401_UNAUTHORIZED,
            status.HTTP_502_BAD_GATEWAY,
        }:
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


@router.get("/registrar-email")
async def get_registrar_email(user: User = Depends(get_current_user)):
    """Return the registrar email for display in approval forms."""
    email = await get_primary_email_by_role("registrar")
    return {"email": email or ""}


@router.get("/event-approval-emails")
async def get_event_approval_emails(user: User = Depends(get_current_user)):
    """Registrar and vice chancellor primary emails for event approval routing UI."""
    registrar = await get_primary_email_by_role("registrar")
    vc = await get_primary_email_by_role("vice_chancellor")
    return {"registrar_email": registrar or "", "vice_chancellor_email": vc or ""}


@router.get("/facility-manager-email")
async def get_facility_manager_email(user: User = Depends(get_current_user)):
    """Return the facility manager email for prefilling request forms."""
    email = await get_primary_email_by_role("facility_manager")
    return {"email": email or ""}


@router.get("/marketing-email")
async def get_marketing_email(user: User = Depends(get_current_user)):
    """Return the marketing email for prefilling request forms."""
    email = await get_primary_email_by_role("marketing")
    return {"email": email or ""}


@router.get("/it-email")
async def get_it_email(user: User = Depends(get_current_user)):
    """Return the IT email for prefilling request forms."""
    email = await get_primary_email_by_role("it")
    return {"email": email or ""}


@router.get("/transport-email")
async def get_transport_email(user: User = Depends(get_current_user)):
    """Return the transport coordinator email for prefilling request forms."""
    email = await get_primary_email_by_role("transport")
    return {"email": email or ""}
