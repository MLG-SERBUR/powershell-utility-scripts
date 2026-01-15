<#
.SYNOPSIS
    Scans specified directories for folders, proposes junctions, and remembers ignored choices.
.DESCRIPTION
    1. Scans $WatchPaths.
    2. Filters out exclusions, existing junctions, AND items in 'junction_ignore_list.txt'.
    3. User selects folders to process in a GUI.
    4. Unselected items are added to the ignore list.
    5. Script SHOWS A SUMMARY of selected items and asks for final confirmation.
    6. Selected items are moved and junctioned.
#>

# --- CONFIGURATION ---

$TargetRoot = 'W:\junction'

$WatchPaths = @(
    "$env:USERPROFILE\AppData\Local",
    "$env:USERPROFILE\AppData\Roaming"
)

# Regex Exclusions (System critical folders)
$Exclusions = @(
    "^Microsoft$",
    "^Temp$",
    "^Packages$",
    "^Google$",
    "^NVIDIA"
)

# Persistence File (Saved next to the script)
$IgnoreFile = Join-Path $PSScriptRoot "junction_ignore_list.txt"

# --- END CONFIGURATION ---

$ErrorActionPreference = 'Stop'

# 1. Load Ignore List
$IgnoredPaths = @()
if (Test-Path $IgnoreFile) {
    $IgnoredPaths = Get-Content $IgnoreFile | Where-Object { $_ -ne "" }
}

# Helper: Resolve collisions
function Get-UniqueTarget {
    param ($Root, $FolderName, $ParentName)
    $Path = Join-Path $Root $FolderName
    if (-not (Test-Path $Path)) { return $Path }
    
    $SuffixName = "$FolderName-$ParentName"
    $SuffixPath = Join-Path $Root $SuffixName
    if (-not (Test-Path $SuffixPath)) { return $SuffixPath }
    
    return $null
}

# Helper: Append to ignore file
function Add-ToIgnoreList {
    param ([string[]]$Paths)
    if ($Paths.Count -eq 0) { return }
    
    try {
        $Paths | Out-File -FilePath $IgnoreFile -Append -Encoding utf8
        Write-Host "Added $($Paths.Count) folder(s) to ignore list." -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "Could not update ignore list: $_"
    }
}

# 2. Ensure Target Root
if (-not (Test-Path $TargetRoot)) {
    New-Item -ItemType Directory -Path $TargetRoot | Out-Null
}

$Candidates = @()
Write-Host "Scanning directories..." -ForegroundColor Cyan

# 3. Scan
foreach ($WatchPath in $WatchPaths) {
    if (-not (Test-Path $WatchPath)) { continue }

    $SubFolders = Get-ChildItem -LiteralPath $WatchPath -Directory -ErrorAction SilentlyContinue

    foreach ($Folder in $SubFolders) {
        # Check Ignore List (Exact full path match)
        if ($Folder.FullName -in $IgnoredPaths) { continue }

        # Check Junction/Symlink
        if ($Folder.LinkType -match "Junction|SymbolicLink") { continue }

        # Check Exclusions
        $IsExcluded = $false
        foreach ($Pattern in $Exclusions) {
            if ($Folder.Name -match $Pattern) { $IsExcluded = $true; break }
        }
        if ($IsExcluded) { continue }

        # Calculate Target
        $ParentName = Split-Path (Split-Path $Folder.FullName -Parent) -Leaf
        $ProposedTarget = Get-UniqueTarget -Root $TargetRoot -FolderName $Folder.Name -ParentName $ParentName

        if ($null -eq $ProposedTarget) { continue }

        # Safe Size Calculation
        $Stats = Get-ChildItem $Folder.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        $SizeMB = 0
        if ($Stats -and $Stats.Sum) {
            $SizeMB = $Stats.Sum / 1MB
        }

        $Candidates += [PSCustomObject]@{
            FolderName   = $Folder.Name
            Source       = $Folder.FullName
            Target       = $ProposedTarget
            SizeMB       = "{0:N2}" -f $SizeMB
            Parent       = $ParentName
        }
    }
}

if ($Candidates.Count -eq 0) {
    Write-Host "No new eligible directories found." -ForegroundColor Green
    exit
}

# 4. GUI Selection
Write-Host "Found $($Candidates.Count) new candidates." -ForegroundColor Cyan
Write-Host "Select folders to JUNCTION."
Write-Host "Any folders visible here that you do NOT select will be added to the Ignore List." -ForegroundColor Yellow
$ToProcess = $Candidates | Out-GridView -Title "Select to Junction (Others will be Ignored)" -PassThru

# 5. Handle "Nothing Selected" case
if (-not $ToProcess) {
    Write-Host "No folders selected." -ForegroundColor Yellow
    $confirm = Read-Host "Do you want to add all displayed folders to the ignore list so they don't show up again? (y/n)"
    if ($confirm -eq 'y') {
        Add-ToIgnoreList -Paths $Candidates.Source
    }
    exit
}

# 6. Handle "Something Selected" case
# Identify what was NOT selected to add to ignore list
$SelectedSources = $ToProcess.Source
$IgnoredCandidates = $Candidates | Where-Object { $_.Source -notin $SelectedSources }

if ($IgnoredCandidates) {
    Add-ToIgnoreList -Paths $IgnoredCandidates.Source
}

# --- NEW: FINAL CONFIRMATION STEP ---
Clear-Host
Write-Host "--- SUMMARY OF ACTIONS ---" -ForegroundColor Yellow
foreach ($Item in $ToProcess) {
    Write-Host "MOVE: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($Item.FolderName)"
    Write-Host "FROM: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($Item.Source)"
    Write-Host " TO : " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($Item.Target)"
    Write-Host "--------------------------" -ForegroundColor DarkGray
}

Write-Host "WARNING: Ensure the applications listed above are NOT RUNNING." -ForegroundColor Red
$FinalCheck = Read-Host "Type 'y' to proceed with these moves, or anything else to cancel"

if ($FinalCheck -ne 'y') {
    Write-Host "Operation cancelled. No files were moved." -ForegroundColor Yellow
    exit
}
# ------------------------------------

# 7. Process Junctions
foreach ($Item in $ToProcess) {
    try {
        Write-Host "Processing: $($Item.FolderName)..." -ForegroundColor Cyan
        
        if (Test-Path $Item.Target) {
            Write-Error "Target $($Item.Target) exists (race condition). Skipping."
            continue
        }

        # Attempt Move
        Move-Item -LiteralPath $Item.Source -Destination $Item.Target -Force -ErrorAction Stop

        # Create Junction
        New-Item -ItemType Junction -Path $Item.Source -Target $Item.Target | Out-Null
        
        Write-Host "  [OK] Success" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to move $($Item.FolderName). `nError: $_"
        Write-Host "Tip: Make sure the app is completely closed." -ForegroundColor Yellow
    }
}

Write-Host "Complete." -ForegroundColor Green
Start-Sleep -Seconds 3