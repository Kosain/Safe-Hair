"""
Firebase Admin + Firestore for the FastAPI backend.

Uses the **same** Firebase project as the Flutter app: `safe-hair-274`
(see `firebase/project.json` and `backend/safe_hair_project.py`).

Credentials (first valid key for safe-hair-274):
  1. FIREBASE_SERVICE_ACCOUNT_PATH or GOOGLE_APPLICATION_CREDENTIALS
  2. backend/firebase-service-account-safe-hair-274.json  (recommended)
  3. backend/firebase-service-account.json  (only if project_id is safe-hair-274)

Keys for other projects (e.g. safehair-f7891) are ignored.

USE_FIREBASE=false → in-memory-only mode.
"""
from __future__ import annotations

import os
from typing import Any, Optional

from safe_hair_project import (
    FALLBACK_SERVICE_ACCOUNT,
    PREFERRED_SERVICE_ACCOUNT,
    PROJECT_ID,
    resolve_service_account_path,
)

_firestore_client: Optional[Any] = None
_init_error: Optional[str] = None


def _use_firebase() -> bool:
    return os.getenv("USE_FIREBASE", "true").strip().lower() in {"1", "true", "yes", "y", "on"}


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
        _init_error = (
            f"missing_service_account_for_{PROJECT_ID}; "
            f"add {PREFERRED_SERVICE_ACCOUNT.name} from Firebase Console"
        )
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
    path = resolve_service_account_path()
    ready = get_firestore() is not None
    return {
        "firebase_project_id": PROJECT_ID,
        "firebase_enabled": _use_firebase(),
        "firestore_ready": ready,
        "init_error": _init_error,
        "service_account_key_found": path is not None,
        "service_account_path": path,
        "preferred_key_file": str(PREFERRED_SERVICE_ACCOUNT),
        "preferred_key_present": PREFERRED_SERVICE_ACCOUNT.is_file(),
        "fallback_key_file": str(FALLBACK_SERVICE_ACCOUNT),
        "fallback_key_present": FALLBACK_SERVICE_ACCOUNT.is_file(),
        "aligned_with_flutter_app": True,
    }
