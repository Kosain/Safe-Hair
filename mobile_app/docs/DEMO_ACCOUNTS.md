# Demo doctor and patient accounts

Passwords are **not** stored in this repository by default. Use the same emails you already registered in **Firebase Authentication**, or create test users in the Firebase Console (Authentication → Users → Add user / Reset password).

## Optional: four “Book a doctor” demo consultants

To create **Dr. Ayesha Khan**, **Dr. Bilal Ahmad**, **Dr. Sana Tariq**, and **Dr. Hamza Noor** in **Auth + Firestore `doctors/{uid}`** with fixed demo passwords, run:

`python backend/scripts/seed_demo_doctors.py`

(from the repo root, with `backend/firebase-service-account.json` present). Intended emails/passwords are listed in `docs/SEEDED_DOCTOR_LOGINS.md`.

## How doctor login matches bookings

- Each doctor profile is stored as `doctors/{documentId}` in Firestore. For accounts that complete in-app registration, that id is usually the **same as the Firebase Auth user id (UID)**.
- When a patient books, the app saves `doctorId` on the appointment. The doctor dashboard loads appointments where `doctorId` equals the **signed-in doctor’s UID**.
- If you book from the **offline fallback** doctor list (numeric ids like `1`, `2`, `3`, `4`), those ids **do not** match a real doctor UID. For end-to-end testing, book a doctor loaded from Firestore (`getVerifiedDoctorsOnce`) so `doctorId` is the consultant’s document id, then sign in as that consultant.

## Flow to verify accept / decline and patient notifications

1. Sign in as a **patient**; book an appointment with a Firestore-listed doctor (pending request).
2. Sign in as that **doctor** (same UID as `doctors/{id}` and as `doctorId` on the booking). Open **Appointments** → **Requests** → accept or decline.
3. Sign back in as the **patient** and open the **dashboard**: unread appointment notifications appear under **Appointment updates** until dismissed.
