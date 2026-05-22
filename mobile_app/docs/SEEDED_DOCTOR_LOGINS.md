# Demo doctor logins (after running the seed script)

These accounts match the four doctors on **Book a doctor** (`/my-appointments`). They are **not** created automatically: run the seed script once so Firebase Auth + Firestore `doctors/{uid}` exist.

```bash
cd backend
python scripts/seed_demo_doctors.py
```

Requires `backend/firebase-service-account.json` (or `GOOGLE_APPLICATION_CREDENTIALS`).

### Same Firebase project as the app

The Flutter app is configured for project **`safe-hair-274`** (`firebase_options.dart`).  
The Admin JSON you use **must** be a key from that same project. If you seed with a JSON from another project (for example **`safehair-f7891`**), Auth users are created there and **doctor login in the app will always say “Invalid email or password.”**

Fix: In [Firebase Console](https://console.firebase.google.com) → project **safe-hair-274** → Project settings → Service accounts → Generate new private key → save as:

**`backend/firebase-service-account-safe-hair-274.json`**

(That filename is checked **first** by the seed script, so you can keep your old `firebase-service-account.json` for another project if needed.)

Then run:

`py backend\scripts\seed_demo_doctors.py`

## Intended credentials (set by the script)

| Doctor | Email | Password |
| --- | --- | --- |
| Dr. Ayesha Khan | drayeshakhan123@gmail.com | drayesha123@ |
| Dr. Bilal Ahmad | drbilalahmad123@gmail.com | bilalahmad123@ |
| Dr. Sana Tariq | drsanatariq123@gmail.com | sanatariq123@ |
| Dr. Hamza Noor | drhamzanoor123@gmail.com | hamzanoor123@ |

If Firebase rejects a password or an email is already taken by another project, edit `DOCTORS` in `backend/scripts/seed_demo_doctors.py` and run again (existing users get a password reset from the script).

After seeding, sign in as **Doctor** with any row above; the dashboard loads appointments where `doctorId` equals that user’s UID. Book from the patient app after the doctors list loads from Firestore so `doctorId` matches.

## Demo patient (Moeed)

| Email | Password |
| --- | --- |
| moeed123@gmail.com | `Moeed123@` (capital **M**, ends with `@`) |

Seed Auth + `patient_details/{uid}`:

```bash
py backend\scripts\seed_demo_patient_moeed.py
```

**Password is case-sensitive.** Wrong examples that fail: `moeed123@`, `Moeed123`, `moed123@gmail.com`.

If doctor login says “Invalid email or password” but you use the table above, your backend `firebase-service-account.json` is probably for project **safehair-f7891** while the app uses **safe-hair-274**. Download the Admin key from **safe-hair-274** and run the seed scripts again.
