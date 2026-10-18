from __future__ import annotations

import os
import secrets
from datetime import datetime, timedelta, timezone
from functools import lru_cache

import bcrypt
import jwt
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlmodel import Session

from backend.db import DATA_DIR, User, get_session

TOKEN_TTL = timedelta(days=30)
_ALGORITHM = "HS256"
_bearer = HTTPBearer(auto_error=False)


@lru_cache(maxsize=1)
def _secret_key() -> str:
    """Signing key from POTHOLE_SECRET_KEY, or one generated once and kept in the data dir."""
    env = os.getenv("POTHOLE_SECRET_KEY", "").strip()
    if env:
        return env
    path = DATA_DIR / "secret.key"
    if not path.exists():
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        path.write_text(secrets.token_urlsafe(48), encoding="utf-8")
    return path.read_text(encoding="utf-8").strip()


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("ascii")


def verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("ascii"))
    except ValueError:
        return False


# Checked when the email is unknown, so a login attempt takes the same time either way.
_DUMMY_HASH = hash_password(secrets.token_urlsafe(16))


def authenticate(user: User | None, password: str) -> User | None:
    ok = verify_password(password, user.password_hash if user else _DUMMY_HASH)
    return user if (user and ok) else None


def create_token(user: User) -> str:
    payload = {"sub": str(user.id), "exp": datetime.now(timezone.utc) + TOKEN_TTL}
    return jwt.encode(payload, _secret_key(), algorithm=_ALGORITHM)


def current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: Session = Depends(get_session),
) -> User:
    user: User | None = None
    if creds is not None:
        try:
            payload = jwt.decode(creds.credentials, _secret_key(), algorithms=[_ALGORITHM])
            user = session.get(User, int(payload["sub"]))
        except (jwt.PyJWTError, KeyError, ValueError):
            user = None
    if user is None:
        raise HTTPException(
            status_code=401,
            detail="Not signed in, or the session has expired.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


def require_admin(user: User = Depends(current_user)) -> User:
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin access required.")
    return user
