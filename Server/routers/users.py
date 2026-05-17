from beanie import PydanticObjectId
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import JSONResponse

from models import ApprovalRequest, Event, FacilityManagerRequest, Invite, ItRequest, MarketingRequest, PendingRoleAssignment, Publication, TransportRequest, User
from routers.deps import require_admin
from schemas import AddUserRequest, PaginatedResponse, UserAdminResponse, UserApprovalAction, UserRoleUpdate

router = APIRouter(prefix="/users", tags=["Users"])


def serialize_user(user: User) -> UserAdminResponse:
    return UserAdminResponse(
        id=str(user.id),
        name=user.name,
        email=user.email,
        role=user.role,
        enabled_modules=normalize_modules(getattr(user, "enabled_modules", []) or []),
        approval_status=getattr(user, "approval_status", None) or "approved",
        approved_by=getattr(user, "approved_by", None),
        approved_at=getattr(user, "approved_at", None),
        rejected_by=getattr(user, "rejected_by", None),
        rejected_at=getattr(user, "rejected_at", None),
        rejection_reason=getattr(user, "rejection_reason", None),
        requested_role=getattr(user, "requested_role", None),
        created_at=user.created_at,
        last_seen=user.last_seen,
    )


ADD_USER_ALLOWED_ROLES = {
    "admin",
    "faculty",
    "registrar",
    "vice_chancellor",
    "deputy_registrar",
    "finance_team",
    "facility_manager",
    "marketing",
    "it",
    "transport",
    "iqac",
}

ALLOWED_ADDON_MODULES = {"iqac"}


def normalize_modules(modules: list[str] | None) -> list[str]:
    seen = set()
    normalized = []
    for module in modules or []:
        value = (module or "").strip().lower()
        if value in ALLOWED_ADDON_MODULES and value not in seen:
            seen.add(value)
            normalized.append(value)
    return normalized


@router.get("", response_model=list[UserAdminResponse])
async def list_users(admin: User = Depends(require_admin)):
    users = await User.find_all().sort("name").to_list()
    return [serialize_user(user) for user in users]


@router.post("/add")
async def add_user(
    payload: AddUserRequest,
    admin: User = Depends(require_admin),
):
    email = (payload.email or "").strip().lower()
    if not email:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email is required")

    role = (payload.role or "").strip().lower()
    if role not in ADD_USER_ALLOWED_ROLES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Role must be one of: {', '.join(sorted(ADD_USER_ALLOWED_ROLES))}",
        )
    enabled_modules = normalize_modules(payload.enabled_modules)

    existing = await User.find_one(User.email == email)
    if existing:
        existing.role = role
        existing.enabled_modules = enabled_modules
        # If user was pending/rejected, adding them via admin console also approves them
        if (getattr(existing, "approval_status", None) or "approved") != "approved":
            existing.approval_status = "approved"
            existing.approved_by = str(admin.id)
            existing.approved_at = datetime.utcnow()
        await existing.save()
        return serialize_user(existing)

    existing_pending = await PendingRoleAssignment.find_one(PendingRoleAssignment.email == email)
    if existing_pending:
        existing_pending.role = role
        existing_pending.enabled_modules = enabled_modules
        existing_pending.created_by = str(admin.id)
        await existing_pending.save()
        return {"detail": "User not yet signed in. Role will apply when they log in.", "status": "pending"}

    pending = PendingRoleAssignment(
        email=email,
        role=role,
        enabled_modules=enabled_modules,
        created_by=str(admin.id),
    )
    await pending.insert()
    return JSONResponse(
        status_code=status.HTTP_201_CREATED,
        content={"detail": "User added. They will get this role when they first sign in.", "status": "pending"},
    )


@router.patch("/{user_id}/role", response_model=UserAdminResponse)
async def update_user_role(
    user_id: str,
    payload: UserRoleUpdate,
    admin: User = Depends(require_admin),
):
    try:
        oid = PydanticObjectId(user_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid user id")

    user = await User.get(oid)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    role = (payload.role or "").strip().lower()
    if not role:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Role is required")

    user.role = role
    if payload.enabled_modules is not None:
        user.enabled_modules = normalize_modules(payload.enabled_modules)
    await user.save()
    return serialize_user(user)


@router.delete("/{user_id}")
async def delete_user(user_id: str, admin: User = Depends(require_admin)):
    if str(admin.id) == user_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot delete yourself")

    try:
        oid = PydanticObjectId(user_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid user id")

    user = await User.get(oid)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    # Cascade delete user-related data
    await Event.find(Event.created_by == user_id).delete()
    await ApprovalRequest.find(ApprovalRequest.requester_id == user_id).delete()
    await FacilityManagerRequest.find(FacilityManagerRequest.requester_id == user_id).delete()
    await MarketingRequest.find(MarketingRequest.requester_id == user_id).delete()
    await ItRequest.find(ItRequest.requester_id == user_id).delete()
    await TransportRequest.find(TransportRequest.requester_id == user_id).delete()
    await Invite.find(Invite.created_by == user_id).delete()
    await Publication.find(Publication.created_by == user_id).delete()
    await PendingRoleAssignment.find(PendingRoleAssignment.email == (user.email or "").strip().lower()).delete()

    await user.delete()
    return {"status": "deleted", "id": user_id}


# ---------------------------------------------------------------------------
# User Approval workflow endpoints
# ---------------------------------------------------------------------------

@router.get("/pending-approvals", response_model=list[UserAdminResponse])
async def list_pending_users(admin: User = Depends(require_admin)):
    """List users awaiting approval."""
    users = await User.find(User.approval_status == "pending").sort("-created_at").to_list()
    return [serialize_user(u) for u in users]


@router.get("/rejected-users", response_model=list[UserAdminResponse])
async def list_rejected_users(admin: User = Depends(require_admin)):
    """List rejected users for audit history."""
    users = await User.find(User.approval_status == "rejected").sort("-rejected_at").to_list()
    return [serialize_user(u) for u in users]


@router.get("/pending-approvals/count")
async def pending_approvals_count(admin: User = Depends(require_admin)):
    """Quick count of pending users for badge display."""
    count = await User.find(User.approval_status == "pending").count()
    return {"count": count}


@router.post("/{user_id}/approval", response_model=UserAdminResponse)
async def decide_user_approval(
    user_id: str,
    payload: UserApprovalAction,
    admin: User = Depends(require_admin),
):
    """Approve or reject a pending user."""
    try:
        oid = PydanticObjectId(user_id)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid user id")

    user = await User.get(oid)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    current_status = (getattr(user, "approval_status", None) or "approved").strip().lower()

    if payload.action == "approve":
        if current_status == "approved":
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="User is already approved")
        role = (payload.role or user.role or "faculty").strip().lower()
        user.role = role
        user.approval_status = "approved"
        user.approved_by = str(admin.id)
        user.approved_at = datetime.utcnow()
        # Clear any previous rejection
        user.rejected_by = None
        user.rejected_at = None
        user.rejection_reason = None
        await user.save()

        # Send approval email (best-effort)
        from notifications import send_notification_email
        try:
            await send_notification_email(
                recipient_email=user.email,
                subject="Your account has been approved",
                body=(
                    f"Hello {user.name},\n\n"
                    f"Your account on the VU Sync: Events and Repository Management system has been approved.\n"
                    f"Your assigned role is: {role}.\n\n"
                    f"You can now sign in and access the application.\n\n"
                    f"Regards,\nVU Sync"
                ),
                requester=admin,
                fallback_role="admin",
            )
        except Exception:
            pass  # email failure should not block the approval

        return serialize_user(user)

    elif payload.action == "reject":
        if current_status == "rejected":
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="User is already rejected")
        user.approval_status = "rejected"
        user.rejected_by = str(admin.id)
        user.rejected_at = datetime.utcnow()
        user.rejection_reason = (payload.rejection_reason or "").strip() or None
        await user.save()

        # Send rejection email (best-effort)
        from notifications import send_notification_email
        reason_line = f"\nReason: {user.rejection_reason}\n" if user.rejection_reason else "\n"
        try:
            await send_notification_email(
                recipient_email=user.email,
                subject="Account access request update",
                body=(
                    f"Hello {user.name},\n\n"
                    f"We regret to inform you that your access request for the VU Sync: Events and Repository Management "
                    f"system has not been approved at this time.{reason_line}\n"
                    f"If you believe this is an error, please contact the administrator.\n\n"
                    f"Regards,\nVU Sync"
                ),
                requester=admin,
                fallback_role="admin",
            )
        except Exception:
            pass

        return serialize_user(user)
    else:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="action must be 'approve' or 'reject'")
