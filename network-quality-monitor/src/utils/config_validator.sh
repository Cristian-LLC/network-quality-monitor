#!/usr/bin/env bash
#
# Network Quality Monitor - Configuration Validator
#
# This module provides advanced validation for configuration files
# to ensure all values are within expected ranges and format.
#
# Author: Cristian O.
# Version: 1.2.0
#

# Source the config module to access global variables
if [ -f "${SRC_DIR}/utils/config.sh" ]; then
  source "${SRC_DIR}/utils/config.sh"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Error collection array
declare -a CONFIG_ERRORS=()
declare -a CONFIG_WARNINGS=()

# Validate numeric value is within range
# $1: variable name (for error message)
# $2: actual value
# $3: minimum value
# $4: maximum value
# $5: optional - "required" if the value is required
validate_numeric_range() {
  local var_name="$1"
  local value="$2"
  local min="$3"
  local max="$4"
  local required="${5:-optional}"
  
  # Check if value is empty and required
  if [ -z "$value" ] && [ "$required" = "required" ]; then
    CONFIG_ERRORS+=("Required config value '$var_name' is missing")
    return 1
  elif [ -z "$value" ]; then
    # Empty but optional is fine
    return 0
  fi
  
  # Check if value is numeric
  if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    CONFIG_ERRORS+=("Config value '$var_name' must be numeric, got '$value'")
    return 1
  fi
  
  # Check minimum value
  if (( $(echo "$value < $min" | bc -l) )); then
    CONFIG_ERRORS+=("Config value '$var_name' must be at least $min, got '$value'")
    return 1
  fi
  
  # Check maximum value
  if (( $(echo "$value > $max" | bc -l) )); then
    CONFIG_ERRORS+=("Config value '$var_name' must be at most $max, got '$value'")
    return 1
  fi
  
  return 0
}

# Validate string is not empty and optionally matches pattern
# $1: variable name (for error message)
# $2: actual value
# $3: optional - regex pattern to match
# $4: optional - "required" if the value is required
validate_string() {
  local var_name="$1"
  local value="$2"
  local pattern="${3:-}"
  local required="${4:-optional}"
  
  # Check if value is empty and required
  if [ -z "$value" ] && [ "$required" = "required" ]; then
    CONFIG_ERRORS+=("Required config value '$var_name' is missing")
    return 1
  elif [ -z "$value" ]; then
    # Empty but optional is fine
    return 0
  fi
  
  # Check pattern if provided
  if [ -n "$pattern" ] && ! [[ "$value" =~ $pattern ]]; then
    CONFIG_ERRORS+=("Config value '$var_name' must match pattern '$pattern', got '$value'")
    return 1
  fi
  
  return 0
}

# Validate boolean value
# $1: variable name (for error message)
# $2: actual value
# $3: optional - "required" if the value is required
validate_boolean() {
  local var_name="$1"
  local value="$2"
  local required="${3:-optional}"
  
  # Check if value is empty and required
  if [ -z "$value" ] && [ "$required" = "required" ]; then
    CONFIG_ERRORS+=("Required config value '$var_name' is missing")
    return 1
  elif [ -z "$value" ]; then
    # Empty but optional is fine
    return 0
  fi
  
  # Check if value is boolean
  if [ "$value" != "true" ] && [ "$value" != "false" ]; then
    CONFIG_ERRORS+=("Config value '$var_name' must be 'true' or 'false', got '$value'")
    return 1
  fi
  
  return 0
}

# Validate array has minimum number of elements
# $1: variable name (for error message)
# $2: array to check
# $3: minimum size
# $4: optional - "required" if the value is required
validate_array_size() {
  local var_name="$1"
  local array=("${!2}")
  local min_size="$3"
  local required="${4:-optional}"
  
  # Check if array is empty and required
  if [ ${#array[@]} -eq 0 ] && [ "$required" = "required" ]; then
    CONFIG_ERRORS+=("Required config array '$var_name' is empty")
    return 1
  elif [ ${#array[@]} -eq 0 ]; then
    # Empty but optional is fine
    return 0
  fi
  
  # Check minimum size
  if [ ${#array[@]} -lt "$min_size" ]; then
    CONFIG_ERRORS+=("Config array '$var_name' must have at least $min_size elements, got ${#array[@]}")
    return 1
  fi
  
  return 0
}

# Validate URL format
# $1: variable name (for error message)
# $2: URL to validate
# $3: optional - "required" if the value is required
validate_url() {
  local var_name="$1"
  local url="$2"
  local required="${3:-optional}"
  
  # Check if URL is empty and required
  if [ -z "$url" ] && [ "$required" = "required" ]; then
    CONFIG_ERRORS+=("Required URL '$var_name' is missing")
    return 1
  elif [ -z "$url" ]; then
    # Empty but optional is fine
    return 0
  fi
  
  # Basic URL validation for http/https
  if ! [[ "$url" =~ ^https?:// ]]; then
    CONFIG_ERRORS+=("URL '$var_name' must start with http:// or https://, got '$url'")
    return 1
  fi
  
  return 0
}

# Validate webhook URL specifically
# $1: variable name (for error message)
# $2: webhook URL
# $3: optional - "required" if the value is required
validate_webhook_url() {
  local var_name="$1"
  local url="$2"
  local required="${3:-optional}"
  
  # First use the generic URL validation
  validate_url "$var_name" "$url" "$required"
  local result=$?
  
  if [ $result -ne 0 ] || [ -z "$url" ]; then
    return $result
  fi
  
  # Add specific checks for Slack webhook format
  if [[ "$var_name" == *"slack"* ]] && ! [[ "$url" =~ ^https://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+ ]]; then
    CONFIG_WARNINGS+=("Slack webhook URL '$var_name' doesn't match expected pattern. It should look like: https://hooks.slack.com/services/T.../B.../...")
  fi
  
  return 0
}

# Validate grace period value to prevent unreasonable values
# $1: variable name (for error message)
# $2: grace period in seconds
validate_grace_period() {
  local var_name="$1"
  local value="$2"
  
  # First use the numeric validation
  validate_numeric_range "$var_name" "$value" 0 3600
  local result=$?
  
  if [ $result -ne 0 ]; then
    return $result
  fi
  
  # Add a warning for very long grace periods
  if [ -n "$value" ] && (( value > 300 )); then
    CONFIG_WARNINGS+=("Grace period '$var_name' is very long ($value seconds). This may delay alerts excessively.")
  fi
  
  return 0
}

# Validate all configuration values
validate_all_config() {
  local valid=true
  
  # Reset error arrays
  CONFIG_ERRORS=()
  CONFIG_WARNINGS=()
  
  # General settings
  validate_boolean "debug_mode" "$DEBUG_MODE"
  
  # Connectivity settings
  validate_boolean "connectivity_check_enabled" "$CONNECTIVITY_CHECK_ENABLED" "required"
  validate_numeric_range "connectivity_check_interval" "$CONNECTIVITY_CHECK_INTERVAL" 1 3600 "required"
  validate_grace_period "grace_period_seconds" "$GRACE_PERIOD_SECONDS"
  validate_boolean "reset_stats_on_recovery" "$RESET_STATS_ON_RECOVERY"
  
  # Connectivity servers
  validate_array_size "CONNECTIVITY_CHECK_SERVERS[@]" CONNECTIVITY_CHECK_SERVERS 1 "required"
  
  # Notification settings
  validate_boolean "notification_queue_enabled" "$NOTIFICATION_QUEUE_ENABLED"
  validate_string "notification_queue_dir" "$NOTIFICATION_QUEUE_DIR" "" "required"
  validate_numeric_range "notification_queue_max_age" "$NOTIFICATION_QUEUE_MAX_AGE" 1 168
  
  # Display settings
  validate_boolean "colors_enabled" "$COLORS_ENABLED"
  
  # Thresholds
  validate_numeric_range "rtt_good_threshold" "$RTT_GOOD_THRESHOLD" 1 500
  validate_numeric_range "rtt_warning_threshold" "$RTT_WARNING_THRESHOLD" 1 1000
  validate_numeric_range "jitter_good_threshold" "$JITTER_GOOD_THRESHOLD" 1 500
  validate_numeric_range "jitter_warning_threshold" "$JITTER_WARNING_THRESHOLD" 1 1000
  validate_numeric_range "ttl_warning_threshold" "$TTL_WARNING_THRESHOLD" 1 255
  validate_numeric_range "ttl_critical_threshold" "$TTL_CRITICAL_THRESHOLD" 1 255
  
  # Slack settings
  validate_boolean "slack_enabled" "$SLACK_ENABLED"
  if [ "$SLACK_ENABLED" = "true" ]; then
    validate_webhook_url "slack_webhook_url" "$SLACK_WEBHOOK_URL" "required"
    validate_string "slack_default_channel" "$SLACK_DEFAULT_CHANNEL" "^#" "required"
  fi
  
  # Check if there are any errors
  if [ ${#CONFIG_ERRORS[@]} -gt 0 ]; then
    echo -e "${RED}Configuration validation failed with ${#CONFIG_ERRORS[@]} errors:${NC}"
    for error in "${CONFIG_ERRORS[@]}"; do
      echo -e "${RED}  - $error${NC}"
    done
    valid=false
  fi
  
  # Show warnings
  if [ ${#CONFIG_WARNINGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Configuration validation generated ${#CONFIG_WARNINGS[@]} warnings:${NC}"
    for warning in "${CONFIG_WARNINGS[@]}"; do
      echo -e "${YELLOW}  - $warning${NC}"
    done
  fi
  
  if $valid; then
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo -e "${GREEN}Configuration validation passed successfully${NC}"
    fi
    return 0
  else
    return 1
  fi
}

# Load environment variable overrides
load_env_overrides() {
  # General settings
  if [ -n "${NETMON_DEBUG:-}" ]; then
    DEBUG_MODE="${NETMON_DEBUG}"
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo "Overriding DEBUG_MODE from environment: $DEBUG_MODE"
    fi
  fi
  
  # Config file paths
  if [ -n "${NETMON_CONFIG_FILE:-}" ]; then
    CONFIG_FILE="${NETMON_CONFIG_FILE}"
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo "Overriding CONFIG_FILE from environment: $CONFIG_FILE"
    fi
  fi
  
  if [ -n "${NETMON_TARGETS_FILE:-}" ]; then
    TARGETS_FILE="${NETMON_TARGETS_FILE}"
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo "Overriding TARGETS_FILE from environment: $TARGETS_FILE"
    fi
  fi
  
  # Connectivity settings
  if [ -n "${NETMON_CONNECTIVITY_CHECK_ENABLED:-}" ]; then
    CONNECTIVITY_CHECK_ENABLED="${NETMON_CONNECTIVITY_CHECK_ENABLED}"
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo "Overriding CONNECTIVITY_CHECK_ENABLED from environment: $CONNECTIVITY_CHECK_ENABLED"
    fi
  fi
  
  if [ -n "${NETMON_CONNECTIVITY_CHECK_INTERVAL:-}" ]; then
    CONNECTIVITY_CHECK_INTERVAL="${NETMON_CONNECTIVITY_CHECK_INTERVAL}"
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo "Overriding CONNECTIVITY_CHECK_INTERVAL from environment: $CONNECTIVITY_CHECK_INTERVAL"
    fi
  fi
  
  if [ -n "${NETMON_GRACE_PERIOD_SECONDS:-}" ]; then
    GRACE_PERIOD_SECONDS="${NETMON_GRACE_PERIOD_SECONDS}"
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo "Overriding GRACE_PERIOD_SECONDS from environment: $GRACE_PERIOD_SECONDS"
    fi
  fi
  
  # Notification settings
  if [ -n "${NETMON_NOTIFICATION_QUEUE_ENABLED:-}" ]; then
    NOTIFICATION_QUEUE_ENABLED="${NETMON_NOTIFICATION_QUEUE_ENABLED}"
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo "Overriding NOTIFICATION_QUEUE_ENABLED from environment: $NOTIFICATION_QUEUE_ENABLED"
    fi
  fi
  
  # Slack settings
  if [ -n "${NETMON_SLACK_ENABLED:-}" ]; then
    SLACK_ENABLED="${NETMON_SLACK_ENABLED}"
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo "Overriding SLACK_ENABLED from environment: $SLACK_ENABLED"
    fi
  fi
  
  if [ -n "${NETMON_SLACK_WEBHOOK_URL:-}" ]; then
    SLACK_WEBHOOK_URL="${NETMON_SLACK_WEBHOOK_URL}"
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo "Overriding SLACK_WEBHOOK_URL from environment: XXXX (hidden for security)"
    fi
  fi
}

# Export any modified variables
export_config_vars() {
  export DEBUG_MODE CONNECTIVITY_CHECK_ENABLED CONNECTIVITY_CHECK_INTERVAL
  export GRACE_PERIOD_SECONDS RESET_STATS_ON_RECOVERY
  export NOTIFICATION_QUEUE_ENABLED NOTIFICATION_QUEUE_DIR NOTIFICATION_QUEUE_MAX_AGE
  export COLORS_ENABLED RTT_GOOD_THRESHOLD RTT_WARNING_THRESHOLD
  export JITTER_GOOD_THRESHOLD JITTER_WARNING_THRESHOLD
  export TTL_WARNING_THRESHOLD TTL_CRITICAL_THRESHOLD
  export SLACK_ENABLED SLACK_WEBHOOK_URL SLACK_DEFAULT_CHANNEL
}