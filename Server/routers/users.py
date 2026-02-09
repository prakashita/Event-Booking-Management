from fastapi import APIRouter, Depends, HTTPException, status

from models import ApprovalRequest, Event, Invite, ItRequest, MarketingRequest, Publication, User
from routers.deps import require_admin
from schemas import UserAdminResponse, UserRoleUpdate

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


@router.get("", response_model=list[UserAdminResponse])
async def list_users(admin: User = Depends(require_admin)):
    users = await User.find_all().sort("name").to_list()
    return [serialize_user(user) for user in users]


@router.patch("/{user_id}/role", response_model=UserAdminResponse)
async def update_user_role(
    user_id: str,
    payload: UserRoleUpdate,
    admin: User = Depends(require_admin),
):
    user = await User.get(user_id)
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

    user = await User.get(user_id)
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    # Cascade delete user-related data
    await Event.find(Event.created_by == user_id).delete()
    await ApprovalRequest.find(ApprovalRequest.requester_id == user_id).delete()
    await MarketingRequest.find(MarketingRequest.requester_id == user_id).delete()
    await ItRequest.find(ItRequest.requester_id == user_id).delete()
    await Invite.find(Invite.created_by == user_id).delete()
    await Publication.find(Publication.created_by == user_id).delete()

    await user.delete()
    return {"status": "deleted", "id": user_id}
