#!/usr/bin/env bash
#
# Network Quality Monitor - Setup Script
#
# This script sets up the Network Quality Monitor environment and verifies
# that all required dependencies are available.
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

# Determine base directory (where the script is located)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Print header
echo -e "${CYAN}=========================================================${NC}"
echo -e "${GREEN}Network Quality Monitor - Setup${NC}"
echo -e "${CYAN}=========================================================${NC}"

# Check for required dependencies
check_dependency() {
  local cmd="$1"
  local install_command="$2"
  
  echo -ne "Checking for ${CYAN}$cmd${NC}... "
  if command -v "$cmd" >/dev/null 2>&1; then
    echo -e "${GREEN}Found${NC}"
    return 0
  else
    echo -e "${RED}Not found${NC}"
    echo -e "  ${YELLOW}Please install using:${NC} $install_command"
    return 1
  fi
}

# Check required directories
check_directories() {
  local missing_dirs=()
  
  echo -e "Checking directory structure..."
  
  # Essential directories that must exist
  local required_dirs=(
    "$BASE_DIR/src"
    "$BASE_DIR/src/core"
    "$BASE_DIR/src/utils"
    "$BASE_DIR/src/notifications"
    "$BASE_DIR/src/notifications/handlers"
    "$BASE_DIR/config"
    "$BASE_DIR/bin"
  )
  
  for dir in "${required_dirs[@]}"; do
    if [ ! -d "$dir" ]; then
      missing_dirs+=("$dir")
    fi
  done
  
  if [ ${#missing_dirs[@]} -eq 0 ]; then
    echo -e "${GREEN}All required directories exist${NC}"
    return 0
  else
    echo -e "${RED}Missing required directories:${NC}"
    for dir in "${missing_dirs[@]}"; do
      echo -e "  ${YELLOW}$dir${NC}"
    done
    
    echo -e "Creating missing directories..."
    for dir in "${missing_dirs[@]}"; do
      mkdir -p "$dir"
      echo -e "  ${GREEN}Created:${NC} $dir"
    done
    
    return 0
  fi
}

# Check required files
check_required_files() {
  local missing_files=()
  
  echo -e "Checking core files..."
  
  # Essential files that must exist
  local required_files=(
    "$BASE_DIR/bin/netmon"
    "$BASE_DIR/config/targets.json"
    "$BASE_DIR/src/core/monitor.sh"
    "$BASE_DIR/src/core/metrics.sh"
    "$BASE_DIR/src/utils/helpers.sh"
    "$BASE_DIR/src/utils/connectivity.sh"
    "$BASE_DIR/src/notifications/queue.sh"
    "$BASE_DIR/src/notifications/handlers/hooks.sh"
  )
  
  for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
      missing_files+=("$file")
    fi
  done
  
  if [ ${#missing_files[@]} -eq 0 ]; then
    echo -e "${GREEN}All required files exist${NC}"
    return 0
  else
    echo -e "${RED}Missing required files:${NC}"
    for file in "${missing_files[@]}"; do
      echo -e "  ${YELLOW}$file${NC}"
    done
    return 1
  fi
}

# Set executable permissions
set_permissions() {
  echo -e "Setting executable permissions..."
  
  # Find all shell scripts and make them executable
  find "$BASE_DIR/bin" "$BASE_DIR/src" "$BASE_DIR/tests" "$BASE_DIR/tools" -name "*.sh" -type f -exec chmod +x {} \;
  chmod +x "$BASE_DIR/bin/netmon"
  
  echo -e "${GREEN}Executable permissions set${NC}"
}

# Create template files if needed
create_template_files() {
  # Check if config files exist, if not, create templates
  if [ ! -f "$BASE_DIR/config/targets.json" ]; then
    echo -e "Creating template targets.json file..."
    cat > "$BASE_DIR/config/targets.json" << EOF
{
  "config": {
    "connectivity_check": {
      "enabled": true,
      "check_interval": 1,
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
    },
    {
      "ip": "8.8.8.8",
      "ping_frequency": 1,
      "consecutive_loss_threshold": 3,
      "loss_threshold_pct": 5,
      "report_interval": 15
    }
  ]
}
EOF
    echo -e "${GREEN}Created template targets.json${NC}"
  fi
  
  if [ ! -f "$BASE_DIR/config/notifications.json" ]; then
    echo -e "Creating template notifications.json file..."
    cat > "$BASE_DIR/config/notifications.json" << EOF
{
  "slack": {
    "enabled": false,
    "webhook_url": "https://hooks.slack.com/services/REPLACE_WITH_YOUR_WEBHOOK_URL",
    "default_channel": "#network-alerts",
    "notifications": {
      "host_down": {
        "channel": "#network-alerts"
      },
      "loss_alert": {
        "channel": "#network-warnings"
      },
      "recovery": {
        "channel": "#network-alerts"
      }
    }
  }
}
EOF
    echo -e "${GREEN}Created template notifications.json${NC}"
  fi
}

# Main function
main() {
  local has_errors=false
  
  # Check dependencies
  echo -e "${CYAN}Checking dependencies...${NC}"
  
  # Detect OS for appropriate install commands
  if [[ "$(uname)" == "Darwin" ]]; then
    check_dependency "fping" "brew install fping" || has_errors=true
    check_dependency "jq" "brew install jq" || has_errors=true
    check_dependency "bc" "brew install bc" || has_errors=true
  elif [[ "$(uname)" == "Linux" ]]; then
    # Check for different package managers
    if command -v apt-get >/dev/null 2>&1; then
      check_dependency "fping" "sudo apt-get install fping" || has_errors=true
      check_dependency "jq" "sudo apt-get install jq" || has_errors=true
      check_dependency "bc" "sudo apt-get install bc" || has_errors=true
    elif command -v yum >/dev/null 2>&1; then
      check_dependency "fping" "sudo yum install fping" || has_errors=true
      check_dependency "jq" "sudo yum install jq" || has_errors=true
      check_dependency "bc" "sudo yum install bc" || has_errors=true
    else
      check_dependency "fping" "Install fping using your distribution's package manager" || has_errors=true
      check_dependency "jq" "Install jq using your distribution's package manager" || has_errors=true
      check_dependency "bc" "Install bc using your distribution's package manager" || has_errors=true
    fi
  else
    echo -e "${RED}Unsupported operating system: $(uname)${NC}"
    echo -e "${RED}This setup script supports macOS and Linux only${NC}"
    exit 1
  fi
  
  echo ""
  
  # Check for optional tools
  echo -e "${CYAN}Checking optional dependencies...${NC}"
  check_dependency "curl" "Install for enhanced connectivity checking and Slack notifications"
  check_dependency "dig" "Install for enhanced DNS connectivity checking"
  check_dependency "host" "Install for enhanced DNS connectivity checking"
  check_dependency "timeout" "Install for limiting operation time on slow connections"
  
  echo ""
  
  # Check directory structure
  check_directories
  echo ""
  
  # Create template files if needed
  create_template_files
  echo ""
  
  # Check required files
  check_required_files || has_errors=true
  echo ""
  
  # Set permissions
  set_permissions
  echo ""
  
  # Final status
  if [ "$has_errors" = "true" ]; then
    echo -e "${YELLOW}Setup completed with warnings. Please address the issues above.${NC}"
    return 1
  else
    echo -e "${GREEN}Setup completed successfully!${NC}"
    echo -e "${CYAN}You can now run the monitor using:${NC}"
    echo -e "  ${GREEN}$BASE_DIR/bin/netmon${NC}"
    return 0
  fi
}

# Run main function
main