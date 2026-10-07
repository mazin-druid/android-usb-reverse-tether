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
$script:BusyText = $null
function Invoke-Wsl {
    $psi = New-Object System.Diagnostics.ProcessStartInfo 'wsl.exe'
    # Quote each argument ourselves: Windows PowerShell 5.1 mangles embedded quotes otherwise.
    # wsl's own options must stay unquoted; only the Linux command's arguments are quoted.
    $psi.Arguments = "-d $Distro --exec " + (($args | ForEach-Object { '"' + ("$_" -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }) -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited) {
        if ($script:BusyText -and $status) { $status.Text = "$script:BusyText  ($([int]$sw.Elapsed.TotalSeconds)s)" }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    $p.WaitForExit()
    $script:WslCode = $p.ExitCode
    ($out.Result + $err.Result) -split "`r?`n" | Where-Object { $_ -ne '' }
}
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
        $progress.Maximum = $items.Count; $progress.Value = 0; $ok = 0; $failed = @()
        foreach ($it in $items) {
            $script:BusyText = "Sending $($it.Text)  ($($progress.Value + 1) of $($items.Count))..."
            [System.Windows.Forms.Application]::DoEvents()
            [void](Invoke-Wsl adb push (To-WslPath $it.Tag) "$target/")
            if ($script:WslCode -eq 0) {
                $ok++
                if ($rbMove.Checked) { Remove-Item -LiteralPath $it.Tag -Recurse -Force -ErrorAction SilentlyContinue }
                $list.Items.Remove($it)
            } else { $failed += $it.Text }
            $progress.Value++
        }
        $script:BusyText = $null
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
        $progress.Maximum = $items.Count; $progress.Value = 0; $ok = 0; $failed = @()
        foreach ($it in $items) {
            $script:BusyText = "Copying $($it.Text)  ($($progress.Value + 1) of $($items.Count))..."
            [System.Windows.Forms.Application]::DoEvents()
            [void](Invoke-Wsl adb pull $it.Tag "$destW/")
            if ($script:WslCode -eq 0) {
                $ok++
                if ($rbMove.Checked) { [void](Invoke-Wsl adb shell "rm -rf $(Quote-Sh $it.Tag)"); $list.Items.Remove($it) }
            } else { $failed += $it.Text }
            $progress.Value++
        }
        $script:BusyText = $null
        $verb = if ($rbMove.Checked) { 'Moved' } else { 'Copied' }
        $status.Text = "$verb $ok item(s) to $destPath" + $(if ($failed) { "  Failed: $($failed -join ', ')" } else { '' })
        Set-Busy $false
        if ($ok) { Start-Process explorer.exe $destPath }
    })
    $form.Add_Shown({ Load-Phone })
}

[void]$form.ShowDialog()
