from datetime import datetime

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User, RefreshToken
from ..schemas import (
    LoginRequest,
    TokenResponse,
    RefreshRequest,
    ForgotPasswordRequest,
    ChangePasswordRequest,
)
from ..security import (
    verify_password,
    hash_password,
    create_access_token,
    create_refresh_token,
    refresh_token_expiry,
    generate_temp_password,
    send_password_reset_email,
)
from ..config import settings
from ..deps import get_current_user

router = APIRouter(prefix="/auth", tags=["auth"])


def _token_payload(user: User) -> dict:
    return {
        "sub": str(user.id),
        "preferred_username": user.username,
        "email": user.email,
        "name": user.name,
        "groups": [g.name for g in user.groups],
    }


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    user = (
        db.query(User)
        .filter(User.username == body.username.lower(), User.is_active == True)
        .first()
    )
    if not user or not verify_password(body.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )

    # Track last login
    user.last_login_at = datetime.utcnow()

    # Determine password policy flags
    must_change = bool(user.must_change_password)
    password_expired = False
    if not must_change and user.password_changed_at:
        days_since = (datetime.utcnow() - user.password_changed_at).days
        if days_since >= settings.password_expiry_days:
            password_expired = True

    access_token = create_access_token(_token_payload(user))
    rt_str = create_refresh_token()
    db.add(RefreshToken(user_id=user.id, token=rt_str, expires_at=refresh_token_expiry()))
    db.commit()

    return TokenResponse(
        access_token=access_token,
        refresh_token=rt_str,
        must_change_password=must_change,
        password_expired=password_expired,
    )


@router.post("/refresh", response_model=TokenResponse)
def refresh(body: RefreshRequest, db: Session = Depends(get_db)):
    rt = (
        db.query(RefreshToken)
        .filter(
            RefreshToken.token == body.refresh_token,
            RefreshToken.expires_at > datetime.utcnow(),
        )
        .first()
    )
    if not rt:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    user = db.query(User).filter(User.id == rt.user_id, User.is_active == True).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    # Rotate refresh token
    db.delete(rt)
    new_rt_str = create_refresh_token()
    db.add(RefreshToken(user_id=user.id, token=new_rt_str, expires_at=refresh_token_expiry()))
    db.commit()

    return TokenResponse(
        access_token=create_access_token(_token_payload(user)),
        refresh_token=new_rt_str,
    )


@router.post("/logout", status_code=204)
def logout(body: RefreshRequest, db: Session = Depends(get_db)):
    rt = db.query(RefreshToken).filter(RefreshToken.token == body.refresh_token).first()
    if rt:
        db.delete(rt)
        db.commit()


@router.post("/forgot-password", status_code=202)
def forgot_password(
    body: ForgotPasswordRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    """Self-service password reset. Always returns 202 to avoid email enumeration."""
    user = db.query(User).filter(User.email == body.email.lower()).first()
    if user and user.is_active:
        temp_pw = generate_temp_password()
        user.hashed_password = hash_password(temp_pw)
        user.must_change_password = True
        user.password_changed_at = datetime.utcnow()
        db.commit()
        background_tasks.add_task(
            send_password_reset_email, user.email, user.name, temp_pw
        )
    return {"detail": "If that email is registered, a reset password has been sent."}


@router.post("/change-password", status_code=200)
def change_password(
    body: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Authenticated users change their own password (or fulfil must_change_password)."""
    if not verify_password(body.current_password, current_user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current password is incorrect.",
        )
    if len(body.new_password) < 8:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="New password must be at least 8 characters.",
        )
    current_user.hashed_password = hash_password(body.new_password)
    current_user.must_change_password = False
    current_user.password_changed_at = datetime.utcnow()
    db.commit()
    return {"detail": "Password changed successfully."}
