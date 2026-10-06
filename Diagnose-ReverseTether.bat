@echo off
setlocal
title Reverse Tether - Diagnostics
rem Read-only health check. Saves the report to diagnostics.txt next to this file
rem (attach it when opening a GitHub issue).
pushd "%~dp0"
set "USBIPD=C:\Program Files\usbipd-win\usbipd.exe"
set "DISTRO=Ubuntu"

call :REPORT > diagnostics.txt 2>&1
type diagnostics.txt
echo.
echo Saved to: %~dp0diagnostics.txt
pause
exit /b 0

:REPORT
echo Reverse Tether diagnostics - %date% %time%
echo.
echo == Windows ==
ver
if not exist "%USBIPD%" (
    echo   [FAIL] usbipd-win not installed -^> run the launcher
    exit /b 0
)
for /f "delims=" %%V in ('"%USBIPD%" --version') do echo   usbipd-win %%V
"%USBIPD%" list
powershell -NoProfile -Command "if (Get-CimInstance Win32_Process -Filter 'Name=''usbipd.exe''' | ? CommandLine -match 'auto-attach') {'  [OK]   USB auto-attach running'} else {'  [WARN] USB auto-attach not running -> run the launcher (phone will not reconnect after a USB drop)'}"
echo.
wsl -d %DISTRO% -- true <nul >nul 2>&1
if errorlevel 1 (
    echo   [FAIL] WSL distro %DISTRO% not available -^> run the launcher
    exit /b 0
)
wsl -d %DISTRO% -- bash diagnose.sh <nul
exit /b 0
