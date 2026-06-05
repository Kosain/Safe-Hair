# Firebase — one project for the whole repo

| Setting | Value |
|--------|--------|
| **Project ID** | `safe-hair-274` |
| **Console** | https://console.firebase.google.com/project/safe-hair-274 |
| **Auth (web)** | `safe-hair-274.firebaseapp.com` |
| **Storage** | `gs://safe-hair-274.firebasestorage.app` |

## What uses this project

| Part | Config file |
|------|-------------|
| Flutter / Web / Android | `mobile_app/lib/firebase_options.dart` |
| Android native | `mobile_app/android/app/google-services.json` |
| Firebase CLI deploy | `mobile_app/.firebaserc` |
| FastAPI backend | `backend/safe_hair_project.py` + Admin SDK JSON |
| Firestore rules | `firebase/firestore.rules` |

## Backend Admin key (required for seeds + API Firestore)

1. Firebase Console → **safe-hair-274** → Project settings → **Service accounts**
2. **Generate new private key**
3. Save as:

   `backend/firebase-service-account-safe-hair-274.json`

Do **not** use keys from `safehair-f7891` — the Flutter app will not see users created there.

## Seed demo users

```powershell
cd "path\to\Safe_Hair"
py backend\scripts\seed_demo_doctors.py
py backend\scripts\seed_demo_patient_moeed.py
```

## Deploy Firestore rules

**Option A — Python (no Node.js required):**

```powershell
cd "path\to\Safe_Hair"
py backend\scripts\deploy_firestore_rules.py
```

**Option B — Firebase CLI:**

```powershell
cd mobile_app
firebase deploy --only firestore:rules
```

**Option C — Firebase Console:** open [Firestore Rules](https://console.firebase.google.com/project/safe-hair-274/firestore/rules), paste `firebase/firestore.rules`, click **Publish**.

## Check alignment

```powershell
py backend\scripts\check_firebase_alignment.py
```
