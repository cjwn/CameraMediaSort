param([switch]$CheckUI)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$enginePath = Join-Path $PSScriptRoot 'Sort-MediaByDate.ps1'
$form = New-Object Windows.Forms.Form
$form.Text = 'CameraMediaSort'
$form.ClientSize = New-Object Drawing.Size(820, 650)
$form.MinimumSize = New-Object Drawing.Size(740, 600)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
$layout = New-Object Windows.Forms.TableLayoutPanel
$layout.Dock = 'Fill'
$layout.Padding = 12
$layout.ColumnCount = 3
$layout.RowCount = 9
[void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 105)))
[void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100)))
[void]$layout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 95)))
foreach ($height in @(36,36,40,42,30,24)) {
  [void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', $height)))
}
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 55)))
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 28)))
[void]$layout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 45)))
$form.Controls.Add($layout)

function Add-PathRow($caption, $row) {
  $label = New-Object Windows.Forms.Label
  $label.Text = $caption; $label.Dock = 'Fill'; $label.TextAlign = 'MiddleLeft'
  $box = New-Object Windows.Forms.TextBox
  $box.Dock = 'Fill'; $box.AllowDrop = $true
  $box.Add_DragEnter({ if ($_.Data.GetDataPresent('FileDrop')) { $_.Effect = 'Copy' } })
  $box.Add_DragDrop({ $this.Text = @($_.Data.GetData('FileDrop'))[0] })
  $button = New-Object Windows.Forms.Button
  $button.Text = 'Browse...'; $button.Dock = 'Fill'; $button.Tag = $box
  $button.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = $this.Tag.Text
    if ($dialog.ShowDialog() -eq 'OK') { $this.Tag.Text = $dialog.SelectedPath }
    $dialog.Dispose()
  })
  $layout.Controls.Add($label, 0, $row)
  $layout.Controls.Add($box, 1, $row)
  $layout.Controls.Add($button, 2, $row)
  return $box
}
$sourceBox = Add-PathRow 'Source' 0
$destBox = Add-PathRow 'Destination' 1
$options = New-Object Windows.Forms.FlowLayoutPanel
$options.Dock = 'Fill'
$move = New-Object Windows.Forms.RadioButton
$move.Text = 'Move'; $move.Checked = $true; $move.AutoSize = $true
$copy = New-Object Windows.Forms.RadioButton
$copy.Text = 'Copy'; $copy.AutoSize = $true
$recursive = New-Object Windows.Forms.CheckBox
$recursive.Text = 'Subfolders'; $recursive.Checked = $true; $recursive.AutoSize = $true
$robo = New-Object Windows.Forms.CheckBox
$robo.Text = 'Robocopy staging'; $robo.AutoSize = $true
$options.Controls.AddRange(@($move,$copy,$recursive,$robo))
$layout.Controls.Add($options,0,2); $layout.SetColumnSpan($options,3)
$buttons = New-Object Windows.Forms.FlowLayoutPanel
$buttons.Dock = 'Fill'
$preview = New-Object Windows.Forms.Button
$preview.Text = 'Preview'; $preview.Width = 110
$run = New-Object Windows.Forms.Button
$run.Text = 'Start'; $run.Width = 110
$buttons.Controls.AddRange(@($preview,$run))
$layout.Controls.Add($buttons,0,3); $layout.SetColumnSpan($buttons,3)
$status = New-Object Windows.Forms.Label
$status.Text = 'Ready'; $status.Dock = 'Fill'; $status.AutoEllipsis = $true
$layout.Controls.Add($status,0,4); $layout.SetColumnSpan($status,3)
$progress = New-Object Windows.Forms.ProgressBar
$progress.Dock = 'Fill'
$layout.Controls.Add($progress,0,5); $layout.SetColumnSpan($progress,3)
$grid = New-Object Windows.Forms.DataGridView
$grid.Dock = 'Fill'; $grid.ReadOnly = $true; $grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false; $grid.RowHeadersVisible = $false
$grid.BackgroundColor = [Drawing.Color]::White
[void]$grid.Columns.Add('Folder','Date folder')
[void]$grid.Columns.Add('Count','Files')
$grid.Columns[0].AutoSizeMode = 'Fill'; $grid.Columns[1].Width = 75
$layout.Controls.Add($grid,0,6); $layout.SetColumnSpan($grid,3)
$logTitle = New-Object Windows.Forms.Label
$logTitle.Text = 'Details'; $logTitle.Dock = 'Fill'
$layout.Controls.Add($logTitle,0,7); $layout.SetColumnSpan($logTitle,3)
$logBox = New-Object Windows.Forms.TextBox
$logBox.Multiline = $true; $logBox.ReadOnly = $true; $logBox.ScrollBars = 'Both'
$logBox.WordWrap = $false; $logBox.Dock = 'Fill'
$layout.Controls.Add($logBox,0,8); $layout.SetColumnSpan($logBox,3)
$script:worker = $null
$script:lastFolders = ''
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 400

function Start-Sort([bool]$isPreview) {
  if (-not (Test-Path -LiteralPath $sourceBox.Text -PathType Container) -or -not $destBox.Text.Trim()) {
    [void][Windows.Forms.MessageBox]::Show('Choose a source folder and destination.', 'CameraMediaSort'); return
  }
  if (-not $isPreview -and $move.Checked) {
    if ([Windows.Forms.MessageBox]::Show('Move files out of the source folder?','Confirm move','YesNo','Warning') -ne 'Yes') { return }
  }
  $script:runFolder = Join-Path ([IO.Path]::GetTempPath()) ('CameraMediaSort-' + [guid]::NewGuid().ToString('N'))
  [void][IO.Directory]::CreateDirectory($runFolder)
  $script:statePath = Join-Path $runFolder 'status.json'
  $script:logPath = Join-Path $runFolder 'details.log'
  $command = "& '" + $enginePath.Replace("'","''") + "' -Source '" + $sourceBox.Text.Replace("'","''") + "' -Destination '" + $destBox.Text.Replace("'","''") + "' -StatusFile '" + $statePath.Replace("'","''") + "' -Mode "
  if ($copy.Checked) { $command += 'Copy' } else { $command += 'Move' }
  if ($recursive.Checked) { $command += ' -Recurse' }
  if ($robo.Checked) { $command += ' -UseRobocopy' }
  if ($isPreview) { $command += ' -Preview' }
  $command = '$ErrorActionPreference = ''Stop''; try { ' + $command + " *> '" + $logPath.Replace("'","''") + "' } catch { " + '$_ | Out-File -Append -Encoding utf8 -LiteralPath ' + "'" + $logPath.Replace("'","''") + "'; exit 1 }"
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = 'powershell.exe'
  $info.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
  $info.UseShellExecute = $false; $info.CreateNoWindow = $true
  $script:worker = [Diagnostics.Process]::Start($info)
  $preview.Enabled = $false; $run.Enabled = $false; $options.Enabled = $false
  $sourceBox.ReadOnly = $true; $destBox.ReadOnly = $true
  $grid.Rows.Clear(); $script:lastFolders = ''; $logBox.Clear()
  $status.Text = 'Scanning...'; $progress.Style = 'Marquee'
  $timer.Start()
}
$preview.Add_Click({ Start-Sort $true })
$run.Add_Click({ Start-Sort $false })
$timer.Add_Tick({
  try {
    if (Test-Path -LiteralPath $statePath) {
      $state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
      $status.Text = '{0}  {1}/{2}  {3} MB/s  {4}' -f $state.Stage,$state.Done,$state.Total,$state.MBps,$state.CurrentFile
      if ($state.Total -gt 0) {
        $progress.Style = 'Continuous'
        $progress.Value = [math]::Min(100,[int](100 * $state.Done / $state.Total))
      }
      $folderJson = ConvertTo-Json -InputObject @($state.Folders) -Compress
      if ($folderJson -ne $lastFolders) {
        $grid.Rows.Clear()
        foreach ($entry in $state.Folders) { [void]$grid.Rows.Add($entry.Folder,[string]$entry.Count) }
        $script:lastFolders = $folderJson
      }
    }
    if (Test-Path -LiteralPath $logPath) {
      $content = Get-Content -LiteralPath $logPath -Raw
      if ($content.Length -gt 32000) { $content = $content.Substring($content.Length - 32000) }
      if ($logBox.Text -ne $content) { $logBox.Text = $content; $logBox.SelectionStart = $logBox.TextLength; $logBox.ScrollToCaret() }
    }
  } catch { }
  if ($worker.HasExited) {
    $timer.Stop(); $progress.Style = 'Continuous'
    if ($worker.ExitCode -ne 0) { $status.Text = 'Failed. See details. Log: ' + $logPath }
    $preview.Enabled = $true; $run.Enabled = $true; $options.Enabled = $true
    $sourceBox.ReadOnly = $false; $destBox.ReadOnly = $false
    $worker.Dispose(); $script:worker = $null
  }
})
$form.Add_FormClosing({
  if ($script:worker -and -not $script:worker.HasExited) {
    $_.Cancel = $true
    [void][Windows.Forms.MessageBox]::Show('A task is running. Wait for it to finish before closing.', 'CameraMediaSort')
  }
})
if ($CheckUI) {
  $form.CreateControl()
  $layout.PerformLayout()
  Write-Output ('UI ready: {0} controls, {1} columns' -f $layout.Controls.Count, $grid.Columns.Count)
} else {
  [void]$form.ShowDialog()
}
$timer.Dispose(); $form.Dispose()
