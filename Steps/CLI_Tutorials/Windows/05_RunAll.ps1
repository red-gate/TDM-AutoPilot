# Run_All.ps1 - Executes all steps in sequence with user confirmation between each step

# ===========================
# File Name: Run_All.ps1
# Version: 1.2.0
# Author: Redgate Software Ltd
# Last Updated: 2025-06-10
# Description: Runs all Windows CLI steps (01, 02, 03, 04) in sequence with user confirmation
# ===========================

Write-Host "Starting Run_All.ps1..." -ForegroundColor Green

# Step 1
Write-Host "Do you want to run step: 01_rgsubset.ps1? (Y/N)" -ForegroundColor Yellow
$input = Read-Host
if ($input -eq "Y" -or $input -eq "y") {
    Write-Host "Running step: 01_rgsubset.ps1" -ForegroundColor Cyan
    .\01_rgsubset.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Step 01_rgsubset.ps1 failed with exit code $LASTEXITCODE." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "Step 01_rgsubset.ps1 completed." -ForegroundColor Green
} else {
    Write-Host "Skipping step: 01_rgsubset.ps1" -ForegroundColor Yellow
}

# Step 2
Write-Host "Do you want to run step: 02_rganonymize_classify.ps1? (Y/N)" -ForegroundColor Yellow
$input = Read-Host
if ($input -eq "Y" -or $input -eq "y") {
    Write-Host "Running step: 02_rganonymize_classify.ps1" -ForegroundColor Cyan
    .\02_rganonymize_classify.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Step 02_rganonymize_classify.ps1 failed with exit code $LASTEXITCODE." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "Step 02_rganonymize_classify.ps1 completed." -ForegroundColor Green
} else {
    Write-Host "Skipping step: 02_rganonymize_classify.ps1" -ForegroundColor Yellow
}

# Step 3
Write-Host "Do you want to run step: 03_rganonymize_map.ps1? (Y/N)" -ForegroundColor Yellow
$input = Read-Host
if ($input -eq "Y" -or $input -eq "y") {
    Write-Host "Running step: 03_rganonymize_map.ps1" -ForegroundColor Cyan
    .\03_rganonymize_map.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Step 03_rganonymize_map.ps1 failed with exit code $LASTEXITCODE." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "Step 03_rganonymize_map.ps1 completed." -ForegroundColor Green
} else {
    Write-Host "Skipping step: 03_rganonymize_map.ps1" -ForegroundColor Yellow
}

# Step 4
Write-Host "Do you want to run step: 04_rganonymize_mask.ps1? (Y/N)" -ForegroundColor Yellow
$input = Read-Host
if ($input -eq "Y" -or $input -eq "y") {
    Write-Host "Running step: 04_rganonymize_mask.ps1" -ForegroundColor Cyan
    .\04_rganonymize_mask.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Step 04_rganonymize_mask.ps1 failed with exit code $LASTEXITCODE." -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "Step 04_rganonymize_mask.ps1 completed." -ForegroundColor Green
} else {
    Write-Host "Skipping step: 04_rganonymize_mask.ps1" -ForegroundColor Yellow
}

Write-Host "All steps completed successfully!" -ForegroundColor Green