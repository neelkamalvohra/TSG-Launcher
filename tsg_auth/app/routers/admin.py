from datetime import datetime

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import (
    get_current_user,
    require_superadmin,
    require_group_manager,
    require_manager,
)
from ..models import User, Group, Tile
from ..schemas import (
    GroupOut, GroupCreate, GroupUpdate, GroupSummary, GroupTileAssign, GroupUserAssign,
    TileOut, TileCreate, TileUpdate,
    UserOut, UserCreate, UserUpdate, UserGroupsSet,
    ResetPasswordAdminResponse,
)
from ..security import hash_password, generate_temp_password, send_password_reset_email

router = APIRouter(prefix="/admin", tags=["admin"])

# Role hierarchy levels (mirror of deps.py / role.dart)
_ROLE_LEVELS: dict[str, int] = {
    "superadmin": 7,
    "admin": 6,
    "head": 5,
    "supervisor": 4,
    "sme": 3,
    "engineer": 2,
    "trainee": 1,
}

# Roles that only superadmin can assign
_PROTECTED_ROLES = {"admin", "superadmin"}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _user_out(u: User) -> UserOut:
    return UserOut(
        pk=str(u.id),
        username=u.username,
        email=u.email,
        name=u.name,
        groups=[GroupSummary(pk=str(g.id), name=g.name) for g in u.groups],
        is_active=u.is_active,
        is_superadmin=u.is_superadmin,
    )


def _tile_out(t: Tile) -> TileOut:
    return TileOut(
        pk=str(t.id),
        name=t.name,
        slug=t.slug,
        meta_launch_url=t.meta_launch_url,
        meta_icon=t.meta_icon,
        meta_description=t.meta_description,
        quick_panel=t.quick_panel,
    )


def _target_highest_role(target: User) -> int:
    """Return the highest role level of a target user (for permission checks)."""
    if target.is_superadmin:
        return _ROLE_LEVELS["superadmin"]
    group_names = {g.name.lower() for g in target.groups}
    return max((_ROLE_LEVELS.get(n, 0) for n in group_names), default=0)


def _check_can_modify_user(caller: User, target: User) -> None:
    """
    Raise 403 if caller does not have permission to modify the target user.
    - Superadmin can modify anyone.
    - admin/head/sme/supervisor cannot modify admin-or-above users.
    """
    if caller.is_superadmin:
        return
    target_level = _target_highest_role(target)
    if target_level >= _ROLE_LEVELS["admin"]:
        raise HTTPException(403, "Cannot modify admin or superadmin users")


# ── Users ─────────────────────────────────────────────────────────────────────

@router.get("/users", response_model=list[UserOut], dependencies=[Depends(require_manager)])
def list_users(db: Session = Depends(get_db)):
    return [_user_out(u) for u in db.query(User).order_by(User.username).all()]


@router.post("/users", response_model=UserOut, status_code=201)
def create_user(
    body: UserCreate,
    caller: User = Depends(require_manager),
    db: Session = Depends(get_db),
):
    # Only superadmin can create admin/superadmin accounts
    if body.is_superadmin and not caller.is_superadmin:
        raise HTTPException(403, "Only superadmin can create superadmin accounts")
    if db.query(User).filter(User.username == body.username.lower()).first():
        raise HTTPException(409, "Username already exists")
    if db.query(User).filter(User.email == body.email).first():
        raise HTTPException(409, "Email already exists")
    user = User(
        username=body.username.lower(),
        email=body.email,
        name=body.name,
        hashed_password=hash_password(body.password),
        is_superadmin=body.is_superadmin if caller.is_superadmin else False,
        must_change_password=True,
        password_changed_at=datetime.utcnow(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return _user_out(user)


@router.patch("/users/{user_id}", response_model=UserOut)
def update_user(
    user_id: int,
    body: UserUpdate,
    caller: User = Depends(require_manager),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    _check_can_modify_user(caller, user)
    if body.email is not None:
        user.email = body.email
    if body.name is not None:
        user.name = body.name
    if body.password is not None:
        user.hashed_password = hash_password(body.password)
        user.must_change_password = True
        user.password_changed_at = datetime.utcnow()
    if body.is_active is not None:
        user.is_active = body.is_active
    # Only superadmin can change is_superadmin
    if body.is_superadmin is not None:
        if not caller.is_superadmin:
            raise HTTPException(403, "Only superadmin can change superadmin status")
        user.is_superadmin = body.is_superadmin
    db.commit()
    db.refresh(user)
    return _user_out(user)


@router.put("/users/{user_id}/groups", status_code=204)
def set_user_groups(
    user_id: int,
    body: UserGroupsSet,
    caller: User = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """Replace all group memberships for a user with the given list."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    _check_can_modify_user(caller, user)
    # Prevent non-superadmin from assigning admin/superadmin groups
    if not caller.is_superadmin:
        new_groups = db.query(Group).filter(Group.id.in_(body.group_ids)).all()
        for g in new_groups:
            if g.name.lower() in _PROTECTED_ROLES:
                raise HTTPException(403, f"Cannot assign protected group '{g.name}'")
    groups = db.query(Group).filter(Group.id.in_(body.group_ids)).all()
    user.groups = groups
    db.commit()


@router.post("/users/{user_id}/reset-password", response_model=ResetPasswordAdminResponse)
def reset_user_password(
    user_id: int,
    background_tasks: BackgroundTasks,
    caller: User = Depends(require_manager),
    db: Session = Depends(get_db),
):
    """Admin-triggered password reset: generates a temp password and emails the user."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    _check_can_modify_user(caller, user)
    temp_pw = generate_temp_password()
    user.hashed_password = hash_password(temp_pw)
    user.must_change_password = True
    user.password_changed_at = datetime.utcnow()
    db.commit()
    background_tasks.add_task(
        send_password_reset_email, user.email, user.name, temp_pw
    )
    return ResetPasswordAdminResponse(
        message=f"Password reset for {user.username}. Email sent to {user.email}.",
        temp_password=temp_pw,
    )


@router.delete("/users/{user_id}", status_code=204, dependencies=[Depends(require_superadmin)])
def delete_user(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    db.delete(user)
    db.commit()


# ── Groups ────────────────────────────────────────────────────────────────────

# Ordered display sequence (for clients that want canonical ordering)
_GROUP_ORDER = ["superadmin", "admin", "head", "sme", "supervisor", "engineer", "trainee"]


def _group_sort_key(name: str) -> int:
    try:
        return _GROUP_ORDER.index(name.lower())
    except ValueError:
        return len(_GROUP_ORDER)  # unknown groups go to the end


@router.get("/groups", response_model=list[GroupOut], dependencies=[Depends(require_manager)])
def list_groups(db: Session = Depends(get_db)):
    groups = db.query(Group).all()
    groups.sort(key=lambda g: _group_sort_key(g.name))
    return [GroupOut(pk=str(g.id), name=g.name) for g in groups]


@router.get("/groups/{group_id}", dependencies=[Depends(require_manager)])
def get_group(group_id: int, db: Session = Depends(get_db)):
    g = db.query(Group).filter(Group.id == group_id).first()
    if not g:
        raise HTTPException(404, "Group not found")
    tiles = [TileOut(
        pk=str(t.id), name=t.name, slug=t.slug,
        meta_launch_url=t.meta_launch_url, meta_icon=t.meta_icon,
        meta_description=t.meta_description
    ) for t in g.tiles]
    users = [{"pk": str(u.id), "username": u.username, "name": u.name, "email": u.email}
             for u in g.users]
    return {"pk": str(g.id), "name": g.name, "tiles": tiles, "users": users}


@router.post("/groups", response_model=GroupOut, status_code=201, dependencies=[Depends(require_group_manager)])
def create_group(body: GroupCreate, db: Session = Depends(get_db)):
    if db.query(Group).filter(Group.name == body.name).first():
        raise HTTPException(409, "Group name already exists")
    g = Group(name=body.name)
    db.add(g)
    db.commit()
    db.refresh(g)
    return GroupOut(pk=str(g.id), name=g.name)


@router.patch("/groups/{group_id}", response_model=GroupOut, dependencies=[Depends(require_group_manager)])
def rename_group(group_id: int, body: GroupUpdate, db: Session = Depends(get_db)):
    g = db.query(Group).filter(Group.id == group_id).first()
    if not g:
        raise HTTPException(404, "Group not found")
    if db.query(Group).filter(Group.name == body.name, Group.id != group_id).first():
        raise HTTPException(409, "Group name already exists")
    g.name = body.name
    db.commit()
    db.refresh(g)
    return GroupOut(pk=str(g.id), name=g.name)


@router.post("/groups/{group_id}/users", status_code=204, dependencies=[Depends(require_manager)])
def add_user_to_group(group_id: int, body: GroupUserAssign, db: Session = Depends(get_db)):
    g = db.query(Group).filter(Group.id == group_id).first()
    if not g:
        raise HTTPException(404, "Group not found")
    user = db.query(User).filter(User.id == body.user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    if user not in g.users:
        g.users.append(user)
        db.commit()


@router.delete("/groups/{group_id}/users/{user_id}", status_code=204, dependencies=[Depends(require_manager)])
def remove_user_from_group(group_id: int, user_id: int, db: Session = Depends(get_db)):
    g = db.query(Group).filter(Group.id == group_id).first()
    if not g:
        raise HTTPException(404, "Group not found")
    user = db.query(User).filter(User.id == user_id).first()
    if user and user in g.users:
        g.users.remove(user)
        db.commit()


@router.post("/groups/{group_id}/tiles", status_code=204, dependencies=[Depends(require_manager)])
def add_tile_to_group(group_id: int, body: GroupTileAssign, db: Session = Depends(get_db)):
    g = db.query(Group).filter(Group.id == group_id).first()
    if not g:
        raise HTTPException(404, "Group not found")
    tile = db.query(Tile).filter(Tile.slug == body.tile_slug).first()
    if not tile:
        raise HTTPException(404, "Tile not found")
    if tile not in g.tiles:
        g.tiles.append(tile)
        db.commit()


@router.delete("/groups/{group_id}/tiles/{tile_id}", status_code=204, dependencies=[Depends(require_manager)])
def remove_tile_from_group(group_id: int, tile_id: int, db: Session = Depends(get_db)):
    g = db.query(Group).filter(Group.id == group_id).first()
    if not g:
        raise HTTPException(404, "Group not found")
    tile = db.query(Tile).filter(Tile.id == tile_id).first()
    if tile and tile in g.tiles:
        g.tiles.remove(tile)
        db.commit()


@router.delete("/groups/{group_id}", status_code=204, dependencies=[Depends(require_group_manager)])
def delete_group(group_id: int, db: Session = Depends(get_db)):
    g = db.query(Group).filter(Group.id == group_id).first()
    if not g:
        raise HTTPException(404, "Group not found")
    db.delete(g)
    db.commit()


# ── Tiles ─────────────────────────────────────────────────────────────────────

@router.get("/tiles", response_model=list[TileOut], dependencies=[Depends(require_manager)])
def list_all_tiles(db: Session = Depends(get_db)):
    return [_tile_out(t) for t in db.query(Tile).order_by(Tile.name).all()]


@router.post("/tiles", response_model=TileOut, status_code=201, dependencies=[Depends(require_manager)])
def create_tile(body: TileCreate, db: Session = Depends(get_db)):
    if db.query(Tile).filter(Tile.slug == body.slug).first():
        raise HTTPException(409, "Slug already exists")
    t = Tile(**body.model_dump())
    db.add(t)
    db.commit()
    db.refresh(t)
    return _tile_out(t)


@router.patch("/tiles/{slug}", response_model=TileOut, dependencies=[Depends(require_manager)])
def update_tile(slug: str, body: TileUpdate, db: Session = Depends(get_db)):
    t = db.query(Tile).filter(Tile.slug == slug).first()
    if not t:
        raise HTTPException(404, "Tile not found")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(t, field, value)
    db.commit()
    db.refresh(t)
    return _tile_out(t)


@router.delete("/tiles/{slug}", status_code=204, dependencies=[Depends(require_manager)])
def delete_tile(slug: str, db: Session = Depends(get_db)):
    t = db.query(Tile).filter(Tile.slug == slug).first()
    if not t:
        raise HTTPException(404, "Tile not found")
    db.delete(t)
    db.commit()



# ── Helpers ───────────────────────────────────────────────────────────────────
