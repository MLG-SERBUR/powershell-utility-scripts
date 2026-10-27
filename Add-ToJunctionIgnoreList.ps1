<#
.SYNOPSIS
    Selects directories to add to the junction scanner's ignore list.
.DESCRIPTION
    Scans the same user-profile locations as AutoJunctionScanner.ps1, then
    appends the selected directories to junction_ignore_list.txt. No files are
    moved and no junctions are created.
#>

$ErrorActionPreference = 'Stop'

$WatchPaths = @(
    "$env:USERPROFILE",
    "$env:USERPROFILE\.local",
    "$env:USERPROFILE\AppData\Local",
    "$env:USERPROFILE\AppData\LocalLow",
    "$env:USERPROFILE\AppData\Roaming"
)

$Exclusions = @(
    "^Microsoft$",
    "^Temp$",
    "^Packages$",
    "^Google$",
    "^NVIDIA$",
    "^AppData$",
    "^\.local$",
    "^Application Data$",
    "^Local Settings$",
    "^NetHood$", "^PrintHood$", "^Cookies$", "^Recent$", "^SendTo$", "^Templates$", "^Start Menu$",
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

$IgnoreFile = Join-Path $PSScriptRoot "junction_ignore_list.txt"
$IgnoredPaths = @()
if (Test-Path -LiteralPath $IgnoreFile) {
    $IgnoredPaths = Get-Content -LiteralPath $IgnoreFile | Where-Object { $_ -ne "" }
}

$Candidates = foreach ($WatchPath in $WatchPaths) {
    if (-not (Test-Path -LiteralPath $WatchPath)) {
        continue
    }

    Get-ChildItem -LiteralPath $WatchPath -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $Folder = $_

            if ($Folder.FullName -in $IgnoredPaths) {
                return
            }

            if ($Folder.LinkType -match "Junction|SymbolicLink") {
                return
            }

            foreach ($Pattern in $Exclusions) {
                if ($Folder.Name -match $Pattern) {
                    return
                }
            }

            $Stats = Get-ChildItem -LiteralPath $Folder.FullName -Recurse -File -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum
            $SizeMB = 0
            if ($Stats -and $Stats.Sum) {
                $SizeMB = $Stats.Sum / 1MB
            }

            [PSCustomObject]@{
                FolderName   = $Folder.Name
                Source       = $Folder.FullName
                SizeMB       = "{0:N2}" -f $SizeMB
                FileCount    = $Stats.Count
                Parent       = Split-Path $Folder.FullName -Parent
                LastWriteTime = $Folder.LastWriteTime
            }
        }
}

if (-not $Candidates) {
    Write-Host "No eligible directories found to add." -ForegroundColor Green
    exit
}

Write-Host "Found $($Candidates.Count) eligible directories." -ForegroundColor Cyan
$ToIgnore = $Candidates | Out-GridView -Title "Select folders to add to junction ignore list" -PassThru

if (-not $ToIgnore) {
    Write-Host "No folders selected. Ignore list unchanged." -ForegroundColor Yellow
    exit
}

Write-Host "`nThese directories will be added to the ignore list:" -ForegroundColor Yellow
$ToIgnore | ForEach-Object { Write-Host " - $($_.Source)" -ForegroundColor Gray }

$Confirm = Read-Host "`nType 'y' to add these paths, or anything else to cancel"
if ($Confirm -ne 'y') {
    Write-Host "Operation cancelled. Ignore list unchanged." -ForegroundColor Yellow
    exit
}

$NewPaths = @(
    $ToIgnore.Source |
        Where-Object { $_ -notin $IgnoredPaths } |
        Sort-Object -Unique
)

if ($NewPaths.Count -eq 0) {
    Write-Host "All selected paths are already in the ignore list." -ForegroundColor Green
    exit
}

try {
    $NewPaths | Add-Content -LiteralPath $IgnoreFile -Encoding UTF8
}
catch {
    Write-Error "Could not update ignore list at '$IgnoreFile': $_"
    exit 1
}

Write-Host "Added $($NewPaths.Count) path(s) to '$IgnoreFile'." -ForegroundColor Green
