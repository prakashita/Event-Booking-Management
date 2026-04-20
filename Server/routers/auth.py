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
from routers.deps import get_current_user, get_current_user_any_status
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

    is_new_user = False
    if not user:
        is_new_user = True
        # Determine initial approval status:
        # - Admin emails get immediate "approved" status
        # - Users with a pre-assigned role (via Add User) get "approved" status
        # - Everyone else starts as "pending"
        pending_role = await PendingRoleAssignment.find_one(PendingRoleAssignment.email == email.lower().strip())
        if is_admin_email(email):
            user = User(
                name=name,
                email=email,
                google_id=google_id,
                role="admin",
                approval_status="approved",
            )
            await user.insert()
        elif pending_role and pending_role.role:
            user = User(
                name=name,
                email=email,
                google_id=google_id,
                role=(pending_role.role or "").strip().lower(),
                approval_status="approved",
            )
            await user.insert()
            await pending_role.delete()
        else:
            user = User(
                name=name,
                email=email,
                google_id=google_id,
                role="faculty",
                approval_status="pending",
                requested_role="faculty",
            )
            await user.insert()
    else:
        # Existing user: backfill approval_status if missing (pre-existing users treated as approved)
        if not getattr(user, "approval_status", None):
            user.approval_status = "approved"
            await user.save()

    # Always enforce admin email -> admin role
    normalized_role = (user.role or "").strip().lower()
    if is_admin_email(email) and normalized_role != "admin":
        user.role = "admin"
        if (getattr(user, "approval_status", None) or "") != "approved":
            user.approval_status = "approved"
        await user.save()

    jwt_token = create_access_token({"user_id": str(user.id)})

    return {
        "access_token": jwt_token,
        "user": {
            "id": str(user.id),
            "name": user.name,
            "email": user.email,
            "role": user.role,
            "approval_status": getattr(user, "approval_status", None) or "approved",
        }
    }


@router.get("/google/status")
async def google_oauth_status(user: User = Depends(get_current_user)):
    # Allow even pending/rejected users to check Google OAuth status
    # (get_current_user_any_status is not needed here since this is  
    #  already behind authentication; but approval gate is at app level)
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
    """Primary emails used by the staged event-approval workflow UI."""
    deputy = await get_primary_email_by_role("deputy_registrar")
    finance = await get_primary_email_by_role("finance_team")
    registrar = await get_primary_email_by_role("registrar")
    vc = await get_primary_email_by_role("vice_chancellor")
    return {
        "deputy_registrar_email": deputy or "",
        "finance_team_email": finance or "",
        "registrar_email": registrar or "",
        "vice_chancellor_email": vc or "",
    }


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


@router.get("/me")
async def get_current_user_info(user: User = Depends(get_current_user_any_status)):
    """Return current user info including approval_status. Accessible by any authenticated user
    regardless of approval state (needed for holding/rejection screens)."""
    return {
        "id": str(user.id),
        "name": user.name,
        "email": user.email,
        "role": user.role,
        "approval_status": getattr(user, "approval_status", None) or "approved",
    }
