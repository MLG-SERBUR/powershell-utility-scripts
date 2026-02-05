# Install-Context.ps1
# This creates a "Send To" shortcut pointing to your existing Compare-Files.ps1 script.

$ErrorActionPreference = "Stop"
$scriptName = "Compare-Files.ps1"

# 1. Locate the Worker Script
# Assumes the worker script is in the same directory as this installer.
$currentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$workerScriptPath = Join-Path -Path $currentDir -ChildPath $scriptName

# If not found automatically, ask user to find it.
if (-not (Test-Path $workerScriptPath)) {
    Write-Host "Could not find '$scriptName' in the current folder." -ForegroundColor Yellow
    Add-Type -AssemblyName System.Windows.Forms
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Title = "Select the Compare-Files.ps1 script"
    $openFileDialog.Filter = "PowerShell Script (*.ps1)|*.ps1"
    
    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $workerScriptPath = $openFileDialog.FileName
    } else {
        Write-Error "Installation cancelled. Script not selected."
    }
}

# 2. Create the Shortcut in SendTo
$sendToFolder = [System.Environment]::GetFolderPath('SendTo')
$shortcutPath = Join-Path -Path $sendToFolder -ChildPath "Compare Hashes.lnk"
$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)

# Target: PowerShell.exe
$shortcut.TargetPath = "powershell.exe"

# Arguments: -File "Path\To\Script"
# We use -WindowStyle Hidden so the console doesn't flash annoyingly.
$shortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$workerScriptPath`""

# Icon: Uses a generic checkmark-style icon from system DLLs
$shortcut.IconLocation = "shell32.dll,238" 

$shortcut.Save()

Write-Host "Success! Installed to: $shortcutPath" -ForegroundColor Green
Write-Host "Target Script: $workerScriptPath"
Write-Host "`nTo use: Select multiple files > Right-Click > Send To > Compare Hashes" -ForegroundColor Cyan
Read-Host "Press Enter to exit"