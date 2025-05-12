#!/usr/bin/env bash
#
# Network Quality Monitor - Slack Notifications Module
#
# This module provides Slack notification capabilities for Network Quality Monitor.
# It sends alerts to Slack channels based on network events and configuration.
#
# Author: Cristian O.
# Version: 1.1.0
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

# Validate the Slack webhook URL
validate_slack_webhook() {
  local webhook_url="$1"

  # Check if webhook URL is empty
  if [ -z "$webhook_url" ]; then
    return 1
  fi

  # Check if webhook URL has the correct format
  if [[ ! "$webhook_url" =~ ^https://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+ ]]; then
    if [ -n "$SHOW_DEBUG" ] && [ "$SHOW_DEBUG" = "true" ]; then
      echo "Warning: Slack webhook URL appears to be invalid. Expected format: https://hooks.slack.com/services/T.../B.../..." >&2
    fi
  fi

  return 0
}

# Get the channel for a specific alert type
get_slack_channel() {
  local alert_type="$1"

  jq -r ".slack.notifications.$alert_type.channel // \".slack.default_channel // \"#network-alerts\"\"" "$NOTIFICATION_CONFIG" 2>/dev/null
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

  # Get and validate configuration
  webhook_url=$(get_slack_webhook)
  if ! validate_slack_webhook "$webhook_url"; then
    echo "Error: No Slack webhook URL configured or URL is invalid." >&2
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

  # Send to Slack with proper error handling
  local response
  local curl_exit_code

  # Add timeout to prevent hanging and retry logic
  for retry in {1..3}; do
    response=$(curl -s -S -X POST -H "Content-type: application/json" \
      --connect-timeout 10 --max-time 15 \
      --retry 2 --retry-delay 1 \
      --data "$payload" "$webhook_url")
    curl_exit_code=$?

    # Check curl exit code
    if [ $curl_exit_code -eq 0 ]; then
      break
    else
      echo "Warning: Slack API request failed (attempt $retry/3), curl exit code: $curl_exit_code" >&2
      sleep 2
    fi
  done

  # Check if curl succeeded
  if [ $curl_exit_code -ne 0 ]; then
    echo "Error: Failed to connect to Slack API after 3 attempts" >&2
    return 1
  fi

  # Check if response is successful
  if [ "$response" = "ok" ]; then
    if [ -n "$SHOW_DEBUG" ] && [ "$SHOW_DEBUG" = "true" ]; then
      echo "Slack notification sent successfully for $ip ($alert_type)"
    fi
    return 0
  elif [[ "$response" == *"rate_limited"* ]]; then
    echo "Warning: Slack API rate limit exceeded. Try again later." >&2
    return 1
  elif [[ "$response" == *"invalid_token"* ]] || [[ "$response" == *"token_revoked"* ]]; then
    echo "Error: Slack webhook URL is invalid or revoked. Please check your configuration." >&2
    return 1
  elif [[ "$response" == *"channel_not_found"* ]]; then
    echo "Error: Slack channel not found. Please check channel name in configuration." >&2
    return 1
  else
    echo "Error sending Slack notification: $response" >&2
    return 1
  fi
}

# Function to test Slack configuration
test_slack_configuration() {
  local test_message="${1:-"This is a test message from Network Quality Monitor"}"

  echo "Testing Slack notification configuration..."

  # Check if Slack is enabled
  if ! is_slack_enabled; then
    echo "Error: Slack notifications are disabled in configuration. Set 'enabled' to true."
    return 1
  fi

  # Get and validate webhook URL
  local webhook_url
  webhook_url=$(get_slack_webhook)

  if ! validate_slack_webhook "$webhook_url"; then
    echo "Error: Invalid or missing Slack webhook URL."
    echo "Please check your 'notifications/notification_config.json' file."
    return 1
  fi

  echo "Webhook URL validated. Sending test message..."

  # Send a test message
  if send_slack_alert "test" "test-host" "$test_message"; then
    echo "Success! Test message sent to Slack."
    echo "Please check your Slack channel for the test message."
    return 0
  else
    echo "Failed to send test message to Slack."
    echo "Please check your network connectivity and Slack configuration."
    return 1
  fi
}

# For testing purposes
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "This script is meant to be sourced, not executed directly."
  echo "Example usage:"
  echo "  source notifications/slack.sh"
  echo "  send_slack_alert \"host_down\" \"192.168.1.1\" \"Host is down!\""
  echo ""
  echo "To test your Slack configuration:"
  echo "  source notifications/slack.sh"
  echo "  test_slack_configuration \"Your test message\""
fi