#!/usr/bin/env bash
#
# Network Quality Monitor - Notification Hooks
#
# This file provides hook functions that are called by the main script
# at specific events. It serves as the integration point for notification
# systems without modifying the core monitoring logic.
#
# Author: Cristian O.
# Version: 1.1.0
#

# Load Slack notification module
if [ -f "notifications/slack.sh" ]; then
  source notifications/slack.sh
fi

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
    send_slack_alert "host_down" "$ip" "Host $ip is DOWN after $consecutive_losses consecutive losses."
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
    send_slack_alert "recovery" "$ip" "Host $ip has RECOVERED with RTT $rtt ms."
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
    send_slack_alert "loss_alert" "$ip" "Host $ip has excessive packet loss: $loss_pct% over $interval seconds."
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