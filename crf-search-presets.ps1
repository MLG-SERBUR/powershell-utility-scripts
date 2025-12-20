param (
    [Parameter(Mandatory = $true)]
    [string]$InputFile
)

# Loop through presets 4 to 8
for ($preset = 4; $preset -le 8; $preset++) {
    Write-Host "Running ab-av1 crf-search for preset $preset..."
    ab-av1 crf-search --input "$InputFile" --preset $preset
}
