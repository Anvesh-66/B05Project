from __future__ import annotations

import argparse
import getpass
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlmodel import Session, select  # noqa: E402

from backend.auth import hash_password  # noqa: E402
from backend.db import User, engine, init_db  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create an admin account, or promote an existing account to admin."
    )
    parser.add_argument("--email", required=True)
    parser.add_argument("--name", default="Admin")
    args = parser.parse_args()

    email = args.email.strip().lower()
    init_db()
    with Session(engine) as session:
        user = session.exec(select(User).where(User.email == email)).first()
        if user is not None:
            user.role = "admin"
            session.add(user)
            session.commit()
            print(f"{email} is now an admin (password unchanged).")
            return 0

        password = getpass.getpass("Password (8-72 characters): ")
        if not 8 <= len(password.encode("utf-8")) <= 72:
            print("Password must be 8 to 72 characters.")
            return 2
        if getpass.getpass("Repeat password: ") != password:
            print("Passwords do not match.")
            return 2

        session.add(User(name=args.name, email=email, password_hash=hash_password(password), role="admin"))
        session.commit()
        print(f"Created admin {email}. Sign in through the admin panel (pothole-admin-panel).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
