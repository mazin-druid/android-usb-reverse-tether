# File transfer window for the control panel (S = send to phone, G = get from phone).
# Files go straight over USB with adb inside WSL (about 30-40 MB/s).
# Move = copy, then delete the original only if that item's transfer succeeded.
param(
    [ValidateSet('Send', 'Get')][string]$Mode = 'Send',
    [string]$Distro = 'Ubuntu'
)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$PhoneFolders = [ordered]@{
    'Download'           = '/sdcard/Download'
    'Camera (DCIM)'      = '/sdcard/DCIM/Camera'
    'Pictures'           = '/sdcard/Pictures'
    'Movies'             = '/sdcard/Movies'
    'Music'              = '/sdcard/Music'
    'Documents'          = '/sdcard/Documents'
}

# Runs a command in WSL (--exec hands arguments to Linux untouched) as a separate process with
# stdin closed, so wsl can't sit waiting on the launcher's console, and keeps the window
# responsive while it runs. Sets $script:WslCode to the exit code; returns output lines.
$script:WslCode = 0
$script:OnTick = $null   # called while a transfer runs, to update the progress bar
function Start-WslProcess($argv) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo 'wsl.exe'
    # Quote each argument ourselves: Windows PowerShell 5.1 mangles embedded quotes otherwise.
    # wsl's own options must stay unquoted; only the Linux command's arguments are quoted.
    $psi.Arguments = "-d $Distro --exec " + (($argv | ForEach-Object { '"' + ("$_" -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $p
}
function Invoke-Wsl {
    $p = Start-WslProcess $args
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    while (-not $p.HasExited) {
        if ($script:OnTick) { & $script:OnTick }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    $p.WaitForExit()
    $script:WslCode = $p.ExitCode
    ($out.Result + $err.Result) -split "`r?`n" | Where-Object { $_ -ne '' }
}
# Short blocking call for the once-a-second size check (no event pumping, so no re-entry).
function Invoke-WslQuick {
    $p = Start-WslProcess $args
    $o = $p.StandardOutput.ReadToEnd(); $p.WaitForExit(5000) | Out-Null
    $o
}

# ---------- byte-accurate progress + time left ----------
# Before a transfer: TotalBytes = sum of all selected items. While an item copies, Measure
# (a scriptblock) returns how many bytes of it have arrived at the destination.
function Start-Progress([double]$total) {   # double in: Measure-Object sums are doubles; >2 GB must not hit Int32
    $script:TotalBytes = [math]::Max([long]1, [long]$total); $script:DoneBytes = 0
    $script:XferSw = [System.Diagnostics.Stopwatch]::StartNew()
    $script:PollSw = [System.Diagnostics.Stopwatch]::StartNew()
    $script:Samples = New-Object System.Collections.Generic.List[object]
    $progress.Maximum = 1000; $progress.Value = 0
    $script:OnTick = {
        if ($script:PollSw.ElapsedMilliseconds -lt 800) { return }
        $script:PollSw.Restart()
        $cur = [long](& $script:Measure)
        Update-Progress ($script:DoneBytes + [math]::Min([long]$cur, [long]$script:CurSize))
    }
}
function Format-Eta([double]$s) {
    if ($s -lt 1) { 'almost done' } elseif ($s -lt 60) { "about $([int][math]::Ceiling($s))s left" }
    elseif ($s -lt 3600) { 'about {0}m {1:D2}s left' -f [int][math]::Floor($s / 60), ([int]$s % 60) }
    else { 'about {0}h {1:D2}m left' -f [int][math]::Floor($s / 3600), ([int][math]::Floor($s / 60) % 60) }
}
function Update-Progress([long]$done) {
    $t = $script:TotalBytes
    $progress.Value = [int][math]::Min(1000, 1000 * $done / $t)
    # Speed over the last ~6 s, so the estimate follows the real current speed.
    $now = $script:XferSw.Elapsed.TotalSeconds
    $script:Samples.Add(@($now, $done))
    while ($script:Samples.Count -gt 2 -and ($now - $script:Samples[0][0]) -gt 6) { $script:Samples.RemoveAt(0) }
    $first = $script:Samples[0]
    $rate = if (($now - $first[0]) -ge 1.5) { ($done - $first[1]) / ($now - $first[0]) } else { 0 }
    $eta = if ($rate -gt 0) { Format-Eta (($t - $done) / $rate) } else { 'estimating time left...' }
    $speed = if ($rate -gt 0) { "$(Format-Size ([long]$rate))/s  -  " } else { '' }
    $status.Text = "$script:ItemText`n$([int](100 * $done / $t))%  -  $(Format-Size $done) of $(Format-Size $t)  -  $speed$eta"
}
function Stop-Progress { $script:OnTick = $null; $progress.Value = $progress.Maximum }

# Bytes of a file or folder on the PC (0 if it doesn't exist yet).
function Get-LocalSize([string]$path) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { return (Get-Item -LiteralPath $path).Length }
    if (Test-Path -LiteralPath $path) {
        return [long](Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    }
    0
}
# Bytes of a file or folder on the phone; $quoted comes from Quote-Sh.
function Get-PhoneSize([string]$quoted) {
    $o = Invoke-WslQuick adb shell "du -sk $quoted 2>/dev/null"
    if ("$o" -match '^\s*(\d+)') { [long]$matches[1] * 1024 } else { 0 }
}
$script:FileSize = @{}
function Quote-Sh([string]$s) { "'" + $s.Replace("'", "'\''") + "'" }  # for adb shell, which re-joins args
function To-WslPath([string]$p) { (Invoke-Wsl wslpath -u $p | Select-Object -First 1).ToString().Trim() }
function Format-Size([long]$b) {
    if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } elseif ($b -ge 1MB) { '{0:N1} MB' -f ($b / 1MB) }
    elseif ($b -ge 1KB) { '{0:N0} KB' -f ($b / 1KB) } else { "$b B" }
}

# ---------- window ----------
$font = New-Object System.Drawing.Font('Segoe UI', 10)
$form = New-Object System.Windows.Forms.Form
$form.Text = if ($Mode -eq 'Send') { 'Send files to phone' } else { 'Get files from phone' }
$form.Size = New-Object System.Drawing.Size(760, 560)
$form.MinimumSize = $form.Size
$form.StartPosition = 'CenterScreen'
$form.Font = $font
$form.TopMost = $true

$title = New-Object System.Windows.Forms.Label
$title.Text = if ($Mode -eq 'Send') { 'PC  >  Phone' } else { 'Phone  >  PC' }
$title.Font = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$title.Location = '16,10'; $title.AutoSize = $true
$form.Controls.Add($title)

$top = New-Object System.Windows.Forms.FlowLayoutPanel
$top.Location = '16,48'; $top.Size = '710,36'; $top.Anchor = 'Top,Left,Right'
$form.Controls.Add($top)

$list = New-Object System.Windows.Forms.ListView
$list.View = 'Details'; $list.FullRowSelect = $true; $list.MultiSelect = $true; $list.HideSelection = $false
$list.Location = '16,90'; $list.Size = '710,300'; $list.Anchor = 'Top,Bottom,Left,Right'
[void]$list.Columns.Add('Name', 420); [void]$list.Columns.Add('Size', 110); [void]$list.Columns.Add('Modified', 150)
$form.Controls.Add($list)

$opts = New-Object System.Windows.Forms.FlowLayoutPanel
$opts.Location = '16,398'; $opts.Size = '710,36'; $opts.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($opts)

$rbCopy = New-Object System.Windows.Forms.RadioButton
$rbCopy.Text = 'Copy (keep originals)'; $rbCopy.Checked = $true; $rbCopy.AutoSize = $true
$rbMove = New-Object System.Windows.Forms.RadioButton
$rbMove.Text = 'Move (delete originals after transfer)'; $rbMove.AutoSize = $true
$opts.Controls.AddRange(@($rbCopy, $rbMove))

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = '16,440'; $progress.Size = '710,18'; $progress.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($progress)

$status = New-Object System.Windows.Forms.Label
$status.Location = '16,462'; $status.Size = '480,40'; $status.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($status)

$btnGo = New-Object System.Windows.Forms.Button
$btnGo.Text = 'Transfer'; $btnGo.Size = '110,34'; $btnGo.Location = '500,468'; $btnGo.Anchor = 'Bottom,Right'
$btnGo.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Close'; $btnClose.Size = '100,34'; $btnClose.Location = '626,468'; $btnClose.Anchor = 'Bottom,Right'
$btnClose.Add_Click({ $form.Close() })
$form.Controls.AddRange(@($btnGo, $btnClose))
$form.AcceptButton = $btnGo; $form.CancelButton = $btnClose

function New-Button($text, $width) {
    $b = New-Object System.Windows.Forms.Button; $b.Text = $text; $b.Size = "$width,30"; $top.Controls.Add($b); $b
}
function New-Label($text) {
    $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.AutoSize = $true
    $l.Margin = '6,7,2,0'; $top.Controls.Add($l); $l
}
function New-FolderCombo {
    $c = New-Object System.Windows.Forms.ComboBox; $c.DropDownStyle = 'DropDownList'; $c.Width = 160
    $PhoneFolders.Keys | ForEach-Object { [void]$c.Items.Add($_) }; $c.SelectedIndex = 0; $top.Controls.Add($c); $c
}
function Set-Busy([bool]$busy) {
    $form.UseWaitCursor = $busy; $btnGo.Enabled = -not $busy; $top.Enabled = -not $busy
    [System.Windows.Forms.Application]::DoEvents()
}

# ---------- Send: PC > phone ----------
if ($Mode -eq 'Send') {
    $btnFiles = New-Button 'Add files...' 110
    $btnDir = New-Button 'Add folder...' 115
    $btnRemove = New-Button 'Remove' 85
    [void](New-Label '  To phone folder:')
    $dest = New-FolderCombo
    $status.Text = 'Add the files or folders to send.'

    function Add-Item([string]$path) {
        if ($list.Items | Where-Object { $_.Tag -eq $path }) { return }
        $isDir = Test-Path -LiteralPath $path -PathType Container
        $info = Get-Item -LiteralPath $path
        $size = if ($isDir) { 'folder' } else { Format-Size $info.Length }
        $it = New-Object System.Windows.Forms.ListViewItem($info.Name)
        [void]$it.SubItems.Add($size); [void]$it.SubItems.Add($info.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
        $it.Tag = $path; [void]$list.Items.Add($it)
    }
    $btnFiles.Add_Click({
        $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Multiselect = $true; $d.Title = 'Files to send to the phone'
        if ($d.ShowDialog($form) -eq 'OK') { $d.FileNames | ForEach-Object { Add-Item $_ } }
    })
    $btnDir.Add_Click({
        $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = 'Folder to send to the phone'
        if ($d.ShowDialog($form) -eq 'OK') { Add-Item $d.SelectedPath }
    })
    $btnRemove.Add_Click({ @($list.SelectedItems) | ForEach-Object { $list.Items.Remove($_) } })
    # Drag files from Explorer straight into the list.
    $list.AllowDrop = $true
    $list.Add_DragEnter({ if ($_.Data.GetDataPresent('FileDrop')) { $_.Effect = 'Copy' } })
    $list.Add_DragDrop({ $_.Data.GetData('FileDrop') | ForEach-Object { Add-Item $_ } })

    $btnGo.Add_Click({
        $items = @($list.Items)
        if (-not $items) { $status.Text = 'Nothing to send. Add files or folders first.'; return }
        $target = $PhoneFolders[$dest.SelectedItem]
        Set-Busy $true
        [void](Invoke-Wsl adb shell "mkdir -p $(Quote-Sh $target)")
        $sizes = @{}; foreach ($it in $items) { $sizes[$it.Tag] = Get-LocalSize $it.Tag }
        Start-Progress ($sizes.Values | Measure-Object -Sum).Sum
        $ok = 0; $failed = @(); $n = 0
        foreach ($it in $items) {
            $n++
            $script:ItemText = "Sending $($it.Text)  ($n of $($items.Count))"
            $script:CurSize = [long]$sizes[$it.Tag]
            $onPhone = Quote-Sh "$target/$($it.Text)"
            $script:Measure = { Get-PhoneSize $onPhone }.GetNewClosure()
            Update-Progress $script:DoneBytes
            [void](Invoke-Wsl adb push (To-WslPath $it.Tag) "$target/")
            $script:DoneBytes += $script:CurSize
            if ($script:WslCode -eq 0) {
                $ok++
                if ($rbMove.Checked) { Remove-Item -LiteralPath $it.Tag -Recurse -Force -ErrorAction SilentlyContinue }
                $list.Items.Remove($it)
            } else { $failed += $it.Text }
        }
        Stop-Progress
        $verb = if ($rbMove.Checked) { 'Moved' } else { 'Copied' }
        $status.Text = "$verb $ok item(s) to the phone's $($dest.SelectedItem) folder." +
            $(if ($failed) { "  Failed: $($failed -join ', ')" } else { '' })
        Set-Busy $false
    })
}

# ---------- Get: phone > PC ----------
else {
    [void](New-Label 'Phone folder:')
    $src = New-FolderCombo
    $btnRefresh = New-Button 'Refresh' 85
    $btnAll = New-Button 'Select all' 95
    $destPath = Join-Path $env:USERPROFILE 'Downloads\From Phone'
    $btnDest = New-Button 'Save to...' 95
    $status.Text = "Save to: $destPath"

    function Load-Phone {
        Set-Busy $true; $list.Items.Clear()
        $dir = $PhoneFolders[$src.SelectedItem]
        # type|size|mtime|name per entry. No double quotes in the command: Windows PowerShell 5.1
        # mangles embedded double quotes when passing arguments to wsl.exe.
        $rows = Invoke-Wsl adb shell "cd $(Quote-Sh $dir) 2>/dev/null && stat -c '%F|%s|%Y|%n' *" |
            ForEach-Object { , ("$_".Split('|', 4)) } | Where-Object { $_.Count -eq 4 } |
            Sort-Object { [long]$_[2] } -Descending
        foreach ($p in $rows) {
            $isDir = $p[0] -eq 'directory'
            $it = New-Object System.Windows.Forms.ListViewItem($p[3])
            [void]$it.SubItems.Add($(if ($isDir) { 'folder' } else { Format-Size ([long]$p[1]) }))
            [void]$it.SubItems.Add([DateTimeOffset]::FromUnixTimeSeconds([long]$p[2]).LocalDateTime.ToString('yyyy-MM-dd HH:mm'))
            $it.Tag = "$dir/$($p[3])"; [void]$list.Items.Add($it)
            if (-not $isDir) { $script:FileSize[$it.Tag] = [long]$p[1] }
        }
        if ($list.Items.Count -eq 0) { $status.Text = "No files in $($src.SelectedItem) (or the phone is not connected)." }
        else { $status.Text = "Select files (Ctrl/Shift-click). Save to: $destPath" }
        Set-Busy $false
    }
    $src.Add_SelectedIndexChanged({ Load-Phone })
    $btnRefresh.Add_Click({ Load-Phone })
    $btnAll.Add_Click({ foreach ($i in $list.Items) { $i.Selected = $true }; $list.Focus() })
    $btnDest.Add_Click({
        $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.SelectedPath = $destPath; $d.Description = 'Save phone files to'
        if ($d.ShowDialog($form) -eq 'OK') { $script:destPath = $d.SelectedPath; $status.Text = "Save to: $destPath" }
    })

    $btnGo.Add_Click({
        $items = @($list.SelectedItems)
        if (-not $items) { $status.Text = 'Select one or more files first (Ctrl/Shift-click or Select all).'; return }
        Set-Busy $true
        New-Item -ItemType Directory -Force -Path $destPath | Out-Null
        $destW = To-WslPath $destPath
        $script:ItemText = 'Measuring...'
        # Folder sizes on the phone aren't in the listing, so measure them now.
        $sizes = @{}; foreach ($it in $items) { $sizes[$it.Tag] = if ($script:FileSize.ContainsKey($it.Tag)) { $script:FileSize[$it.Tag] } else { Get-PhoneSize (Quote-Sh $it.Tag) } }
        Start-Progress ($sizes.Values | Measure-Object -Sum).Sum
        $ok = 0; $failed = @(); $n = 0
        foreach ($it in $items) {
            $n++
            $script:ItemText = "Copying $($it.Text)  ($n of $($items.Count))"
            $script:CurSize = [long]$sizes[$it.Tag]
            $onPc = Join-Path $destPath $it.Text
            $script:Measure = { Get-LocalSize $onPc }.GetNewClosure()
            Update-Progress $script:DoneBytes
            [void](Invoke-Wsl adb pull $it.Tag "$destW/")
            $script:DoneBytes += $script:CurSize
            if ($script:WslCode -eq 0) {
                $ok++
                if ($rbMove.Checked) { [void](Invoke-Wsl adb shell "rm -rf $(Quote-Sh $it.Tag)"); $list.Items.Remove($it) }
            } else { $failed += $it.Text }
        }
        Stop-Progress
        $verb = if ($rbMove.Checked) { 'Moved' } else { 'Copied' }
        $status.Text = "$verb $ok item(s) to $destPath" + $(if ($failed) { "  Failed: $($failed -join ', ')" } else { '' })
        Set-Busy $false
        if ($ok) { Start-Process explorer.exe $destPath }
    })
    $form.Add_Shown({ Load-Phone })
}

[void]$form.ShowDialog()
