from beanie import PydanticObjectId
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import JSONResponse

from models import ApprovalRequest, Event, FacilityManagerRequest, Invite, ItRequest, MarketingRequest, PendingRoleAssignment, Publication, TransportRequest, User
from routers.deps import require_admin
from schemas import AddUserRequest, UserAdminResponse, UserRoleUpdate

router = APIRouter(prefix="/users", tags=["Users"])


def serialize_user(user: User) -> UserAdminResponse:
    return UserAdminResponse(
        id=str(user.id),
        name=user.name,
        email=user.email,
        role=user.role,
        created_at=user.created_at,
        last_seen=user.last_seen,
    )


ADD_USER_ALLOWED_ROLES = {"registrar", "facility_manager", "marketing", "it", "transport"}


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

    existing = await User.find_one(User.email == email)
    if existing:
        existing.role = role
        await existing.save()
        return serialize_user(existing)

    existing_pending = await PendingRoleAssignment.find_one(PendingRoleAssignment.email == email)
    if existing_pending:
        existing_pending.role = role
        existing_pending.created_by = str(admin.id)
        await existing_pending.save()
        return {"detail": "User not yet signed in. Role will apply when they log in.", "status": "pending"}

    pending = PendingRoleAssignment(
        email=email,
        role=role,
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

    await user.delete()
    return {"status": "deleted", "id": user_id}
