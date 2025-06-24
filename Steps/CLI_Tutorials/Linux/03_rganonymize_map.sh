#!/bin/bash

# Map data using rganonymize
# This script demonstrates how to run the rganonymize CLI command with example values.
# For more details, visit: https://documentation.red-gate.com/testdatamanager
#
# Key Options:
#   --classification-file: Path to the JSON file containing classification rules.
#   --masking-file: Path to the JSON file where masking rules will be generated.

# Example Offline Licensing https://documentation.red-gate.com/testdatamanager/getting-started/licensing/activating-your-license # 
#REDGATE_LICENSING_PAT_EMAIL=""
#REDGATE_LICENSING_PAT_TOKEN=""

# Example values
CLASSIFICATION_FILE="../classification.json"
MASKING_FILE="../masking.json"
LOG_LEVEL="Verbose"

echo "Running mapping from classification file to masking file"

rganonymize map \
  --classification-file "$CLASSIFICATION_FILE" \
  --masking-file "$MASKING_FILE" \
  --log-level "$LOG_LEVEL"