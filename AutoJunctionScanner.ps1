<#
.SYNOPSIS
    Scans specified directories for folders, proposes junctions, and handles collision detection.
.DESCRIPTION
    1. Scans WatchPaths (including UserProfile, Local, LocalLow, Roaming).
    2. Filters exclusions and User Profile defaults.
    3. Prevents target naming collisions during the scan phase.
    4. User selects folders to process.
    5. Performs Moves/Junctions.
    6. Asks user specifically if they want to ignore the unselected items at the end.
#>

param(
    [switch]$SSD
)

# --- CONFIGURATION ---

if ($SSD) {
    $TargetRoot = 'E:\junction'
} else {
    $TargetRoot = 'W:\junction'
}

$WatchPaths = @(
    "$env:USERPROFILE",
    "$env:USERPROFILE\AppData\Local",
    "$env:USERPROFILE\AppData\LocalLow",
    "$env:USERPROFILE\AppData\Roaming"
)

# Regex Exclusions (System critical folders & Windows Defaults)
$Exclusions = @(
    "^Microsoft$",
    "^Temp$",
    "^Packages$",
    "^Google$",
    "^NVIDIA$",
    "^AppData$",              # Don't move the root AppData (we scan inside it)
    "^Application Data$",     # Legacy junction
    "^Local Settings$",       # Legacy junction
    "^NetHood$", "^PrintHood$", "^Cookies$", "^Recent$", "^SendTo$", "^Templates$", "^Start Menu$",
    # Standard User Profile Folders to exclude by default:
    "^Documents$",
    "^Pictures$",
    "^Desktop$",
    "^Downloads$",
    "^Music$",
    "^Videos$",
    "^Saved Games$",
    "^Favorites$",
    "^Links$",
    "^Contacts$",
    "^Searches$",
    "^3D Objects$",
    "^OneDrive$"
)

# Persistence File
$IgnoreFile = Join-Path $PSScriptRoot "junction_ignore_list.txt"

# --- END CONFIGURATION ---

$ErrorActionPreference = 'Stop'

# 1. Load Ignore List
$IgnoredPaths = @()
if (Test-Path $IgnoreFile) {
    $IgnoredPaths = Get-Content $IgnoreFile | Where-Object { $_ -ne "" }
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
# Track targets reserved in THIS session to prevent "Same Name" collisions
$ReservedTargets = New-Object System.Collections.Generic.HashSet[string]

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

        # --- COLLISION LOGIC ---
        $ParentName = Split-Path (Split-Path $Folder.FullName -Parent) -Leaf
        
        # 1. Try exact name
        $ProposedPath = Join-Path $TargetRoot $Folder.Name
        
        # Check if exists on DISK or if we already RESERVED it in this specific scan loop
        if ((Test-Path $ProposedPath) -or ($ReservedTargets.Contains($ProposedPath))) {
            # 2. Collision found: Try Name-ParentName
            $ProposedPath = Join-Path $TargetRoot "$($Folder.Name)-$($ParentName)"
            
            # If that also exists/reserved, skip it to be safe (or add manual logic here)
            if ((Test-Path $ProposedPath) -or ($ReservedTargets.Contains($ProposedPath))) {
                Write-Warning "Skipping $($Folder.FullName) - could not generate unique target name."
                continue 
            }
        }

        # Reserve this path so the next folder in the loop can't take it
        [void]$ReservedTargets.Add($ProposedPath)

        # Safe Size Calculation
        $Stats = Get-ChildItem $Folder.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
        $SizeMB = 0
        if ($Stats -and $Stats.Sum) {
            $SizeMB = $Stats.Sum / 1MB
        }

        $Candidates += [PSCustomObject]@{
            FolderName   = $Folder.Name
            Source       = $Folder.FullName
            Target       = $ProposedPath
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
$ToProcess = $Candidates | Out-GridView -Title "Select folders to Junction" -PassThru

# 5. Handle "Nothing Selected" case
if (-not $ToProcess) {
    Write-Host "No folders selected." -ForegroundColor Yellow
    # $confirm = Read-Host "Do you want to add ALL displayed folders to the ignore list? (y/n)"
    # if ($confirm -eq 'y') {
    #     Add-ToIgnoreList -Paths $Candidates.Source
    # }
    exit
}

# 6. Separate Lists (But don't ignore yet)
$SelectedSources = $ToProcess.Source
$UnselectedCandidates = $Candidates | Where-Object { $_.Source -notin $SelectedSources }

# 7. FINAL CONFIRMATION
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

# 8. Process Junctions
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

Write-Host "`nOperations Complete." -ForegroundColor Green

# 9. Post-Process: Ask to Ignore
if ($UnselectedCandidates) {
    Write-Host "`nYou chose NOT to process the following folders:" -ForegroundColor Yellow
    $UnselectedCandidates | ForEach-Object { Write-Host " - $($_.Source)" -ForegroundColor Gray }
    
    $IgnoreConfirm = Read-Host "`nDo you want to add these unselected folders to the Ignore List? (y/n)"
    if ($IgnoreConfirm -eq 'y') {
        Add-ToIgnoreList -Paths $UnselectedCandidates.Source
    }
}

Start-Sleep -Seconds 3