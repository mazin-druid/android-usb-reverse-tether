@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Errors are checked with "!errorlevel! neq 0", not "if errorlevel 1": wsl.exe fails with
rem NEGATIVE codes (e.g. -1 for a missing distro), which "if errorlevel 1" treats as success.
title Android USB Reverse Tether
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

rem ANSI colours (Windows 10+ consoles). forfiles can print a raw ESC character (0x1B).
rem Set NO_COLOR=1 before running to turn colours off.
if not defined NO_COLOR for /f %%e in ('forfiles /m "%~nx0" /c "cmd /c echo 0x1B"') do set "ESC=%%e"
if defined ESC (
    set "N=%ESC%[0m"
    set "DIM=%ESC%[90m"
    set "HI=%ESC%[1;97m"
    set "STEP=%ESC%[1;96m"
    set "GOOD=%ESC%[92m"
    set "WARN=%ESC%[93m"
    set "BAD=%ESC%[91m"
    set "ACT=%ESC%[1;93m"
    set "BAR=%ESC%[1;97;44m"
    set "WIN=%ESC%[1;30;102m"
)
set "OK=  %GOOD%[ OK ]%N%"
set "DO=  %WARN%[ .. ]%N%"
set "WRN=  %WARN%[WARN]%N%"
set "ERR=  %BAD%[FAIL]%N%"

cls
echo.
echo(  %BAR%                                                        %N%
echo(  %BAR%       ANDROID USB REVERSE TETHER  for Windows          %N%
echo(  %BAR%                                                        %N%
echo   %DIM%Share this PC's internet with your phone over USB.%N%
echo   %DIM%Powered by OpenTether - github.com/pyd-07/NetcoN-OpenTether%N%
echo.

echo  %STEP%[1/9]%N% %HI%USB passthrough%N% %DIM%(usbipd-win)%N%
if not exist "%USBIPD%" (
    echo %DO% Not found. Installing usbipd-win with winget...
    winget install --exact --id dorssel.usbipd-win --accept-source-agreements --accept-package-agreements
    if not exist "%USBIPD%" (
        echo %ERR% usbipd-win install failed.
        pause
        exit /b 1
    )
)
echo %OK% usbipd-win installed
echo.

echo  %STEP%[2/9]%N% %HI%Linux environment%N% %DIM%(WSL Ubuntu)%N%
rem Fresh installs are often named Ubuntu-24.04 etc., so use the first one that exists.
if not defined DISTRO for %%D in (Ubuntu Ubuntu-24.04 Ubuntu-22.04 Ubuntu-20.04) do if not defined DISTRO (
    wsl -d %%D -- true <nul >nul 2>&1
    if !errorlevel! equ 0 set "DISTRO=%%D"
)
if not defined DISTRO (
    echo %DO% Ubuntu not found. Installing WSL + Ubuntu...
    echo %DO% Create your Linux username and password when asked.
    wsl --install -d Ubuntu
    echo.
    echo   %ACT%ACTION:%N% If Windows asks for a restart, restart. Then run this launcher again.
    pause
    exit /b 1
)
echo %OK% Using WSL distro %HI%!DISTRO!%N%
echo.

echo  %STEP%[3/9]%N% %HI%Linux tools%N% %DIM%(adb, lsusb, wget, iptables)%N%
rem Not redirected: apt may ask for your Ubuntu sudo password here.
wsl -d %DISTRO% -- bash -lc "command -v adb && command -v lsusb && command -v wget && command -v iptables || (echo '  Installing tools - enter your Ubuntu password if asked...' >&2; sudo apt-get update && sudo apt-get install -y adb usbutils wget iptables)" >nul
if !errorlevel! neq 0 (
    echo %ERR% Could not install adb/usbutils/wget/iptables in %DISTRO%.
    pause
    exit /b 1
)
echo %OK% Linux tools installed
echo.

echo  %STEP%[4/9]%N% %HI%OpenTether relay%N%
rem Uses ~/%RELAY% if present, else a copy next to this .bat, else downloads it.
wsl -d %DISTRO% -- bash -lc "test -x ~/%RELAY% || { cp %RELAY% ~/ 2>/dev/null || wget -q --show-progress %BASE_URL%/%RELAY% -O ~/%RELAY%; } && chmod +x ~/%RELAY%" <nul
if !errorlevel! neq 0 (
    echo %ERR% Could not get the OpenTether relay.
    pause
    exit /b 1
)
echo %OK% Relay %DIM%%VER%%N% ready
echo.

echo  %STEP%[5/9]%N% %HI%Finding your phone%N%
call :FIND_PHONE
if not defined BUSID (
    echo.
    echo   %ACT%ACTION:%N% Connect the phone by USB and turn on %HI%USB debugging%N%.
    pause
    call :FIND_PHONE
)
if not defined BUSID (
    echo %WRN% No known phone maker found. USB devices:
    "%USBIPD%" list
    set /p "PICK=  Type the BUSID of your phone (e.g. 1-5): "
    call :FIND_PHONE
)
if not defined BUSID (
    echo %ERR% Phone was not found.
    pause
    exit /b 1
)
echo %OK% Found %HI%!NAME!%N% %DIM%(BUSID !BUSID!, !VIDPID!, !USBSTATE!)%N%
echo.

echo  %STEP%[6/9]%N% %HI%Connecting phone to Linux%N%
if "!USBSTATE!"=="Not shared" (
    echo %DO% Requesting Administrator permission to share it...
    powershell -NoProfile -Command "$p = Start-Process -FilePath '%USBIPD%' -ArgumentList 'bind','--busid','!BUSID!','--force' -Verb RunAs -Wait -PassThru; exit $p.ExitCode"
    if !errorlevel! neq 0 (
        echo %ERR% Could not share the USB device.
        pause
        exit /b 1
    )
)
rem A Windows adb server (Android Studio, platform-tools, phone suites) grabs the phone,
rem and attaching it to WSL then fails with "Device busy". Stop it first.
tasklist /fi "imagename eq adb.exe" 2>nul | find /i "adb.exe" >nul && (
    echo %DO% Stopping the Windows adb server so Linux can use the phone...
    taskkill /f /im adb.exe >nul 2>&1
)
rem A plain attach is lost whenever the phone resets USB (it falls back to "Shared"
rem and ADB loses it). --auto-attach stays running and re-attaches it every time.
powershell -NoProfile -Command "if (Get-CimInstance Win32_Process -Filter 'Name=''usbipd.exe''' | ? CommandLine -match 'auto-attach') {exit 0}; exit 1"
if !errorlevel! neq 0 (
    echo %DO% Starting USB Auto-Attach in a minimized window %DIM%^(keep it open^)%N%
    start "USB Auto-Attach" /min "%USBIPD%" attach --wsl --busid !BUSID! --auto-attach
) else (
    echo %OK% USB Auto-Attach already running
)
set /a tries=0
:WAITUSB
set /a tries+=1
wsl -d %DISTRO% -- bash -lc "lsusb | grep -q '!VIDPID!'" <nul >nul 2>&1
if !errorlevel! equ 0 goto USBOK
if !tries! GEQ 20 (
    echo %ERR% Phone did not appear inside WSL.
    pause
    exit /b 1
)
ping -n 2 127.0.0.1 >nul
goto WAITUSB
:USBOK
echo %OK% Phone is visible in Linux
echo.

echo  %STEP%[7/9]%N% %HI%USB debugging permission%N%
call :ADB_OK
if !errorlevel! neq 0 (
    echo.
    echo   %ACT%ACTION ON PHONE:%N% Unlock it and tap %HI%Allow%N% on the USB debugging prompt.
    echo   Then press any key here.
    pause
    call :ADB_OK
)
if !errorlevel! neq 0 (
    echo %ERR% ADB is not authorized.
    wsl -d %DISTRO% -- adb devices
    pause
    exit /b 1
)
echo %OK% ADB authorized
echo.

echo  %STEP%[8/9]%N% %HI%OpenTether app on the phone%N%
call :APP_OK
if !errorlevel! neq 0 (
    echo %DO% Not installed. Installing it...
    echo   %ACT%WATCH THE PHONE%N% and approve any install or Play Protect prompt.
    rem APK search order: next to this .bat, then ~ in Ubuntu, else download.
    rem --exec matters: without it WSL's shell expands $apk and $(...) to nothing first.
    wsl -d %DISTRO% --exec bash -lc "apk=$(ls %APK% ~/%APK% 2>/dev/null | head -n1); [ -z $apk ] && { wget -q --show-progress %BASE_URL%/%APK% -O ~/%APK% && apk=~/%APK%; }; adb install -r $apk" <nul
    call :APP_OK
)
if !errorlevel! neq 0 (
    echo.
    echo   %ACT%ACTION:%N% Install the OpenTether app on the phone manually:
    echo   %HI%%BASE_URL%/%APK%%N%
    echo   Open that link on the phone %DIM%^(or copy the APK over^)%N%, install it, then press any key.
    pause
    call :APP_OK
)
if !errorlevel! neq 0 (
    echo %ERR% The OpenTether app is still not installed.
    pause
    exit /b 1
)
echo %OK% OpenTether app installed

wsl -d %DISTRO% -- pgrep -f "%RELAY%" <nul >nul 2>&1
if !errorlevel! equ 0 (
    echo %OK% Relay already running
) else (
    echo %DO% Starting the relay in a new window. %ACT%Enter your Ubuntu password there.%N%
    start "OpenTether Relay" wsl -d %DISTRO% -- bash -lc "cd ~ && sudo ./%RELAY%; echo Relay exited.; read -p 'Press Enter to close'"
    ping -n 4 127.0.0.1 >nul
)
echo.

echo  %STEP%[9/9]%N% %HI%Start the VPN on your phone%N%
echo.
echo   %ACT%+----------------------------------------------------------+%N%
echo   %ACT%^|%N%  %HI%ON YOUR PHONE%N%                                           %ACT%^|%N%
echo   %ACT%^|%N%    1. Open the %HI%OpenTether%N% app                            %ACT%^|%N%
echo   %ACT%^|%N%    2. Tap %HI%START VPN%N% and approve the VPN prompt           %ACT%^|%N%
echo   %ACT%^|%N%                                                          %ACT%^|%N%
echo   %ACT%^|%N%  %DIM%Tip: keep Mobile data ON and set OpenTether's battery%N%   %ACT%^|%N%
echo   %ACT%^|%N%  %DIM%usage to Unrestricted, or the phone may freeze it.%N%      %ACT%^|%N%
echo   %ACT%+----------------------------------------------------------+%N%
echo.
echo   Press any key here %HI%after%N% the VPN is running...
pause >nul

echo.
echo %DO% Waiting for the phone to connect to the relay...
rem ot0 exists as soon as the relay runs, so check for the phone's actual session instead.
rem (Waits use ping, not timeout: timeout aborts when input is redirected.)
set /a tries=0
:WAITVPN
set /a tries+=1
call :STATUS
if "!CONNECTED!"=="1" goto VPNOK
if !tries! LSS 15 (
    ping -n 2 127.0.0.1 >nul
    goto WAITVPN
)
echo %WRN% The phone has not connected yet. In OpenTether tap %HI%STOP%N%, then %HI%START VPN%N%.
echo   %DIM%The control panel below shows when it connects. Still stuck? Run Diagnose-ReverseTether.bat%N%
goto PANEL

:VPNOK
echo.
echo(  %WIN%                                                        %N%
echo(  %WIN%           REVERSE TETHERING ACTIVE                     %N%
echo(  %WIN%                                                        %N%
echo.
echo   Your phone is now using this PC's internet.
echo   Keep these windows open: %HI%OpenTether Relay%N% and %HI%USB Auto-Attach%N%.
echo   %DIM%Problems? Run Diagnose-ReverseTether.bat or see docs\TROUBLESHOOTING.md%N%

rem Control panel: stays open so torrent mode can be switched on/off.
:PANEL
set "EMPTY=0"
:MENU
call :STATUS
echo.
echo   %STEP%CONTROL PANEL%N%
echo     Phone tunnel : !PH!
echo     Torrent mode : !TS!
echo   %DIM%  Torrent mode routes only the phone's traffic through free Cloudflare WARP,%N%
echo   %DIM%  for networks that block BitTorrent. Windows is untouched.%N%
echo.
echo     %HI%S%N%  Send files to phone          %HI%G%N%  Get files from phone
echo     %HI%T%N%  Turn torrent mode !TNEXT!      %HI%R%N%  Refresh status      %HI%Q%N%  Close this window
set "CH="
set /p "CH=  Choose [S/G/T/R/Q]: "
rem Enter alone just refreshes; many empty answers in a row means input has closed, so stop.
if defined CH (set "EMPTY=0") else set /a EMPTY+=1
if !EMPTY! GEQ 20 exit /b 0
if /I "!CH!"=="Q" exit /b 0
if /I "!CH!"=="S" call :SEND
if /I "!CH!"=="G" call :GET
if /I "!CH!"=="T" (
    if "!TNEXT!"=="OFF" (call :TORRENT_OFF) else (call :TORRENT_ON)
)
goto MENU

rem ---------------------------------------------------------------
rem File transfer runs straight over the USB link with adb (about 30-40 MB/s),
rem much faster than going through the network tunnel. --exec passes paths with
rem spaces to Linux untouched.
:SEND
echo %DO% Choose the files to send in the window that opens...
set "SENT=0"
for /f "usebackq delims=" %%F in (`powershell -NoProfile -STA -Command "Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Multiselect = $true; $d.Title = 'Send to phone'; if ($d.ShowDialog() -eq 'OK') { $d.FileNames }"`) do (
    for /f "usebackq delims=" %%W in (`wsl -d %DISTRO% --exec wslpath -u "%%~F" ^<nul`) do (
        echo %DO% Sending "%%~nxF"
        wsl -d %DISTRO% --exec adb push "%%W" /sdcard/Download/ <nul
        if !errorlevel! equ 0 (set /a SENT+=1) else echo %ERR% Could not send "%%~nxF"
    )
)
if !SENT! equ 0 (echo %WRN% Nothing sent.) else (echo %OK% Sent !SENT! file^(s^) to the phone's %HI%Download%N% folder)
exit /b 0

:GET
rem Counter is FN, not n: batch names ignore case, so n would overwrite N (the colour reset).
set "DEST=%USERPROFILE%\Downloads\From Phone"
echo   Newest files in the phone's Download folder:
set "FN=0"
for /f "usebackq delims=" %%L in (`wsl -d %DISTRO% --exec bash -lc "adb shell ls -t /sdcard/Download | head -n 15" ^<nul`) do (
    set /a FN+=1
    set "F!FN!=%%L"
    echo     %HI%!FN!%N%. %%L
)
if !FN! equ 0 (
    echo %WRN% The phone's Download folder is empty or not readable.
    exit /b 0
)
set "PICKF="
set /p "PICKF=  Number to copy to the PC (A = all of them, Enter = cancel): "
if not defined PICKF exit /b 0
if not exist "%DEST%" mkdir "%DEST%"
for /f "usebackq delims=" %%W in (`wsl -d %DISTRO% --exec wslpath -u "%DEST%" ^<nul`) do set "DESTW=%%W"
if /I "!PICKF!"=="A" (
    for /l %%i in (1,1,!FN!) do wsl -d %DISTRO% --exec adb pull "/sdcard/Download/!F%%i!" "!DESTW!/" <nul
) else (
    if not defined F!PICKF! (
        echo %WRN% No file number !PICKF!.
        exit /b 0
    )
    call set "NAMEIN=%%F!PICKF!%%"
    wsl -d %DISTRO% --exec adb pull "/sdcard/Download/!NAMEIN!" "!DESTW!/" <nul
)
echo %OK% Saved to %HI%%DEST%%N%
start "" explorer "%DEST%"
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
    echo %WRN% Could not create the WARP profile. Torrent mode skipped.
    exit /b 0
)
echo %DO% Turning on torrent mode. %ACT%Enter your Ubuntu password if asked.%N%
wsl -d %DISTRO% -- sudo bash torrent-vpn.sh up
if !errorlevel! neq 0 (
    echo %WRN% Torrent mode failed. Normal internet still works.
) else (
    echo %OK% Torrent mode is on
)
exit /b 0

:TORRENT_OFF
echo %DO% Turning off torrent mode. %ACT%Enter your Ubuntu password if asked.%N%
wsl -d %DISTRO% -- sudo bash torrent-vpn.sh down
exit /b 0

:STATUS
rem Sets CONNECTED/PH (phone session on the relay), TS (torrent mode) and TNEXT (what T switches it to).
wsl -d %DISTRO% -- bash -lc "ss -tn | grep -q ':8765'" <nul >nul 2>&1
if !errorlevel! equ 0 (set "CONNECTED=1" & set "PH=%GOOD%connected%N%") else (set "CONNECTED=0" & set "PH=%WARN%not connected - tap START VPN in OpenTether%N%")
wsl -d %DISTRO% -- ip link show wg-ot <nul >nul 2>&1
if !errorlevel! equ 0 (set "TS=%GOOD%ON%N%" & set "TNEXT=OFF") else (set "TS=%DIM%OFF%N%" & set "TNEXT=ON")
exit /b 0

:APP_OK
rem Check pm's output, not adb's exit code: older adb versions don't pass the phone's exit code back.
wsl -d %DISTRO% -- bash -lc "adb shell pm path %APP_PKG% | grep -q package:" <nul >nul 2>&1
exit /b

:ADB_OK
rem findstr's $ only matches before CR; Linux output is LF-only, so grep in WSL.
wsl -d %DISTRO% -- bash -lc "adb devices | grep -q 'device$'" <nul >nul 2>&1
exit /b
