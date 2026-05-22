"""
Create the four "Book a doctor" demo consultants in Firebase Auth + Firestore.

Prerequisites:
  - Service account JSON for the **same** Firebase project as the Flutter app
    (`mobile_app/lib/firebase_options.dart` → currently **safe-hair-274**).
  - If the JSON is for a *different* project than the Flutter app, the script **exits with an error**
    (so users are not created in the wrong Firebase project).

Place a **Safe Hair** Admin key as (either works):
  - `backend/firebase-service-account-safe-hair-274.json`  ← preferred name (script checks this first), or
  - `FIREBASE_SERVICE_ACCOUNT_PATH` / `GOOGLE_APPLICATION_CREDENTIALS` pointing at that JSON.

Run from repo root:
  py backend\\scripts\\seed_demo_doctors.py

If an email is already registered to another Firebase project, change that row's
email in DOCTORS below (or use Gmail plus-addressing: you+ayesha@gmail.com).

Passwords are demo-only — change them in production.
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

_BACKEND = Path(__file__).resolve().parent.parent
if str(_BACKEND) not in sys.path:
    sys.path.insert(0, str(_BACKEND))

from safe_hair_project import (  # noqa: E402
    PROJECT_ID,
    PREFERRED_SERVICE_ACCOUNT,
    ensure_firebase_admin_app,
)

from firebase_admin import auth, firestore  # noqa: E402


def _utc_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

# Same names/fees as the in-app fallback list on "Book a doctor".
DOCTORS: list[dict] = [
    {
        "email": "drayeshakhan123@gmail.com",
        "password": "drayesha123@",
        "fullName": "Dr. Ayesha Khan",
        "clinicName": "Safe Hair Clinic",
        "city": "Lahore",
        "fee": 3000,
        "rating": 4.8,
    },
    {
        "email": "drbilalahmad123@gmail.com",
        "password": "bilalahmad123@",
        "fullName": "Dr. Bilal Ahmad",
        "clinicName": "Hair Wellness Center",
        "city": "Islamabad",
        "fee": 2500,
        "rating": 4.6,
    },
    {
        "email": "drsanatariq123@gmail.com",
        "password": "sanatariq123@",
        "fullName": "Dr. Sana Tariq",
        "clinicName": "Derma Care Studio",
        "city": "Karachi",
        "fee": 3500,
        "rating": 4.9,
    },
    {
        "email": "drhamzanoor123@gmail.com",
        "password": "hamzanoor123@",
        "fullName": "Dr. Hamza Noor",
        "clinicName": "Scalp Expert Hub",
        "city": "Faisalabad",
        "fee": 2200,
        "rating": 4.5,
    },
]


def _upsert_auth_user(email: str, password: str, display_name: str) -> tuple[str, bool]:
    try:
        u = auth.get_user_by_email(email)
        auth.update_user(u.uid, password=password, display_name=display_name)
        return u.uid, True
    except auth.UserNotFoundError:
        u = auth.create_user(
            email=email,
            password=password,
            display_name=display_name,
            email_verified=False,
            disabled=False,
        )
        return u.uid, False


def _firestore_doc(uid: str, row: dict) -> dict:
    email = row["email"]
    return {
        "userId": uid,
        "role": "doctor",
        "email": email,
        "fullName": row["fullName"],
        "clinicName": row["clinicName"],
        "clinicAddress": row["city"],
        "city": row["city"],
        "consultationFee": row["fee"],
        "rating": row["rating"],
        "phone": "+920000000000",
        "address": row["city"],
        "qualification": "MBBS",
        "specialization": "Hair & scalp",
        "licenseNumber": f"DEMO-SEED-{uid[:8]}",
        "registrationNumber": f"DEMO-SEED-{uid[:8]}",
        "yearsExperience": 5,
        "profileCompleted": True,
        "profileCompletedAt": _utc_iso(),
        "isVerified": False,
        "createdAt": _utc_iso(),
    }


def main() -> None:
    path = ensure_firebase_admin_app()
    db = firestore.client()
    sa_pid = ""
    try:
        with open(path, encoding="utf-8") as f:
            sa_pid = json.load(f).get("project_id", "")
    except OSError:
        pass
    print(f"Firebase Admin project (service account): {sa_pid or PROJECT_ID}")
    print(f"Flutter app + backend use: {PROJECT_ID} (see firebase/project.json)\n")
    print("Seeding demo doctors (Auth + Firestore doctors/{uid})...\n")
    lines = ["| Doctor | Email | Password | Firestore doc |", "| --- | --- | --- | --- |"]
    for row in DOCTORS:
        email = row["email"]
        pw = row["password"]
        uid, existed = _upsert_auth_user(email, pw, row["fullName"])
        db.collection("doctors").document(uid).set(_firestore_doc(uid, row), merge=True)
        action = "updated" if existed else "created"
        print(f"  {row['fullName']}: {email}  ({action})  uid={uid}")
        lines.append(f"| {row['fullName']} | {email} | `{pw}` | `doctors/{uid}` |")

    print("\nDone. Use **Doctor** login in the app with the emails above.\n")
    print("Credential summary (copy for your notes):\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
