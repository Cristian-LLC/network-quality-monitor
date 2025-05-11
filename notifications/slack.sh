#!/usr/bin/env bash
#
# Network Quality Monitor - Slack Notifications Module
#
# This module provides Slack notification capabilities for Network Quality Monitor.
# It sends alerts to Slack channels based on network events and configuration.
#
# Author: Cristian O.
# Version: 1.0.0
#

# Default locations for configuration
NOTIFICATION_CONFIG="${NOTIFICATION_CONFIG:-notifications/notification_config.json}"

# Colors for Slack messages
SLACK_COLOR_DOWN="#FF0000"      # Red
SLACK_COLOR_LOSS="#FFA500"      # Orange
SLACK_COLOR_RECOVERY="#36A64F"  # Green
SLACK_COLOR_INFO="#0000FF"      # Blue

# Check if jq is available
if ! command -v jq &>/dev/null; then
  echo "Warning: jq is required for Slack notifications, but not found. Notifications disabled."
  return 1
fi

# Check if curl is available
if ! command -v curl &>/dev/null; then
  echo "Warning: curl is required for Slack notifications, but not found. Notifications disabled."
  return 1
fi

# Check if the configuration file exists
if [ ! -f "$NOTIFICATION_CONFIG" ]; then
  echo "Warning: Notification configuration not found at $NOTIFICATION_CONFIG. Notifications disabled."
  return 1
fi

# Check if Slack notifications are enabled in the config
is_slack_enabled() {
  local enabled
  enabled=$(jq -r '.slack.enabled // false' "$NOTIFICATION_CONFIG" 2>/dev/null)
  
  if [ "$enabled" = "true" ]; then
    return 0
  else
    return 1
  fi
}

# Get the Slack webhook URL from config
get_slack_webhook() {
  jq -r '.slack.webhook_url // ""' "$NOTIFICATION_CONFIG" 2>/dev/null
}

# Get the channel for a specific alert type
get_slack_channel() {
  local alert_type="$1"
  
  jq -r ".slack.notifications.$alert_type.channel // \".slack.default_channel // \"#network-alerts\"\"" "$NOTIFICATION_CONFIG" 2>/dev/null
}

# Get throttling period for a specific alert type
get_slack_throttle() {
  local alert_type="$1"
  
  jq -r ".slack.notifications.$alert_type.throttle_minutes // 5" "$NOTIFICATION_CONFIG" 2>/dev/null
}

# Send a notification to Slack
# $1: Alert type (host_down, loss_alert, recovery)
# $2: IP address or hostname
# $3: Message text
send_slack_alert() {
  local alert_type="$1"
  local ip="$2"
  local message="$3"
  local webhook_url
  local channel
  
  # Get configuration
  webhook_url=$(get_slack_webhook)
  if [ -z "$webhook_url" ]; then
    echo "Error: No Slack webhook URL configured." >&2
    return 1
  fi
  
  channel=$(get_slack_channel "$alert_type")
  
  # Determine emoji and color based on alert type
  local emoji=""
  local color=""
  
  case "$alert_type" in
    host_down)
      emoji=":red_circle:"
      color="$SLACK_COLOR_DOWN"
      ;;
    loss_alert)
      emoji=":warning:"
      color="$SLACK_COLOR_LOSS"
      ;;
    recovery)
      emoji=":large_green_circle:"
      color="$SLACK_COLOR_RECOVERY"
      ;;
    *)
      emoji=":information_source:"
      color="$SLACK_COLOR_INFO"
      ;;
  esac
  
  # Build the payload
  local payload
  payload=$(cat << EOF
{
  "channel": "$channel",
  "username": "Network Monitor",
  "icon_emoji": ":satellite_antenna:",
  "attachments": [
    {
      "fallback": "$message",
      "color": "$color",
      "pretext": "$emoji Network Alert",
      "title": "Host: $ip",
      "text": "$message",
      "footer": "Network Quality Monitor",
      "ts": $(date +%s)
    }
  ]
}
EOF
  )
  
  # Send to Slack
  local response
  response=$(curl -s -X POST -H "Content-type: application/json" --data "$payload" "$webhook_url")
  
  # Check if successful
  if [ "$response" = "ok" ]; then
    if [ -n "$SHOW_DEBUG" ] && [ "$SHOW_DEBUG" = "true" ]; then
      echo "Slack notification sent successfully for $ip ($alert_type)"
    fi
    return 0
  else
    echo "Error sending Slack notification: $response" >&2
    return 1
  fi
}

# For testing purposes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This script is meant to be sourced, not executed directly."
  echo "Example usage:"
  echo "  source notifications/slack.sh"
  echo "  send_slack_alert \"host_down\" \"192.168.1.1\" \"Host is down!\""
fi