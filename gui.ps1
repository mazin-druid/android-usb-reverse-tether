# Android USB Reverse Tether - main window.
# Same steps as Start-ReverseTether.bat, shown as live status rows with buttons.
# Built on OpenTether (https://github.com/pyd-07/NetcoN-OpenTether), usbipd-win and WSL2.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- settings ----------
$Here     = $PSScriptRoot
$USBIPD   = 'C:\Program Files\usbipd-win\usbipd.exe'
$Ver      = 'v0.9.5-beta.1'
$Relay    = "OpenTether-$Ver-linux-amd64"
$Apk      = "OpenTether-$Ver-android.apk"
$BaseUrl  = "https://github.com/pyd-07/NetcoN-OpenTether/releases/download/$Ver"
$AppPkg   = 'com.opentether'
$WgcfUrl  = 'https://github.com/ViRb3/wgcf/releases/download/v2.3.0/wgcf_2.3.0_linux_amd64'
$RepoUrl  = 'https://github.com/mazin-druid/android-usb-reverse-tether'
# USB vendor IDs of common Android phone makers (same list as the .bat).
$Vendors  = '18d1 04e8 22d9 2a70 2717 12d1 22b8 1004 0fce 0bb4 2d95 19d2 05c6 0e8d 2b4c 0b05 2e04' -split ' '
$script:Distro = $null; $script:Pw = $null; $script:Phone = $null; $script:Busy = $false

# ---------- running commands in WSL ----------
# Each command runs as its own wsl.exe process (stdin given or closed, so it can't block on a
# console). --exec hands arguments to Linux untouched; we quote them ourselves because
# Windows PowerShell 5.1 mangles embedded quotes.
function Start-WslProcess([string[]]$Cmd, [string]$Stdin) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo 'wsl.exe'
    $psi.Arguments = "-d $script:Distro --exec " + (($Cmd | ForEach-Object { '"' + ("$_" -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }) -join ' ')
    $psi.WorkingDirectory = $Here   # so files bundled next to this script are visible in Linux
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    if ($Stdin) { $p.StandardInput.WriteLine($Stdin) }
    $p.StandardInput.Close()
    $p
}
# Runs a command and keeps the window responsive while it works. Returns output lines; sets $script:Code.
function Invoke-Wsl([string[]]$Cmd, [string]$Stdin) {
    $p = Start-WslProcess $Cmd $Stdin
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    while (-not $p.HasExited) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 80 }
    $p.WaitForExit(); $script:Code = $p.ExitCode
    ($out.Result + $err.Result) -split "`r?`n" | Where-Object { $_ -ne '' }
}
function Test-Wsl([string[]]$Cmd) { [void](Invoke-Wsl $Cmd); $script:Code -eq 0 }
function Bash([string]$Script) { Invoke-Wsl @('bash', '-lc', $Script) }
# Runs a bash command as root, feeding the Ubuntu password to sudo on stdin.
function Sudo([string]$Script) { Invoke-Wsl @('bash', '-lc', "sudo -S -p '' bash -c $(Quote-Sh $Script)") $script:Pw }
function Quote-Sh([string]$s) { "'" + $s.Replace("'", "'\''") + "'" }
function To-WslPath([string]$p) { (Invoke-Wsl @('wslpath', '-u', $p) | Select-Object -First 1) }

# ---------- window ----------
$C = @{ ok = [System.Drawing.Color]::FromArgb(22, 163, 74); warn = [System.Drawing.Color]::FromArgb(217, 119, 6)
        bad = [System.Drawing.Color]::FromArgb(220, 38, 38); busy = [System.Drawing.Color]::FromArgb(37, 99, 235)
        idle = [System.Drawing.Color]::FromArgb(156, 163, 175) }
$Dot = [string][char]0x25CF
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Android USB Reverse Tether'
$form.ClientSize = New-Object System.Drawing.Size(640, 640)
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.BackColor = [System.Drawing.Color]::White

$header = New-Object System.Windows.Forms.Panel
$header.Location = '0,0'; $header.Size = '640,72'; $header.BackColor = [System.Drawing.Color]::FromArgb(30, 64, 175)
$form.Controls.Add($header)
$h1 = New-Object System.Windows.Forms.Label
$h1.Text = 'Android USB Reverse Tether'; $h1.ForeColor = 'White'; $h1.AutoSize = $true; $h1.Location = '18,10'
$h1.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$h2 = New-Object System.Windows.Forms.Label
$h2.Text = "Share this PC's internet with your phone over USB  -  powered by OpenTether"
$h2.ForeColor = [System.Drawing.Color]::FromArgb(219, 234, 254); $h2.AutoSize = $true; $h2.Location = '20,44'
$header.Controls.AddRange(@($h1, $h2))

# Status rows: a coloured dot, a name, and a detail line.
$Rows = [ordered]@{}
$y = 86
foreach ($r in @(
        @('usbipd', 'USB passthrough'), @('wsl', 'Ubuntu (WSL)'), @('tools', 'Linux tools'),
        @('relaybin', 'OpenTether relay'), @('phone', 'Phone'), @('usb', 'Phone in Linux'),
        @('adb', 'USB debugging'), @('app', 'OpenTether app'), @('relay', 'Relay running'),
        @('tunnel', 'Phone tunnel'), @('torrent', 'Torrent mode'))) {
    $dot = New-Object System.Windows.Forms.Label
    $dot.Text = $Dot; $dot.ForeColor = $C.idle; $dot.Location = "20,$y"; $dot.Size = '20,24'
    $dot.Font = New-Object System.Drawing.Font('Segoe UI', 12)
    $name = New-Object System.Windows.Forms.Label
    $name.Text = $r[1]; $name.Location = "44,$($y + 2)"; $name.Size = '150,22'
    $name.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
    $detail = New-Object System.Windows.Forms.Label
    $detail.Text = '-'; $detail.Location = "198,$($y + 2)"; $detail.Size = '420,22'; $detail.ForeColor = [System.Drawing.Color]::FromArgb(75, 85, 99)
    $form.Controls.AddRange(@($dot, $name, $detail))
    $Rows[$r[0]] = @{ Dot = $dot; Detail = $detail; State = 'idle' }
    $y += 28
}
function Set-Row([string]$key, [string]$state, [string]$text) {
    $Rows[$key].State = $state; $Rows[$key].Dot.ForeColor = $C[$state]; $Rows[$key].Detail.Text = $text
    [System.Windows.Forms.Application]::DoEvents()
}

function New-Btn([string]$text, [int]$x, [int]$yy, [int]$w, [bool]$primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = "$x,$yy"; $b.Size = "$w,36"; $b.FlatStyle = 'Flat'
    if ($primary) { $b.BackColor = [System.Drawing.Color]::FromArgb(30, 64, 175); $b.ForeColor = 'White'; $b.FlatAppearance.BorderSize = 0
        $b.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10) }
    $form.Controls.Add($b); $b
}
$y += 8
$btnConnect = New-Btn 'Connect' 20 $y 140 $true
$btnDisconnect = New-Btn 'Disconnect' 168 $y 120 $false
$btnTorrent = New-Btn 'Torrent mode: OFF' 448 $y 172 $false
$y += 44
$btnSend = New-Btn 'Send files to phone' 20 $y 170 $false
$btnGet = New-Btn 'Get files from phone' 198 $y 170 $false
$btnDiag = New-Btn 'Diagnostics' 376 $y 120 $false
$btnHelp = New-Btn 'Help' 504 $y 116 $false
$y += 46
$hint = New-Object System.Windows.Forms.Label
$hint.Location = "20,$y"; $hint.Size = '600,22'; $hint.ForeColor = $C.busy
$hint.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$form.Controls.Add($hint)
$y += 26
$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'; $log.Location = "20,$y"; $log.Size = "600,$(630 - $y)"
$log.Font = New-Object System.Drawing.Font('Consolas', 9); $log.BackColor = [System.Drawing.Color]::FromArgb(249, 250, 251)
$form.Controls.Add($log)

function Log([string]$msg) { $log.AppendText("$(Get-Date -Format 'HH:mm:ss')  $msg`r`n"); [System.Windows.Forms.Application]::DoEvents() }
function Hint([string]$msg) { $hint.Text = $msg; [System.Windows.Forms.Application]::DoEvents() }
function Set-Busy([bool]$b) {
    $script:Busy = $b; $form.UseWaitCursor = $b
    foreach ($x in $btnConnect, $btnDisconnect, $btnTorrent, $btnSend, $btnGet, $btnDiag) { $x.Enabled = -not $b }
}

# ---------- Ubuntu password (kept in memory for this session only, never saved) ----------
function Get-Password {
    if ($null -ne $script:Pw) { return $true }
    if (Test-Wsl @('sudo', '-n', 'true')) { $script:Pw = ''; return $true }   # passwordless sudo
    $user = (Invoke-Wsl @('whoami') | Select-Object -First 1)
    while ($true) {
        $d = New-Object System.Windows.Forms.Form
        $d.Text = 'Ubuntu password'; $d.ClientSize = '380,150'; $d.FormBorderStyle = 'FixedDialog'
        $d.StartPosition = 'CenterParent'; $d.MaximizeBox = $false; $d.MinimizeBox = $false; $d.Font = $form.Font
        $l = New-Object System.Windows.Forms.Label
        $l.Text = "Enter the Linux (Ubuntu) password for '$user'.`nIt is used for this session only and never saved."
        $l.Location = '14,12'; $l.Size = '360,42'
        $t = New-Object System.Windows.Forms.TextBox; $t.UseSystemPasswordChar = $true; $t.Location = '16,60'; $t.Width = 346
        $ok = New-Object System.Windows.Forms.Button; $ok.Text = 'OK'; $ok.Location = '196,102'; $ok.Size = '80,30'; $ok.DialogResult = 'OK'
        $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = 'Cancel'; $cancel.Location = '282,102'; $cancel.Size = '80,30'; $cancel.DialogResult = 'Cancel'
        $d.Controls.AddRange(@($l, $t, $ok, $cancel)); $d.AcceptButton = $ok; $d.CancelButton = $cancel
        if ($d.ShowDialog($form) -ne 'OK') { return $false }
        [void](Invoke-Wsl @('bash', '-lc', "sudo -S -p '' -v") $t.Text)
        if ($script:Code -eq 0) { $script:Pw = $t.Text; return $true }
        [void][System.Windows.Forms.MessageBox]::Show($form, 'That password was not accepted. Please try again.', 'Ubuntu password', 'OK', 'Warning')
    }
}

# ---------- connect steps ----------
function Find-Distro {
    foreach ($d in 'Ubuntu', 'Ubuntu-24.04', 'Ubuntu-22.04', 'Ubuntu-20.04') {
        & wsl.exe -d $d --exec true 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $d }
    }
    $null
}
# Parses "usbipd list" by regex: BUSID, VID:PID, name (has spaces), state.
function Get-UsbDevices {
    & $USBIPD list 2>$null | ForEach-Object {
        if ($_ -match '^(\d+-\d+)\s+([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\s+(.+?)\s+(Not shared|Shared|Attached)\s*$') {
            [pscustomobject]@{ BusId = $matches[1]; Vid = $matches[2].ToLower(); VidPid = "$($matches[2]):$($matches[3])".ToLower(); Name = $matches[4]; State = $matches[5] }
        }
    }
}
function Pick-Device($devices) {
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Which device is your phone?'; $d.ClientSize = '460,260'; $d.StartPosition = 'CenterParent'; $d.Font = $form.Font
    $d.FormBorderStyle = 'FixedDialog'; $d.MaximizeBox = $false; $d.MinimizeBox = $false
    $lb = New-Object System.Windows.Forms.ListBox; $lb.Location = '12,12'; $lb.Size = '436,190'
    $devices | ForEach-Object { [void]$lb.Items.Add("$($_.BusId)   $($_.VidPid)   $($_.Name)") }
    $ok = New-Object System.Windows.Forms.Button; $ok.Text = 'Use this'; $ok.Location = '262,214'; $ok.Size = '90,32'; $ok.DialogResult = 'OK'
    $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = 'Cancel'; $cancel.Location = '358,214'; $cancel.Size = '90,32'; $cancel.DialogResult = 'Cancel'
    $d.Controls.AddRange(@($lb, $ok, $cancel)); $d.AcceptButton = $ok
    if ($d.ShowDialog($form) -eq 'OK' -and $lb.SelectedIndex -ge 0) { return @($devices)[$lb.SelectedIndex] }
    $null
}
function Wait-Until([scriptblock]$test, [int]$seconds) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $seconds) {
        if (& $test) { return $true }
        for ($i = 0; $i -lt 10; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    }
    $false
}
function Test-RelayRunning { Test-Wsl @('pgrep', '-f', $Relay) }

function Connect {
    Set-Busy $true; Hint ''
    try {
        # 1. usbipd-win
        if (-not (Test-Path $USBIPD)) {
            Set-Row usbipd busy 'installing with winget...'; Log 'Installing usbipd-win (approve the Windows prompt)...'
            Start-Process winget -ArgumentList 'install --exact --id dorssel.usbipd-win --accept-source-agreements --accept-package-agreements' -Wait
            if (-not (Test-Path $USBIPD)) { Set-Row usbipd bad 'install failed - see Help'; return }
        }
        Set-Row usbipd ok 'installed'

        # 2. Ubuntu
        Set-Row wsl busy 'checking...'
        $script:Distro = Find-Distro
        if (-not $script:Distro) {
            Set-Row wsl bad 'not installed'
            $a = [System.Windows.Forms.MessageBox]::Show($form, "Ubuntu (WSL) is needed. Install it now?`n`nA console window opens: create a Linux username and password there. Restart Windows if asked, then open this app again.", 'Install Ubuntu', 'YesNo', 'Question')
            if ($a -eq 'Yes') { Start-Process wsl.exe -ArgumentList '--install -d Ubuntu' }
            return
        }
        Set-Row wsl ok $script:Distro

        # 3. Linux tools
        Set-Row tools busy 'checking...'
        if (-not (Test-Wsl @('bash', '-lc', 'command -v adb && command -v lsusb && command -v wget && command -v iptables'))) {
            if (-not (Get-Password)) { Set-Row tools bad 'need your Ubuntu password to install'; return }
            Set-Row tools busy 'installing adb, usbutils, wget, iptables...'; Log 'Installing Linux tools (about a minute)...'
            [void](Sudo 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq adb usbutils wget iptables')
            if ($script:Code -ne 0) { Set-Row tools bad 'install failed - run Diagnostics'; return }
        }
        Set-Row tools ok 'adb, lsusb, wget, iptables'

        # 4. relay binary (home folder, else next to this app, else download)
        Set-Row relaybin busy 'checking...'
        [void](Bash "test -x ~/$Relay || { cp $Relay ~/ 2>/dev/null || wget -q $BaseUrl/$Relay -O ~/$Relay; } && chmod +x ~/$Relay")
        if ($script:Code -ne 0) { Set-Row relaybin bad 'download failed - check internet'; return }
        Set-Row relaybin ok $Ver

        # 5. phone
        Set-Row phone busy 'looking...'
        $devs = @(Get-UsbDevices)
        $script:Phone = $devs | Where-Object { $Vendors -contains $_.Vid } | Select-Object -First 1
        if (-not $script:Phone -and $devs) { $script:Phone = Pick-Device $devs }
        if (-not $script:Phone) { Set-Row phone bad 'not found'; Hint 'Plug in the phone with a data cable and turn on USB debugging, then click Connect.'; return }
        Set-Row phone ok "$($script:Phone.Name)  ($($script:Phone.BusId), $($script:Phone.VidPid))"

        # 6. hand the phone to Linux
        Set-Row usb busy 'connecting...'
        # A Windows adb server holds the phone and makes attaching fail with "Device busy".
        if (Get-Process adb -ErrorAction SilentlyContinue) { Log 'Stopping the Windows adb server so Linux can use the phone.'; Stop-Process -Name adb -Force -ErrorAction SilentlyContinue }
        if ($script:Phone.State -eq 'Not shared') {
            Log 'Sharing the phone with Linux (approve the Administrator prompt)...'
            try { $b = Start-Process $USBIPD -ArgumentList "bind --busid $($script:Phone.BusId) --force" -Verb RunAs -Wait -PassThru } catch { $b = $null }
            if (-not $b -or $b.ExitCode -ne 0) { Set-Row usb bad 'sharing was cancelled or failed'; return }
        }
        # --auto-attach re-attaches the phone every time its USB connection resets.
        $aa = Get-CimInstance Win32_Process -Filter "Name='usbipd.exe'" | Where-Object { $_.CommandLine -match 'auto-attach' }
        if (-not $aa) { Start-Process $USBIPD -ArgumentList "attach --wsl --busid $($script:Phone.BusId) --auto-attach" -WindowStyle Hidden }
        $vp = $script:Phone.VidPid
        if (-not (Wait-Until { Test-Wsl @('bash', '-lc', "lsusb | grep -qi $vp") } 25)) { Set-Row usb bad 'did not appear in Linux - see Help'; return }
        Set-Row usb ok 'attached (auto re-attach on)'

        # 7. USB debugging authorisation
        Set-Row adb busy 'checking...'
        $adbOk = { Test-Wsl @('bash', '-lc', "adb devices | grep -q 'device$'") }
        if (-not (& $adbOk)) {
            Set-Row adb warn 'unlock the phone and tap Allow on the USB debugging prompt'
            Hint 'On the phone: unlock it and tap ALLOW on "Allow USB debugging?"'
            if (-not (Wait-Until $adbOk 90)) { Set-Row adb bad 'not authorized - see Help'; return }
            Hint ''
        }
        Set-Row adb ok 'authorized'

        # 8. OpenTether app
        Set-Row app busy 'checking...'
        $appOk = { Test-Wsl @('bash', '-lc', "adb shell pm path $AppPkg | grep -q package:") }
        if (-not (& $appOk)) {
            Set-Row app busy 'installing - watch the phone for an install prompt'
            Log 'Installing the OpenTether app on the phone...'
            [void](Bash "apk=`$(ls $Apk ~/$Apk 2>/dev/null | head -n1); [ -z `"`$apk`" ] && { wget -q $BaseUrl/$Apk -O ~/$Apk && apk=~/$Apk; }; adb install -r `"`$apk`"")
            if (-not (& $appOk)) {
                Set-Row app bad 'install failed'
                [System.Windows.Forms.Clipboard]::SetText("$BaseUrl/$Apk")
                [void][System.Windows.Forms.MessageBox]::Show($form, "Install the OpenTether app on the phone manually from:`n$BaseUrl/$Apk`n`n(The link is copied to the clipboard.) Then click Connect again.", 'OpenTether app', 'OK', 'Information')
                return
            }
        }
        Set-Row app ok 'installed'

        # 9. relay: runs hidden in the background, logging to ~/opentether-relay.log
        Set-Row relay busy 'checking...'
        if (-not (Test-RelayRunning)) {
            if (-not (Get-Password)) { Set-Row relay bad 'needs your Ubuntu password'; return }
            Set-Row relay busy 'starting...'; Log 'Starting the OpenTether relay in the background.'
            $script:RelayProc = Start-WslProcess @('bash', '-lc', "cd ~ && exec sudo -S -p '' ./$Relay > ~/opentether-relay.log 2>&1") $script:Pw
            if (-not (Wait-Until { Test-Wsl @('bash', '-lc', 'ip link show ot0') } 15)) {
                Set-Row relay bad 'failed to start - Diagnostics shows its log'; Log ((Bash 'tail -n 5 ~/opentether-relay.log') -join "`r`n"); return
            }
        }
        Set-Row relay ok 'running in the background'
        Log 'Ready. Open OpenTether on the phone and tap START VPN.'
        Update-Live
    } finally { Set-Busy $false }
}

# ---------- live status (every few seconds once connected) ----------
function Update-Live {
    if (-not $script:Distro) { return }
    # One quick call for everything: T = phone session on the relay, W = torrent mode, R = relay running.
    $p = Start-WslProcess @('bash', '-lc', "ss -tn | grep -q ':8765' && echo T; ip link show wg-ot >/dev/null 2>&1 && echo W; pgrep -f $Relay >/dev/null && echo R")
    $o = $p.StandardOutput.ReadToEnd(); $p.WaitForExit(4000) | Out-Null
    $script:TorrentOn = $o -match 'W'
    if ($o -match 'R') {
        if ($o -match 'T') { Set-Row tunnel ok 'connected - the phone is using this PC''s internet'; if ($hint.Text -like '*START VPN*') { Hint '' } }
        else { Set-Row tunnel warn 'not connected'; Hint 'On the phone: open OpenTether and tap START VPN.' }
    } elseif ($Rows.relay.Detail.Text -ne '-') { Set-Row relay bad 'stopped'; Set-Row tunnel idle '-' }
    if ($script:TorrentOn) { Set-Row torrent ok 'ON - phone traffic goes through Cloudflare WARP'; $btnTorrent.Text = 'Torrent mode: ON' }
    else { Set-Row torrent idle 'off'; $btnTorrent.Text = 'Torrent mode: OFF' }
}
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ if (-not $script:Busy -and $Rows.relay.State -eq 'ok') { Update-Live } })
$timer.Start()

# ---------- buttons ----------
$btnConnect.Add_Click({ Connect })

$btnDisconnect.Add_Click({
    if (-not $script:Distro) { $script:Distro = Find-Distro; if (-not $script:Distro) { return } }
    if (-not (Get-Password)) { return }
    Set-Busy $true
    try {
        if ($script:TorrentOn) { Log 'Turning off torrent mode...'; [void](Sudo "bash $(Quote-Sh (To-WslPath (Join-Path $Here 'torrent-vpn.sh'))) down") }
        Log 'Stopping the relay...'; [void](Sudo "pkill -INT -f $Relay; sleep 1; pkill -f $Relay; true")
        Get-CimInstance Win32_Process -Filter "Name='usbipd.exe'" | Where-Object { $_.CommandLine -match 'auto-attach' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
        if ($script:Phone) { & $USBIPD detach --busid $script:Phone.BusId 2>$null | Out-Null; Log 'Phone released back to Windows.' }
        foreach ($k in 'usb', 'adb', 'relay', 'tunnel', 'torrent') { Set-Row $k idle '-' }
        Hint 'Disconnected. Click Connect to start again.'
    } finally { Set-Busy $false }
})

$btnTorrent.Add_Click({
    if (-not $script:Distro -or $Rows.relay.State -ne 'ok') { Hint 'Click Connect first.'; return }
    if (-not (Get-Password)) { return }
    Set-Busy $true
    try {
        $script_ = To-WslPath (Join-Path $Here 'torrent-vpn.sh')
        if ($script:TorrentOn) { Log 'Turning off torrent mode...'; [void](Sudo "bash $(Quote-Sh $script_) down") }
        else {
            Log 'Turning on torrent mode (free Cloudflare WARP profile is created the first time)...'
            [void](Bash "mkdir -p ~/warp && cd ~/warp && { test -x wgcf || { wget -q $WgcfUrl -O wgcf && chmod +x wgcf; }; } && { test -f wgcf-account.toml || ./wgcf register --accept-tos >/dev/null; } && { test -f wgcf-profile.conf || ./wgcf generate >/dev/null; }")
            if ($script:Code -ne 0) { Log 'Could not create the WARP profile.'; return }
            $o = Sudo "bash $(Quote-Sh $script_) up"
            if ($script:Code -ne 0) { Log "Torrent mode failed: $($o -join ' ')" }
        }
    } finally { Set-Busy $false; Update-Live }
})

function Open-Transfer([string]$mode) {
    if (-not $script:Distro -or $Rows.adb.State -ne 'ok') { Hint 'Click Connect first.'; return }
    Start-Process powershell.exe -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Here\transfer.ps1`" -Mode $mode -Distro $script:Distro"
}
$btnSend.Add_Click({ Open-Transfer 'Send' })
$btnGet.Add_Click({ Open-Transfer 'Get' })

$btnDiag.Add_Click({
    Set-Busy $true; Log 'Running diagnostics...'
    try {
        $p = Start-Process cmd.exe -ArgumentList "/c `"`"$Here\Diagnose-ReverseTether.bat`" < nul > nul`"" -WindowStyle Hidden -PassThru
        while (-not $p.HasExited) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
        $text = Get-Content (Join-Path $Here 'diagnostics.txt') -Raw -ErrorAction SilentlyContinue
        if ($script:Distro) { $text += "`r`n== Relay log (last lines) ==`r`n" + ((Bash 'tail -n 15 ~/opentether-relay.log 2>/dev/null') -join "`r`n") }
    } finally { Set-Busy $false }
    $d = New-Object System.Windows.Forms.Form
    $d.Text = 'Diagnostics'; $d.ClientSize = '760,560'; $d.StartPosition = 'CenterParent'; $d.Font = $form.Font
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Both'; $tb.WordWrap = $false
    $tb.Font = New-Object System.Drawing.Font('Consolas', 9); $tb.Location = '10,10'; $tb.Size = '740,500'; $tb.Anchor = 'Top,Bottom,Left,Right'
    $tb.Text = ($text -replace "$([char]27)\[[0-9;]*m", '') -replace "(?<!`r)`n", "`r`n"
    $copy = New-Object System.Windows.Forms.Button; $copy.Text = 'Copy report'; $copy.Location = '10,518'; $copy.Size = '120,32'; $copy.Anchor = 'Bottom,Left'
    $copy.Add_Click({ [System.Windows.Forms.Clipboard]::SetText($tb.Text); $copy.Text = 'Copied' })
    $issue = New-Object System.Windows.Forms.Button; $issue.Text = 'Report a problem'; $issue.Location = '138,518'; $issue.Size = '150,32'; $issue.Anchor = 'Bottom,Left'
    $issue.Add_Click({ Start-Process "$RepoUrl/issues/new" })
    $d.Controls.AddRange(@($tb, $copy, $issue)); [void]$d.ShowDialog($form)
})

$btnHelp.Add_Click({
    $local = Join-Path $Here 'docs\TROUBLESHOOTING.md'
    if (Test-Path $local) { Start-Process notepad.exe $local } else { Start-Process "$RepoUrl/blob/main/docs/TROUBLESHOOTING.md" }
})

$form.Add_FormClosing({
    if (-not $env:OT_GUI_SELFTEST -and $Rows.relay.State -eq 'ok') {
        $a = [System.Windows.Forms.MessageBox]::Show($form, "Keep the phone's internet running after closing this window?`n`nYes = keep tethering in the background`nNo = disconnect now", 'Closing', 'YesNoCancel', 'Question')
        if ($a -eq 'Cancel') { $_.Cancel = $true; return }
        if ($a -eq 'No') { $btnDisconnect.PerformClick() }
    }
    $timer.Stop()
})

# On open: show what's already running (e.g. tethering left on last time) without changing anything.
$form.Add_Shown({
    Log 'Welcome. Plug in your phone (USB debugging on) and click Connect.'
    $script:Distro = Find-Distro
    if ($script:Distro -and (Test-RelayRunning)) { Log 'Tethering is already running - click Connect to check everything.'; Set-Row relay ok 'running in the background'; Update-Live }
    # Self-test for development: OT_GUI_SELFTEST=<file> runs Connect, writes every row to <file>, closes.
    if ($env:OT_GUI_SELFTEST) {
        Connect; Update-Live
        ($Rows.Keys | ForEach-Object { '{0,-9} {1,-5} {2}' -f $_, $Rows[$_].State, $Rows[$_].Detail.Text }) + '--- log' + $log.Lines | Set-Content $env:OT_GUI_SELFTEST
        $form.Close()
    }
})
[void]$form.ShowDialog()
