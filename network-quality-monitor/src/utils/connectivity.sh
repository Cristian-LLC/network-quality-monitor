#!/usr/bin/env bash
#
# Network Quality Monitor - Connectivity Detection Module
#
# This module provides functions to check local internet connectivity
# to avoid false alerts when the monitoring machine loses connectivity.
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

# Function to check if local machine has internet connectivity
# This is used to prevent false-positive alerts when the monitoring machine loses internet
# Returns: Sets LOCAL_CONNECTIVITY to true or false
check_local_connectivity() {
  # If connectivity checking is disabled, always return true
  if [ "$LOCAL_CONNECTIVITY_CHECK_ENABLED" = "false" ]; then
    LOCAL_CONNECTIVITY=true
    return 0
  fi

  local now
  now=$(date +%s)
  
  # Only check at the specified interval to avoid excessive checks
  # Unless LAST_CONNECTIVITY_CHECK is 0, which means we forced a check
  if [ $LAST_CONNECTIVITY_CHECK -ne 0 ] && [ $((now - LAST_CONNECTIVITY_CHECK)) -lt "$LOCAL_CONNECTIVITY_CHECK_INTERVAL" ]; then
    return 0
  fi
  
  LAST_CONNECTIVITY_CHECK=$now
  
  if [ "$SHOW_DEBUG" = "true" ]; then
    echo "Checking local connectivity using: ${LOCAL_CONNECTIVITY_CHECK_SERVERS[*]}"
  fi
  
  # Variable to track if any server is reachable
  local any_reachable=false
  
  # Determine which DNS check commands are available
  local has_host=false
  local has_dig=false
  local has_nslookup=false
  local has_timeout=false
  
  if command -v host >/dev/null 2>&1; then
    has_host=true
  fi
  
  if command -v dig >/dev/null 2>&1; then
    has_dig=true
  fi
  
  if command -v nslookup >/dev/null 2>&1; then
    has_nslookup=true
  fi
  
  if command -v timeout >/dev/null 2>&1; then
    has_timeout=true
  fi
  
  # Check if we're on macOS
  local is_macos=false
  if [[ "$(uname)" == "Darwin" ]]; then
    is_macos=true
  fi
  
  # Helper function to run a command with timeout
  # Usage: run_with_timeout <seconds> <command> [args...]
  run_with_timeout() {
    local timeout_secs=$1
    shift
    
    if $has_timeout; then
      # Use the timeout command if available
      timeout "$timeout_secs" "$@"
      return $?
    else
      # If timeout command not available, use perl as fallback
      # This is useful on macOS where timeout might not be installed
      perl -e '
        use strict;
        my $timeout = $ARGV[0];
        shift @ARGV;
        my $cmd = join(" ", @ARGV);
        
        # Set alarm for timeout seconds
        eval {
          local $SIG{ALRM} = sub { die "timeout\n" };
          alarm $timeout;
          system($cmd);
          alarm 0;
        };
        if ($@ =~ /timeout/) {
          exit 124;  # Same exit code as timeout command
        } else {
          exit $? >> 8;  # Return command exit code
        }
      ' "$timeout_secs" "$@"
      return $?
    fi
  }
  
  # Try DNS resolution using appropriate command with correct timeout flags for the OS
  if $has_dig; then
    # dig has consistent timeout flags on both macOS and Linux
    if dig +timeout=1 +tries=1 google.com @8.8.8.8 >/dev/null 2>&1 || \
       dig +timeout=1 +tries=1 cloudflare.com @1.1.1.1 >/dev/null 2>&1; then
      any_reachable=true
      if [ "$SHOW_DEBUG" = "true" ]; then
        echo "Connectivity check succeeded using dig"
      fi
    fi
  elif $has_host; then
    # host command has different timeout flags on macOS vs Linux
    if $is_macos; then
      # macOS host command doesn't support -W flag, so use our timeout wrapper
      if run_with_timeout 1 host google.com >/dev/null 2>&1 || \
         run_with_timeout 1 host cloudflare.com >/dev/null 2>&1; then
        any_reachable=true
        if [ "$SHOW_DEBUG" = "true" ]; then
          echo "Connectivity check succeeded using host with timeout wrapper"
        fi
      fi
    else
      # Linux host command supports -W flag
      if host -W 1 google.com >/dev/null 2>&1 || \
         host -W 1 cloudflare.com >/dev/null 2>&1; then
        any_reachable=true
        if [ "$SHOW_DEBUG" = "true" ]; then
          echo "Connectivity check succeeded using host -W"
        fi
      fi
    fi
  elif $has_nslookup; then
    # nslookup doesn't have built-in timeout on either OS, so use our timeout wrapper
    if run_with_timeout 1 nslookup google.com >/dev/null 2>&1 || \
       run_with_timeout 1 nslookup cloudflare.com >/dev/null 2>&1; then
      any_reachable=true
      if [ "$SHOW_DEBUG" = "true" ]; then
        echo "Connectivity check succeeded using nslookup"
      fi
    fi
  fi
  
  # If DNS didn't resolve, try HTTP(S) check using curl if available
  if ! $any_reachable && command -v curl >/dev/null 2>&1; then
    if curl --connect-timeout 1 -s https://1.1.1.1/cdn-cgi/trace >/dev/null 2>&1 || \
       curl --connect-timeout 1 -s https://www.google.com >/dev/null 2>&1; then
      any_reachable=true
      if [ "$SHOW_DEBUG" = "true" ]; then
        echo "Connectivity check succeeded using curl"
      fi
    fi
  fi
  
  # As a last resort, try pinging servers
  if ! $any_reachable; then
    for server in "${LOCAL_CONNECTIVITY_CHECK_SERVERS[@]}"; do
      # Determine correct ping flags based on OS
      if $is_macos; then
        # macOS ping flags
        if ping -c 1 -t 1 "$server" >/dev/null 2>&1; then
          any_reachable=true
          if [ "$SHOW_DEBUG" = "true" ]; then
            echo "Connectivity check succeeded by pinging $server"
          fi
          break
        fi
      else
        # Linux ping flags
        if ping -c 1 -W 1 "$server" >/dev/null 2>&1; then
          any_reachable=true
          if [ "$SHOW_DEBUG" = "true" ]; then
            echo "Connectivity check succeeded by pinging $server"
          fi
          break
        fi
      fi
    done
  fi
  
  # Check if connectivity status changed
  if $any_reachable; then
    # We have connectivity
    if [ "$LOCAL_CONNECTIVITY" = "false" ]; then
      if [ "$SHOW_DEBUG" = "true" ]; then
        echo "Local connectivity restored!"
      fi

      # Set a 30 second grace period - no alerts during this time
      # Calculate timestamp 30 seconds from now
      CONNECTIVITY_GRACE_PERIOD_UNTIL=$(($(date +%s) + 30))

      # First save grace period end time to a file for all processes to read
      # This must happen BEFORE showing messages to prevent race conditions
      echo "$CONNECTIVITY_GRACE_PERIOD_UNTIL" > /tmp/connectivity_restored

      # Clear any pending loss counters immediately to prevent false alerts
      # Reset all statistics now to prevent any false alerts
      OK_PINGS=0
      LOST_PINGS=0
      CONSECUTIVE_LOSS=0
      START_TS=$(date +%s)
      MIN_RTT="9999.9"
      MAX_RTT="0.0"
      RECENT_RTT=()
      JITTER="0.0"

      # Reset IP-specific temporary files
      rm -f /tmp/reset_needed_*

      # Print a notice when connectivity is restored (only once)
      if ! $GRACE_PERIOD_NOTICE_SHOWN && [ ! -f "/tmp/network_monitor_flags/grace_period_notice_shown" ]; then
        echo -e "${GREEN}⚡ Local connectivity has been restored! Starting 30 second grace period...${NC}"
        touch "/tmp/network_monitor_flags/grace_period_notice_shown"
        GRACE_PERIOD_NOTICE_SHOWN=true
        # Also reset the end notice flag
        rm -f "/tmp/network_monitor_flags/grace_end_notice_shown"
        GRACE_END_NOTICE_SHOWN=false
      fi

      # Process queued alerts now that we have connectivity
      if type process_alert_queue &>/dev/null; then
        process_alert_queue
      fi
    fi
    LOCAL_CONNECTIVITY=true
  else
    # We don't have connectivity
    if [ "$LOCAL_CONNECTIVITY" = "true" ]; then
      if [ "$SHOW_DEBUG" = "true" ]; then
        echo "Local connectivity lost! Cannot reach any of: ${LOCAL_CONNECTIVITY_CHECK_SERVERS[*]}"
      fi
      # Print a notice when connectivity is lost
      echo -e "${YELLOW}⚠️ Local connectivity has been lost! Alerts will be suppressed until connectivity is restored.${NC}"

      # Reset the grace period notification flags in both memory and filesystem
      GRACE_PERIOD_NOTICE_SHOWN=false
      GRACE_END_NOTICE_SHOWN=false
      rm -f /tmp/network_monitor_flags/grace_period_notice_shown
      rm -f /tmp/network_monitor_flags/grace_end_notice_shown
    fi
    LOCAL_CONNECTIVITY=false
  fi
}