from typing import Optional, List
from pydantic import BaseModel, EmailStr

# ── Auth ──────────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    must_change_password: bool = False
    password_expired: bool = False


class RefreshRequest(BaseModel):
    refresh_token: str


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


class ResetPasswordAdminResponse(BaseModel):
    message: str
    temp_password: str  # returned to admin in case email delivery fails


# ── Groups ────────────────────────────────────────────────────────────────────

class GroupSummary(BaseModel):
    pk: str
    name: str


class GroupOut(BaseModel):
    pk: str
    name: str


class GroupDetail(BaseModel):
    pk: str
    name: str
    tiles: List["TileOut"] = []


class GroupCreate(BaseModel):
    name: str


class GroupUpdate(BaseModel):
    name: str


class GroupTileAssign(BaseModel):
    tile_slug: str


class GroupUserAssign(BaseModel):
    user_id: int


# ── Tiles ─────────────────────────────────────────────────────────────────────

class TileOut(BaseModel):
    pk: str
    name: str
    slug: str
    meta_launch_url: str
    meta_icon: Optional[str] = None
    meta_description: Optional[str] = None
    quick_panel: Optional[str] = None


class TileCreate(BaseModel):
    name: str
    slug: str
    meta_launch_url: str
    meta_icon: Optional[str] = None
    meta_description: Optional[str] = None
    quick_panel: Optional[str] = None


class TileUpdate(BaseModel):
    name: Optional[str] = None
    meta_launch_url: Optional[str] = None
    meta_icon: Optional[str] = None
    meta_description: Optional[str] = None
    quick_panel: Optional[str] = None


# ── Users ─────────────────────────────────────────────────────────────────────

class UserOut(BaseModel):
    pk: str
    username: str
    email: str
    name: str
    groups: List[GroupSummary] = []
    is_active: bool = True
    is_superadmin: bool = False


class UserCreate(BaseModel):
    username: str
    email: EmailStr
    name: str = ""
    password: str
    is_superadmin: bool = False


class UserUpdate(BaseModel):
    email: Optional[EmailStr] = None
    name: Optional[str] = None
    password: Optional[str] = None
    is_active: Optional[bool] = None
    is_superadmin: Optional[bool] = None


class UserGroupsSet(BaseModel):
    group_ids: List[int]


# ── /me ───────────────────────────────────────────────────────────────────────

class MeResponse(BaseModel):
    pk: str
    username: str
    email: str
    name: str
    groups: List[GroupSummary] = []
    tiles: List[TileOut] = []
