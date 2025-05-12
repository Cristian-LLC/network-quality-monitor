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