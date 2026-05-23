"""
Safe Hair FastAPI Backend
AI Scalp Analysis (OpenCV bald detection + graft estimation when cv2 available), Recommendations, Guidelines, Booking, Reports
"""
import base64
import os
import re
from datetime import datetime
from typing import List, Optional, Dict, Any

from fastapi import FastAPI, HTTPException, UploadFile, File, Header, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

try:
  import scalp_analyzer  # noqa: F401 — strict overlay colors (red/orange/teal)
  from scalp_processor import analyze_scalp_with_opencv
  _has_opencv = True
except ImportError:
  _has_opencv = False

from firebase_client import firebase_status, get_firestore

def _analyze_scalp_fallback(image_bytes: bytes) -> dict:
  """Fallback when OpenCV/model pipeline is unavailable."""
  raise RuntimeError(
      "AI scalp analysis pipeline unavailable. Install OpenCV and enable trained model."
  )

app = FastAPI(title="Safe Hair API", version="2.0.0")

# Optional CNN + regressor. Default: "auto" = use backend/models/* when files exist.
_BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
_DEFAULT_ONNX = os.path.join(_BACKEND_DIR, "models", "scalp_seg.onnx")
_DEFAULT_JOBLIB = os.path.join(_BACKEND_DIR, "models", "bald_regressor.joblib")
_DEFAULT_CONDITIONS = os.path.join(_BACKEND_DIR, "models", "scalp_conditions.joblib")


def _env_tri_bool(name: str, default: str = "auto") -> str:
    """Returns 'on' | 'off' | 'auto'."""
    v = os.getenv(name, default).strip().lower()
    if v in {"1", "true", "yes", "y", "on"}:
        return "on"
    if v in {"0", "false", "no", "n", "off"}:
        return "off"
    return "auto"


_CNN_TOGGLE = _env_tri_bool("USE_CNN", "auto")
_CNN_MODEL_PATH = os.getenv("CNN_MODEL_PATH", "").strip() or _DEFAULT_ONNX
_USE_CNN = _CNN_TOGGLE == "on" or (_CNN_TOGGLE == "auto" and os.path.isfile(_CNN_MODEL_PATH))
_HAS_CNN = bool(_USE_CNN and os.path.isfile(_CNN_MODEL_PATH))

_TRAINED_TOGGLE = _env_tri_bool("USE_TRAINED_MODEL", "auto")
_TRAINED_MODEL_PATH = os.getenv("TRAINED_MODEL_PATH", "").strip() or _DEFAULT_JOBLIB
if not os.path.isfile(_TRAINED_MODEL_PATH) and os.path.isfile(_DEFAULT_JOBLIB):
    _TRAINED_MODEL_PATH = _DEFAULT_JOBLIB
_USE_TRAINED_MODEL = _TRAINED_TOGGLE == "on" or (
    _TRAINED_TOGGLE == "auto" and os.path.isfile(_TRAINED_MODEL_PATH)
)
_HAS_TRAINED_MODEL = bool(_USE_TRAINED_MODEL and os.path.isfile(_TRAINED_MODEL_PATH))

_CONDITIONS_TOGGLE = _env_tri_bool("USE_CONDITION_MODEL", "auto")
_CONDITIONS_MODEL_PATH = os.getenv("CONDITIONS_MODEL_PATH", "").strip() or _DEFAULT_CONDITIONS
_USE_CONDITION_MODEL = _CONDITIONS_TOGGLE == "on" or (
    _CONDITIONS_TOGGLE == "auto" and os.path.isfile(_CONDITIONS_MODEL_PATH)
)
_HAS_CONDITION_MODEL = bool(_USE_CONDITION_MODEL and os.path.isfile(_CONDITIONS_MODEL_PATH))

_STRICT_AI = os.getenv("STRICT_AI", "false").strip().lower() in {"1", "true", "yes", "y", "on"}


def _strict_ai_blocks() -> Optional[str]:
    """If strict mode rejects the request, return an error detail string; else None."""
    if not _STRICT_AI:
        return None
    if not _has_opencv:
        return "OpenCV pipeline unavailable. Install opencv-python-headless in the backend venv."
    if _USE_TRAINED_MODEL and not _HAS_TRAINED_MODEL:
        return (
            "Trained model enabled but file missing. Set TRAINED_MODEL_PATH to a valid .joblib "
            "or disable USE_TRAINED_MODEL."
        )
    return None

# JWT is sent in Authorization header (not cookies). allow_credentials=False keeps CORS valid
# with allow_origins=["*"] for any Flutter web port or LAN device origin during dev.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============ Pydantic Models ============

class ScalpAnalysisRequest(BaseModel):
    image_base64: Optional[str] = None
    patient_gender: Optional[str] = None
    patient_age: Optional[int] = None


class ScalpAnalysisResult(BaseModel):
    hair_strength: float
    scalp_health: float
    hair_density: float
    moisture_level: float
    conditions: List[str]
    recommendations: List[str]


class AppointmentCreate(BaseModel):
    user_id: str
    doctor_id: str
    doctor_name: str
    date: str
    time_slot: str
    reminder_minutes: int = 30
    consultation_notes: Optional[str] = None
    patient_name: Optional[str] = None
    priority: Optional[str] = None


class ReportCreate(BaseModel):
    user_id: str
    type: str
    title: str
    doctor_name: Optional[str] = None
    summary: dict = {}
    recommendations: List[str] = []


class RegisterRequest(BaseModel):
    email: str
    password: str
    role: str = "user"
    name: Optional[str] = None


class LoginRequest(BaseModel):
    email: str
    password: str


class VerifyOtpRequest(BaseModel):
    email: str
    otp: str


class ForgotPasswordRequest(BaseModel):
    email: str


class UserProfileUpdate(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None


class ConsultationRequestModel(BaseModel):
    user_id: str
    doctor_id: str
    report_id: Optional[str] = None
    note: Optional[str] = None


class ConsultationRespondModel(BaseModel):
    doctor_id: str
    action: str  # accepted / rejected / follow_up
    response_note: Optional[str] = None


# ============ Seed Data ============

doctors_db = [
    {"id": "1", "name": "Dr. Daniyal Ahmad", "location": "Johar Town, Lahore", "rating": 4.0, "consultation_fee": 120000},
    {"id": "2", "name": "Dr. Hina Alam", "location": "DHA Rahbar, Lahore", "rating": 5.0, "consultation_fee": 135000},
    {"id": "3", "name": "Dr. Ammar Hassan", "location": "Samnabad, Lahore", "rating": 3.5, "consultation_fee": 125000},
    {"id": "4", "name": "Dr. Ayesha Hassan", "location": "Lake City, Lahore", "rating": 3.5, "consultation_fee": 118000},
]

guidelines_db = [
    {"id": "1", "title": "Daily Scalp Care", "category": "Care", "content": "Clean your scalp daily with a gentle shampoo. Avoid harsh chemicals and hot water which can strip natural oils.", "tips": ["Use lukewarm water", "Massage gently", "Rinse thoroughly"]},
    {"id": "2", "title": "Nutrition for Hair", "category": "Nutrition", "content": "A balanced diet rich in protein, iron, zinc, and vitamins A, C, D, and E promotes healthy hair growth.", "tips": ["Eat eggs and fish", "Include leafy greens", "Stay hydrated"]},
    {"id": "3", "title": "Hair Loss Prevention", "category": "Prevention", "content": "Early intervention is key. Avoid tight hairstyles, reduce stress, and consult a specialist if you notice excessive shedding.", "tips": ["Avoid tight ponytails", "Manage stress", "Get regular checkups"]},
    {"id": "4", "title": "Scalp Massage Benefits", "category": "Care", "content": "Spend 3-5 minutes every night massaging your scalp with fingertips. This improves blood circulation and promotes growth.", "tips": ["Use circular motions", "Apply light pressure", "Be consistent"]},
    {"id": "5", "title": "Choosing the Right Products", "category": "Products", "content": "Select products based on your scalp type: oily, dry, or sensitive. Look for pH-balanced and sulfate-free options.", "tips": ["Know your scalp type", "Read ingredients", "Patch test new products"]},
]

appointments_db = []
reports_db = []
consultations_db = []
users_db: Dict[str, Dict[str, Any]] = {
    "usr_1": {
        "id": "usr_1",
        "email": "clinic.demo1@safehair.com",
        "password": "Clinic@123",
        "role": "doctor",
        "name": "Safe Hair Clinic One",
        "email_verified": True,
        "created_at": "2026-01-10T09:00:00",
    },
    "usr_2": {
        "id": "usr_2",
        "email": "clinic.demo2@safehair.com",
        "password": "Clinic@123",
        "role": "doctor",
        "name": "Safe Hair Clinic Two",
        "email_verified": True,
        "created_at": "2026-01-10T09:05:00",
    },
    "usr_3": {
        "id": "usr_3",
        "email": "patient.demo1@safehair.com",
        "password": "Patient@123",
        "role": "patient",
        "name": "Ali Raza",
        "email_verified": True,
        "created_at": "2026-01-10T09:10:00",
    },
    "usr_4": {
        "id": "usr_4",
        "email": "patient.demo2@safehair.com",
        "password": "Patient@123",
        "role": "patient",
        "name": "Sara Khan",
        "email_verified": True,
        "created_at": "2026-01-10T09:15:00",
    },
}
appointments_db = [
    {
        "id": "apt_1",
        "user_id": "usr_3",
        "doctor_id": "usr_1",
        "doctor_name": "Dr. Daniyal Ahmad",
        "date": "2026-04-10",
        "time_slot": "10:00 AM",
        "reminder_minutes": 30,
        "consultation_notes": "Initial scalp thinning consultation",
        "patient_name": "Ali Raza",
        "priority": "normal",
        "status": "confirmed",
        "created_at": "2026-04-08T10:00:00",
    },
    {
        "id": "apt_2",
        "user_id": "usr_4",
        "doctor_id": "usr_1",
        "doctor_name": "Dr. Daniyal Ahmad",
        "date": "2026-04-10",
        "time_slot": "11:30 AM",
        "reminder_minutes": 30,
        "consultation_notes": "Urgent shedding concern",
        "patient_name": "Sara Khan",
        "priority": "urgent",
        "status": "confirmed",
        "created_at": "2026-04-08T10:05:00",
    },
    {
        "id": "apt_3",
        "user_id": "usr_3",
        "doctor_id": "usr_2",
        "doctor_name": "Dr. Hina Alam",
        "date": "2026-04-11",
        "time_slot": "02:00 PM",
        "reminder_minutes": 45,
        "consultation_notes": "Follow-up for treatment plan",
        "patient_name": "Ali Raza",
        "priority": "normal",
        "status": "completed",
        "created_at": "2026-04-08T10:10:00",
    },
]
reports_db = [
    {
        "id": "rpt_1",
        "user_id": "usr_3",
        "type": "scalp_analysis",
        "title": "Scalp Analysis Report",
        "doctor_name": "Dr. Daniyal Ahmad",
        "summary": {
            "hair_strength": 63.0,
            "scalp_health": 58.0,
            "hair_density": 54.0,
            "moisture_level": 61.0,
            "conditions": ["Mild thinning", "Dry scalp"],
        },
        "recommendations": [
            "Use sulfate-free shampoo",
            "Increase protein intake",
            "Schedule monthly follow-up",
        ],
        "created_at": "2026-04-08T10:20:00",
    },
    {
        "id": "rpt_2",
        "user_id": "usr_4",
        "type": "scalp_analysis",
        "title": "Scalp Analysis Report",
        "doctor_name": "Dr. Daniyal Ahmad",
        "summary": {
            "hair_strength": 71.0,
            "scalp_health": 68.0,
            "hair_density": 66.0,
            "moisture_level": 64.0,
            "conditions": ["Early pattern loss"],
        },
        "recommendations": [
            "Start topical routine",
            "Avoid heat styling",
            "Repeat scan in 6 weeks",
        ],
        "created_at": "2026-04-08T10:22:00",
    },
]
consultations_db = [
    {
        "id": "con_1",
        "user_id": "usr_3",
        "doctor_id": "usr_1",
        "report_id": "rpt_1",
        "note": "Need treatment guidance",
        "status": "accepted",
        "created_at": "2026-04-08T10:30:00",
        "responded_at": "2026-04-08T10:45:00",
    },
    {
        "id": "con_2",
        "user_id": "usr_4",
        "doctor_id": "usr_1",
        "report_id": "rpt_2",
        "note": "Rapid hair fall in 2 months",
        "status": "pending",
        "created_at": "2026-04-08T10:32:00",
    },
]
_EMAIL_RE = re.compile(r"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$")
_PASSWORD_SPECIAL_RE = re.compile(r"[!@#$%^&*()_+\-=\[\]{}|;:\",.<>?/\\`~]")


def _new_id(prefix: str, current_len: int) -> str:
    return f"{prefix}_{current_len + 1}"


def _find_user_by_email(email: str) -> Optional[Dict[str, Any]]:
    em = email.strip().lower()
    for u in users_db.values():
        if str(u.get("email", "")).lower() == em:
            return u
    return None


def _is_valid_email(email: str) -> bool:
    return bool(_EMAIL_RE.match(email.strip()))


def _is_valid_password(password: str) -> bool:
    if len(password) < 8:
        return False
    if not re.search(r"[A-Z]", password):
        return False
    if not re.search(r"[a-z]", password):
        return False
    if not re.search(r"[0-9]", password):
        return False
    if not _PASSWORD_SPECIAL_RE.search(password):
        return False
    return True


def _normalize_role(role: Optional[str]) -> str:
    raw = (role or "patient").strip().lower()
    if raw in {"clinic", "doctor"}:
        return "doctor"
    if raw in {"patient", "user"}:
        return "patient"
    return "patient"


def _resolve_user_id(
    user_id: Optional[str],
    x_user_id: Optional[str],
    x_user_email: Optional[str],
) -> Optional[str]:
    if user_id:
        return user_id
    if x_user_id:
        return x_user_id
    if x_user_email:
        u = _find_user_by_email(x_user_email)
        if u:
            return str(u.get("id"))
    return None


# ============ API Endpoints ============

@app.get("/")
def root():
    return {
        "message": "Safe Hair API v2",
        "status": "running",
        "firebase": firebase_status(),
    }


@app.get("/api/firebase/status")
def api_firebase_status():
    return firebase_status()


@app.get("/api/ai/status")
def ai_status():
    return {
        "opencv_available": _has_opencv,
        "cnn_enabled": _USE_CNN,
        "cnn_model_path": _CNN_MODEL_PATH,
        "cnn_model_loaded": _HAS_CNN,
        "use_cnn_env": _CNN_TOGGLE,
        "trained_model_enabled": _USE_TRAINED_MODEL,
        "trained_model_path": _TRAINED_MODEL_PATH,
        "trained_model_loaded": _HAS_TRAINED_MODEL,
        "use_trained_model_env": _TRAINED_TOGGLE,
        "condition_model_enabled": _USE_CONDITION_MODEL,
        "condition_model_path": _CONDITIONS_MODEL_PATH,
        "condition_model_loaded": _HAS_CONDITION_MODEL,
        "use_condition_model_env": _CONDITIONS_TOGGLE,
        "strict_ai": _STRICT_AI,
    }


@app.post("/api/ai/scalp-analyze")
def ai_scalp_analyze(request: ScalpAnalysisRequest):
    if not request.image_base64:
        raise HTTPException(status_code=400, detail="Image required")
    try:
        image_bytes = base64.b64decode(request.image_base64)
        block = _strict_ai_blocks()
        if block:
            raise HTTPException(status_code=503, detail=block)
        result = (
            analyze_scalp_with_opencv(
                image_bytes,
                use_cnn=_HAS_CNN,
                cnn_model_path=_CNN_MODEL_PATH,
                use_trained_model=_HAS_TRAINED_MODEL,
                trained_model_path=_TRAINED_MODEL_PATH,
                use_condition_model=_HAS_CONDITION_MODEL,
                condition_model_path=_CONDITIONS_MODEL_PATH,
                patient_profile_gender=request.patient_gender,
                patient_profile_age=request.patient_age,
            )
            if _has_opencv
            else _analyze_scalp_fallback(image_bytes)
        )
        return {"success": True, **result}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.post("/api/ai/scalp-analyze-upload")
async def ai_scalp_analyze_upload(file: UploadFile = File(...)):
    try:
        image_bytes = await file.read()
        block = _strict_ai_blocks()
        if block:
            raise HTTPException(status_code=503, detail=block)
        result = (
            analyze_scalp_with_opencv(
                image_bytes,
                use_cnn=_HAS_CNN,
                cnn_model_path=_CNN_MODEL_PATH,
                use_trained_model=_HAS_TRAINED_MODEL,
                trained_model_path=_TRAINED_MODEL_PATH,
                use_condition_model=_HAS_CONDITION_MODEL,
                condition_model_path=_CONDITIONS_MODEL_PATH,
            )
            if _has_opencv
            else _analyze_scalp_fallback(image_bytes)
        )
        return {"success": True, **result}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# ============ API v1 (Requested Contract) ============

@app.post("/api/v1/auth/register")
def v1_auth_register(payload: RegisterRequest):
    if not _is_valid_email(payload.email):
        raise HTTPException(status_code=400, detail="Invalid email format")
    if not _is_valid_password(payload.password):
        raise HTTPException(
            status_code=400,
            detail="Password must be 8+ chars with upper, lower, number, and special character",
        )
    if _find_user_by_email(payload.email):
        raise HTTPException(status_code=409, detail="Email already registered")
    role = _normalize_role(payload.role)
    uid = _new_id("usr", len(users_db))
    user = {
        "id": uid,
        "email": payload.email.strip().lower(),
        "password": payload.password,
        "role": role,
        "name": payload.name or payload.email.split("@")[0],
        "email_verified": False,
        "created_at": datetime.utcnow().isoformat(),
    }
    users_db[uid] = user
    return {"success": True, "user": {k: v for k, v in user.items() if k != "password"}}


@app.post("/api/v1/auth/login")
def v1_auth_login(payload: LoginRequest):
    if not _is_valid_email(payload.email):
        raise HTTPException(status_code=400, detail="Invalid email format")
    if not _is_valid_password(payload.password):
        raise HTTPException(status_code=400, detail="Invalid credentials")
    user = _find_user_by_email(payload.email)
    if not user or user.get("password") != payload.password:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    # Lightweight demo token for local dev.
    token = base64.b64encode(f"{user['id']}:{user['email']}".encode()).decode()
    return {
        "success": True,
        "access_token": token,
        "token_type": "bearer",
        "user": {k: v for k, v in user.items() if k != "password"},
    }


@app.post("/api/v1/auth/verify-otp")
def v1_auth_verify_otp(payload: VerifyOtpRequest):
    user = _find_user_by_email(payload.email)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    # Demo OTP behavior: accepts 123456 for local integration.
    if payload.otp != "123456":
        raise HTTPException(status_code=400, detail="Invalid OTP")
    user["email_verified"] = True
    user["verified_at"] = datetime.utcnow().isoformat()
    return {"success": True, "message": "OTP verified"}


@app.post("/api/v1/auth/forgot-password")
def v1_auth_forgot_password(payload: ForgotPasswordRequest):
    # For local/dev API we only acknowledge request.
    return {"success": True, "message": f"Password reset email queued for {payload.email}"}


@app.get("/api/v1/users/me")
def v1_users_me(
    user_id: Optional[str] = Query(default=None),
    x_user_id: Optional[str] = Header(default=None),
    x_user_email: Optional[str] = Header(default=None),
):
    uid = _resolve_user_id(user_id, x_user_id, x_user_email)
    if not uid or uid not in users_db:
        raise HTTPException(status_code=404, detail="User not found")
    user = users_db[uid]
    return {"success": True, "user": {k: v for k, v in user.items() if k != "password"}}


@app.put("/api/v1/users/me")
def v1_users_me_update(
    payload: UserProfileUpdate,
    user_id: Optional[str] = Query(default=None),
    x_user_id: Optional[str] = Header(default=None),
    x_user_email: Optional[str] = Header(default=None),
):
    uid = _resolve_user_id(user_id, x_user_id, x_user_email)
    if not uid or uid not in users_db:
        raise HTTPException(status_code=404, detail="User not found")
    user = users_db[uid]
    for k, v in payload.model_dump(exclude_none=True).items():
        user[k] = v
    user["updated_at"] = datetime.utcnow().isoformat()
    return {"success": True, "user": {k: v for k, v in user.items() if k != "password"}}


@app.post("/api/v1/reports/upload")
async def v1_reports_upload(
    file: UploadFile = File(...),
    user_id: Optional[str] = Query(default=None),
    patient_gender: Optional[str] = Query(default=None),
    patient_age: Optional[int] = Query(default=None),
):
    image_bytes = await file.read()
    block = _strict_ai_blocks()
    if block:
        raise HTTPException(status_code=503, detail=block)
    result = (
        analyze_scalp_with_opencv(
            image_bytes,
            use_cnn=_HAS_CNN,
            cnn_model_path=_CNN_MODEL_PATH,
            use_trained_model=_HAS_TRAINED_MODEL,
            trained_model_path=_TRAINED_MODEL_PATH,
            use_condition_model=_HAS_CONDITION_MODEL,
            condition_model_path=_CONDITIONS_MODEL_PATH,
            patient_profile_gender=patient_gender,
            patient_profile_age=patient_age,
        )
        if _has_opencv
        else _analyze_scalp_fallback(image_bytes)
    )
    rpt = {
        "id": _new_id("rpt", len(reports_db)),
        "user_id": user_id or "unknown",
        "type": "scalp_analysis",
        "title": "Scalp Analysis Report",
        "summary": result,
        "recommendations": result.get("recommendations", []),
        "created_at": datetime.utcnow().isoformat(),
    }
    reports_db.append(rpt)
    return {"success": True, "report": rpt, "analysis": result, **result}


@app.get("/api/v1/reports/id/{report_id}")
def v1_report_get_compat(report_id: str):
    for r in reports_db:
        if str(r.get("id")) == report_id:
            return {"success": True, "report": r}
    raise HTTPException(status_code=404, detail="Report not found")


@app.get("/api/v1/reports/my")
def v1_reports_my(
    user_id: Optional[str] = Query(default=None),
    x_user_id: Optional[str] = Header(default=None),
):
    uid = user_id or x_user_id
    if not uid:
        return {"success": True, "reports": []}
    mine = [r for r in reports_db if str(r.get("user_id")) == str(uid)]
    return {"success": True, "reports": mine}


@app.get("/api/v1/reports/{report_id}")
def v1_report_get(report_id: str):
    for r in reports_db:
        if str(r.get("id")) == report_id:
            return {"success": True, "report": r}
    raise HTTPException(status_code=404, detail="Report not found")


@app.post("/api/v1/doctors/register")
def v1_doctor_register(payload: dict):
    uid = str(payload.get("user_id") or payload.get("userId") or _new_id("doc", len(doctors_db)))
    doc = {
        "id": uid,
        "name": payload.get("name") or payload.get("doctor_name") or "Doctor",
        "location": payload.get("location") or "",
        "rating": float(payload.get("rating") or 0),
        "consultation_fee": int(payload.get("consultation_fee") or 0),
        "verified": bool(payload.get("verified", True)),
        "created_at": datetime.utcnow().isoformat(),
    }
    doctors_db.append(doc)
    return {"success": True, "doctor": doc}


@app.get("/api/v1/doctors/verified")
def v1_doctors_verified():
    return {"success": True, "doctors": [d for d in doctors_db if d.get("verified", True)]}


@app.post("/api/v1/consultations/request")
def v1_consultation_request(payload: ConsultationRequestModel):
    req = {
        "id": _new_id("con", len(consultations_db)),
        **payload.model_dump(),
        "status": "pending",
        "created_at": datetime.utcnow().isoformat(),
    }
    consultations_db.append(req)
    return {"success": True, "consultation": req}


@app.get("/api/v1/consultations/my")
def v1_consultations_my(
    user_id: Optional[str] = Query(default=None),
    doctor_id: Optional[str] = Query(default=None),
):
    if user_id:
        data = [c for c in consultations_db if str(c.get("user_id")) == str(user_id)]
    elif doctor_id:
        data = [c for c in consultations_db if str(c.get("doctor_id")) == str(doctor_id)]
    else:
        data = consultations_db
    return {"success": True, "consultations": data}


@app.put("/api/v1/consultations/{id}/respond")
def v1_consultation_respond(id: str, payload: ConsultationRespondModel):
    for c in consultations_db:
        if str(c.get("id")) == id:
            if str(c.get("doctor_id")) != str(payload.doctor_id):
                raise HTTPException(status_code=403, detail="Doctor mismatch")
            c["status"] = payload.action
            c["response_note"] = payload.response_note
            c["responded_at"] = datetime.utcnow().isoformat()
            return {"success": True, "consultation": c}
    raise HTTPException(status_code=404, detail="Consultation not found")


@app.get("/api/doctors")
def get_doctors():
    return doctors_db


@app.get("/api/guidelines")
def get_guidelines(category: Optional[str] = None):
    items = []
    db = get_firestore()
    if db:
        try:
            for snap in db.collection("guidelines").stream():
                d = snap.to_dict() or {}
                items.append({
                    "id": snap.id,
                    "title": d.get("title", ""),
                    "category": d.get("category", ""),
                    "content": d.get("content", ""),
                    "tips": d.get("tips") or [],
                })
        except Exception:
            items = []
    base = items if items else guidelines_db
    if category:
        return [g for g in base if g.get("category") == category]
    return base


@app.post("/api/appointments")
def create_appointment(appointment: AppointmentCreate):
    data = appointment.model_dump()
    apt = {
        "id": str(len(appointments_db) + 1),
        **data,
        "created_at": datetime.utcnow().isoformat(),
        "status": "confirmed",
    }
    db = get_firestore()
    if db:
        try:
            now = datetime.utcnow().isoformat() + "Z"
            fs_doc = {
                "userId": data["user_id"],
                "user_id": data["user_id"],
                "doctorId": data["doctor_id"],
                "doctor_id": data["doctor_id"],
                "doctor_name": data["doctor_name"],
                "doctorName": data["doctor_name"],
                "date": data["date"],
                "timeSlot": data["time_slot"],
                "time_slot": data["time_slot"],
                "reminderMinutes": data["reminder_minutes"],
                "reminder_minutes": data["reminder_minutes"],
                "consultationNotes": data.get("consultation_notes"),
                "consultation_notes": data.get("consultation_notes"),
                "status": "confirmed",
                "createdAt": now,
                "created_at": now,
            }
            pn = data.get("patient_name")
            if pn:
                fs_doc["patientName"] = pn
                fs_doc["patient_name"] = pn
            pr = data.get("priority")
            if pr:
                fs_doc["priority"] = pr
            ref = db.collection("appointments").document()
            ref.set(fs_doc)
            apt["id"] = ref.id
            apt["firestore_id"] = ref.id
        except Exception as e:
            apt["firestore_error"] = str(e)
    appointments_db.append(apt)
    return {"success": True, "appointment": apt}


@app.post("/api/reports")
def create_report(report: ReportCreate):
    data = report.model_dump()
    rpt = {
        "id": str(len(reports_db) + 1),
        **data,
        "created_at": datetime.utcnow().isoformat(),
    }
    db = get_firestore()
    if db:
        try:
            now = datetime.utcnow().isoformat() + "Z"
            payload = {**data, "createdAt": now, "created_at": now}
            ref = db.collection("reports").document()
            ref.set(payload)
            rpt["id"] = ref.id
            rpt["firestore_id"] = ref.id
        except Exception as e:
            rpt["firestore_error"] = str(e)
    reports_db.append(rpt)
    return {"success": True, "report": rpt}


@app.post("/api/scalp-analysis")
def save_scalp_analysis(analysis: dict):
    db = get_firestore()
    if db:
        try:
            now = datetime.utcnow().isoformat() + "Z"
            payload = {**analysis, "createdAt": analysis.get("createdAt") or now}
            ref = db.collection("scalp_analyses").document()
            ref.set(payload)
            return {"success": True, "id": ref.id, "analysis": analysis, "stored": "firestore"}
        except Exception as e:
            return {"success": False, "detail": str(e), "analysis": analysis}
    return {"success": True, "analysis": analysis, "stored": "memory"}


@app.post("/api/patient-details")
def save_patient_details(details: dict):
    db = get_firestore()
    uid = details.get("user_id") or details.get("userId")
    if db and uid:
        try:
            uid_s = str(uid)
            now = datetime.utcnow().isoformat() + "Z"
            payload = {
                **details,
                "userId": uid_s,
                "user_id": uid_s,
                "profileCompleted": True,
                "updatedAt": now,
            }
            db.collection("patient_details").document(uid_s).set(payload, merge=True)
            return {"success": True, "stored": "firestore"}
        except Exception as e:
            return {"success": False, "detail": str(e)}
    return {"success": True, "stored": "memory"}


@app.post("/api/doctor-profile")
def save_doctor_profile(profile: dict):
    """Persist clinic / doctor registration data (same collection as the Flutter app: `doctors`)."""
    db = get_firestore()
    uid = profile.get("user_id") or profile.get("userId")
    if db and uid:
        try:
            uid_s = str(uid)
            now = datetime.utcnow().isoformat() + "Z"
            payload = {
                **profile,
                "userId": uid_s,
                "user_id": uid_s,
                "updatedAt": now,
            }
            db.collection("doctors").document(uid_s).set(payload, merge=True)
            return {"success": True, "stored": "firestore"}
        except Exception as e:
            return {"success": False, "detail": str(e)}
    return {"success": True, "stored": "memory"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
