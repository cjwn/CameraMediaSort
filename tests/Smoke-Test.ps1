param([string]$Engine = (Join-Path (Split-Path $PSScriptRoot -Parent) 'Sort-MediaByDate.ps1'))

$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('CameraMediaSort-check-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$results = New-Object 'System.Collections.Generic.List[object]'
Add-Type -AssemblyName System.Drawing

function Assert-True($Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

function New-Fixture([string]$Name) {
  $root = Join-Path $testRoot $Name
  $source = Join-Path $root ('source space ' + [char]0x7167 + [char]0x7247)
  $nested = Join-Path $source 'nested'
  $dest = Join-Path $root 'output space'
  [void][IO.Directory]::CreateDirectory($nested)
  foreach ($n in @(1,2,4)) {
    $image = New-Object Drawing.Bitmap(24,24)
    try {
      $image.SetPixel($n,0,[Drawing.Color]::Red)
      $image.Save((Join-Path $source ('CAM_{0:D4}.jpg' -f $n)),[Drawing.Imaging.ImageFormat]::Jpeg)
    } finally { $image.Dispose() }
  }
  # Synthetic payloads exercise extension selection, not RAW/video decoding.
  [IO.File]::WriteAllBytes((Join-Path $source 'CAM_0001.rw2'),[byte[]](1,3,5,7))
  [IO.File]::WriteAllBytes((Join-Path $nested 'clip.mp4'),[byte[]](2,4,6,8))
  [IO.File]::WriteAllText((Join-Path $source 'keep.txt'),'not selected')
  foreach ($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
    $file.LastWriteTime = [datetime]'2026-05-01T12:00:00'
  }
  $hashes = @{}
  Get-ChildItem -LiteralPath $source -File -Recurse |
    Where-Object Extension -ne '.txt' |
    ForEach-Object { $hashes[$_.Name] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
  return @{ Root=$root; Source=$source; Dest=$dest; Hashes=$hashes }
}

function Invoke-Case([string]$Name,[string]$Mode,[switch]$Preview,[switch]$Robo,[switch]$Repeat) {
  $fixture = New-Fixture $Name
  $stateFile = Join-Path $fixture.Root 'state.json'
  $logFile = Join-Path $fixture.Root 'run.log'
  $argsList = @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$Engine,
    '-Source',$fixture.Source,'-Destination',$fixture.Dest,'-Recurse','-Mode',$Mode,'-StatusFile',$stateFile)
  if ($Preview) { $argsList += '-Preview' }
  if ($Robo) { $argsList += '-UseRobocopy' }
  & powershell.exe @argsList *> $logFile
  Assert-True ($LASTEXITCODE -eq 0) "$Name process failed; see $logFile"
  $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
  if ($Preview) {
    Assert-True ($state.Stage -eq 'Preview complete') "$Name preview status"
    Assert-True (@(Get-ChildItem -LiteralPath $fixture.Source -File -Recurse).Count -eq 6) "$Name changed source"
    Assert-True (@(Get-ChildItem -LiteralPath $fixture.Dest -File -Recurse).Count -eq 0) "$Name copied during preview"
  } else {
    Assert-True ($state.Stage -eq 'Complete' -and $state.Done -eq 5 -and $state.Total -eq 5) "$Name completion progress"
    $folderCount = ($state.Folders | Measure-Object Count -Sum).Sum
    Assert-True ($folderCount -eq 5) "$Name folder counts"
    $outputs = @(Get-ChildItem -LiteralPath $fixture.Dest -File -Recurse)
    Assert-True ($outputs.Count -eq 5) "$Name output file count"
    foreach ($file in $outputs) {
      Assert-True ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -eq $fixture.Hashes[$file.Name]) "$Name content mismatch: $($file.Name)"
    }
    $remaining = @(Get-ChildItem -LiteralPath $fixture.Source -File -Recurse)
    if ($Mode -eq 'Copy') { Assert-True ($remaining.Count -eq 6) "$Name lost source files" }
    else { Assert-True ($remaining.Count -eq 1 -and $remaining[0].Name -eq 'keep.txt') "$Name move or filtering failed" }
    Assert-True (@(Get-ChildItem -LiteralPath $fixture.Dest -Directory -Filter '_media_sort_incoming_*').Count -eq 0) "$Name staging cleanup failed"
    if ($Repeat) {
      & powershell.exe @argsList *> (Join-Path $fixture.Root 'repeat.log')
      Assert-True ($LASTEXITCODE -eq 0) "$Name repeated copy failed"
      $repeated = @(Get-ChildItem -LiteralPath $fixture.Dest -File -Recurse)
      Assert-True ($repeated.Count -eq 10) "$Name repeat overwrote files"
      Assert-True (@($repeated | Where-Object BaseName -like '* (1)').Count -eq 5) "$Name collision suffixes missing"
      foreach ($file in $repeated) {
        $original = ($file.BaseName -replace ' \(1\)$','') + $file.Extension
        Assert-True ((Get-FileHash -LiteralPath $file.FullName).Hash -eq $fixture.Hashes[$original]) "$Name repeated content mismatch"
      }
    }
  }
  $results.Add([pscustomobject]@{ Test=$Name; Result='PASS' })
}

Invoke-Case 'preview' Copy -Preview
Invoke-Case 'copy-and-collision' Copy -Repeat
Invoke-Case 'move' Move
Invoke-Case 'robocopy-copy' Copy -Robo
Invoke-Case 'robocopy-move' Move -Robo
$results | Format-Table -AutoSize
Write-Output "Fixtures and logs: $testRoot"
