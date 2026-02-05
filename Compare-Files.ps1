<#
.SYNOPSIS
    Compares the hashes of selected files to see if they are identical.
.DESCRIPTION
    Designed to be run via the "Send To" context menu.
    It takes a list of file paths, calculates SHA256 hashes, and compares them.
#>

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FilePaths
)

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()

# 1. Validation
if ($null -eq $FilePaths -or $FilePaths.Count -lt 2) {
    [System.Windows.Forms.MessageBox]::Show("Please select at least two files to compare.", "Hash Compare", "OK", "Warning")
    exit
}

try {
    # 2. Setup Loading State
    $loadingForm = New-Object System.Windows.Forms.Form
    $loadingForm.Text = "Processing..."
    $loadingForm.Size = New-Object System.Drawing.Size(300, 100)
    $loadingForm.StartPosition = "CenterScreen"
    $loadingForm.FormBorderStyle = "FixedDialog"
    $loadingForm.ControlBox = $false
    
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Calculating hashes for $($FilePaths.Count) files..."
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point(20, 30)
    $loadingForm.Controls.Add($lbl)
    $loadingForm.Show()
    $loadingForm.Refresh()

    # 3. Calculate Hashes
    $results = @()
    $referenceHash = $null
    $allMatch = $true

    foreach ($path in $FilePaths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $hashObj = Get-FileHash -LiteralPath $path -Algorithm SHA256
            $hash = $hashObj.Hash
            
            if ($null -eq $referenceHash) { $referenceHash = $hash }
            elseif ($hash -ne $referenceHash) { $allMatch = $false }

            $results += [PSCustomObject]@{
                File   = [System.IO.Path]::GetFileName($path)
                Status = "Wait"
                Hash   = $hash
                Path   = $path
            }
        }
    }
    $loadingForm.Close()

    # 4. Determine Final Status
    foreach ($r in $results) {
        if ($r.Hash -eq $referenceHash) { $r.Status = "MATCH" }
        else { $r.Status = "MISMATCH" }
    }

    # 5. Show Results
    if ($allMatch) {
        [System.Windows.Forms.MessageBox]::Show("SUCCESS: All files are IDENTICAL.`n`nHash (SHA256):`n$referenceHash", "Hash Compare", "OK", "Information")
    }
    else {
        $msgResult = [System.Windows.Forms.MessageBox]::Show("MISMATCH: The selected files are DIFFERENT.`n`nDo you want to see the details?", "Hash Compare", "YesNo", "Error")
        
        if ($msgResult -eq 'Yes') {
            # Display GridView for detailed inspection
            $results | Select-Object Status, File, Hash, Path | Out-GridView -Title "Hash Comparison Results (SHA256)" -Wait
        }
    }
}
catch {
    [System.Windows.Forms.MessageBox]::Show("Error: $_", "Hash Compare Failed", "OK", "Error")
}