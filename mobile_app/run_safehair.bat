@echo off
setlocal

set "ROOT=%~dp0"
set "BACKEND_DIR=%ROOT%backend"
set "MOBILE_DIR=%ROOT%mobile_app"

echo Starting Safe Hair backend and frontend...

if exist "%BACKEND_DIR%\.venv\Scripts\python.exe" (
  start "Safe Hair Backend" cmd /k "cd /d \"%BACKEND_DIR%\" && .venv\Scripts\python.exe -m uvicorn main:app --reload --host 0.0.0.0 --port 8000"
) else (
  start "Safe Hair Backend" cmd /k "cd /d \"%BACKEND_DIR%\" && python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000"
)

start "Safe Hair Frontend" cmd /k "cd /d \"%MOBILE_DIR%\" && flutter run -d chrome"

echo Done. Two windows opened: Backend + Frontend.
endlocal
