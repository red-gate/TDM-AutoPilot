#!/bin/bash
# Make the script executable: chmod +x 00_Install_TDM_CLIs.sh
# 00_Install_TDM_CLIs.sh - Ensures TDM CLI tools are installed if they don't already exist

# ===========================
# File Name: 00_Install_TDM_CLIs.sh
# Version: 1.8.0
# Author: Redgate Software Ltd
# Last Updated: 2025-06-10
# Description: Validate and Install TDM Data Treatment CLIs
# ===========================

# === Configuration ===
# Directory where the CLIs will be installed
TDM_INSTALL_DIR=${TDM_INSTALL_DIR:-"/usr/local/bin"}

# URLs for downloading the CLIs
RGANONYMIZE_URL=${RGANONYMIZE_URL:-"https://download.red-gate.com/EAP/AnonymizeLinux64.zip"}
RGSUBSET_URL=${RGSUBSET_URL:-"https://download.red-gate.com/EAP/SubsetterLinux64.zip"}

# Temporary directory for downloads and extraction
TEMP_DIR=${TEMP_DIR:-"/tmp/tdm_cli_install"}

# Profile file to update PATH
PROFILE_FILE="$HOME/.bashrc"

# === Echo Configuration ===
echo "INFO: Configuration:"
echo "  TDM_INSTALL_DIR: $TDM_INSTALL_DIR"
echo "  RGANONYMIZE_URL: $RGANONYMIZE_URL"
echo "  RGSUBSET_URL: $RGSUBSET_URL"
echo "  TEMP_DIR: $TEMP_DIR"
echo "  PROFILE_FILE: $PROFILE_FILE"

# Ensure the script is run as root or with sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root or with sudo."
    echo "Skipping installation."
    exit 1
fi

# === Ensure Required Tools ===
# Check if `unzip` is installed, and install it if missing
if ! command -v unzip &> /dev/null; then
    echo "INFO: 'unzip' is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y unzip
else
    echo "INFO: 'unzip' is already installed."
fi

# === Helper Functions ===
# Function to add a directory to PATH if not already present
add_to_path() {
    local dir="$1"
    if ! grep -q "$dir" "$PROFILE_FILE"; then
        echo "INFO: Adding $dir to PATH in $PROFILE_FILE..."
        echo "export PATH=\$PATH:$dir" >> "$PROFILE_FILE"
        echo "INFO: Please run 'source $PROFILE_FILE' or restart your shell to apply changes."
    else
        echo "INFO: $dir is already in PATH."
    fi
}

# Function to install a CLI
install_cli() {
    local cli_name=$1
    local cli_url=$2
    local cli_path="$TDM_INSTALL_DIR/$cli_name"

    echo "INFO: Installing $cli_name..."

    mkdir -p "$TEMP_DIR"
    mkdir -p "$TDM_INSTALL_DIR"

    local zip_file="$TEMP_DIR/${cli_name}.zip"
    local extract_dir="$TEMP_DIR/${cli_name}_extracted"
    curl -L -o "$zip_file" "$cli_url"
    unzip -o "$zip_file" -d "$extract_dir"

    local extracted_cli
    extracted_cli=$(find "$extract_dir" -type f -name "$cli_name" -executable)
    if [ -n "$extracted_cli" ]; then
        if sudo mv "$extracted_cli" "$cli_path"; then
            chmod +x "$cli_path"
            echo "INFO: $cli_name installed successfully at $cli_path"
        else
            echo "ERROR: Permission denied while moving $cli_name to $TDM_INSTALL_DIR."
            echo "ERROR: Please run the script with sufficient permissions or check directory permissions."
            rm -rf "$TEMP_DIR"
            exit 1
        fi
    else
        echo "ERROR: Failed to find $cli_name in the extracted files."
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    rm -rf "$TEMP_DIR"
}

# === Main Logic ===
echo "INFO: Checking for required TDM CLI tools..."

# Check for rganonymize
if ! command -v rganonymize &> /dev/null; then
    echo "INFO: rganonymize is not installed. Installing..."
    install_cli "rganonymize" "$RGANONYMIZE_URL"
else
    echo "INFO: rganonymize is already installed and available in PATH."
fi

# Check for rgsubset
if ! command -v rgsubset &> /dev/null; then
    echo "INFO: rgsubset is not installed. Installing..."
    install_cli "rgsubset" "$RGSUBSET_URL"
else
    echo "INFO: rgsubset is already installed and available in PATH."
fi

# Add the install directory to PATH
if ! grep -q "$TDM_INSTALL_DIR" "$PROFILE_FILE"; then
    echo "export PATH=\$PATH:$TDM_INSTALL_DIR" >> "$PROFILE_FILE"
    echo "INFO: Added $TDM_INSTALL_DIR to PATH in $PROFILE_FILE."
    source "$PROFILE_FILE"
fi

# Final verification
if command -v rganonymize &> /dev/null && command -v rgsubset &> /dev/null; then
    echo "INFO: Both rganonymize and rgsubset are installed and available in PATH."
    echo "INFO: TDM CLI installation process completed successfully."
else
    echo "ERROR: One or both CLIs are not available in PATH. Please check the installation."
    exit 1
fi