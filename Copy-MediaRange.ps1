param(
  [Parameter(Mandatory = $true)]
  [string]$Source,

  [Parameter(Mandatory = $true)]
  [string]$From,

  [Parameter(Mandatory = $true)]
  [string]$To,

  [Parameter(Mandatory = $true)]
  [string]$Destination,

  [ValidateSet("Copy", "Move")]
  [string]$Mode = "Copy",

  [switch]$Recurse,

  [switch]$Preview
)

$mediaExtensions = @(
  ".jpg", ".jpeg", ".png", ".heic", ".heif", ".gif", ".hif",
  ".mp4", ".mov", ".avi", ".mkv", ".mts", ".m2ts", ".mpg", ".mpeg"
)

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
  throw "Source folder does not exist: $Source"
}

if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
}

$files = Get-ChildItem -LiteralPath $Source -File -Recurse:$Recurse |
  Where-Object { $mediaExtensions -contains $_.Extension.ToLowerInvariant() } |
  Sort-Object Name, FullName

$names = @($files | ForEach-Object { $_.Name })
$fromIndex = [Array]::FindIndex($names, [Predicate[string]]{ param($name) $name -ieq $From })
$toIndex = [Array]::FindIndex($names, [Predicate[string]]{ param($name) $name -ieq $To })

if ($fromIndex -lt 0) {
  throw "Start file was not found: $From"
}

if ($toIndex -lt 0) {
  throw "End file was not found: $To"
}

if ($fromIndex -gt $toIndex) {
  $temp = $fromIndex
  $fromIndex = $toIndex
  $toIndex = $temp
}

$selected = $files[$fromIndex..$toIndex]

Write-Host "Selected $($selected.Count) file(s):"
$selected | ForEach-Object { Write-Host "  $($_.Name)" }

if ($Preview) {
  Write-Host ""
  Write-Host "Preview only. No files were copied or moved."
  exit 0
}

if ($Mode -eq "Move") {
  $selected | Move-Item -Destination $Destination
  Write-Host ""
  Write-Host "Moved to: $Destination"
} else {
  $selected | Copy-Item -Destination $Destination
  Write-Host ""
  Write-Host "Copied to: $Destination"
}
