@echo off
setlocal
cd /d "%~dp0"

echo Safe Hair AI backend - http://localhost:8000
echo Trained models: models\scalp_seg.onnx + models\bald_regressor.joblib

if exist ".venv\Scripts\python.exe" (
  ".venv\Scripts\python.exe" -c "import cv2" 2>nul
  if not errorlevel 1 (
    ".venv\Scripts\python.exe" -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
    goto end
  )
  echo .venv broken - using py -3 instead. Recreate: py -3 -m venv .venv
)

py -3 -m uvicorn main:app --reload --host 0.0.0.0 --port 8000

:end
endlocal
