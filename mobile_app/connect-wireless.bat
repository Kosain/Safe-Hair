@echo off
echo.
echo === Wireless Android Connect ===
echo On phone: Settings ^> Developer options ^> Wireless debugging ^> Pair device with pairing code
echo.

set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
if not exist "%ADB%" set ADB=adb

set /p PAIR="Enter PAIR address from phone (e.g. 192.168.1.10:37123): "
if not "%PAIR%"=="" "%ADB%" pair %PAIR%

echo.
echo Now on phone: note "Device IP address" (e.g. 192.168.1.10:5555)
echo.

set /p CONNECT="Enter CONNECT address (e.g. 192.168.1.10:5555): "
if not "%CONNECT%"=="" "%ADB%" connect %CONNECT%

"%ADB%" devices
echo.
echo Done! Run: flutter run
pause
