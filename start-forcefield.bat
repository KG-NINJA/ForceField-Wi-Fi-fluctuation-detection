@echo off
setlocal
pushd "%~dp0"

echo [1/4] Installing dependencies (if needed)...
if not exist "node_modules\ws" (
  call npm install
  if errorlevel 1 (
    echo Failed to install dependencies.
    exit /b 1
  )
)

echo [2/4] Starting Node.js server...
set "PID8080="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "(Get-NetTCPConnection -State Listen -LocalPort 8080 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess)"`) do set "PID8080=%%P"

if defined PID8080 (
  echo Port 8080 is already in use by PID %PID8080%. Skipping server start.
) else (
  start "Forcefield Server" cmd /k "cd /d %cd% && node server.js"
)

set /a WAIT_COUNT=0
:wait_server
powershell -NoProfile -Command "if ((Test-NetConnection 127.0.0.1 -Port 8080 -WarningAction SilentlyContinue).TcpTestSucceeded) { exit 0 } else { exit 1 }" >nul 2>&1
if errorlevel 1 (
  set /a WAIT_COUNT+=1
  if %WAIT_COUNT% GEQ 10 (
    echo Server is not reachable on 127.0.0.1:8080
    popd
    exit /b 1
  )
  timeout /t 1 /nobreak >nul
  goto wait_server
)

echo [3/4] Opening browser...
timeout /t 2 /nobreak >nul
start "" "http://localhost:8080"

echo [4/4] Starting PowerShell sensor...
start "Forcefield Sensor" powershell -NoExit -ExecutionPolicy Bypass -File "%cd%\powershell-sensor.ps1" -Url ws://127.0.0.1:8080 -Target 127.0.0.1

echo Forcefield stack launched.
popd
endlocal
