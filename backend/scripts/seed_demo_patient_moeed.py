"""
Ensure demo patient Moeed exists in Firebase Auth + patient_details (safe-hair-274).

Run from repo root:
  py backend\\scripts\\seed_demo_patient_moeed.py
"""
from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path

_BACKEND = Path(__file__).resolve().parent.parent
if str(_BACKEND) not in sys.path:
    sys.path.insert(0, str(_BACKEND))

from safe_hair_project import PROJECT_ID, ensure_firebase_admin_app  # noqa: E402
from seed_demo_doctors import _upsert_auth_user  # noqa: E402

from firebase_admin import firestore  # noqa: E402

PATIENT = {
    "email": "moeed123@gmail.com",
    "password": "Moeed123@",
    "fullName": "Moeed",
}


def _utc_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def main() -> None:
    ensure_firebase_admin_app()
    db = firestore.client()
    email = PATIENT["email"]
    pw = PATIENT["password"]
    uid, existed = _upsert_auth_user(email, pw, PATIENT["fullName"])
    db.collection("patient_details").document(uid).set(
        {
            "userId": uid,
            "user_id": uid,
            "email": email,
            "name": PATIENT["fullName"],
            "profileCompleted": True,
            "updatedAt": _utc_iso(),
        },
        merge=True,
    )
    action = "updated" if existed else "created"
    print(f"Patient {PATIENT['fullName']}: {email} ({action}) uid={uid}")
    print(f"Firestore: patient_details/{uid}")
    print(f"\nLogin: Patient -> {email} / {pw}")
    print(f"App project: {PROJECT_ID}")


if __name__ == "__main__":
    main()
