# FYP login fix checklist

## Demo logins (project **safe-hair-274** only)

| Role | Email | Password |
|------|--------|----------|
| Patient | `moeed123@gmail.com` | `Moeed123@` |
| Dr. Ayesha | `drayeshakhan123@gmail.com` | `drayesha123@` |

Passwords are **case-sensitive**.

## If doctor shows "Invalid password"

1. Firebase Console → **safe-hair-274** → **Authentication** → **Sign-in method** → enable **Email/Password**.
2. **Authentication** → **Settings** → **Authorized domains** → add:
   - `localhost`
   - `127.0.0.1`
3. Stop the app completely, then run:
   ```powershell
   cd mobile_app
   flutter run -d chrome --web-port=8080
   ```
4. Optional seed (needs Admin key from **this** project):
   - Save key as `backend/firebase-service-account-safe-hair-274.json`
   - `py backend\scripts\seed_demo_doctors.py`
   - `py backend\scripts\seed_demo_patient_moeed.py`

**Do not** use `firebase-service-account.json` if its `project_id` is `safehair-f7891` — that is a different project than the app.

## URLs

- Patient login: http://127.0.0.1:8080/#/login/patient
- Doctor login: http://127.0.0.1:8080/#/login/doctor
