@echo off
setlocal

set "ROOT=%~dp0"
set "BACKEND_DIR=%ROOT%backend"

if exist "%BACKEND_DIR%\.venv\Scripts\python.exe" (
  start "Safe Hair Backend" /D "%BACKEND_DIR%" cmd /k ".venv\Scripts\python.exe -m uvicorn main:app --reload --host 0.0.0.0 --port 8000"
) else (
  start "Safe Hair Backend" /D "%BACKEND_DIR%" cmd /k "python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000"
)

endlocal
