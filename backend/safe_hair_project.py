"""
Single Firebase project for the whole Safe Hair repo (Flutter + FastAPI + seeds).

Must match `mobile_app/lib/firebase_options.dart` and `firebase/project.json`.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

_BACKEND = Path(__file__).resolve().parent
_REPO_ROOT = _BACKEND.parent
_PROJECT_JSON = _REPO_ROOT / "firebase" / "project.json"

PROJECT_ID = "safe-hair-274"
STORAGE_BUCKET = "safe-hair-274.firebasestorage.app"
AUTH_DOMAIN = "safe-hair-274.firebaseapp.com"

PREFERRED_SERVICE_ACCOUNT = _BACKEND / "firebase-service-account-safe-hair-274.json"
FALLBACK_SERVICE_ACCOUNT = _BACKEND / "firebase-service-account.json"


def load_project_json() -> dict:
    if _PROJECT_JSON.is_file():
        with open(_PROJECT_JSON, encoding="utf-8") as f:
            return json.load(f)
    return {
        "projectId": PROJECT_ID,
        "storageBucket": STORAGE_BUCKET,
        "authDomain": AUTH_DOMAIN,
    }


def read_service_account_project_id(path: str | Path) -> str:
    with open(path, encoding="utf-8") as f:
        return str(json.load(f).get("project_id", "")).strip()


def resolve_service_account_path() -> str | None:
    """Admin SDK key for **safe-hair-274** only (same as Flutter app)."""
    import os

    explicit = (
        os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "").strip()
        or os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    )
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit))
    candidates.extend([PREFERRED_SERVICE_ACCOUNT, FALLBACK_SERVICE_ACCOUNT])

    for p in candidates:
        if not p.is_file():
            continue
        try:
            if read_service_account_project_id(p) == PROJECT_ID:
                return str(p.resolve())
        except (OSError, json.JSONDecodeError):
            continue
    return None


def ensure_firebase_admin_app():
    """Initialize Firebase Admin for [PROJECT_ID]. Exits with instructions if misconfigured."""
    path = resolve_service_account_path()
    if not path:
        print(
            f"\nNo service account JSON for Firebase project **{PROJECT_ID}**.\n"
            f"  1. Open {load_project_json().get('consoleUrl', 'Firebase Console')}\n"
            "  2. Project settings → Service accounts → Generate new private key\n"
            f"  3. Save as:\n     {PREFERRED_SERVICE_ACCOUNT}\n"
            "  Or set FIREBASE_SERVICE_ACCOUNT_PATH to that file.\n"
            "\n  Do NOT use keys from project **safehair-f7891** — the app will not see those users.\n",
            file=sys.stderr,
        )
        sys.exit(1)

    import firebase_admin
    from firebase_admin import credentials

    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate(path))
    return path
