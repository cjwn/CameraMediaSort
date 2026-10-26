param(
  [switch]$PauseOnExit,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$DroppedPaths
)

$ErrorActionPreference = "Stop"

function Wait-BeforeExit {
  if ($PauseOnExit) {
    Write-Host ""
    Read-Host "Press Enter to close"
  }
}

function Test-IsSameOrChildPath {
  param(
    [string]$Parent,
    [string]$Child
  )

  $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\')
  $childFull = [IO.Path]::GetFullPath($Child).TrimEnd('\')

  return $childFull.Equals($parentFull, [StringComparison]::OrdinalIgnoreCase) -or
    $childFull.StartsWith($parentFull + "\", [StringComparison]::OrdinalIgnoreCase)
}

if ($DroppedPaths.Count -lt 1) {
  Write-Host "Drag a folder onto Drop-SortMediaByDate.bat."
  Wait-BeforeExit
  exit 1
}

$source = (Resolve-Path -LiteralPath $DroppedPaths[0]).Path

if (-not (Test-Path -LiteralPath $source -PathType Container)) {
  Write-Host "Please drag a folder, not a file."
  Wait-BeforeExit
  exit 1
}

if ($DroppedPaths.Count -ge 2) {
  $destination = $DroppedPaths[1]
  if (-not (Test-Path -LiteralPath $destination -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
  }
  $destination = (Resolve-Path -LiteralPath $destination).Path
} else {
  $shell = New-Object -ComObject Shell.Application
  $folder = $shell.BrowseForFolder(0, "Choose destination folder. Cancel = sort inside source folder.", 0)

  if ($null -eq $folder) {
    $destination = $source
  } else {
    $destination = $folder.Self.Path
  }
}

$scriptPath = Join-Path $PSScriptRoot "Sort-MediaByDate.ps1"

Write-Host ""
Write-Host "Source:      $source"
Write-Host "Destination: $destination"
Write-Host ""

& $scriptPath -Source $source -Destination $destination -Recurse -Preview

$canUseRobocopy = -not (Test-IsSameOrChildPath -Parent $source -Child $destination)

Write-Host ""
$choice = Read-Host "Enter/M = move, C = copy, R = robocopy move, RC = robocopy copy, other = cancel"
$choice = $choice.Trim()

if ($choice -ieq "C") {
  & $scriptPath -Source $source -Destination $destination -Recurse -Mode Copy
} elseif ([string]::IsNullOrWhiteSpace($choice) -or $choice -ieq "M") {
  & $scriptPath -Source $source -Destination $destination -Recurse -Mode Move
} elseif ($choice -ieq "R") {
  if ($canUseRobocopy) {
    & $scriptPath -Source $source -Destination $destination -Recurse -Mode Move -UseRobocopy
  } else {
    Write-Host "Robocopy staging is not available when destination is inside the source. Using normal move."
    & $scriptPath -Source $source -Destination $destination -Recurse -Mode Move
  }
} elseif ($choice -ieq "RC" -or $choice -ieq "CR") {
  if ($canUseRobocopy) {
    & $scriptPath -Source $source -Destination $destination -Recurse -Mode Copy -UseRobocopy
  } else {
    Write-Host "Robocopy staging is not available when destination is inside the source. Using normal copy."
    & $scriptPath -Source $source -Destination $destination -Recurse -Mode Copy
  }
} else {
  Write-Host "Cancelled."
}

Wait-BeforeExit
