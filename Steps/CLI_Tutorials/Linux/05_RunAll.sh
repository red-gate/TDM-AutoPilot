#!/bin/bash
# Make the script executable: chmod +x 05_RunAll.sh
# Run_All.sh - Executes all steps in sequence with user confirmation between each step

# ===========================
# File Name: Run_All.sh
# Version: 1.5.0
# Author: Redgate Software Ltd
# Last Updated: 2025-06-10
# Description: Runs all Linux CLI steps (01, 02, 03, 04) in sequence with user confirmation
# ===========================

# Expected working directory
#EXPECTED_DIR="/path/to/Manual_CLI/Linux"
EXPECTED_DIR="/mnt/c/Redgate/GIT/Repos/GitHub/Autopilot/Development/TDM-Autopilot/Steps/Manual_CLI/Linux"

# Ensure the script is running in the correct directory
if [ "$PWD" != "$EXPECTED_DIR" ]; then
    echo "WARNING: You are not in the expected working directory."
    echo "Current directory: $PWD"
    echo "Expected directory: $EXPECTED_DIR"
    echo "Do you want to change to the expected directory? (Y/N)"
    read -r change_dir
    change_dir=${change_dir:-Y} # Default to Y if no input is given
    if [ "$change_dir" = "Y" ] || [ "$change_dir" = "y" ]; then
        cd "$EXPECTED_DIR" || { echo "ERROR: Failed to change to $EXPECTED_DIR. Exiting."; exit 1; }
        echo "Changed to directory: $EXPECTED_DIR"
    else
        echo "ERROR: Script cannot proceed without being in the correct directory. Exiting."
        exit 1
    fi
fi

echo "Starting Run_All.sh..."

# Step 1
echo "Do you want to run step: 01_Install_TDMCLIs.sh? (Y/N)"
read -r input
input=${input:-Y} # Default to Y if no input is given
if [ "$input" = "Y" ] || [ "$input" = "y" ]; then
    echo "Running step: 01_Install_TDMCLIs.sh"
    sudo -E bash 00_Install_TDM_CLIs.sh
    if [ $? -ne 0 ]; then
        echo "ERROR: Step 01_Install_TDMCLIs.sh failed."
        exit 1
    fi
    echo "Step 01_Install_TDMCLIs.sh completed."
else
    echo "Skipping step: 01_Install_TDMCLIs.sh"
fi

# Step 1
echo "Do you want to run step: Subset? (Y/N)"
read -r input
input=${input:-Y} # Default to Y if no input is given
if [ "$input" = "Y" ] || [ "$input" = "y" ]; then
    echo "Running step: 01_rgsubset.sh"
    bash 01_rgsubset.sh
    if [ $? -ne 0 ]; then
        echo "ERROR: Step 01_rgsubset.sh failed."
        exit 1
    fi
    echo "Step 01_rgsubset.sh completed."
else
    echo "Skipping step: 01_rgsubset.sh"
fi

# Step 2
echo "Do you want to run step: Classify? (Y/N)"
read -r input
input=${input:-Y} # Default to Y if no input is given
if [ "$input" = "Y" ] || [ "$input" = "y" ]; then
    echo "Running step: 02_rganonymize_classify.sh"
    bash 02_rganonymize_classify.sh
    if [ $? -ne 0 ]; then
        echo "ERROR: Step 02_rganonymize_classify.sh failed."
        exit 1
    fi
    echo "Step 02_rganonymize_classify.sh completed."
else
    echo "Skipping step: 02_rganonymize_classify.sh"
fi

# Step 3
echo "Do you want to run step: Map? (Y/N)"
read -r input
input=${input:-Y} # Default to Y if no input is given
if [ "$input" = "Y" ] || [ "$input" = "y" ]; then
    echo "Running step: 03_rganonymize_map.sh"
    bash 03_rganonymize_map.sh
    if [ $? -ne 0 ]; then
        echo "ERROR: Step 03_rganonymize_map.sh failed."
        exit 1
    fi
    echo "Step 03_rganonymize_map.sh completed."
else
    echo "Skipping step: 03_rganonymize_map.sh"
fi

# Step 4
echo "Do you want to run step: Mask? (Y/N)"
read -r input
input=${input:-Y} # Default to Y if no input is given
if [ "$input" = "Y" ] || [ "$input" = "y" ]; then
    echo "Running step: 04_rganonymize_mask.sh"
    bash 04_rganonymize_mask.sh
    if [ $? -ne 0 ]; then
        echo "ERROR: Step 04_rganonymize_mask.sh failed."
        exit 1
    fi
    echo "Step 04_rganonymize_mask.sh completed."
else
    echo "Skipping step: 04_rganonymize_mask.sh"
fi

echo "All steps completed successfully!"