from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from .database import get_db
from .models import User
from .security import decode_access_token

bearer = HTTPBearer()

# Role hierarchy levels (must match Flutter role.dart)
_ROLE_LEVELS: dict[str, int] = {
    "superadmin": 7,
    "admin": 6,
    "head": 5,
    "supervisor": 4,
    "sme": 3,
    "engineer": 2,
    "trainee": 1,
}


def _highest_role_level(user: User) -> int:
    if user.is_superadmin:
        return _ROLE_LEVELS["superadmin"]
    group_names = {g.name.lower() for g in user.groups}
    return max((_ROLE_LEVELS.get(n, 0) for n in group_names), default=0)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer),
    db: Session = Depends(get_db),
) -> User:
    payload = decode_access_token(credentials.credentials)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
        )
    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
        )
    user = (
        db.query(User)
        .filter(User.id == int(user_id), User.is_active == True)
        .first()
    )
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive",
        )
    return user


def require_superadmin(user: User = Depends(get_current_user)) -> User:
    """superadmin only."""
    if not user.is_superadmin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Superadmin access required",
        )
    return user


def require_admin(user: User = Depends(get_current_user)) -> User:
    """superadmin or admin — legacy alias kept for backwards compat."""
    if _highest_role_level(user) < _ROLE_LEVELS["admin"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required",
        )
    return user


def require_group_manager(user: User = Depends(get_current_user)) -> User:
    """superadmin, admin, or head — can create/rename/delete groups."""
    if _highest_role_level(user) < _ROLE_LEVELS["head"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Head-level or above access required",
        )
    return user


def require_manager(user: User = Depends(get_current_user)) -> User:
    """superadmin, admin, head, sme, or supervisor — can manage users/tiles."""
    if _highest_role_level(user) < _ROLE_LEVELS["sme"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Manager-level access required",
        )
    return user
