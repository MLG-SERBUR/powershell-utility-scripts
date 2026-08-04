# Run as Administrator

$DestRoot = "D:\EpicRedirects"

$Mappings = @(
    @{
        Source = "C:\ProgramData\Epic"
        Dest   = "$DestRoot\ProgramData\Epic"
    },
    @{
        Source = "$env:LOCALAPPDATA\EpicGamesLauncher"
        Dest   = "$DestRoot\LocalAppData\EpicGamesLauncher"
    },
    @{
        Source = "$env:LOCALAPPDATA\Epic Games"
        Dest   = "$DestRoot\LocalAppData\Epic Games"
    },
    @{
        Source = "$env:APPDATA\Epic"
        Dest   = "$DestRoot\Roaming\Epic"
    },
    @{
        Source = "$env:LOCALAPPDATA\UnrealEngine"
        Dest   = "$DestRoot\LocalAppData\UnrealEngine"
    },
    @{
        Source = "$env:LOCALAPPDATA\UnrealEngineLauncher"
        Dest   = "$DestRoot\LocalAppData\UnrealEngineLauncher"
    },
    @{
        Source = "$env:APPDATA\Unreal Engine"
        Dest   = "$DestRoot\Roaming\Unreal Engine"
    },
    @{
        Source = "$env:LOCALAPPDATA\UnrealBuildTool"
        Dest   = "$DestRoot\LocalAppData\UnrealBuildTool"
    }
)

Write-Host "Closing Epic processes just in case..."
Get-Process | Where-Object { $_.ProcessName -match "Epic|Unreal" } | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "Setting up Epic Games Junctions..."

foreach ($Map in $Mappings) {

    $Source = $Map.Source
    $Dest   = $Map.Dest

    Write-Host ""
    Write-Host "Processing:"
    Write-Host "  Source: $Source"
    Write-Host "  Dest:   $Dest"

    # 1. Ensure Target Directory Exists on D: Drive
    if (-not (Test-Path $Dest)) {
        Write-Host "  Creating destination directory..."
        New-Item -ItemType Directory -Path $Dest -Force | Out-Null
    }

    # 2. Handle Existing Source on C: Drive (if Epic was already installed)
    if (Test-Path $Source) {
        $item = Get-Item $Source -Force
        # Check if it's already a junction
        if ($item.Attributes -match "ReparsePoint") {
            Write-Host "  Junction already exists. Skipping."
            continue
        } else {
            Write-Host "  WARNING: Existing folder found. Moving contents to D: drive..."
            robocopy $Source $Dest /E /MOVE /R:1 /W:1 | Out-Null
            
            # Wait a second to release file locks, then delete the old C: folder
            Start-Sleep -Seconds 1
            Remove-Item $Source -Force -Recurse -ErrorAction SilentlyContinue
        }
    }

    # 3. Create the Directory Junction
    Write-Host "  Creating junction..."
    cmd /c "mklink /J `"$Source`" `"$Dest`""
}

Write-Host ""
Write-Host "Done! Your C drive is protected."
Write-Host "You can now safely run the Epic Games Installer."