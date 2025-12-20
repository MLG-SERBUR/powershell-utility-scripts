param (
    [Parameter(Mandatory = $true)]
    [string]$SourceDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

try {
    $SourceDir = (Resolve-Path -LiteralPath $SourceDir).ProviderPath
    $FolderName = Split-Path $SourceDir -Leaf
    $TargetRoot = 'W:\junction'
    $TargetDir  = Join-Path $TargetRoot $FolderName

    # Create target root if it doesn't exist
    if (-not (Test-Path $TargetRoot)) {
        New-Item -ItemType Directory -Path $TargetRoot | Out-Null
    }

    # Idempotent: already a junction
    $item = Get-Item $SourceDir -ErrorAction SilentlyContinue
    if ($item -and $item.LinkType -eq 'Junction') {
        Write-Host "Already a junction. Nothing to do."
        return
    }

    if (Test-Path $TargetDir) {
        throw "Target directory already exists: $TargetDir"
    }

    # Move the directory as a whole
    Move-Item -LiteralPath $SourceDir -Destination $TargetRoot

    # Create junction at original location
    New-Item -ItemType Junction -Path $SourceDir -Target $TargetDir | Out-Null

    Write-Host "Done."
}
catch {
    Write-Error $_
    exit 1
}
