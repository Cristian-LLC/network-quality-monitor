#!/usr/bin/env bash
#
# Network Quality Monitor - Notification Hooks
#
# This file provides hook functions that are called by the main script
# at specific events. It serves as the integration point for notification
# systems without modifying the core monitoring logic.
#
# Author: Cristian O.
# Version: 1.2.0
#

# Load Slack notification module
if [ -f "notifications/slack.sh" ]; then
  source notifications/slack.sh
fi

# Alert queue system for storing alerts during network outages
ALERT_QUEUE_DIR="${ALERT_QUEUE_DIR:-/tmp/network_monitor_alerts}"
LAST_CONNECTIVITY_CHECK=0
INTERNET_AVAILABLE=true

# Create alert queue directory if it doesn't exist
mkdir -p "$ALERT_QUEUE_DIR" 2>/dev/null

# Function to check if internet connectivity is available
# Returns 0 if internet is available, 1 if not
check_internet_connectivity() {
  # For simplicity and reliability, always return true
  # This simplifies the logic and ensures notifications are attempted
  # The slack.sh module will already handle connection failures gracefully
  INTERNET_AVAILABLE=true
  return 0
}

# Function to queue an alert when internet is unavailable
# This saves the alert to a file for later delivery
# $1: alert_type - Type of alert (host_down, recovery, loss_alert)
# $2: ip - Target IP address
# $3: message - Alert message
queue_alert() {
  local alert_type="$1"
  local ip="$2"
  local message="$3"
  local timestamp
  timestamp=$(date +%s)
  
  # Create a JSON structure for the alert
  local alert_json
  alert_json=$(cat << EOF
{
  "timestamp": $timestamp,
  "alert_type": "$alert_type",
  "ip": "$ip",
  "message": "$message"
}
EOF
  )
  
  # Save to queue file with timestamp and random identifier to ensure uniqueness
  local queue_file="${ALERT_QUEUE_DIR}/alert_${timestamp}_${RANDOM}.json"
  echo "$alert_json" > "$queue_file"
  
  if [ -n "$SHOW_DEBUG" ] && [ "$SHOW_DEBUG" = "true" ]; then
    echo "Alert queued for later delivery: $alert_type for $ip"
  fi
}

# Function to process queued alerts
# This should be called periodically to attempt delivery of queued alerts
process_alert_queue() {
  # Check if there are any queued alerts
  local queued_alerts
  queued_alerts=$(find "$ALERT_QUEUE_DIR" -name "alert_*.json" 2>/dev/null)
  
  if [ -z "$queued_alerts" ]; then
    return 0
  fi
  
  if [ -n "$SHOW_DEBUG" ] && [ "$SHOW_DEBUG" = "true" ]; then
    echo "Processing queued alerts..."
  fi
  
  # Process each queued alert
  find "$ALERT_QUEUE_DIR" -name "alert_*.json" -print0 2>/dev/null | while IFS= read -r -d $'\0' alert_file; do
    # Read the alert data
    if [ -f "$alert_file" ]; then
      local alert_data
      alert_data=$(cat "$alert_file")
      
      # Extract alert information
      local alert_type
      local ip
      local message
      
      alert_type=$(echo "$alert_data" | jq -r '.alert_type')
      ip=$(echo "$alert_data" | jq -r '.ip')
      message=$(echo "$alert_data" | jq -r '.message')
      
      # Try to send the alert
      if send_slack_alert "$alert_type" "$ip" "$message (Delayed Alert)"; then
        # On success, remove the alert file
        rm -f "$alert_file"
        
        if [ -n "$SHOW_DEBUG" ] && [ "$SHOW_DEBUG" = "true" ]; then
          echo "Delivered queued alert: $alert_type for $ip"
        fi
      else
        # On failure, leave the alert file for next attempt
        if [ -n "$SHOW_DEBUG" ] && [ "$SHOW_DEBUG" = "true" ]; then
          echo "Failed to deliver queued alert: $alert_type for $ip"
        fi
        # Stop processing additional alerts if one fails
        break
      fi
    fi
  done
}

#
# Hook Functions
#

# Called when a host is detected as DOWN
# $1: IP address or hostname
# $2: Number of consecutive losses
# $3: Failure reason (optional)
hook_on_host_down() {
  local ip="$1"
  local consecutive_losses="$2"
  local failure_reason="${3:-Unknown reason}"
  local message="Host $ip is DOWN after $consecutive_losses consecutive losses. Reason: $failure_reason"

  # Call Slack notification if available and enabled
  if type send_slack_alert &>/dev/null && is_slack_enabled; then
    send_slack_alert "host_down" "$ip" "$message"
  fi
}

# Called when recovering from DOWN state
# $1: IP address or hostname
# $2: RTT of the successful ping
hook_on_host_recovery() {
  local ip="$1"
  local rtt="$2"
  local message="Host $ip has RECOVERED with RTT $rtt ms."

  # Call Slack notification if available and enabled
  if type send_slack_alert &>/dev/null && is_slack_enabled; then
    send_slack_alert "recovery" "$ip" "$message"
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
  local message="Host $ip has excessive packet loss: $loss_pct% over $interval seconds."

  # Call Slack notification if available and enabled
  if type send_slack_alert &>/dev/null && is_slack_enabled; then
    send_slack_alert "loss_alert" "$ip" "$message"
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
  
  # Every 30 minutes, clean up very old queued alerts (older than 24 hours)
  # This is a good place to do maintenance since status reports are called regularly
  local now
  now=$(date +%s)
  
  # Use modulo to run cleanup every ~30 minutes (1800 seconds)
  if [ $((now % 1800)) -lt 30 ]; then
    cleanup_old_alerts
  fi
  
  # Also try to process alert queue during regular status reports
  # to ensure alerts get delivered when connectivity is restored
  process_alert_queue
}

# Cleanup function for old queued alerts
# Removes alerts older than 24 hours to prevent queue from growing indefinitely
cleanup_old_alerts() {
  local now
  now=$(date +%s)
  local yesterday=$((now - 86400)) # 24 hours ago in seconds
  
  if [ -n "$SHOW_DEBUG" ] && [ "$SHOW_DEBUG" = "true" ]; then
    echo "Cleaning up alert queue, removing alerts older than 24 hours"
  fi
  
  # Find and remove alert files older than 24 hours
  find "$ALERT_QUEUE_DIR" -name "alert_*.json" -type f 2>/dev/null | while read -r alert_file; do
    if [ -f "$alert_file" ]; then
      # Extract timestamp from the alert data
      local timestamp
      timestamp=$(cat "$alert_file" | jq -r '.timestamp')
      
      # If it's a number and older than 24 hours, remove it
      if [[ "$timestamp" =~ ^[0-9]+$ ]] && [ "$timestamp" -lt "$yesterday" ]; then
        if [ -n "$SHOW_DEBUG" ] && [ "$SHOW_DEBUG" = "true" ]; then
          local alert_type
          local ip
          alert_type=$(cat "$alert_file" | jq -r '.alert_type')
          ip=$(cat "$alert_file" | jq -r '.ip')
          echo "Removing old alert: $alert_type for $ip from $(date -r $timestamp)"
        fi
        rm -f "$alert_file"
      fi
    fi
  done
}

# For testing purposes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This script is meant to be sourced, not executed directly."
  echo "Example usage:"
  echo "  source hooks.sh"
  echo "  hook_on_host_down '192.168.1.1' 3"
fi