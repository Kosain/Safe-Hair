"""Ensure one confirmed appointment exists between demo patient and demo doctor."""

from __future__ import annotations

import sys
from datetime import datetime, timezone

from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from firebase_admin import auth, firestore  # noqa: E402

from safe_hair_project import PROJECT_ID, ensure_firebase_admin_app  # noqa: E402

DEMO_PATIENT_EMAIL = "moeed123@gmail.com"
DEMO_DOCTOR_EMAIL = "drayeshakhan123@gmail.com"
DEMO_APPOINTMENT_ID = "demo_chat_moeed_drayesha"


def main() -> None:
    ensure_firebase_admin_app()
    db = firestore.client()
    patient_uid = auth.get_user_by_email(DEMO_PATIENT_EMAIL).uid
    doctor_uid = auth.get_user_by_email(DEMO_DOCTOR_EMAIL).uid

    doctor_name = "Dr. Ayesha Khan"
    doctor_doc = db.collection("doctors").document(doctor_uid).get()
    if doctor_doc.exists:
        doctor_name = (doctor_doc.to_dict() or {}).get("fullName") or doctor_name

    now = datetime.now(timezone.utc)
    payload = {
        "userId": patient_uid,
        "patientId": patient_uid,
        "patientName": "Moeed",
        "doctorId": doctor_uid,
        "doctorName": doctor_name,
        "status": "confirmed",
        "date": now.strftime("%Y-%m-%d"),
        "timeSlot": "10:00 AM",
        "updatedAt": firestore.SERVER_TIMESTAMP,
    }
    ref = db.collection("appointments").document(DEMO_APPOINTMENT_ID)
    if not ref.get().exists:
        payload["createdAt"] = firestore.SERVER_TIMESTAMP
    ref.set(payload, merge=True)

    print(f"Demo chat appointment ready in {PROJECT_ID}")
    print(f"  appointmentId: {DEMO_APPOINTMENT_ID}")
    print(f"  patient: {DEMO_PATIENT_EMAIL} ({patient_uid})")
    print(f"  doctor:  {DEMO_DOCTOR_EMAIL} ({doctor_uid})")


if __name__ == "__main__":
    main()
