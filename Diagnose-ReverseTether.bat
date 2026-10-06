@echo off
setlocal EnableDelayedExpansion
title Reverse Tether - Diagnostics
rem Read-only health check. Saves the report to diagnostics.txt next to this file
rem (attach it when opening a GitHub issue).
pushd "%~dp0"
set "USBIPD=C:\Program Files\usbipd-win\usbipd.exe"
set "DISTRO="

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
echo == WSL distros ==
rem WSL_UTF8=1 makes wsl print UTF-8 instead of UTF-16, so it is readable in the report.
set WSL_UTF8=1
wsl -l -v
rem Same auto-detect as the launcher. wsl.exe fails with negative codes, so compare with neq 0.
if not defined DISTRO for %%D in (Ubuntu Ubuntu-24.04 Ubuntu-22.04 Ubuntu-20.04) do if not defined DISTRO (
    wsl -d %%D -- true <nul >nul 2>&1
    if !errorlevel! equ 0 set "DISTRO=%%D"
)
if not defined DISTRO (
    echo   [FAIL] No Ubuntu WSL distro found -^> run the launcher ^(it installs one^)
    exit /b 0
)
echo   [OK]   using WSL distro %DISTRO%
echo.
wsl -d %DISTRO% -- bash diagnose.sh <nul
exit /b 0
