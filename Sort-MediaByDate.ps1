param(
  [Parameter(Mandatory = $true)]
  [string]$Source,

  [string]$Destination,

  [ValidateSet("Copy", "Move")]
  [string]$Mode = "Move",

  [string]$DateFormat = "yyyy-MM-dd",

  [switch]$Recurse,

  [switch]$Preview,

  [switch]$UseRobocopy,

  [string]$StatusFile
)

$ErrorActionPreference = "Stop"

function Write-RunStatus {
  param([string]$Stage, [int]$Done = 0, [int]$Total = 0, [string]$CurrentFile = '')
  if (-not $StatusFile) { return }
  $rows = @($summary | ForEach-Object { @{ Folder = $_.Name; Count = $_.Count } })
  $state = @{
    Stage = $Stage; Done = $Done; Total = $Total; CurrentFile = $CurrentFile
    Folders = $rows
  }
  if ($transferWatch -and $transferWatch.Elapsed.TotalSeconds -gt 0) {
    $state.MBps = [math]::Round($completedBytes / 1MB / $transferWatch.Elapsed.TotalSeconds, 1)
  }
  [IO.File]::WriteAllText($StatusFile, ($state | ConvertTo-Json -Depth 5))
}

Write-RunStatus 'Scanning'

$mediaExtensions = @(
  ".jpg", ".jpeg", ".png", ".heic", ".heif", ".gif", ".tif", ".tiff", ".hif",
  ".rw2", ".raw", ".dng", ".cr2", ".cr3", ".nef", ".nrw", ".arw", ".srf", ".sr2",
  ".orf", ".raf", ".pef", ".srw", ".x3f", ".erf", ".kdc", ".dcr", ".mrw",
  ".mp4", ".mov", ".avi", ".mkv", ".mts", ".m2ts", ".mpg", ".mpeg", ".wmv",
  ".xml"
)

$mediaPatterns = $mediaExtensions | ForEach-Object { "*$_" }

function Convert-WindowsDate {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $null
  }

  $clean = $Value -replace [char]8206, "" -replace [char]8207, ""
  $clean = $clean.Trim()

  $date = [datetime]::MinValue
  if ([datetime]::TryParse($clean, [ref]$date)) {
    return $date
  }

  return $null
}

function Get-SafeName {
  param(
    [string]$Folder,
    [string]$FileName
  )

  $target = Join-Path $Folder $FileName
  if (-not (Test-Path -LiteralPath $target)) {
    return $target
  }

  $name = [IO.Path]::GetFileNameWithoutExtension($FileName)
  $ext = [IO.Path]::GetExtension($FileName)
  $i = 1

  do {
    $target = Join-Path $Folder ("{0} ({1}){2}" -f $name, $i, $ext)
    $i++
  } while (Test-Path -LiteralPath $target)

  return $target
}

function Invoke-FileTransfer {
  param(
    $File,
    [string]$Target,
    [string]$TransferMode
  )

  if ($TransferMode -eq "Move") {
    try {
      [IO.File]::Move($File.FullName, $Target)
      return
    } catch {
      Move-Item -LiteralPath $File.FullName -Destination $Target
      return
    }
  }

  try {
    [IO.File]::Copy($File.FullName, $Target, $false)
  } catch {
    Copy-Item -LiteralPath $File.FullName -Destination $Target
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

function Invoke-RobocopyStage {
  param(
    [string]$From,
    [string]$To,
    [string]$TransferMode,
    [switch]$IncludeSubfolders
  )

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $stage = Join-Path $To ("_media_sort_incoming_{0}_{1}" -f $stamp, [guid]::NewGuid().ToString('N'))

  if (Test-IsSameOrChildPath -Parent $From -Child $stage) {
    throw "When using -UseRobocopy, destination must not be inside the source folder."
  }

  New-Item -ItemType Directory -Force -Path $stage | Out-Null

  $args = @($From, $stage)
  $args += $mediaPatterns

  if ($IncludeSubfolders) {
    $args += "/E"
  }

  if ($TransferMode -eq "Move") {
    $args += "/MOV"
  }

  $args += @("/COPY:DAT", "/DCOPY:DAT", "/R:2", "/W:1", "/ETA", "/TEE")

  Write-Host ""
  Write-Host "Robocopy staging:"
  Write-Host "  From: $From"
  Write-Host "  To:   $stage"
  Write-Host ""

  & robocopy @args | ForEach-Object { Write-Host $_ }
  $exitCode = $LASTEXITCODE

  if ($exitCode -ge 8) {
    throw "Robocopy failed with exit code $exitCode. Staging folder was left at: $stage"
  }

  return $stage
}

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
  throw "Source folder does not exist: $Source"
}

if ([string]::IsNullOrWhiteSpace($Destination)) {
  $Destination = $Source
}

if ($DateFormat -cmatch "[HhmsfFtT]") {
  throw "DateFormat must only include date parts. For example: yyyy-MM-dd or yyyy\\MM\\dd"
}

if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
}

$sourceItem = Get-Item -LiteralPath $Source
$destinationItem = Get-Item -LiteralPath $Destination
$stagingRoot = $null

if ($UseRobocopy -and -not $Preview) {
  Write-RunStatus 'Robocopy staging'
  $stagedSource = Invoke-RobocopyStage `
    -From $sourceItem.FullName `
    -To $destinationItem.FullName `
    -TransferMode $Mode `
    -IncludeSubfolders:$Recurse

  $Source = $stagedSource
  $stagingRoot = $stagedSource
  $sourceItem = Get-Item -LiteralPath $Source
  $Mode = "Move"
}

$shell = New-Object -ComObject Shell.Application
$folderCache = @{}
$datePropertyIndexes = 12, 208, 190, 27, 3, 4
$dateCache = @{}
$directDateReads = 0
$inferredDateReads = 0

function Get-MediaDate {
  param($File)

  if ($dateCache.ContainsKey($File.FullName)) {
    return $dateCache[$File.FullName]
  }

  if (-not $folderCache.ContainsKey($File.DirectoryName)) {
    $folderCache[$File.DirectoryName] = $shell.Namespace($File.DirectoryName)
  }

  $folder = $folderCache[$File.DirectoryName]
  $item = $folder.ParseName($File.Name)

  $takenDate = $null
  foreach ($index in $datePropertyIndexes) {
    $raw = $folder.GetDetailsOf($item, $index)
    $takenDate = Convert-WindowsDate $raw
    if ($null -ne $takenDate) {
      break
    }
  }

  if ($null -eq $takenDate) {
    $takenDate = $File.LastWriteTime
  }

  $script:directDateReads++
  $dateCache[$File.FullName] = $takenDate
  return $takenDate
}

function New-Action {
  param(
    $File,
    [datetime]$Date,
    [switch]$Inferred
  )

  if ($Inferred) {
    $script:inferredDateReads++
  }

  $dateFolder = $Date.ToString($DateFormat)
  $targetFolder = Join-Path $destinationItem.FullName $dateFolder

  [pscustomobject]@{
    File = $File
    Date = $Date
    TargetFolder = $targetFolder
    Inferred = [bool]$Inferred
  }
}

function Get-NumberedInfo {
  param($File)

  if ($File.BaseName -notmatch "^(.*?)(\d+)$") {
    return $null
  }

  $numberText = $matches[2]

  [pscustomobject]@{
    File = $File
    Prefix = $matches[1]
    NumberText = $numberText
    Number = [int64]$numberText
    Width = $numberText.Length
    GroupKey = "{0}|{1}|{2}" -f $File.DirectoryName.ToLowerInvariant(), $matches[1].ToLowerInvariant(), $numberText.Length
  }
}

function Add-InferredRangeActions {
  param(
    $Buckets,
    [int]$Start,
    [int]$End,
    [System.Collections.ArrayList]$Output
  )

  if ($Start -gt $End) {
    return
  }

  $startDate = (Get-MediaDate $Buckets[$Start].Files[0]).Date
  $endDate = (Get-MediaDate $Buckets[$End].Files[0]).Date

  if ($startDate -eq $endDate) {
    for ($i = $Start; $i -le $End; $i++) {
      foreach ($file in $Buckets[$i].Files) {
        [void]$Output.Add((New-Action -File $file -Date $startDate -Inferred))
      }
    }
    return
  }

  if ($Start -eq $End) {
    foreach ($file in $Buckets[$Start].Files) {
      [void]$Output.Add((New-Action -File $file -Date (Get-MediaDate $file)))
    }
    return
  }

  $low = $Start + 1
  $high = $End

  while ($low -lt $high) {
    $mid = [int][math]::Floor(($low + $high) / 2)
    $midDate = (Get-MediaDate $Buckets[$mid].Files[0]).Date

    if ($midDate -eq $startDate) {
      $low = $mid + 1
    } else {
      $high = $mid
    }
  }

  $changeAt = $low

  for ($i = $Start; $i -lt $changeAt; $i++) {
    foreach ($file in $Buckets[$i].Files) {
      [void]$Output.Add((New-Action -File $file -Date $startDate -Inferred))
    }
  }

  Add-InferredRangeActions -Buckets $Buckets -Start $changeAt -End $End -Output $Output
}

$files = Get-ChildItem -LiteralPath $sourceItem.FullName -File -Recurse:$Recurse |
  Where-Object { $mediaExtensions -contains $_.Extension.ToLowerInvariant() }

$actionsList = [System.Collections.ArrayList]::new()
$numbered = @()
$plainFiles = @()

foreach ($file in $files) {
  $info = Get-NumberedInfo $file
  if ($null -eq $info) {
    $plainFiles += $file
  } else {
    $numbered += $info
  }
}

foreach ($file in $plainFiles) {
  [void]$actionsList.Add((New-Action -File $file -Date (Get-MediaDate $file)))
}

$numbered |
  Group-Object GroupKey |
  ForEach-Object {
    $items = @($_.Group | Sort-Object Number, { $_.File.Name })
    $buckets = @(
      $items |
        Group-Object Number |
        Sort-Object { [int64]$_.Name } |
        ForEach-Object {
          [pscustomobject]@{
            Number = [int64]$_.Name
            Files = @($_.Group | ForEach-Object { $_.File } | Sort-Object Name)
          }
        }
    )

    $runStart = 0
    for ($i = 1; $i -le $buckets.Count; $i++) {
      $isEnd = $i -eq $buckets.Count
      $isBreak = -not $isEnd -and $buckets[$i].Number -ne ($buckets[$i - 1].Number + 1)

      if ($isEnd -or $isBreak) {
        $runEnd = $i - 1

        if ($runEnd -gt $runStart) {
          Add-InferredRangeActions -Buckets $buckets -Start $runStart -End $runEnd -Output $actionsList
        } else {
          foreach ($file in $buckets[$runStart].Files) {
            [void]$actionsList.Add((New-Action -File $file -Date (Get-MediaDate $file)))
          }
        }

        $runStart = $i
      }
    }
  }

$actions = @($actionsList | Sort-Object { $_.File.FullName })

if ($actions.Count -eq 0) {
  Write-Host "No photo or video files found."
  Write-RunStatus 'No media files'
  exit 0
}

$actions |
  Group-Object TargetFolder |
  Sort-Object Name |
  ForEach-Object {
    Write-Host ""
    Write-Host $_.Name
    $_.Group | Sort-Object { $_.File.Name } | ForEach-Object {
      Write-Host ("  {0}  ->  {1}" -f $_.File.Name, $_.Date.ToString("yyyy-MM-dd HH:mm:ss"))
    }
  }

Write-Host ""
Write-Host "Selected $($actions.Count) file(s). Mode: $Mode"
Write-Host "Date reads: $directDateReads direct, $inferredDateReads inferred from continuous filename ranges."

$summary = $actions |
  Group-Object TargetFolder |
  Sort-Object Name

function Write-FolderSummary {
  param($Groups)

  Write-Host ""
  Write-Host "Folder summary:"
  foreach ($group in $Groups) {
    Write-Host ("  {0}  ({1} file(s))" -f $group.Name, $group.Count)
  }
}

if ($Preview) {
  Write-FolderSummary $summary
  Write-Host ""
  Write-Host "Preview only. No files were copied or moved."
  Write-RunStatus 'Preview complete' 0 $actions.Count
  exit 0
}

$transferWatch = [Diagnostics.Stopwatch]::StartNew()
$completedBytes = 0L
$completedFiles = 0
foreach ($action in $actions) {
  Write-RunStatus 'Transferring' $completedFiles $actions.Count $action.File.Name
  if (-not (Test-Path -LiteralPath $action.TargetFolder -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $action.TargetFolder | Out-Null
  }

  $target = Get-SafeName -Folder $action.TargetFolder -FileName $action.File.Name

  Invoke-FileTransfer -File $action.File -Target $target -TransferMode $Mode
  $completedBytes += $action.File.Length
  $completedFiles++
}

Write-Host ""
Write-Host "$Mode complete."
Write-FolderSummary $summary

if (-not [string]::IsNullOrWhiteSpace($stagingRoot) -and (Test-Path -LiteralPath $stagingRoot -PathType Container)) {
  Get-ChildItem -LiteralPath $stagingRoot -Directory -Recurse |
    Sort-Object { $_.FullName.Length } -Descending |
    ForEach-Object {
      if (@(Get-ChildItem -LiteralPath $_.FullName -Force).Count -eq 0) {
        [IO.Directory]::Delete($_.FullName)
      }
    }
  if (@(Get-ChildItem -LiteralPath $stagingRoot -Force).Count -eq 0) {
    [IO.Directory]::Delete($stagingRoot)
    Write-Host "Removed empty staging folder: $stagingRoot"
  } else {
    Write-Warning "Staging folder still contains files and was preserved: $stagingRoot"
  }
}
Write-RunStatus 'Complete' $completedFiles $actions.Count
