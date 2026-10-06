@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Errors are checked with "!errorlevel! neq 0", not "if errorlevel 1": wsl.exe fails with
rem NEGATIVE codes (e.g. -1 for a missing distro), which "if errorlevel 1" treats as success.
title PC to Android - Reverse Tether
rem wsl starts in the current Windows folder, so bundled files next to this .bat are visible to it.
pushd "%~dp0"

set "USBIPD=C:\Program Files\usbipd-win\usbipd.exe"
rem WSL distro to use. Empty = auto-detect Ubuntu, Ubuntu-24.04, Ubuntu-22.04 or Ubuntu-20.04.
set "DISTRO="
set "VER=v0.9.5-beta.1"
set "RELAY=OpenTether-%VER%-linux-amd64"
set "APK=OpenTether-%VER%-android.apk"
set "BASE_URL=https://github.com/pyd-07/NetcoN-OpenTether/releases/download/%VER%"
set "APP_PKG=com.opentether"
set "WGCF_URL=https://github.com/ViRb3/wgcf/releases/download/v2.3.0/wgcf_2.3.0_linux_amd64"
rem USB vendor IDs of common Android phone makers (Google, Samsung, OnePlus/OPPO/realme,
rem Xiaomi, Huawei, Motorola, LG, Sony, HTC, vivo, ZTE, Qualcomm, MediaTek, Nothing, Asus, Nokia).
rem ponytail: fixed list; a phone from another maker is picked manually by BUSID.
set "VENDORS= 18d1 04e8 22d9 2a70 2717 12d1 22b8 1004 0fce 0bb4 2d95 19d2 05c6 0e8d 2b4c 0b05 2e04 "

echo.
echo ================================================
echo       PC ^> ANDROID USB REVERSE TETHER
echo ================================================
echo.

echo [1/9] Checking usbipd-win...
if not exist "%USBIPD%" (
    echo       Not found. Installing usbipd-win with winget...
    winget install --exact --id dorssel.usbipd-win --accept-source-agreements --accept-package-agreements
    if not exist "%USBIPD%" (
        echo [ERROR] usbipd-win install failed.
        pause
        exit /b 1
    )
)
echo       usbipd-win OK.
echo.

echo [2/9] Checking WSL Ubuntu...
rem Fresh installs are often named Ubuntu-24.04 etc., so use the first one that exists.
if not defined DISTRO for %%D in (Ubuntu Ubuntu-24.04 Ubuntu-22.04 Ubuntu-20.04) do if not defined DISTRO (
    wsl -d %%D -- true <nul >nul 2>&1
    if !errorlevel! equ 0 set "DISTRO=%%D"
)
if not defined DISTRO (
    echo       Ubuntu not found. Installing WSL + Ubuntu...
    echo       Create your Linux username/password when asked.
    wsl --install -d Ubuntu
    echo.
    echo [ACTION REQUIRED] If Windows asks for a restart, restart.
    echo Then run this launcher again.
    pause
    exit /b 1
)
echo       Using WSL distro !DISTRO!.
echo.

echo [3/9] Checking Linux tools (adb, lsusb, wget, iptables)...
rem Not redirected: apt may ask for your Ubuntu sudo password here.
wsl -d %DISTRO% -- bash -lc "command -v adb && command -v lsusb && command -v wget && command -v iptables || (sudo apt-get update && sudo apt-get install -y adb usbutils wget iptables)" >nul
if !errorlevel! neq 0 (
    echo [ERROR] Could not install adb/usbutils/wget/iptables in %DISTRO%.
    pause
    exit /b 1
)
echo       Linux tools OK.
echo.

echo [4/9] Checking OpenTether relay...
rem Uses ~/%RELAY% if present, else a copy next to this .bat, else downloads it.
wsl -d %DISTRO% -- bash -lc "test -x ~/%RELAY% || { cp %RELAY% ~/ 2>/dev/null || wget -q --show-progress %BASE_URL%/%RELAY% -O ~/%RELAY%; } && chmod +x ~/%RELAY%" <nul
if !errorlevel! neq 0 (
    echo [ERROR] Could not get the OpenTether relay.
    pause
    exit /b 1
)
echo       Relay OK.
echo.

echo [5/9] Looking for an Android phone...
call :FIND_PHONE
if not defined BUSID (
    echo.
    echo [ACTION REQUIRED]
    echo Connect the phone by USB and make sure USB debugging is enabled.
    pause
    call :FIND_PHONE
)
if not defined BUSID (
    echo       No known phone maker found. Devices:
    "%USBIPD%" list
    set /p "PICK=Type the BUSID of your phone (e.g. 1-5): "
    call :FIND_PHONE
)
if not defined BUSID (
    echo [ERROR] Phone was not found.
    pause
    exit /b 1
)
echo       Found !NAME! - BUSID !BUSID! - !VIDPID! - !USBSTATE!
echo.

echo [6/9] Connecting USB to WSL...
if "!USBSTATE!"=="Not shared" (
    echo       Requesting Administrator permission to share it...
    powershell -NoProfile -Command "$p = Start-Process -FilePath '%USBIPD%' -ArgumentList 'bind','--busid','!BUSID!','--force' -Verb RunAs -Wait -PassThru; exit $p.ExitCode"
    if !errorlevel! neq 0 (
        echo [ERROR] Could not share the USB device.
        pause
        exit /b 1
    )
)
rem A plain attach is lost whenever the phone resets USB (it falls back to "Shared"
rem and ADB loses it). --auto-attach stays running and re-attaches it every time.
powershell -NoProfile -Command "if (Get-CimInstance Win32_Process -Filter 'Name=''usbipd.exe''' | ? CommandLine -match 'auto-attach') {exit 0}; exit 1"
if !errorlevel! neq 0 (
    echo       Starting USB auto-attach in a minimized window ^(keep it open^)...
    start "USB Auto-Attach" /min "%USBIPD%" attach --wsl --busid !BUSID! --auto-attach
) else (
    echo       USB auto-attach already running.
)
set /a tries=0
:WAITUSB
set /a tries+=1
wsl -d %DISTRO% -- bash -lc "lsusb | grep -q '!VIDPID!'" <nul >nul 2>&1
if !errorlevel! equ 0 goto USBOK
if !tries! GEQ 20 (
    echo [ERROR] Phone did not appear inside WSL.
    pause
    exit /b 1
)
timeout /t 1 /nobreak >nul
goto WAITUSB
:USBOK
echo       Phone is visible in WSL.
echo.

echo [7/9] Checking ADB authorization...
call :ADB_OK
if !errorlevel! neq 0 (
    echo.
    echo [ACTION REQUIRED ON PHONE]
    echo Unlock the phone and accept the USB debugging prompt.
    echo Then press any key here.
    pause
    call :ADB_OK
)
if !errorlevel! neq 0 (
    echo [ERROR] ADB is not authorized.
    wsl -d %DISTRO% -- adb devices
    pause
    exit /b 1
)
echo       ADB authorized.
echo.

echo [8/9] Checking OpenTether app on the phone...
call :APP_OK
if !errorlevel! neq 0 (
    echo       Not installed. Installing it - WATCH THE PHONE and approve any
    echo       install or Play Protect prompt...
    rem APK search order: next to this .bat, then ~ in Ubuntu, else download.
    rem --exec matters: without it WSL's shell expands $apk and $(...) to nothing first.
    wsl -d %DISTRO% --exec bash -lc "apk=$(ls %APK% ~/%APK% 2>/dev/null | head -n1); [ -z $apk ] && { wget -q --show-progress %BASE_URL%/%APK% -O ~/%APK% && apk=~/%APK%; }; adb install -r $apk" <nul
    call :APP_OK
)
if !errorlevel! neq 0 (
    echo.
    echo [ACTION REQUIRED] Install the OpenTether app on the phone manually:
    echo   %BASE_URL%/%APK%
    echo   Open that link on the phone ^(or copy the APK over^), install it,
    echo   then press any key here.
    pause
    call :APP_OK
)
if !errorlevel! neq 0 (
    echo [ERROR] The OpenTether app is still not installed.
    pause
    exit /b 1
)
echo       OpenTether app OK.
echo.

wsl -d %DISTRO% -- pgrep -f "%RELAY%" <nul >nul 2>&1
if !errorlevel! equ 0 (
    echo       Relay is already running.
) else (
    echo       Starting OpenTether relay in a new window ^(enter your Ubuntu sudo password there^)...
    start "OpenTether Relay" wsl -d %DISTRO% -- bash -lc "cd ~ && sudo ./%RELAY%; echo Relay exited.; read -p 'Press Enter to close'"
    timeout /t 3 /nobreak >nul
)

echo.
echo       Torrent mode: some ISPs block BitTorrent. It routes ONLY the phone's
echo       traffic through free Cloudflare WARP inside Ubuntu. Windows is untouched.
wsl -d %DISTRO% -- ip link show wg-ot <nul >nul 2>&1
if !errorlevel! equ 0 (
    echo       Torrent mode is already on.
) else (
    set "TORRENT="
    set /p "TORRENT=      Turn on torrent mode? [y/N]: "
    if /I "!TORRENT!"=="y" call :TORRENT_ON
)

echo.
echo ================================================
echo [9/9] ACTION REQUIRED ON PHONE
echo ================================================
echo.
echo Open OpenTether on your phone.
echo Tap START VPN and approve the Android VPN prompt.
echo.
echo Tips (see README): keep Mobile data ON and set OpenTether's battery
echo usage to Unrestricted, or the phone may freeze it in the background.
echo.
echo Press any key here AFTER the VPN is running.
echo ================================================
pause >nul

echo.
echo Checking tunnel...
wsl -d %DISTRO% -- ip link show ot0 <nul >nul 2>&1
if !errorlevel! neq 0 (
    echo [WARNING] ot0 was not detected.
    echo Check the OpenTether Relay window.
    pause
    exit /b 1
)

echo.
echo ================================================
echo          REVERSE TETHERING ACTIVE
echo ================================================
echo.
echo Keep the OpenTether Relay window open.
echo.
pause
exit /b 0

rem ---------------------------------------------------------------
rem Sets BUSID, VIDPID, NAME and USBSTATE (Not shared / Shared / Attached).
rem Picks the first device whose vendor is in VENDORS, or BUSID=PICK if set.
rem usebackq with exactly two quotes is deliberate: a for /f command
rem like ('"C:\Program Files\..." list ^| findstr "x"') has >2 quotes,
rem so cmd /c strips the first and last one and runs C:\Program.
rem Only tokens 1-2 (BUSID, VID:PID) are split; names contain spaces.
:FIND_PHONE
set "BUSID="
set "LINE="
for /f "usebackq tokens=1,2* delims= " %%A in (`"%USBIPD%" list`) do (
    set "ID=%%B"
    if not defined LINE if "!ID:~4,1!"==":" (
        set "V=!ID:~0,4!"
        if defined PICK (
            if "%%A"=="!PICK!" set "LINE=%%C" & set "BUSID=%%A" & set "VIDPID=%%B"
        ) else (
            for %%X in (!V!) do if not "!VENDORS: %%X =!"=="!VENDORS!" set "LINE=%%C" & set "BUSID=%%A" & set "VIDPID=%%B"
        )
    )
)
if not defined LINE exit /b 0
rem "Not shared" contains "shared", so test it first.
if not "!LINE:Not shared=!"=="!LINE!" (set "USBSTATE=Not shared") else if not "!LINE:Attached=!"=="!LINE!" (set "USBSTATE=Attached") else set "USBSTATE=Shared"
set "NAME=!LINE:  Not shared=!"
set "NAME=!NAME:  Attached=!"
set "NAME=!NAME:  Shared=!"
:TRIM
if "!NAME:~-1!"==" " set "NAME=!NAME:~0,-1!" & goto TRIM
exit /b 0

:TORRENT_ON
rem Free WARP profile in ~/warp (no sudo, made once), then torrent-vpn.sh from this folder.
wsl -d %DISTRO% -- bash -lc "mkdir -p ~/warp && cd ~/warp && { test -x wgcf || { wget -q %WGCF_URL% -O wgcf && chmod +x wgcf; }; } && { test -f wgcf-account.toml || ./wgcf register --accept-tos >/dev/null; } && { test -f wgcf-profile.conf || ./wgcf generate >/dev/null; }" <nul
if !errorlevel! neq 0 (
    echo [WARNING] Could not create the WARP profile. Torrent mode skipped.
    exit /b 0
)
echo       Enter your Ubuntu sudo password if asked...
wsl -d %DISTRO% -- sudo bash torrent-vpn.sh up
if !errorlevel! neq 0 echo [WARNING] Torrent mode failed. Normal internet still works.
exit /b 0

:APP_OK
rem Check pm's output, not adb's exit code: older adb versions don't pass the phone's exit code back.
wsl -d %DISTRO% -- bash -lc "adb shell pm path %APP_PKG% | grep -q package:" <nul >nul 2>&1
exit /b

:ADB_OK
rem findstr's $ only matches before CR; Linux output is LF-only, so grep in WSL.
wsl -d %DISTRO% -- bash -lc "adb devices | grep -q 'device$'" <nul >nul 2>&1
exit /b
