# Step-by-Step: Connect Flutter App to FastAPI Backend

---

## Part A: Start the FastAPI Backend (on your PC)

### Step 1: Open a terminal/command prompt

- **Windows:** Press `Win + R`, type `cmd`, press Enter.  
- Or open **PowerShell** or **Command Prompt**.

### Step 2: Go to the backend folder

```text
cd "d:\Safe Hair\Safe_Hair\backend"
```

(If your project is elsewhere, use that path instead.)

### Step 3: Activate the Python virtual environment

**Windows (Command Prompt or PowerShell):**

```text
.venv\Scripts\activate
```

You should see something like `(.venv)` at the start of the line.

**If you don’t have a `.venv` folder yet:**

```text
python -m venv .venv
.venv\Scripts\activate
```

### Step 4: Install FastAPI and Uvicorn (if needed)

```text
pip install fastapi uvicorn
```

### Step 5: Run the backend server

```text
python main.py
```

You should see something like:

```text
INFO:     Uvicorn running on http://0.0.0.0:8000
```

**Leave this terminal open.** The backend must keep running while you use the app.

### Step 6: Check that the backend is working

1. Open a **browser** (Chrome, Edge, etc.).
2. Go to: **http://localhost:8000**
3. You should see something like: `{"message":"Safe Hair API v2","status":"running"}`.

If you see that, the backend is running correctly.  
If not, go back to Step 5 and fix any error shown in the terminal.

---

## Part B: Run the Flutter App

### Step 7: Open a second terminal

- Keep the first terminal running the backend.
- Open a **new** terminal/command prompt for Flutter.

### Step 8: Go to the project folder

```text
cd "d:\Safe Hair\Safe_Hair"
```

### Step 9: Choose how you want to run the app

**Option A – Run in Chrome (easiest to test):**

```text
flutter run -d chrome
```

**Option B – Run on Android emulator:**

1. Start your Android emulator (e.g. from Android Studio).
2. Then run:

```text
flutter run
```

**Option C – Run on a real Android phone:**

1. Connect the phone with USB (or wireless debugging).
2. Enable **USB debugging** (or wireless) on the phone.
3. Run:

```text
flutter run
```

Flutter will list devices; pick your phone if asked.

### Step 10: Use the app

- Wait for the app to build and open.
- Use features that call the API, for example:
  - **Doctors** list
  - **AI Scalp Analysis**
  - **Guidelines**
  - **Patient details** (Continue after signup)

If the backend is running and the app is using the right URL (see Part C), these should load from the FastAPI server.

---

## Part C: If you use a REAL Android phone (not emulator, not web)

On a real device, the app cannot use `localhost` or `10.0.2.2` to reach your PC. You must use your PC’s IP address.

### Step 11: Put phone and PC on the same Wi‑Fi

- Same network for both.

### Step 12: Find your PC’s IP address

**Windows:**

1. In the same terminal (or a new one), run:

```text
ipconfig
```

2. Find the line **IPv4 Address** under your **Wi‑Fi** adapter.  
   It looks like: `192.168.1.5` or `192.168.0.10`.  
   That number is your PC IP.

### Step 13: Set that IP in the Flutter app

1. Open the project in your editor (e.g. Cursor/VS Code).
2. Open this file: **`lib/core/constants.dart`**
3. Find this line:

```dart
static const String apiBaseUrlMobile = 'http://10.0.2.2:8000';
```

4. Change it to use **your** PC IP (from Step 12), for example:

```dart
static const String apiBaseUrlMobile = 'http://192.168.1.5:8000';
```

Replace `192.168.1.5` with the IP you found.  
Do **not** add a slash at the end. Port `8000` must stay.

5. Save the file.

### Step 14: Run the app again on the phone

```text
cd "d:\Safe Hair\Safe_Hair"
flutter run
```

Select your phone as the device. The app will now use `http://YOUR_PC_IP:8000` to talk to the backend.

---

## Part D: If it still doesn’t connect

### Checklist

| Check | What to do |
|--------|------------|
| Backend running? | In the first terminal you should see `Uvicorn running on http://0.0.0.0:8000`. If not, run `python main.py` again from the `backend` folder. |
| Browser test | Open **http://localhost:8000** in a browser. You must see the API JSON response. |
| Real device? | If you use a real phone, you must set `apiBaseUrlMobile` to your PC IP in `lib/core/constants.dart` (Part C). |
| Same Wi‑Fi? | Phone and PC must be on the same network. |
| Firewall? | Windows Firewall might block port 8000. Allow Python or add a rule for port **8000**. |

### Test the doctors API in the browser

Open: **http://localhost:8000/api/doctors**

You should see a JSON list of doctors. If this works, the backend is fine; the issue is then app URL or device/network.

---

## Quick reference

| Step | Action |
|------|--------|
| 1–6 | Start backend: `cd backend` → activate venv → `python main.py` → check http://localhost:8000 |
| 7–10 | Run app: `cd "d:\Safe Hair\Safe_Hair"` → `flutter run -d chrome` (or `flutter run` for device) |
| 11–14 | **Only for real phone:** get PC IP with `ipconfig`, set `apiBaseUrlMobile` in `lib/core/constants.dart`, then run app again |
