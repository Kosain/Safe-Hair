"""
Firebase Admin + Firestore for the FastAPI backend.

Credentials (first match wins):
  1. FIREBASE_SERVICE_ACCOUNT_PATH or GOOGLE_APPLICATION_CREDENTIALS
  2. backend/.env (loaded automatically if python-dotenv is installed)
  3. backend/firebase-service-account.json (drop the Firebase private key here)

Use USE_FIREBASE=false to force in-memory-only mode even if credentials exist.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Optional

_BACKEND_DIR = Path(__file__).resolve().parent

try:
    from dotenv import load_dotenv

    load_dotenv(_BACKEND_DIR / ".env")
except ImportError:
    pass

DEFAULT_SERVICE_ACCOUNT_FILE = _BACKEND_DIR / "firebase-service-account.json"

_firestore_client: Optional[Any] = None
_init_error: Optional[str] = None


def _use_firebase() -> bool:
    return os.getenv("USE_FIREBASE", "true").strip().lower() in {"1", "true", "yes", "y", "on"}


def resolve_service_account_path() -> Optional[str]:
    """Path to the JSON key file, or None if not found."""
    path = (
        os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "").strip()
        or os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "").strip()
    )
    if not path and DEFAULT_SERVICE_ACCOUNT_FILE.is_file():
        path = str(DEFAULT_SERVICE_ACCOUNT_FILE)
    if path and os.path.isfile(path):
        return path
    return None


def get_firestore():
    """Returns Firestore client or None if disabled / not configured / init failed."""
    global _firestore_client, _init_error
    if not _use_firebase():
        return None
    if _firestore_client is not None:
        return _firestore_client
    if _init_error is not None:
        return None

    path = resolve_service_account_path()
    if not path:
        _init_error = "missing_service_account_file"
        return None

    try:
        import firebase_admin
        from firebase_admin import credentials, firestore

        if not firebase_admin._apps:
            cred = credentials.Certificate(path)
            firebase_admin.initialize_app(cred)
        _firestore_client = firestore.client()
        return _firestore_client
    except Exception as e:
        _init_error = str(e)
        return None


def firebase_status() -> dict:
    ready = get_firestore() is not None
    return {
        "firebase_enabled": _use_firebase(),
        "firestore_ready": ready,
        "init_error": _init_error,
        "service_account_key_found": resolve_service_account_path() is not None,
        "default_key_file": "firebase-service-account.json",
        "default_key_file_present": DEFAULT_SERVICE_ACCOUNT_FILE.is_file(),
    }
