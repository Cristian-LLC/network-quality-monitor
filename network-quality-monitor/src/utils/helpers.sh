#!/usr/bin/env bash
#
# Network Quality Monitor - Helper Functions
#
# This module provides utility functions for the Network Quality Monitor.
#
# Author: Cristian O.
# Version: 1.2.0
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check required dependencies for script execution
# Verifies presence of required utilities (fping, jq, bc) and correct configuration
# Displays error messages and installation suggestions if components are missing
check_dependencies() {
  local tools=("jq" "bc")

  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo -e "${RED}Error: $tool is missing. Install it with: brew install $tool${NC}"
      exit 1
    fi
  done

  # Check if fping is available
  if command -v "fping" >/dev/null 2>&1; then
    echo -e "${GREEN}Info: fping detected${NC}"

    # Get fping version for diagnostic purposes
    local FPING_VERSION
    FPING_VERSION=$(fping -v 2>&1 | head -n1 | sed 's/.*version \([0-9.]*\).*/\1/')
    echo -e "${GREEN}fping version: ${FPING_VERSION}${NC}"

    # Check if fping version supports the --print-ttl option
    if ! fping --help 2>&1 | grep -q "\-\-print-ttl"; then
      echo -e "${YELLOW}Warning: Your fping version doesn't support the --print-ttl option. Some statistics may be limited.${NC}"
    fi
  else
    echo -e "${RED}Error: fping is missing. This script requires fping.${NC}"
    echo -e "${RED}Install fping with: brew install fping (MacOS) or apt install fping (Linux)${NC}"
    exit 1
  fi

  # Check if the targets.json file exists
  if [ ! -f "$TARGET_FILE" ]; then
    echo -e "${RED}Error: File $TARGET_FILE does not exist.${NC}"
    echo -e "${YELLOW}Create a targets.json file with the following structure:${NC}"
    echo -e '{
  "config": {
    "connectivity_check": {
      "enabled": true,
      "check_interval": 30,
      "servers": ["1.1.1.1", "8.8.8.8", "9.9.9.9"]
    }
  },
  "targets": [
    {
      "ip": "1.1.1.1",
      "ping_frequency": 1,
      "consecutive_loss_threshold": 2,
      "loss_threshold_pct": 10,
      "report_interval": 10
    }
  ]
}'
    exit 1
  fi

  # Check JSON file structure
  if ! jq empty "$TARGET_FILE" 2>/dev/null; then
    echo -e "${RED}Error: File $TARGET_FILE does not contain valid JSON.${NC}"
    exit 1
  fi
}