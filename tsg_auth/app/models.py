from datetime import datetime
from sqlalchemy import (
    Column, Integer, String, Boolean, DateTime, ForeignKey, Table
)
from sqlalchemy.orm import relationship
from .database import Base

# ── Association tables ────────────────────────────────────────────────────────

user_groups = Table(
    "user_groups",
    Base.metadata,
    Column("user_id", Integer, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
    Column("group_id", Integer, ForeignKey("groups.id", ondelete="CASCADE"), primary_key=True),
)

group_tiles = Table(
    "group_tiles",
    Base.metadata,
    Column("group_id", Integer, ForeignKey("groups.id", ondelete="CASCADE"), primary_key=True),
    Column("tile_id", Integer, ForeignKey("tiles.id", ondelete="CASCADE"), primary_key=True),
)

# ── ORM models ────────────────────────────────────────────────────────────────

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(150), unique=True, nullable=False, index=True)
    email = Column(String(254), unique=True, nullable=False)
    name = Column(String(300), nullable=False, default="")
    hashed_password = Column(String(200), nullable=False)
    is_active = Column(Boolean, nullable=False, default=True)
    is_superadmin = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    # Password policy columns
    must_change_password = Column(Boolean, nullable=False, default=True)
    last_login_at = Column(DateTime, nullable=True)
    password_changed_at = Column(DateTime, nullable=True, default=datetime.utcnow)

    groups = relationship("Group", secondary=user_groups, back_populates="users")
    refresh_tokens = relationship(
        "RefreshToken", back_populates="user", cascade="all, delete-orphan"
    )


class Group(Base):
    __tablename__ = "groups"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), unique=True, nullable=False)

    users = relationship("User", secondary=user_groups, back_populates="groups")
    tiles = relationship("Tile", secondary=group_tiles, back_populates="groups")


class Tile(Base):
    __tablename__ = "tiles"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(200), nullable=False)
    slug = Column(String(200), unique=True, nullable=False, index=True)
    meta_launch_url = Column(String(500), nullable=False)
    meta_icon = Column(String(500), nullable=True)
    meta_description = Column(String, nullable=True)
    quick_panel = Column(String(50), nullable=True)  # e.g. 'roster', 'time', 'date'
    created_at = Column(DateTime, default=datetime.utcnow)

    groups = relationship("Group", secondary=group_tiles, back_populates="tiles")


class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    token = Column(String(100), unique=True, nullable=False, index=True)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="refresh_tokens")
