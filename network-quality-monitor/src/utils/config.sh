#!/usr/bin/env bash
#
# Network Quality Monitor - Configuration Management Module
#
# This module provides functions to load, validate, and access configuration
# settings throughout the application.
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

# Default configuration paths
CONFIG_FILE="${CONFIG_DIR}/config.json"
TARGETS_FILE="${CONFIG_DIR}/targets.json"

# Global configuration variables with defaults
GRACE_PERIOD_SECONDS=30
DEBUG_MODE=false
CONFIG_LOADED=false

# Load main configuration file
# Returns: 0 on success, 1 on failure
load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Configuration file $CONFIG_FILE does not exist.${NC}" >&2
    return 1
  fi

  # Validate JSON
  if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo -e "${RED}Error: Invalid JSON in configuration file $CONFIG_FILE${NC}" >&2
    return 1
  fi

  # Load global settings
  DEBUG_MODE=$(jq -r '.general.debug_mode // false' "$CONFIG_FILE")
  LOG_LEVEL=$(jq -r '.general.log_level // "info"' "$CONFIG_FILE")
  LOG_DIRECTORY=$(jq -r '.general.log_directory // "logs"' "$CONFIG_FILE")
  LOG_RETENTION_DAYS=$(jq -r '.general.log_retention_days // 7' "$CONFIG_FILE")

  # Create log directory if it doesn't exist
  mkdir -p "${BASE_DIR}/${LOG_DIRECTORY}" 2>/dev/null

  # Load connectivity check settings
  CONNECTIVITY_CHECK_ENABLED=$(jq -r '.connectivity.enabled // true' "$CONFIG_FILE")
  CONNECTIVITY_CHECK_INTERVAL=$(jq -r '.connectivity.check_interval // 30' "$CONFIG_FILE")

  # Load grace period settings
  GRACE_PERIOD_SECONDS=$(jq -r '.connectivity.recovery.grace_period_seconds // 30' "$CONFIG_FILE")
  RESET_STATS_ON_RECOVERY=$(jq -r '.connectivity.recovery.reset_statistics_on_recovery // true' "$CONFIG_FILE")

  # Load connectivity servers
  mapfile -t CONNECTIVITY_CHECK_SERVERS < <(jq -r '.connectivity.servers[].host' "$CONFIG_FILE" 2>/dev/null)

  # If no servers were found, use default ones
  if [ ${#CONNECTIVITY_CHECK_SERVERS[@]} -eq 0 ]; then
    CONNECTIVITY_CHECK_SERVERS=("1.1.1.1" "8.8.8.8" "9.9.9.9")
  fi

  # Load notification settings
  NOTIFICATION_QUEUE_ENABLED=$(jq -r '.notifications.queue.enabled // true' "$CONFIG_FILE")
  NOTIFICATION_QUEUE_DIR=$(jq -r '.notifications.queue.directory // "/tmp/network_monitor_alerts"' "$CONFIG_FILE")
  NOTIFICATION_QUEUE_MAX_AGE=$(jq -r '.notifications.queue.max_age_hours // 24' "$CONFIG_FILE")

  # Load alerting settings
  HOST_DOWN_ALERT_ENABLED=$(jq -r '.notifications.event_handlers.host_down.enabled // true' "$CONFIG_FILE")
  HOST_DOWN_RETRY_INTERVAL=$(jq -r '.notifications.event_handlers.host_down.retry_interval_seconds // 300' "$CONFIG_FILE")
  HOST_DOWN_MAX_ALERTS=$(jq -r '.notifications.event_handlers.host_down.max_alerts_per_hour // 5' "$CONFIG_FILE")

  LOSS_ALERT_ENABLED=$(jq -r '.notifications.event_handlers.loss_alert.enabled // true' "$CONFIG_FILE")
  LOSS_ALERT_RETRY_INTERVAL=$(jq -r '.notifications.event_handlers.loss_alert.retry_interval_seconds // 600' "$CONFIG_FILE")
  LOSS_ALERT_MAX_ALERTS=$(jq -r '.notifications.event_handlers.loss_alert.max_alerts_per_hour // 3' "$CONFIG_FILE")

  RECOVERY_ALERT_ENABLED=$(jq -r '.notifications.event_handlers.recovery.enabled // true' "$CONFIG_FILE")

  # Load display settings
  COLORS_ENABLED=$(jq -r '.display.colors.enabled // true' "$CONFIG_FILE")
  COMPACT_MODE=$(jq -r '.display.console.compact_mode // false' "$CONFIG_FILE")
  SHOW_ALERTS_ONLY=$(jq -r '.display.console.show_alerts_only // false' "$CONFIG_FILE")

  # Load color thresholds
  RTT_GOOD_THRESHOLD=$(jq -r '.display.colors.rtt.good_threshold_ms // 80' "$CONFIG_FILE")
  RTT_WARNING_THRESHOLD=$(jq -r '.display.colors.rtt.warning_threshold_ms // 150' "$CONFIG_FILE")

  JITTER_GOOD_THRESHOLD=$(jq -r '.display.colors.jitter.good_threshold_ms // 10' "$CONFIG_FILE")
  JITTER_WARNING_THRESHOLD=$(jq -r '.display.colors.jitter.warning_threshold_ms // 30' "$CONFIG_FILE")

  TTL_WARNING_THRESHOLD=$(jq -r '.display.colors.ttl.warning_threshold // 64' "$CONFIG_FILE")
  TTL_CRITICAL_THRESHOLD=$(jq -r '.display.colors.ttl.critical_threshold // 32' "$CONFIG_FILE")

  # Load UI indicators
  UP_INDICATOR=$(jq -r '.display.console.indicators.up // "✅"' "$CONFIG_FILE")
  DOWN_INDICATOR=$(jq -r '.display.console.indicators.down // "🛑"' "$CONFIG_FILE")
  WARNING_INDICATOR=$(jq -r '.display.console.indicators.warning // "⚠️"' "$CONFIG_FILE")
  RECOVERY_INDICATOR=$(jq -r '.display.console.indicators.recovery // "⚡"' "$CONFIG_FILE")
  LOSS_INDICATOR=$(jq -r '.display.console.indicators.loss // "📉"' "$CONFIG_FILE")

  # Load Slack integration settings
  SLACK_ENABLED=$(jq -r '.integrations.slack.enabled // false' "$CONFIG_FILE")
  SLACK_WEBHOOK_URL=$(jq -r '.integrations.slack.webhook_url // ""' "$CONFIG_FILE")
  SLACK_DEFAULT_CHANNEL=$(jq -r '.integrations.slack.default_channel // "#network-alerts"' "$CONFIG_FILE")
  SLACK_RETRIES=$(jq -r '.integrations.slack.retries // 3' "$CONFIG_FILE")
  SLACK_RETRY_DELAY=$(jq -r '.integrations.slack.retry_delay_seconds // 1' "$CONFIG_FILE")
  SLACK_TIMEOUT=$(jq -r '.integrations.slack.timeout_seconds // 15' "$CONFIG_FILE")

  # Export relevant variables to be used by other modules
  export DEBUG_MODE LOG_LEVEL LOG_DIRECTORY LOG_RETENTION_DAYS
  export CONNECTIVITY_CHECK_ENABLED CONNECTIVITY_CHECK_INTERVAL
  export GRACE_PERIOD_SECONDS RESET_STATS_ON_RECOVERY CONNECTIVITY_CHECK_SERVERS
  export NOTIFICATION_QUEUE_ENABLED NOTIFICATION_QUEUE_DIR NOTIFICATION_QUEUE_MAX_AGE
  export HOST_DOWN_ALERT_ENABLED HOST_DOWN_RETRY_INTERVAL HOST_DOWN_MAX_ALERTS
  export LOSS_ALERT_ENABLED LOSS_ALERT_RETRY_INTERVAL LOSS_ALERT_MAX_ALERTS
  export RECOVERY_ALERT_ENABLED
  export COLORS_ENABLED COMPACT_MODE SHOW_ALERTS_ONLY
  export RTT_GOOD_THRESHOLD RTT_WARNING_THRESHOLD
  export JITTER_GOOD_THRESHOLD JITTER_WARNING_THRESHOLD
  export TTL_WARNING_THRESHOLD TTL_CRITICAL_THRESHOLD
  export UP_INDICATOR DOWN_INDICATOR WARNING_INDICATOR RECOVERY_INDICATOR LOSS_INDICATOR
  export SLACK_ENABLED SLACK_WEBHOOK_URL SLACK_DEFAULT_CHANNEL
  export SLACK_RETRIES SLACK_RETRY_DELAY SLACK_TIMEOUT

  # Set the loaded flag
  CONFIG_LOADED=true

  if [ "$DEBUG_MODE" = "true" ] || [ "$SHOW_DEBUG" = "true" ]; then
    echo -e "${GREEN}Configuration loaded successfully${NC}"
    echo -e "  ${CYAN}Debug Mode:${NC} $DEBUG_MODE"
    echo -e "  ${CYAN}Log Level:${NC} $LOG_LEVEL"
    echo -e "  ${CYAN}Connectivity Check:${NC} $CONNECTIVITY_CHECK_ENABLED (Interval: ${CONNECTIVITY_CHECK_INTERVAL}s)"
    echo -e "  ${CYAN}Grace Period:${NC} ${GRACE_PERIOD_SECONDS}s"
    echo -e "  ${CYAN}Connectivity Servers:${NC} ${CONNECTIVITY_CHECK_SERVERS[*]}"
  fi

  return 0
}

# Load targets configuration file
# Returns: 0 on success, 1 on failure
load_targets() {
  if [ ! -f "$TARGETS_FILE" ]; then
    echo -e "${RED}Error: Targets file $TARGETS_FILE does not exist.${NC}" >&2
    return 1
  fi
  
  # Validate JSON
  if ! jq empty "$TARGETS_FILE" 2>/dev/null; then
    echo -e "${RED}Error: Invalid JSON in targets file $TARGETS_FILE${NC}" >&2
    return 1
  fi
  
  if [ "$DEBUG_MODE" = "true" ] || [ "$SHOW_DEBUG" = "true" ]; then
    # Count number of targets
    local target_count
    target_count=$(jq '.targets | length' "$TARGETS_FILE")
    
    # Count number of target groups
    local group_count
    group_count=$(jq '.target_groups | length // 0' "$TARGETS_FILE")
    
    echo -e "${GREEN}Targets configuration loaded successfully${NC}"
    echo -e "  ${CYAN}Targets:${NC} $target_count"
    echo -e "  ${CYAN}Target Groups:${NC} $group_count"
  fi
  
  return 0
}

# Validate both configuration files
# Returns: 0 if both files are valid, 1 otherwise
validate_configuration() {
  local valid=true
  
  # Check if config file exists and is valid JSON
  if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Configuration file $CONFIG_FILE does not exist.${NC}" >&2
    valid=false
  elif ! jq empty "$CONFIG_FILE" 2>/dev/null; then
    echo -e "${RED}Error: Invalid JSON in configuration file $CONFIG_FILE${NC}" >&2
    valid=false
  fi
  
  # Check if targets file exists and is valid JSON
  if [ ! -f "$TARGETS_FILE" ]; then
    echo -e "${RED}Error: Targets file $TARGETS_FILE does not exist.${NC}" >&2
    valid=false
  elif ! jq empty "$TARGETS_FILE" 2>/dev/null; then
    echo -e "${RED}Error: Invalid JSON in targets file $TARGETS_FILE${NC}" >&2
    valid=false
  fi
  
  # Validate specific required fields in config.json
  if [ -f "$CONFIG_FILE" ] && jq empty "$CONFIG_FILE" 2>/dev/null; then
    # Check if connectivity servers is an array
    if ! jq -e '.connectivity.servers | type == "array"' "$CONFIG_FILE" >/dev/null 2>&1; then
      echo -e "${YELLOW}Warning: connectivity.servers should be an array in $CONFIG_FILE${NC}" >&2
    fi
    
    # Check if connectivity.recovery exists
    if ! jq -e '.connectivity.recovery' "$CONFIG_FILE" >/dev/null 2>&1; then
      echo -e "${YELLOW}Warning: connectivity.recovery section is missing in $CONFIG_FILE${NC}" >&2
    fi
  fi
  
  # Validate specific required fields in targets.json
  if [ -f "$TARGETS_FILE" ] && jq empty "$TARGETS_FILE" 2>/dev/null; then
    # Check if targets is an array
    if ! jq -e '.targets | type == "array"' "$TARGETS_FILE" >/dev/null 2>&1; then
      echo -e "${RED}Error: targets should be an array in $TARGETS_FILE${NC}" >&2
      valid=false
    else
      # Check if there's at least one target
      if [ "$(jq '.targets | length' "$TARGETS_FILE")" -eq 0 ]; then
        echo -e "${RED}Error: No targets defined in $TARGETS_FILE${NC}" >&2
        valid=false
      fi
      
      # Validate each target has required fields
      local missing_fields
      missing_fields=$(jq -r '.targets[] | select(.ip == null or .monitoring == null) | .id // .name // "Unknown target"' "$TARGETS_FILE")
      
      if [ -n "$missing_fields" ]; then
        echo -e "${RED}Error: The following targets are missing required fields (ip, monitoring):${NC}" >&2
        echo "$missing_fields" | while read -r target; do
          echo -e "  ${YELLOW}- $target${NC}" >&2
        done
        valid=false
      fi
    fi
  fi
  
  if [ "$valid" = "true" ]; then
    return 0
  else
    return 1
  fi
}