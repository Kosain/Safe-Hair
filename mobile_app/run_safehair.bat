@echo off
setlocal

set "ROOT=%~dp0"
set "BACKEND_DIR=%ROOT%backend"
set "MOBILE_DIR=%ROOT%mobile_app"

echo Starting Safe Hair backend and frontend...

start "Safe Hair Backend" cmd /k "cd /d \"%BACKEND_DIR%\" && start_backend.bat"

start "Safe Hair Frontend" cmd /k "cd /d \"%MOBILE_DIR%\" && flutter run -d chrome"

echo Done. Two windows opened: Backend + Frontend.
endlocal
