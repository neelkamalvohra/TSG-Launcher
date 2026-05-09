import logging
import time
from datetime import datetime

from apscheduler.schedulers.background import BackgroundScheduler
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .database import Base, engine, SessionLocal
from .models import User, Group  # noqa: F401 — ensure models are registered
from .security import hash_password
from .config import settings
from .routers import auth, me, admin

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _wait_for_db(max_retries: int = 15, delay: float = 3.0) -> None:
    """Retry DB connection until Postgres is reachable (handles Docker startup race)."""
    for attempt in range(1, max_retries + 1):
        try:
            Base.metadata.create_all(bind=engine)
            logger.info("Database tables created / verified on attempt %d", attempt)
            return
        except Exception as exc:
            logger.warning(
                "Database not ready (attempt %d/%d): %s", attempt, max_retries, exc
            )
            if attempt == max_retries:
                raise
            time.sleep(delay)


def _run_migrations() -> None:
    """Safe ALTER TABLE migrations for columns added after initial deployment."""
    from sqlalchemy import text
    with engine.connect() as conn:
        conn.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT FALSE"
        ))
        conn.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP WITHOUT TIME ZONE"
        ))
        conn.execute(text(
            "ALTER TABLE users ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMP WITHOUT TIME ZONE"
        ))
        # Backfill: existing users keep current password, avoid forced change
        conn.execute(text(
            "UPDATE users SET password_changed_at = created_at WHERE password_changed_at IS NULL"
        ))
        conn.commit()
    logger.info("Schema migrations applied.")


def _disable_inactive_users() -> None:
    """Daily job: disable users who haven't logged in for inactivity_disable_days."""
    db = SessionLocal()
    try:
        cutoff = datetime.utcnow() - __import__('datetime').timedelta(
            days=settings.inactivity_disable_days
        )
        users = (
            db.query(User)
            .filter(
                User.is_active == True,
                User.is_superadmin == False,
                User.last_login_at < cutoff,
            )
            .all()
        )
        for u in users:
            u.is_active = False
            logger.info("Auto-disabled inactive user: %s (last login: %s)", u.username, u.last_login_at)
        if users:
            db.commit()
    except Exception:
        db.rollback()
        logger.exception("Error in inactivity sweep job.")
    finally:
        db.close()


app = FastAPI(title="TSG Auth Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(me.router)
app.include_router(admin.router)


@app.on_event("startup")
def seed_initial_data() -> None:
    """Create the default groups and superadmin user on first run."""
    _wait_for_db()
    _run_migrations()
    db = SessionLocal()
    try:
        default_groups = [
            "superadmin", "admin", "head", "supervisor", "sme", "engineer", "trainee"
        ]
        created_groups: dict[str, Group] = {}
        for gname in default_groups:
            g = db.query(Group).filter(Group.name == gname).first()
            if not g:
                g = Group(name=gname)
                db.add(g)
            created_groups[gname] = g
        db.flush()

        if not db.query(User).filter(User.username == settings.init_superadmin_username).first():
            user = User(
                username=settings.init_superadmin_username,
                email=settings.init_superadmin_email,
                name="Super Admin",
                hashed_password=hash_password(settings.init_superadmin_password),
                is_superadmin=True,
                is_active=True,
                must_change_password=False,
                password_changed_at=datetime.utcnow(),
            )
            db.add(user)
            db.flush()
            sg = created_groups.get("superadmin")
            if sg and user not in sg.users:
                sg.users.append(user)
            logger.info("Superadmin user '%s' created.", settings.init_superadmin_username)

        db.commit()
    except Exception:
        db.rollback()
        logger.exception("Failed to seed initial data.")
    finally:
        db.close()

    # Start APScheduler: daily inactivity sweep at 00:00 IST
    scheduler = BackgroundScheduler(timezone="Asia/Calcutta")
    scheduler.add_job(_disable_inactive_users, "cron", hour=0, minute=0)
    scheduler.start()
    logger.info("APScheduler started — inactivity sweep runs daily at 00:00 IST.")


@app.get("/health")
def health():
    return {"status": "ok"}
