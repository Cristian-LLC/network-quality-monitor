#!/usr/bin/env bash
#
# Network Quality Monitor - Alert Queue System
#
# This module provides functionality for storing alerts during network outages
# and delivering them when connectivity is restored.
#
# Author: Cristian O.
# Version: 1.2.0
#

# Alert queue system for storing alerts during network outages
ALERT_QUEUE_DIR="${ALERT_QUEUE_DIR:-/tmp/network_monitor_alerts}"

# Create alert queue directory if it doesn't exist
mkdir -p "$ALERT_QUEUE_DIR" 2>/dev/null

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