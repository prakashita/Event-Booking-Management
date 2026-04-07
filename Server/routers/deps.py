import logging
from typing import Optional

from beanie import PydanticObjectId
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from auth import decode_access_token, is_admin_email
from models import ChatConversation, User

security = HTTPBearer(auto_error=False)
logger = logging.getLogger("event-booking.auth")


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> User:
    if not credentials:
        logger.warning("get_current_user: Missing token")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing token")

    try:
        payload = decode_access_token(credentials.credentials)
    except HTTPException as exc:
        logger.warning("get_current_user: Token decode failed: %s", exc.detail)
        raise

    user_id = payload.get("user_id")
    if not user_id:
        logger.warning("get_current_user: No user_id in payload")
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    try:
        oid = PydanticObjectId(user_id)
    except Exception:
        logger.warning("get_current_user: Invalid user_id format user_id=%s", user_id)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    user = await User.get(oid)
    if not user:
        logger.warning("get_current_user: User not found user_id=%s", user_id)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user

async def require_admin(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> User:
    user = await get_current_user(credentials)
    allowed_roles = {"admin", "registrar"}
    if (user.role or '').strip().lower() not in allowed_roles:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Admin access required')
    return user


# Roles that may access IQAC Data Collection (criteria, upload/list/download/delete).
# Frontend must mirror this for sidebar visibility and route guard (see ROLES_WITH_IQAC_ACCESS in Client).
IQAC_ALLOWED_ROLES = frozenset({"iqac", "faculty", "admin", "registrar"})
# Faculty may upload and view but not delete; must match Client ROLES_WITH_IQAC_DELETE_ACCESS.
IQAC_DELETE_ALLOWED_ROLES = frozenset({"iqac", "admin", "registrar"})


async def require_iqac(
    credentials: HTTPAuthorizationCredentials = Depends(security),
) -> User:
    user = await get_current_user(credentials)
    if (user.role or '').strip().lower() not in IQAC_ALLOWED_ROLES:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='IQAC access required')
    return user


# ---------------------------------------------------------------------------
# Conversation / thread access helpers
# ---------------------------------------------------------------------------

def _user_role(user: User) -> str:
    return (user.role or "").strip().lower()


def _is_privileged(user: User) -> bool:
    """Admin or registrar-level access."""
    return _user_role(user) in ("admin", "registrar") or is_admin_email(user.email or "")


def can_view_conversation(user: User, conversation: ChatConversation) -> bool:
    """Check if *user* is authorized to view *conversation*.

    Rules:
    - Direct / event threads: user must be a listed participant.
    - Approval threads: user must be a participant OR an admin.
      Registrars are treated as participants only for registrar-department
      threads, not for other department threads (unless explicitly added).
    """
    uid = str(user.id)
    kind = getattr(conversation, "thread_kind", None) or "direct"

    # Participant check — always sufficient
    if uid in (conversation.participants or []):
        return True

    # For approval_threads, admin may view for oversight
    if kind == "approval_thread" and _user_role(user) == "admin":
        return True

    return False


def can_post_to_conversation(user: User, conversation: ChatConversation) -> bool:
    """Check if *user* can send messages to *conversation*.

    Must be participant, and thread must not be resolved/closed.
    """
    uid = str(user.id)
    if uid not in (conversation.participants or []):
        return False

    kind = getattr(conversation, "thread_kind", None) or "direct"
    if kind == "approval_thread":
        ts = getattr(conversation, "thread_status", None) or "active"
        if ts in ("resolved", "closed"):
            return False

    return True


async def require_conversation_access(
    user: User,
    conversation_id: str,
    *,
    write: bool = False,
) -> ChatConversation:
    """Load a conversation and verify the user can access (and optionally post to) it.

    Raises 404 if not found or not authorized (intentionally vague to avoid
    leaking conversation existence).
    """
    try:
        conv = await ChatConversation.get(PydanticObjectId(conversation_id))
    except Exception:
        conv = None
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")
    if not can_view_conversation(user, conv):
        raise HTTPException(status_code=404, detail="Conversation not found")
    if write and not can_post_to_conversation(user, conv):
        raise HTTPException(status_code=403, detail="Cannot send to this conversation")
    return conv

