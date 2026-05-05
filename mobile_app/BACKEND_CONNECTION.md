# How to Connect the Flutter App to the FastAPI Backend

## 1. Start the FastAPI backend

On your **PC** (same machine or the one the app will connect to):

```bash
cd backend
# Activate virtual env (Windows)
.venv\Scripts\activate
# Or (Linux/Mac): source .venv/bin/activate

# Install deps if needed
pip install fastapi uvicorn

# Run the server (listens on all interfaces, port 8000)
python main.py
```

Or with uvicorn directly:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```

You should see: `Uvicorn running on http://0.0.0.0:8000`

**Check it works:** open in a browser: [http://localhost:8000](http://localhost:8000) — you should see `{"message":"Safe Hair API v2","status":"running"}`.

---

## 2. Set the API URL in the app

The app picks the base URL automatically by platform:

| Where you run the app | URL used | What to do |
|----------------------|----------|------------|
| **Web** (Chrome)     | `http://localhost:8000` | Nothing. Just run backend on same PC. |
| **Android emulator** | `http://10.0.2.2:8000`  | Nothing. 10.0.2.2 is the emulator’s “host PC”. |
| **Real Android phone** | `http://10.0.2.2:8000` | **Change this** to your PC’s IP (see below). |

### Using a real Android device

1. **PC and phone on the same Wi‑Fi.**
2. **Find your PC’s IP:**
   - Windows: `ipconfig` → look for “IPv4 Address” (e.g. `192.168.1.5`).
   - Mac/Linux: `ifconfig` or `ip addr`.
3. **Set that IP in the app:**  
   Edit `lib/core/constants.dart` and change `apiBaseUrlMobile`:

   ```dart
   static const String apiBaseUrlMobile = 'http://192.168.1.5:8000';  // use YOUR PC IP
   ```

4. Rebuild and run the app on the device.

---

## 3. Run the Flutter app

- **Web:** `flutter run -d chrome` (backend on same PC).
- **Android emulator:** `flutter run` (or `flutter run -d emulator-5554`). Backend on same PC.
- **Real device:** After setting `apiBaseUrlMobile` to your PC IP, run `flutter run -d <device-id>`.

---

## 4. If it still doesn’t connect

- **Backend not running:** Start it (step 1) and check [http://localhost:8000](http://localhost:8000) in the browser.
- **Real device:** Confirm `apiBaseUrlMobile` in `lib/core/constants.dart` is `http://YOUR_PC_IP:8000` (no trailing slash).
- **Firewall:** Allow port **8000** on your PC (Windows Firewall / antivirus).
- **Android:** The app already has `usesCleartextTraffic="true"` so HTTP is allowed.
- **CORS:** The backend allows all origins (`allow_origins=["*"]`), so CORS should not block the app.

---

## Quick test

1. Start backend: `cd backend && python main.py`
2. Open [http://localhost:8000/api/doctors](http://localhost:8000/api/doctors) — you should see a JSON list of doctors.
3. Run the app (web or emulator) and use a feature that calls the API (e.g. Doctors list, Scalp Analysis, Guidelines).
