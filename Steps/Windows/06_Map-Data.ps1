# 06_Map-Data.ps1 - Runs mapping using rganonymize

# ===========================
# File Name: 04_Map-Data.ps1
# Version: 1.0.0
# Author: Redgate Software Ltd
# Last Updated: 2025-04-23
# Description: TDM Data Treatment: Create mapping file for masking process
# Last Update Comment:
# ===========================

# === Pull Variables from Environment ===
# These values are typically set by Run-Autopilot.ps1 or passed via CI/CD pipelines.
# Ensure these are set before running manually.

param (
    [switch]$previewOnly  # If set, shows the CLI command but does not run it
)

$output               = $env:output                          # Output directory where logs/results should be saved
$logLevel             = $env:logLevel                        # Log verbosity for the current step (e.g., info, debug, error)

if ($previewOnly) {
    # === CLI Command Preview ===
	Write-Host "> CLI Command Example:" -ForegroundColor Cyan
	Write-Host "  rganonymize map --classification-file=`"$output\classification.json`" --masking-file=`"$output\masking.json`" --log-level=$logLevel" -ForegroundColor Blue  -BackgroundColor Black 
	Write-Host "" 
    return
}

# === Mapping Step ===
Write-Host "Creating masking.json from classification.json in $output" -ForegroundColor DarkCyan

try {
    $mapArgs = @(
        'map'
        "--classification-file=$output\classification.json"
        "--masking-file=$output\masking.json"
        "--log-level=$logLevel"
    )

    & rganonymize @mapArgs | Tee-Object -Variable mapOutput

    if ($LASTEXITCODE -ne 0 -or ($mapOutput -match "ERROR")) {
        throw "rganonymize (Map) failed with exit code $LASTEXITCODE."
    }

    Write-Host "Mapping completed successfully." -ForegroundColor Green
} catch {
    Write-Error "Mapping failed: $_"
    exit 1
}
