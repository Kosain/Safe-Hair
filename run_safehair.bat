@echo off
setlocal

set "ROOT=%~dp0"
set "BACKEND_DIR=%ROOT%backend"
set "MOBILE_DIR=%ROOT%mobile_app"

echo Starting Safe Hair backend and frontend...

if exist "%BACKEND_DIR%\.venv\Scripts\python.exe" (
  start "Safe Hair Backend" /D "%BACKEND_DIR%" cmd /k ".venv\Scripts\python.exe -m uvicorn main:app --reload --host 0.0.0.0 --port 8000"
) else (
  start "Safe Hair Backend" /D "%BACKEND_DIR%" cmd /k "python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000"
)

start "Safe Hair Frontend" /D "%MOBILE_DIR%" cmd /k "flutter run -d chrome"

echo Done. Two windows opened: Backend + Frontend.
endlocal
