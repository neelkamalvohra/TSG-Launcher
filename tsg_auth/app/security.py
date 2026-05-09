import secrets
import smtplib
import string
import logging
from datetime import datetime, timedelta, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Optional

import bcrypt
from jose import jwt, JWTError

from .config import settings

logger = logging.getLogger(__name__)


def verify_password(plain: str, hashed: str) -> bool:
    return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))


def hash_password(plain: str) -> str:
    return bcrypt.hashpw(plain.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def create_access_token(payload: dict) -> str:
    data = payload.copy()
    data["exp"] = datetime.now(timezone.utc) + timedelta(
        minutes=settings.access_token_expire_minutes
    )
    return jwt.encode(data, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def decode_access_token(token: str) -> Optional[dict]:
    try:
        return jwt.decode(
            token, settings.jwt_secret, algorithms=[settings.jwt_algorithm]
        )
    except JWTError:
        return None


def create_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def refresh_token_expiry() -> datetime:
    return datetime.utcnow() + timedelta(days=settings.refresh_token_expire_days)


def generate_temp_password(length: int = 10) -> str:
    """Generate a human-readable temporary password: 2 upper + 2 digits + rest lower."""
    alphabet = string.ascii_lowercase + string.ascii_uppercase + string.digits
    while True:
        pwd = "".join(secrets.choice(alphabet) for _ in range(length))
        has_upper = any(c.isupper() for c in pwd)
        has_digit = any(c.isdigit() for c in pwd)
        has_lower = any(c.islower() for c in pwd)
        if has_upper and has_digit and has_lower:
            return pwd


def send_password_reset_email(to_email: str, to_name: str, temp_password: str) -> None:
    """Send a password reset email via Gmail SMTP. Runs synchronously (call via BackgroundTasks)."""
    subject = "TSG App — Your Password Has Been Reset"
    body_html = f"""\
<html><body style="font-family:Arial,sans-serif;background:#f4f4f4;padding:24px">
<div style="max-width:480px;margin:0 auto;background:#fff;border-radius:10px;padding:32px;
            box-shadow:0 2px 8px rgba(0,0,0,.12)">
  <h2 style="color:#1a3a6e;margin-top:0">TSG Password Reset</h2>
  <p>Hi <strong>{to_name}</strong>,</p>
  <p>Your TSG account password has been reset by an administrator.</p>
  <p style="margin:24px 0">
    <span style="background:#f0f4ff;border:1px solid #b0c4de;border-radius:6px;
                 padding:10px 20px;font-size:20px;font-family:monospace;letter-spacing:2px">
      {temp_password}
    </span>
  </p>
  <p>Please sign in with this temporary password. <strong>You will be required to set a
  new password immediately after signing in.</strong></p>
  <p style="color:#888;font-size:12px;margin-top:32px">
    This is an automated message from the TSG application. Do not reply.
  </p>
</div>
</body></html>"""

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = f"{settings.smtp_from_name} <{settings.smtp_username}>"
    msg["To"] = to_email
    msg.attach(MIMEText(body_html, "html"))

    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=15) as server:
            server.ehlo()
            server.starttls()
            server.login(settings.smtp_username, settings.smtp_password)
            server.sendmail(settings.smtp_username, [to_email], msg.as_string())
        logger.info("Password reset email sent to %s", to_email)
    except Exception as exc:
        logger.error("Failed to send password reset email to %s: %s", to_email, exc)
