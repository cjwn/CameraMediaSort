param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$DroppedPaths
)

$ErrorActionPreference = "Stop"

if ($DroppedPaths.Count -lt 2) {
  Write-Host "Drag two files onto Drop-MediaRange.bat:"
  Write-Host "  1. the first file in the range"
  Write-Host "  2. the last file in the range"
  Write-Host ""
  Read-Host "Press Enter to close"
  exit 1
}

$firstPath = (Resolve-Path -LiteralPath $DroppedPaths[0]).Path
$lastPath = (Resolve-Path -LiteralPath $DroppedPaths[1]).Path

$firstFile = Get-Item -LiteralPath $firstPath
$lastFile = Get-Item -LiteralPath $lastPath

if (-not $firstFile.PSIsContainer -and -not $lastFile.PSIsContainer) {
  $source = $firstFile.DirectoryName
} else {
  throw "Please drag files, not folders."
}

if ($firstFile.DirectoryName -ne $lastFile.DirectoryName) {
  Write-Host "The two files are in different folders."
  Write-Host "Start: $($firstFile.DirectoryName)"
  Write-Host "End:   $($lastFile.DirectoryName)"
  Write-Host ""
  Read-Host "Press Enter to close"
  exit 1
}

$shell = New-Object -ComObject Shell.Application
$folder = $shell.BrowseForFolder(0, "Choose destination folder", 0)

if ($null -eq $folder) {
  Write-Host "Cancelled."
  exit 0
}

$destination = $folder.Self.Path
$scriptPath = Join-Path $PSScriptRoot "Copy-MediaRange.ps1"

Write-Host ""
Write-Host "Source:      $source"
Write-Host "From:        $($firstFile.Name)"
Write-Host "To:          $($lastFile.Name)"
Write-Host "Destination: $destination"
Write-Host ""

& $scriptPath `
  -Source $source `
  -From $firstFile.Name `
  -To $lastFile.Name `
  -Destination $destination `
  -Preview

Write-Host ""
$choice = Read-Host "Type C to copy, M to move, or anything else to cancel"

if ($choice -ieq "C") {
  & $scriptPath `
    -Source $source `
    -From $firstFile.Name `
    -To $lastFile.Name `
    -Destination $destination
} elseif ($choice -ieq "M") {
  & $scriptPath `
    -Source $source `
    -From $firstFile.Name `
    -To $lastFile.Name `
    -Destination $destination `
    -Mode Move
} else {
  Write-Host "Cancelled."
}

Write-Host ""
Read-Host "Press Enter to close"
