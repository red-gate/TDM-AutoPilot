# 05_Classify-Data.ps1 - Runs classification using rganonymize

# ===========================
# File Name: 04_Classify-Data.ps1
# Version: 1.0.0
# Author: Redgate Software Ltd
# Last Updated: 2025-04-23
# Description: TDM Data Treatment: Classify target database
# Last Update Comment:
# ===========================

# === Pull Variables from Environment ===
# These values are expected to be set by the main Run-Autopilot.ps1 script or provided via environment variables
# Useful when running this step manually or in a CI/CD pipeline

param (
    [switch]$previewOnly  # If set, shows the CLI command but does not run it
)

$targetConnectionString = $env:targetConnectionString          # Full connection string to the target database
$output                 = $env:output                          # Output directory for classification/mapping results
$logLevel               = $env:logLevel                        # Log level for rganonymize (e.g., info, debug, error)

# === Build real args ===
$rganonymizeArgs = @(
    'classify'
    '--database-engine=sqlserver'
    "--connection-string=$targetConnectionString"
    "--classification-file=$output\classification.json"
    '--output-all-columns'
    "--log-level=$logLevel"
)

# === Redact password in preview ===
$previewArgs = $rganonymizeArgs.ForEach({
    if ($_ -like "--connection-string=*") {
        return ($_ -replace '(?i)(Password|Pwd)=.*?(;|$)', '${1}=[REDACTED]$2')
    }
    return $_
})

if ($previewOnly) {
	Write-Host "`n> CLI Command Example:" -ForegroundColor Cyan
	Write-Host "  rganonymize $($previewArgs -join ' ')" -ForegroundColor Blue  -BackgroundColor Black 
	Write-Host ""
    return
}

Write-Host "Creating classification.json in $output" -ForegroundColor DarkCyan

# === Execute the real command ===
try {
    & rganonymize @rganonymizeArgs | Tee-Object -Variable classifyOutput

    if ($LASTEXITCODE -ne 0 -or ($classifyOutput -match "ERROR")) {
        throw "rganonymize (Classify) failed with exit code $LASTEXITCODE."
    }

    Write-Host "Classification completed successfully." -ForegroundColor Green
} catch {
    Write-Error "Classification failed: $_"
    exit 1
}
