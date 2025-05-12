#!/usr/bin/env bash
#
# Network Quality Monitor - Configuration Hot Reload
#
# This module provides functionality to reload configuration files
# without restarting the monitoring process.
#
# Author: Cristian O.
# Version: 1.2.0
#

# Source the config module to access global variables
if [ -f "${SRC_DIR}/utils/config.sh" ]; then
  source "${SRC_DIR}/utils/config.sh"
fi

# Source the config validator
if [ -f "${SRC_DIR}/utils/config_validator.sh" ]; then
  source "${SRC_DIR}/utils/config_validator.sh"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Keep track of config file modification times
CONFIG_LAST_MODIFIED=0
TARGETS_LAST_MODIFIED=0
CONFIG_RELOAD_INTERVAL=5  # Check every 5 seconds

# Get file modification time in seconds
# $1: file path
get_file_mtime() {
  local file="$1"
  local mtime=0
  
  if [ -f "$file" ]; then
    # Different implementations for macOS and Linux
    if [[ "$(uname)" == "Darwin" ]]; then
      mtime=$(stat -f %m "$file" 2>/dev/null || echo "0")
    else
      mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
    fi
  fi
  
  echo "$mtime"
}

# Initialize file modification times
init_config_mtimes() {
  CONFIG_LAST_MODIFIED=$(get_file_mtime "$CONFIG_FILE")
  TARGETS_LAST_MODIFIED=$(get_file_mtime "$TARGETS_FILE")
  
  if [ "$SHOW_DEBUG" = "true" ]; then
    echo -e "${CYAN}Initialized config file modification times:${NC}"
    echo -e "  ${GREEN}$CONFIG_FILE:${NC} $CONFIG_LAST_MODIFIED"
    echo -e "  ${GREEN}$TARGETS_FILE:${NC} $TARGETS_LAST_MODIFIED"
  fi
}

# Check if configuration files have changed
check_config_changed() {
  local config_mtime=$(get_file_mtime "$CONFIG_FILE")
  local targets_mtime=$(get_file_mtime "$TARGETS_FILE")
  local changed=false
  
  if [ "$config_mtime" -gt "$CONFIG_LAST_MODIFIED" ]; then
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo -e "${YELLOW}Config file changed: $CONFIG_FILE${NC}"
      echo -e "  Old mtime: $CONFIG_LAST_MODIFIED"
      echo -e "  New mtime: $config_mtime"
    fi
    changed=true
  fi
  
  if [ "$targets_mtime" -gt "$TARGETS_LAST_MODIFIED" ]; then
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo -e "${YELLOW}Targets file changed: $TARGETS_FILE${NC}"
      echo -e "  Old mtime: $TARGETS_LAST_MODIFIED"
      echo -e "  New mtime: $targets_mtime"
    fi
    changed=true
  fi
  
  if $changed; then
    return 0  # Config changed
  else
    return 1  # No change
  fi
}

# Reload configuration files
reload_config() {
  local old_config_file="$CONFIG_FILE"
  local old_targets_file="$TARGETS_FILE"
  
  echo -e "${CYAN}Reloading configuration files...${NC}"
  
  # Store old values for comparison
  local old_debug_mode="$DEBUG_MODE"
  local old_connectivity_check_enabled="$CONNECTIVITY_CHECK_ENABLED"
  local old_grace_period_seconds="$GRACE_PERIOD_SECONDS"
  local old_slack_enabled="$SLACK_ENABLED"
  
  # Reload config files
  if ! load_config; then
    echo -e "${RED}Failed to reload main configuration file: $CONFIG_FILE${NC}"
    return 1
  fi
  
  if ! load_targets; then
    echo -e "${RED}Failed to reload targets file: $TARGETS_FILE${NC}"
    return 1
  fi
  
  # Load environment overrides
  load_env_overrides
  
  # Validate the new configuration
  if ! validate_all_config; then
    echo -e "${RED}Configuration validation failed, reverting to previous configuration${NC}"
    
    # Restore original files (they're still valid)
    CONFIG_FILE="$old_config_file"
    TARGETS_FILE="$old_targets_file"
    
    # Reload previous config
    load_config
    load_targets
    
    return 1
  fi
  
  # Update modification times
  CONFIG_LAST_MODIFIED=$(get_file_mtime "$CONFIG_FILE")
  TARGETS_LAST_MODIFIED=$(get_file_mtime "$TARGETS_FILE")
  
  # Report changes to major settings
  if [ "$old_debug_mode" != "$DEBUG_MODE" ]; then
    echo -e "${YELLOW}Debug mode changed:${NC} $old_debug_mode -> $DEBUG_MODE"
  fi
  
  if [ "$old_connectivity_check_enabled" != "$CONNECTIVITY_CHECK_ENABLED" ]; then
    echo -e "${YELLOW}Connectivity check enabled changed:${NC} $old_connectivity_check_enabled -> $CONNECTIVITY_CHECK_ENABLED"
  fi
  
  if [ "$old_grace_period_seconds" != "$GRACE_PERIOD_SECONDS" ]; then
    echo -e "${YELLOW}Grace period changed:${NC} $old_grace_period_seconds -> $GRACE_PERIOD_SECONDS seconds"
  fi
  
  if [ "$old_slack_enabled" != "$SLACK_ENABLED" ]; then
    echo -e "${YELLOW}Slack notifications changed:${NC} $old_slack_enabled -> $SLACK_ENABLED"
  fi
  
  # Export updated config variables
  export_config_vars
  
  echo -e "${GREEN}Configuration reloaded successfully${NC}"
  return 0
}

# Main hot reload check function
# This should be called periodically from the main loop
check_and_reload_config() {
  # Only check at specific intervals to reduce filesystem operations
  local now=$(date +%s)
  local last_check=${LAST_CONFIG_CHECK:-0}
  
  if [ $((now - last_check)) -lt "$CONFIG_RELOAD_INTERVAL" ]; then
    return 0
  fi
  
  LAST_CONFIG_CHECK=$now
  
  # Check if config has changed
  if check_config_changed; then
    reload_config
    return $?
  fi
  
  return 0
}

# Send SIGHUP to reload configuration
# This can be used to force a reload from another process
setup_reload_signal_handler() {
  trap reload_config SIGHUP
  
  if [ "$SHOW_DEBUG" = "true" ]; then
    echo -e "${CYAN}Configuration reload signal handler installed${NC}"
    echo -e "  To reload configuration: kill -SIGHUP $BASHPID"
  fi
}

# Initialize hot reload system
init_hot_reload() {
  # Initialize modification times
  init_config_mtimes
  
  # Set up signal handler
  setup_reload_signal_handler
  
  if [ "$SHOW_DEBUG" = "true" ]; then
    echo -e "${GREEN}Hot reload system initialized${NC}"
    echo -e "  Config check interval: ${CONFIG_RELOAD_INTERVAL}s"
  fi
}