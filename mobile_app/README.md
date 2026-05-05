# Safe Hair - Full Functional Hair & Scalp Health App

A complete cross-platform application with **AI Scalp Analysis**, **Recommendations Portal**, **Guidelines**, **Booking with Consultation**, **Reports**, and **Firebase** integration.

## Features

### AI Scalp Analyzer
- Capture or upload scalp/head image
- AI analysis returns: Hair Strength, Scalp Health, Hair Density, Moisture Level
- Detected conditions and personalized recommendations
- Results saved to Firebase

### Recommendation Portal
- Personalized recommendations based on scalp analysis
- Quick actions: New Analysis, Book Consultation, Guidelines, Reports

### Guidelines
- Expert hair care tips and educational content
- Categories: Care, Nutrition, Prevention, Products
- Loaded from FastAPI (or Firebase when configured)

### Booking with Consultation
- Calendar date selection
- Time slots and reminder options
- **Consultation notes** for doctor
- Saves to Firebase + creates consultation report

### Reports
- Scalp analysis reports
- Consultation reports
- View summary and recommendations

### Firebase Integration
- **Authentication** (when configured)
- **Firestore**: scalp_analyses, appointments, patient_details, reports
- **Storage**: Scalp images

## Setup

### 1. Flutter App
```bash
cd "d:\Safe Hair\Safe_Hair"
flutter pub get
```

### 2. FastAPI Backend (Required for AI Analysis)
```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Optional CNN (ONNX segmentation):
- Set environment variables before running:
  - `USE_CNN=true`
  - `CNN_MODEL_PATH=/absolute/path/to/your_model.onnx`
- If not set, the backend falls back to OpenCV-based bald detection.

Optional dataset-trained bald regressor:
1. Train model from your mask-labeled dataset:
   ```bash
   cd backend
   python train_bald_model.py --dataset "d:\Zain's DOCUMENT\fyp\SAFE_HAIR DATASET\Male" --output "models/bald_regressor.joblib"
   ```
2. Enable trained model in API:
   - `USE_TRAINED_MODEL=true`
   - `TRAINED_MODEL_PATH=backend/models/bald_regressor.joblib` (or absolute path)

Strict real AI mode (recommended):
- `STRICT_AI=true`
- In this mode, API refuses analysis requests unless:
  - OpenCV pipeline is available, and
  - trained model file exists at `TRAINED_MODEL_PATH`
- Check runtime status at:
  - `GET /api/ai/status`

### 3. Firebase (Optional - app works without it)
1. Create project at [Firebase Console](https://console.firebase.google.com)
2. Enable: Authentication (Email), Firestore, Storage
3. Run: `flutterfire configure`
4. Deploy rules:
   ```bash
   firebase deploy --only firestore:rules
   firebase deploy --only storage
   ```

### 4. Seed Guidelines in Firestore (Optional)
Add documents to `guidelines` collection with: `id`, `title`, `category`, `content`, `tips` (array).

## Run

**Web:**
```bash
flutter run -d chrome
```

**Mobile:**
```bash
flutter run
```

**API URL:** Edit `lib/core/constants.dart`:
- Web: `http://localhost:8000`
- Android Emulator: `http://10.0.2.2:8000`

## Project Structure

```
lib/
├── core/           # Theme, router, constants
├── models/         # ScalpAnalysis, Report, Guideline, Appointment
├── providers/      # AuthProvider (Firebase + mock)
├── screens/        # All UI screens
├── services/       # ApiService, FirebaseService
└── widgets/        # BottomNavBar

backend/
├── main.py         # FastAPI + AI scalp analysis
└── requirements.txt

firebase/
├── firestore.rules
└── storage.rules
```

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /api/ai/scalp-analyze | AI scalp analysis (image base64) |
| GET | /api/doctors | List doctors |
| GET | /api/guidelines | List guidelines |
| POST | /api/appointments | Create appointment |
| POST | /api/reports | Create report |
| POST | /api/scalp-analysis | Save analysis |
| POST | /api/patient-details | Save patient details |
