import logging

from beanie import PydanticObjectId
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from auth import decode_access_token
from models import User

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

