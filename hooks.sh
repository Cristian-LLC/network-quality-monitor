#!/usr/bin/env bash
#
# Network Quality Monitor - Notification Hooks
#
# This file provides hook functions that are called by the main script
# at specific events. It serves as the integration point for notification
# systems without modifying the core monitoring logic.
#
# Author: Cristian O.
# Version: 1.0.0
#

# Load Slack notification module
if [ -f "notifications/slack.sh" ]; then
  source notifications/slack.sh
fi

# State tracking to prevent duplicate notifications
declare -A LAST_NOTIFICATION_TIME 2>/dev/null || {
  # For bash < 4, use alternate implementation with parallel arrays
  declare -a NOTIFICATION_KEYS
  declare -a NOTIFICATION_TIMES
}

# Helper function to check rate limiting
# $1: notification key (e.g., "down:1.1.1.1")
# $2: throttle period in minutes
# Returns: 0 if notification should proceed, 1 if it should be throttled
should_notify() {
  local key="$1"
  local throttle_minutes="$2"
  
  # If throttling is disabled (0), always notify
  if [ "$throttle_minutes" -eq 0 ]; then
    return 0
  fi
  
  local now
  now=$(date +%s)
  local throttle_seconds=$((throttle_minutes * 60))
  local last_time=0
  
  # Check if we have a previous notification time
  if type declare -A &>/dev/null && declare -p LAST_NOTIFICATION_TIME 2>/dev/null | grep -q "declare -A"; then
    # Using associative array
    last_time="${LAST_NOTIFICATION_TIME[$key]:-0}"
  else
    # Using parallel arrays
    local index=-1
    for i in "${!NOTIFICATION_KEYS[@]}"; do
      if [ "${NOTIFICATION_KEYS[$i]}" = "$key" ]; then
        index=$i
        break
      fi
    done
    
    if [ $index -ge 0 ]; then
      last_time="${NOTIFICATION_TIMES[$index]}"
    fi
  fi
  
  # Calculate elapsed time since last notification
  local elapsed=$((now - last_time))
  
  # Update the last notification time
  if type declare -A &>/dev/null && declare -p LAST_NOTIFICATION_TIME 2>/dev/null | grep -q "declare -A"; then
    # Using associative array
    LAST_NOTIFICATION_TIME["$key"]=$now
  else
    # Using parallel arrays
    if [ $index -ge 0 ]; then
      NOTIFICATION_TIMES[$index]=$now
    else
      NOTIFICATION_KEYS+=("$key")
      NOTIFICATION_TIMES+=("$now")
    fi
  fi
  
  # Return whether enough time has passed
  if [ $elapsed -ge $throttle_seconds ]; then
    return 0
  else
    return 1
  fi
}

#
# Hook Functions
#

# Called when a host is detected as DOWN
# $1: IP address or hostname
# $2: Number of consecutive losses
hook_on_host_down() {
  local ip="$1"
  local consecutive_losses="$2"
  
  # Call Slack notification if available and enabled
  if type send_slack_alert &>/dev/null && is_slack_enabled; then
    local throttle
    throttle=$(get_slack_throttle "host_down")
    
    if should_notify "down:$ip" "$throttle"; then
      send_slack_alert "host_down" "$ip" "Host $ip is DOWN after $consecutive_losses consecutive losses."
    fi
  fi
}

# Called when recovering from DOWN state
# $1: IP address or hostname
# $2: RTT of the successful ping
hook_on_host_recovery() {
  local ip="$1"
  local rtt="$2"
  
  # Call Slack notification if available and enabled
  if type send_slack_alert &>/dev/null && is_slack_enabled; then
    local throttle
    throttle=$(get_slack_throttle "recovery")
    
    if should_notify "recovery:$ip" "$throttle"; then
      send_slack_alert "recovery" "$ip" "Host $ip has RECOVERED with RTT $rtt ms."
    fi
  fi
}

# Called when excessive packet loss is detected
# $1: IP address or hostname
# $2: Loss percentage
# $3: Report interval in seconds
hook_on_loss_alert() {
  local ip="$1"
  local loss_pct="$2"
  local interval="$3"
  
  # Call Slack notification if available and enabled
  if type send_slack_alert &>/dev/null && is_slack_enabled; then
    local throttle
    throttle=$(get_slack_throttle "loss_alert")
    
    if should_notify "loss:$ip" "$throttle"; then
      send_slack_alert "loss_alert" "$ip" "Host $ip has excessive packet loss: $loss_pct% over $interval seconds."
    fi
  fi
}

# Called for each regular status report (can be frequent)
# Use with caution to avoid notification spam
# $1: IP address or hostname
# $2: Status data as JSON
hook_on_status_report() {
  local ip="$1"
  local status_data="$2"
  
  # By default, we don't send regular status reports to avoid spam
  # This hook is provided for extending the system with custom logic
}

# For testing purposes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This script is meant to be sourced, not executed directly."
  echo "Example usage:"
  echo "  source hooks.sh"
  echo "  hook_on_host_down '192.168.1.1' 3"
fi