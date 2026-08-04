<#
.SYNOPSIS
    Scans specified directories for existing junctions pointing to a non-SSD drive, 
    and migrates the underlying files to an SSD drive, updating the junction.
.DESCRIPTION
    1. Scans WatchPaths specifically for Junctions.
    2. Filters for junctions pointing to the Non-SSD target root (W:\junction).
    3. User selects which ones to migrate via Out-GridView.
    4. Safely removes the old link, moves the target folder to the SSD, and creates a new link.
#>

# --- CONFIGURATION ---
$NonSsdRoot = 'W:\junction'
$SsdRoot    = 'E:\junction'

$WatchPaths = @(
    "$env:USERPROFILE",
    "$env:USERPROFILE\.local",
    "$env:USERPROFILE\AppData\Local",
    "$env:USERPROFILE\AppData\LocalLow",
    "$env:USERPROFILE\AppData\Roaming"
)
# --- END CONFIGURATION ---

$ErrorActionPreference = 'Stop'

# Ensure SSD Target Root exists
if (-not (Test-Path $SsdRoot)) {
    New-Item -ItemType Directory -Path $SsdRoot -Force | Out-Null
}

$Candidates = @()

Write-Host "Scanning directories for existing junctions pointing to $NonSsdRoot..." -ForegroundColor Cyan

foreach ($WatchPath in $WatchPaths) {
    if (-not (Test-Path $WatchPath)) { continue }

    # Find ONLY Directories that are currently Junctions or Symlinks
    $Junctions = Get-ChildItem -LiteralPath $WatchPath -Directory -Force -ErrorAction SilentlyContinue | 
                 Where-Object { $_.LinkType -match "Junction|SymbolicLink" }

    foreach ($Junc in $Junctions) {
        $Target = $Junc.Target
        
        # If the junction points to the non-SSD drive
        if ($Target -and $Target.StartsWith($NonSsdRoot, [StringComparison]::OrdinalIgnoreCase)) {
            
            # Calculate the new target path on the SSD
            $RelativePath = $Target.Substring($NonSsdRoot.Length).TrimStart('\')
            $NewTarget = Join-Path $SsdRoot $RelativePath

            # Calculate size for the GUI (helpful because moving across drives takes time)
            $SizeMB = 0
            if (Test-Path $Target) {
                $Stats = Get-ChildItem -LiteralPath $Target -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
                if ($Stats -and $Stats.Sum) {
                    $SizeMB = $Stats.Sum / 1MB
                }
            }

            $Candidates += [PSCustomObject]@{
                FolderName   = $Junc.Name
                JunctionPath = $Junc.FullName
                OldTarget    = $Target
                NewTarget    = $NewTarget
                SizeMB       = "{0:N2}" -f $SizeMB
            }
        }
    }
}

if ($Candidates.Count -eq 0) {
    Write-Host "No junctions pointing to $NonSsdRoot were found." -ForegroundColor Green
    Start-Sleep -Seconds 3
    exit
}

# Select via GUI
Write-Host "Found $($Candidates.Count) junctions currently on the Non-SSD." -ForegroundColor Cyan
Write-Host "Select junctions to MIGRATE to SSD."
$ToProcess = $Candidates | Out-GridView -Title "Select Junctions to Migrate to SSD" -PassThru

if (-not $ToProcess) {
    Write-Host "No folders selected. Exiting." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    exit
}

Clear-Host
Write-Host "--- SUMMARY OF MIGRATION ---" -ForegroundColor Yellow
foreach ($Item in $ToProcess) {
    Write-Host "MIGRATE: " -NoNewline -ForegroundColor Cyan
    Write-Host "$($Item.FolderName) ($($Item.SizeMB) MB)"
    Write-Host "   FROM: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($Item.OldTarget)"
    Write-Host "     TO: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($Item.NewTarget)"
    Write-Host "JUNCTION: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$($Item.JunctionPath)"
    Write-Host "--------------------------" -ForegroundColor DarkGray
}

Write-Host "WARNING: Ensure the applications using these folders are NOT RUNNING." -ForegroundColor Red
Write-Host "NOTE: Moving across drives actually copies the files and deletes the originals, which may take some time depending on size." -ForegroundColor Yellow
$FinalCheck = Read-Host "Type 'y' to proceed with migration, or anything else to cancel"

if ($FinalCheck -ne 'y') {
    Write-Host "Operation cancelled. No files were moved." -ForegroundColor Yellow
    exit
}

# Process Migrations
foreach ($Item in $ToProcess) {
    try {
        Write-Host "Migrating: $($Item.FolderName)... " -NoNewline -ForegroundColor Cyan
        
        if (Test-Path $Item.NewTarget) {
            Write-Error "Target $($Item.NewTarget) already exists on SSD. Skipping to prevent data loss."
            continue
        }
        if (-not (Test-Path $Item.OldTarget)) {
            Write-Error "Source $($Item.OldTarget) does not exist (broken junction?). Skipping."
            continue
        }

        # 1. Remove the old junction (This ONLY deletes the shortcut link, the actual data is safe)
        Remove-Item -LiteralPath $Item.JunctionPath -Force -ErrorAction Stop

        # 2. Move the target folder from W: to E:
        Move-Item -LiteralPath $Item.OldTarget -Destination $Item.NewTarget -Force -ErrorAction Stop

        # 3. Create the new junction pointing to the SSD
        New-Item -ItemType Junction -Path $Item.JunctionPath -Target $Item.NewTarget | Out-Null
        
        Write-Host "[OK] Success" -ForegroundColor Green
    }
    catch {
        Write-Host ""
        Write-Error "Failed to migrate $($Item.FolderName). `nError: $_"
        Write-Host "Tip: Make sure the app is completely closed." -ForegroundColor Yellow
    }
}

Write-Host "`nMigration Complete." -ForegroundColor Green
Start-Sleep -Seconds 5