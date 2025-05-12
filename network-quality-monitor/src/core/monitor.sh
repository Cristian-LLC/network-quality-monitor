#!/usr/bin/env bash
#
# Network Quality Monitor - Core Monitoring Module
#
# This module provides the core monitoring functionality for the Network Quality Monitor.
# It manages the monitoring processes and handles process synchronization.
#
# Author: Cristian O.
# Version: 1.2.0
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Global state for monitoring processes
declare -a MONITOR_PIDS=()
declare -a MONITOR_TARGETS=()
declare -a FPING_PIDS=()
declare -a FPING_TARGETS=()

# Check bash version to determine if we can use associative arrays
BASH_SUPPORTS_ASSOC_ARRAYS=0

# First check Bash version
if [ -n "$BASH_VERSION" ]; then
  BASH_VERSION_MAJOR=${BASH_VERSION%%.*}
  if [ "$BASH_VERSION_MAJOR" -ge 4 ]; then
    # Try in a subshell to avoid affecting the main script
    if (
      set +e  # Don't exit on error
      declare -A _test_array 2>/dev/null
      echo $?
    ) ; then
      BASH_SUPPORTS_ASSOC_ARRAYS=1
      # Actually declare our associative array now
      declare -A FPING_PROCESSES
    fi
  fi
fi

# Global state for local connectivity checking
LOCAL_CONNECTIVITY=true
LOCAL_CONNECTIVITY_CHECK_INTERVAL=30  # seconds
LOCAL_CONNECTIVITY_CHECK_SERVERS=("1.1.1.1" "8.8.8.8" "9.9.9.9") # Default servers
LOCAL_CONNECTIVITY_CHECK_ENABLED=true # Can be disabled in config
LAST_CONNECTIVITY_CHECK=0

# Grace period after connectivity restoration (ignore all stats during this period)
CONNECTIVITY_GRACE_PERIOD_UNTIL=0
GRACE_PERIOD_NOTICE_SHOWN=false       # Flag to track if we've shown a notice about entering grace period
GRACE_END_NOTICE_SHOWN=false          # Flag to track if we've shown a notice about exiting grace period

# Cleanup function for interrupt signals (Ctrl+C)
# Ensures clean termination of all processes and removal of temporary files
# Called automatically by trap upon receiving SIGINT, SIGTERM, EXIT signals
cleanup() {
  echo -e "\n${CYAN}⛔ Ctrl+C detected, stopping all monitoring processes...${NC}"

  # First kill all known fping processes directly
  if [ ${#FPING_PIDS[@]} -gt 0 ]; then
    echo -e "${CYAN}Terminating fping processes:${NC}"

    # Use associative arrays if supported, otherwise use parallel arrays
    if [ $BASH_SUPPORTS_ASSOC_ARRAYS -eq 1 ] && [ ${#FPING_PROCESSES[@]} -gt 0 ]; then
      # For Bash 4+ with associative array support
      for target in "${!FPING_PROCESSES[@]}"; do
        local fpid="${FPING_PROCESSES[$target]}"
        if ps -p "$fpid" > /dev/null 2>&1; then
          echo -e "  ${YELLOW}Killing fping (PID: $fpid) ${NC}for target ${GREEN}$target${NC}"
          kill -9 "$fpid" 2>/dev/null
        fi
      done
    else
      # For Bash 3.x compatibility using parallel arrays
      for ((i=0; i<${#FPING_PIDS[@]}; i++)); do
        local fpid="${FPING_PIDS[$i]}"
        local target="${FPING_TARGETS[$i]}"
        if ps -p "$fpid" > /dev/null 2>&1; then
          echo -e "  ${YELLOW}Killing fping (PID: $fpid) ${NC}for target ${GREEN}$target${NC}"
          kill -9 "$fpid" 2>/dev/null
        fi
      done
    fi
  fi

  # Then terminate all monitor processes
  if [ ${#MONITOR_PIDS[@]} -gt 0 ]; then
    # First print process info with their targets
    echo -e "${CYAN}Terminating monitoring processes:${NC}"
    for ((i=0; i<${#MONITOR_PIDS[@]}; i++)); do
      local pid="${MONITOR_PIDS[$i]}"
      local target="${MONITOR_TARGETS[$i]:-Unknown}"

      # Get child processes (fping instances) for this monitor process
      # Get better information about child processes (fping and others)
      local child_info=""
      local fping_pids
      fping_pids=$(pgrep -f "fping.*$target" || echo "")

      if [[ -n "$fping_pids" ]]; then
        child_info="fping: $fping_pids"
      else
        # Try to get any children
        local all_children
        all_children=$(pgrep -P "$pid" 2>/dev/null || echo "")
        if [[ -n "$all_children" ]]; then
          child_info="process(es): $all_children"
        else
          child_info="none detected"
        fi
      fi

      echo -e "  ${YELLOW}PID: $pid ${NC}- ${GREEN}Target: $target${NC} - Child processes: ${CYAN}$child_info${NC}"

      # Terminate fping processes first - specifically target the ones for this target
      if [[ -n "$fping_pids" ]]; then
        echo -e "    ${RED}Terminating fping processes: $fping_pids${NC}"
        for fpid in $fping_pids; do
          kill -9 "$fpid" 2>/dev/null
        done
      fi

      # Then terminate any other child processes
      echo -e "    ${RED}Cleaning up all child processes of $pid${NC}"
      pkill -P "$pid" 2>/dev/null

      # Terminate the main process
      echo -e "    ${RED}Terminating main process: $pid${NC}"
      kill -9 "$pid" 2>/dev/null
    done
  else
    echo -e "${YELLOW}No active monitoring processes found.${NC}"
  fi

  # Terminate any residual processes that may belong to this script
  pkill -P "$BASHPID" 2>/dev/null

  # Clean up temporary files (named pipes and signal files)
  local num_fifos
  num_fifos=$(find /tmp -name "fping_fifo_*" -type p 2>/dev/null | wc -l)
  if [ "$num_fifos" -gt 0 ]; then
    echo -e "${CYAN}Cleaning up $num_fifos temporary files...${NC}"
    rm -f /tmp/fping_fifo_*
  fi

  # Remove connectivity grace period file if it exists
  if [ -f /tmp/connectivity_restored ]; then
    rm -f /tmp/connectivity_restored
  fi

  # Clean up flag files
  rm -f /tmp/network_monitor_flags/grace_period_notice_shown
  rm -f /tmp/network_monitor_flags/grace_end_notice_shown

  # Final verification to make sure all processes are properly terminated
  local remaining_fping
  remaining_fping=$(pgrep -c "fping" 2>/dev/null || echo "0")
  if [[ $remaining_fping -gt 0 ]]; then
    echo -e "${YELLOW}Found $remaining_fping remaining fping processes. Force killing all fping processes...${NC}"
    killall -9 fping 2>/dev/null
  fi

  # Check if any of our monitored processes are still running
  local still_running=0
  for pid in "${MONITOR_PIDS[@]}"; do
    if ps -p "$pid" > /dev/null 2>&1; then
      still_running=$((still_running + 1))
    fi
  done

  if [[ $still_running -gt 0 ]]; then
    echo -e "${YELLOW}Warning: $still_running monitoring processes may still be running.${NC}"
  else
    echo -e "${GREEN}All monitoring processes successfully terminated.${NC}"
  fi

  echo -e "${GREEN}Cleanup completed. Exiting...${NC}"
  exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# Alert function - displays messages with timestamp and color
# $1: color code (RED, GREEN, etc. variable)
# $2: message to display
alert() {
  local color="$1"
  local msg="$2"
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${color}${msg}${NC}"
}

# Main monitoring function - uses fping in loop mode
# Launches fping process, continuously parses its output and calculates statistics
# $1: IP address or hostname to monitor
# $2: ping frequency in seconds
# $3: consecutive loss threshold for DOWN alert
# $4: percentage loss threshold for LOSS alert
# $5: reporting interval in seconds
monitor_target() {
  local IP="$1"
  local PING_FREQUENCY="$2"
  local MAX_CONSECUTIVE_LOSS="$3"
  local LOSS_ALERT_THRESHOLD="$4"
  local REPORT_INTERVAL="$5"

  local NETWORK_OK=true
  local OK_PINGS=0
  local LOST_PINGS=0
  local CONSECUTIVE_LOSS=0
  local START_TS
  START_TS=$(date +%s)

  # Variables for RTT statistics
  local RTT_AVG="0.0"
  local JITTER="0.0"
  local JITTER_COLOR="$GREEN"
  local TTL="0"
  local MIN_RTT="9999.9"
  local MAX_RTT="0.0"
  local RECENT_RTT=()
  local MOS="N/A"
  local R_FACTOR="N/A"
  
  # Convert interval to ms for fping
  local INTERVAL_MS
  INTERVAL_MS=$(echo "$PING_FREQUENCY * 1000" | bc | cut -d. -f1)

  # We'll get the correct monitor PID after we're in the background
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${CYAN}▶️ Monitor started for $IP | Ping frequency: ${PING_FREQUENCY}s | [DOWN] after $MAX_CONSECUTIVE_LOSS losses | [LOSS ALERT] above $LOSS_ALERT_THRESHOLD% | Report every ${REPORT_INTERVAL}s${NC}"

  # Create a fifo to read fping output
  local FIFO="/tmp/fping_fifo_${IP}_$$"
  rm -f "$FIFO"
  mkfifo "$FIFO"
  
  # Start fping in loop mode with TTL printing
  # -l = loop mode (continuous pings)
  # -D = timestamp
  # --print-ttl = show TTL values
  # -p = interval between pings in ms
  fping -l -D --print-ttl -p "$INTERVAL_MS" "$IP" > "$FIFO" 2>&1 &
  local FPING_PID=$!

  # Store both the monitoring process PID and the fping PID
  # Get the actual PID of this process
  local MONITOR_PID=$BASHPID  # This should be more accurate than $$
  MONITOR_PIDS+=("$MONITOR_PID")
  # Store target for mapping back in cleanup
  MONITOR_TARGETS+=("$IP")

  # For the primary monitor (1.1.1.1), ensure flags are freshly reset
  # This prevents race conditions with flag files from other monitors
  if [ "$IP" = "1.1.1.1" ]; then
    # Reset flags in the filesystem for all processes
    rm -f /tmp/network_monitor_flags/grace_period_notice_shown
    rm -f /tmp/network_monitor_flags/grace_end_notice_shown
  fi

  # Store fping PID and target in parallel arrays for compatibility
  FPING_PIDS+=("$FPING_PID")
  FPING_TARGETS+=("$IP")

  # If bash supports associative arrays, also use them as a backup/convenience
  if [ $BASH_SUPPORTS_ASSOC_ARRAYS -eq 1 ]; then
    FPING_PROCESSES["$IP"]=$FPING_PID
  fi

  if [ "$SHOW_DEBUG" = "true" ]; then
    echo -e "${GREEN}Associated fping PID $FPING_PID with target $IP${NC}"
  fi
  
  # Get the actual PID of this process
  local MONITOR_PID
  MONITOR_PID=$BASHPID  # This should be more accurate than $$

  if [ "$SHOW_DEBUG" = "true" ]; then
    echo -e "${GREEN}Debug:${NC} fping process started with ${YELLOW}PID $FPING_PID${NC} for target ${CYAN}$IP${NC}"
    # Add process association for better debugging
    echo -e "${GREEN}Debug:${NC} Monitor process ${YELLOW}PID $MONITOR_PID${NC} is managing fping ${YELLOW}PID $FPING_PID${NC} for ${CYAN}$IP${NC}"
  fi

  # Create a process-specific reset state file
  touch "/tmp/reset_needed_$MONITOR_PID"

  # Now that we're in the background process, show PID in a status message
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}Monitor process ${MONITOR_PID}${NC} active for ${GREEN}$IP${NC}"
  
  # Read fping output and process the data
  while read -r line; do
    # First, check for the global grace period
    local now
    now=$(date +%s)

    # Update global grace period if file exists
    if [ -f "/tmp/connectivity_restored" ]; then
      # Check file modification time - ignore if the file is older than 2 minutes
      local file_mtime
      file_mtime=$(stat -c %Y "/tmp/connectivity_restored" 2>/dev/null || stat -f %m "/tmp/connectivity_restored" 2>/dev/null)
      local now_time=$now

      # Only process if file is recent (last 2 minutes) and if the file has contents
      if [ "$((now_time - file_mtime))" -lt 120 ] && [ -s "/tmp/connectivity_restored" ]; then
        # Read grace period end time
        local file_grace_period
        file_grace_period=$(cat "/tmp/connectivity_restored")

        # Make sure it's a valid timestamp (numeric and reasonable)
        if [[ "$file_grace_period" =~ ^[0-9]+$ ]] && [ "$file_grace_period" -gt 0 ]; then
          # Only update if the file has a more recent timestamp than our current setting
          # AND it's in the future (not from an old run)
          if [ "$file_grace_period" -gt "$CONNECTIVITY_GRACE_PERIOD_UNTIL" ] && [ "$file_grace_period" -gt "$now_time" ]; then
            CONNECTIVITY_GRACE_PERIOD_UNTIL="$file_grace_period"

            # Always reset statistics immediately when entering grace period
            OK_PINGS=0
            LOST_PINGS=0
            CONSECUTIVE_LOSS=0

            # Check for the presence of flag file to prevent multiple notices
            if [ "$IP" = "1.1.1.1" ] && [ ! -f "/tmp/network_monitor_flags/grace_period_notice_shown" ]; then
              echo -e "${YELLOW}Entering grace period - monitoring statistics will be reset${NC}"
              # Create flag file to prevent duplicate messages across processes
              touch "/tmp/network_monitor_flags/grace_period_notice_shown"
              GRACE_PERIOD_NOTICE_SHOWN=true
            else
              # Read flag from file for other processes
              GRACE_PERIOD_NOTICE_SHOWN=true
            fi

            # Reset network status to up immediately
            if ! $NETWORK_OK; then
              NETWORK_OK=true
              alert "$GREEN" "[$IP] [UP] ✅ RECOVERED: Connectivity restored during grace period"
            fi
          fi
        fi
      fi
    fi

    # If we're in the grace period after connectivity restoration
    if [ "$now" -lt "$CONNECTIVITY_GRACE_PERIOD_UNTIL" ]; then
      # We're in the grace period - reset all counters and ignore all data
      if [ "$SHOW_DEBUG" = "true" ] && [ "$IP" = "1.1.1.1" ]; then
        local seconds_left=$((CONNECTIVITY_GRACE_PERIOD_UNTIL - now))
        if [ $((seconds_left % 5)) -eq 0 ]; then  # Only show every 5 seconds
          echo -e "${YELLOW}In grace period - $((CONNECTIVITY_GRACE_PERIOD_UNTIL - now)) seconds remaining${NC}"
        fi
      fi

      # Reset all statistics
      OK_PINGS=0
      LOST_PINGS=0
      CONSECUTIVE_LOSS=0
      START_TS=$now
      MIN_RTT="9999.9"
      MAX_RTT="0.0"
      RECENT_RTT=()
      JITTER="0.0"

      # If network was marked as down, mark it up again
      if ! $NETWORK_OK; then
        NETWORK_OK=true
        # Show recovery message
        alert "$GREEN" "[$IP] [UP] ✅ RECOVERED: Connectivity restored during grace period"
      fi

      # Skip this iteration completely
      continue
    fi

    # Check if grace period just ended (within last 5 seconds)
    # Note: Use a wider window to catch the transition
    if [ "$now" -ge "$CONNECTIVITY_GRACE_PERIOD_UNTIL" ] && [ "$now" -le $((CONNECTIVITY_GRACE_PERIOD_UNTIL + 5)) ]; then
      # Only show this message once across all processes
      # Check for the presence of flag file to prevent multiple notices
      if [ "$IP" = "1.1.1.1" ] && [ ! -f "/tmp/network_monitor_flags/grace_end_notice_shown" ]; then
        # Notify that grace period has ended
        echo -e "${GREEN}✓ Grace period ended - resuming normal monitoring with fresh statistics${NC}"
        # Create flag file to prevent duplicate messages across processes
        touch "/tmp/network_monitor_flags/grace_end_notice_shown"
        GRACE_END_NOTICE_SHOWN=true
      else
        # Update local flag based on file presence
        GRACE_END_NOTICE_SHOWN=true
      fi

      # Force a reset of stats at the end of grace period
      OK_PINGS=0
      LOST_PINGS=0
      CONSECUTIVE_LOSS=0
      START_TS=$now
      MIN_RTT="9999.9"
      MAX_RTT="0.0"
      RECENT_RTT=()
      JITTER="0.0"

      # Clear grace period to avoid multiple messages
      # By setting it to 1, we ensure it's in the past
      CONNECTIVITY_GRACE_PERIOD_UNTIL=1

      # Clear connectivity restoration file to prevent reprocessing
      if [ "$IP" = "1.1.1.1" ]; then
        rm -f /tmp/connectivity_restored
      fi
    fi

    # Debug - display the line to see the format
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo "Debug: $line"
    fi

    # Get current timestamp
    local NOW_TS
    NOW_TS=$(date +%s)

    # Process ping result - format is:
    # [timestamp] IP : [seq], 64 bytes, 24.6 ms (24.6 avg, 0% loss) (TTL 116)
    if [[ "$line" == *"$IP"* ]]; then
      if [[ "$line" =~ bytes,\ ([0-9.]+)\ ms\ \(([0-9.]+)\ avg,.*\).*\(TTL\ ([0-9]+)\) ]]; then
        # Successful ping - extract values from regex matches
        local TIME_MS="${BASH_REMATCH[1]}"   # Current RTT
        local AVG_MS="${BASH_REMATCH[2]}"    # Average RTT calculated by fping
        local TTL_VAL="${BASH_REMATCH[3]}"   # TTL value

        # Save values
        OK_PINGS=$((OK_PINGS + 1))
        CONSECUTIVE_LOSS=0

        # Set RTT values
        RTT_AVG="$AVG_MS"
        TTL="$TTL_VAL"

        # Update min/max RTT values
        if (( $(echo "$TIME_MS < $MIN_RTT" | bc -l) )); then
          MIN_RTT="$TIME_MS"
        fi

        if (( $(echo "$TIME_MS > $MAX_RTT" | bc -l) )); then
          MAX_RTT="$TIME_MS"
        fi

        # Add to recent values for jitter calculation
        RECENT_RTT+=("$TIME_MS")
        if [ ${#RECENT_RTT[@]} -gt 5 ]; then
          RECENT_RTT=("${RECENT_RTT[@]:1}")
        fi

        # Calculate jitter and update MOS
        calculate_jitter "$TIME_MS"
        update_mos_rfactor

        # Display information about successful ping
        if [ "$SHOW_DEBUG" = "true" ]; then
          echo "Successful ping: RTT=$TIME_MS ms, AVG=$AVG_MS ms, TTL=$TTL_VAL"
        fi

        # If network was down before, announce recovery
        if ! $NETWORK_OK; then
          alert "$GREEN" "[$IP] [UP] ✅ RECOVERED: ping OK (${TIME_MS} ms)"
          NETWORK_OK=true

          # Call hook if available
          if type hook_on_host_recovery &>/dev/null; then
            hook_on_host_recovery "$IP" "${TIME_MS}"
          fi
        fi
      elif [[ "$line" == *"unreachable"* || "$line" == *"timeout"* || "$line" == *"timed out"* ||
              "$line" == *"Network unreachable"* || "$line" == *"No route to host"* ||
              "$line" == *"Network is down"* || "$line" == *"Host unreachable"* ||
              "$line" == *"Destination host unreachable"* || "$line" == *"ICMP Host Unreachable"* ]]; then
        # Failed ping
        LOST_PINGS=$((LOST_PINGS + 1))
        CONSECUTIVE_LOSS=$((CONSECUTIVE_LOSS + 1))

        # Extract the failure reason from the line
        local failure_reason="Unknown reason"

        # Try to extract the exact error message
        if [[ "$line" =~ :[[:space:]]*(.*) ]]; then
          # This will capture everything after the colon and space
          local error_part="${BASH_REMATCH[1]}"

          # Clean up the message
          error_part=$(echo "$error_part" | sed -E 's/\[[0-9]+\],\s*//; s/\([^)]*\)//g; s/\.$//g; s/from.*//g' | xargs)

          # Handle specific error messages
          case "$error_part" in
            *[Tt]"imed out"*|*"100% loss"*)
              # Check if it's a WiFi off scenario or just a normal timeout
              if [[ "$line" == *"is unreachable"* ]]; then
                error_part="Network connectivity lost"
              else
                error_part="Timed out"
              fi
              ;;
            *"Network is unreachable"*|*"network is unreachable"*)
              error_part="Network is unreachable"
              ;;
            *"No route to host"*|*"no route to host"*)
              error_part="No route to host"
              ;;
            *[Uu]"nreachable"*)
              error_part="Host unreachable"
              ;;
            *)
              # For any other message, capitalize first letter for consistency
              error_part=$(echo "$error_part" | sed 's/^\([a-z]\)/\U\1/')
              ;;
          esac

          if [ -n "$error_part" ]; then
            failure_reason="$error_part"
          fi
        else
          # Fallback categorization if regex extraction fails
          if [[ "$line" == *"is unreachable"* ]]; then
            failure_reason="Network connectivity lost"
          elif [[ "$line" == *"unreachable"* ]]; then
            failure_reason="Host unreachable"
          elif [[ "$line" == *"timeout"* || "$line" == *"timed out"* || "$line" == *"100% loss"* ]]; then
            failure_reason="Timed out"
          elif [[ "$line" == *"Network unreachable"* || "$line" == *"network is unreachable"* ]]; then
            failure_reason="Network is unreachable"
          elif [[ "$line" == *"No route to host"* || "$line" == *"no route to host"* ]]; then
            failure_reason="No route to host"
          elif [[ "$line" == *"Network is down"* || "$line" == *"network is down"* ]]; then
            failure_reason="Network is down"
          elif [[ "$line" == *"Destination host unreachable"* || "$line" == *"ICMP Host Unreachable"* ]]; then
            failure_reason="ICMP Host Unreachable"
          fi
        fi

        if [ "$SHOW_DEBUG" = "true" ]; then
          echo "Debug - Parsed error: '$failure_reason' from line: '$line'"
        fi

        # Only check connectivity if it's already up or we don't have a recent restoration
        if [ "$LOCAL_CONNECTIVITY" = "true" ] || [ ! -f "/tmp/connectivity_restored" ]; then
          # Force a connectivity check immediately when we detect a failure
          LAST_CONNECTIVITY_CHECK=0
          check_local_connectivity
        else
          # Check if we're already in the grace period - if so, reset consecutive losses
          if [ "$(date +%s)" -lt "$CONNECTIVITY_GRACE_PERIOD_UNTIL" ]; then
            # Reset counters to prevent false alerts during grace period
            CONSECUTIVE_LOSS=0
          fi
        fi

        # If we have many consecutive losses and grace period is active, reset stats
        if [ $CONSECUTIVE_LOSS -gt 5 ] && [ "$(date +%s)" -lt "$CONNECTIVITY_GRACE_PERIOD_UNTIL" ]; then
          # Reset statistics as we're likely recovering from connection issues
          reset_all_statistics
          # Skip processing this line
          continue
        fi

        # Check if network is down - but first check if we're in or entering grace period
        local now_check=$(date +%s)
        # Check if there's a recent connectivity_restored file indicating grace period
        local entering_grace=false
        if [ -f "/tmp/connectivity_restored" ]; then
          local file_mtime
          file_mtime=$(stat -c %Y "/tmp/connectivity_restored" 2>/dev/null || stat -f %m "/tmp/connectivity_restored" 2>/dev/null)

          # File exists and is very recent (created in last 2 seconds)
          if [ $((now_check - file_mtime)) -lt 2 ]; then
            entering_grace=true
            # Reset consecutive losses to prevent immediate false alerts during transition
            CONSECUTIVE_LOSS=0
          fi
        fi

        # Proceed with normal DOWN check if we're not entering grace period
        if [ "$entering_grace" = "false" ] && "$NETWORK_OK" && [ $CONSECUTIVE_LOSS -ge "$MAX_CONSECUTIVE_LOSS" ]; then
          # Don't show alerts during grace period
          if [ $now_check -lt "$CONNECTIVITY_GRACE_PERIOD_UNTIL" ]; then
            # In grace period - quietly mark the network as up instead of down
            NETWORK_OK=true
            CONSECUTIVE_LOSS=0
          # When local connectivity is lost, suppress or mark differently
          elif [ "$LOCAL_CONNECTIVITY" = "false" ]; then
            # Show warning only in debug mode but don't send notifications when local connectivity is lost
            if [ "$SHOW_DEBUG" = "true" ]; then
              alert "$YELLOW" "[$IP] [DOWN?] ⚠️ ${CONSECUTIVE_LOSS} consecutive losses! (Local connectivity lost, possible false alarm)"
            fi
            NETWORK_OK=false
          else
            # Normal alert when we have local connectivity
            alert "$RED" "[$IP] [DOWN] 🛑 ${CONSECUTIVE_LOSS} consecutive losses! Reason: $failure_reason"
            NETWORK_OK=false

            # Call hook if available
            if type hook_on_host_down &>/dev/null; then
              hook_on_host_down "$IP" "$CONSECUTIVE_LOSS" "$failure_reason"
            fi
          fi
        fi
      fi
      
      # Check if we need to display the report
      # Skip report if current time is within the grace period
      if (( NOW_TS - START_TS >= "$REPORT_INTERVAL" )) && [ $NOW_TS -gt "$CONNECTIVITY_GRACE_PERIOD_UNTIL" ]; then
        generate_and_display_report "$IP" "$REPORT_INTERVAL" "$LOSS_ALERT_THRESHOLD"
        
        # Reset counters
        OK_PINGS=0
        LOST_PINGS=0

        # Reset min/max for next report interval
        MIN_RTT="9999.9"
        MAX_RTT="0.0"
        START_TS=$NOW_TS
      fi
    fi
    
  done < "$FIFO"
  
  # Clean up the fifo at the end
  rm -f "$FIFO"
}

# Helper function to calculate jitter
# $1: current RTT value
calculate_jitter() {
  local current_val="$1"
  
  # Calculate jitter using the EWMA (Exponential Weighted Moving Average) method
  # RFC 3550 approach with 1/16 gain factor
  if [ "${#RECENT_RTT[@]}" -gt 1 ]; then
    # If we have a previous RTT value, calculate the difference
    local prev_val="${RECENT_RTT[0]}"

    # Calculate absolute difference between successive RTT values
    local diff
    diff=$(safe_bc "($current_val - $prev_val)" "positive")

    # Apply the exponential filter: J(i) = J(i-1) + (|D(i-1,i)| - J(i-1))/16
    local jitter_calc
    jitter_calc=$(safe_bc "$JITTER + ($diff - $JITTER) / 16" "positive")
    JITTER=$(printf "%.1f" "$jitter_calc")

    # Update jitter color based on industry standards
    # < 10ms: Green (good)
    # 10-30ms: Yellow (warning)
    # > 30ms: Red (bad)
    if (( $(echo "$JITTER > 30.0" | bc -l) )); then
      JITTER_COLOR="$RED"
    elif (( $(echo "$JITTER > 10.0" | bc -l) )); then
      JITTER_COLOR="$YELLOW"
    else
      JITTER_COLOR="$GREEN"
    fi
  fi
}

# Helper function to update MOS and R-factor values
update_mos_rfactor() {
  # Calculate MOS and R-factor if we have valid RTT
  MOS="N/A"
  R_FACTOR="N/A"
  if [[ "$RTT_AVG" != "0.0" ]]; then
    # If jitter is 0, use a minimum value of 0.1 for calculation
    local jitter_value="$JITTER"
    if [[ "$JITTER" == "0.0" ]]; then
      jitter_value="0.1"
    fi
    # Use function from metrics.sh to calculate MOS and R-factor
    local CALC_RESULT
    CALC_RESULT=$(calculate_mos "$RTT_AVG" "$jitter_value")
    MOS=$(echo "$CALC_RESULT" | cut -d':' -f1)
    R_FACTOR=$(echo "$CALC_RESULT" | cut -d':' -f2)
  fi
}

# Function to generate and display a report for a target
# $1: IP address or hostname
# $2: Reporting interval in seconds
# $3: Loss threshold percentage for alerting
generate_and_display_report() {
  local IP="$1"
  local REPORT_INTERVAL="$2"
  local LOSS_ALERT_THRESHOLD="$3"
  local TOTAL_PINGS=$((OK_PINGS + LOST_PINGS))
  local LOSS_PERCENT="0.0"

  if [ $TOTAL_PINGS -gt 0 ]; then
    local loss_calc
    loss_calc=$(safe_bc "$LOST_PINGS * 100 / $TOTAL_PINGS")
    LOSS_PERCENT=$loss_calc
  fi

  # Set color for packet loss
  local LOSS_COLOR="$GREEN"
  if (( $(echo "$LOSS_PERCENT >= $LOSS_ALERT_THRESHOLD" | bc -l) )); then
    LOSS_COLOR="$RED"

    # Only show loss alert if network is UP
    # This prevents showing loss alerts for hosts we already know are down
    if $NETWORK_OK; then
      # Force a connectivity check before alerting
      LAST_CONNECTIVITY_CHECK=0
      check_local_connectivity

      # If local connectivity is lost, suppress completely or mark differently
      if [ "$LOCAL_CONNECTIVITY" = "false" ]; then
        # Show warning only in debug mode but don't send notifications when local connectivity is lost
        if [ "$SHOW_DEBUG" = "true" ]; then
          alert "$YELLOW" "[$IP] 📉 [LOSS ALERT?] Excessive packet loss: ${LOSS_PERCENT}% (Local connectivity lost, possible false alarm)"
        fi
      else
        # Normal alert when we have local connectivity
        alert "$RED" "[$IP] 📉 [LOSS ALERT] Excessive packet loss in the last ${REPORT_INTERVAL} seconds: ${LOSS_PERCENT}%"

        # Call hook if available
        if type hook_on_loss_alert &>/dev/null; then
          hook_on_loss_alert "$IP" "${LOSS_PERCENT}" "${REPORT_INTERVAL}"
        fi
      fi
    fi
  elif (( $(echo "$LOSS_PERCENT > 0" | bc -l) )); then
    LOSS_COLOR="$YELLOW"
  fi

  # Set colors for MIN/AVG/MAX RTT values
  local RTT_LABEL_COLOR="$GREEN"  # Color for the "RTT:" label

  # Color for MIN RTT
  local MIN_RTT_COLOR="$GREEN"
  if (( $(echo "$MIN_RTT > 150" | bc -l) )); then
    MIN_RTT_COLOR="$RED"
  elif (( $(echo "$MIN_RTT > 80" | bc -l) )); then
    MIN_RTT_COLOR="$YELLOW"
  fi

  # Color for AVG RTT - this also determines the label color
  local AVG_RTT_COLOR="$GREEN"
  if (( $(echo "$RTT_AVG > 150" | bc -l) )); then
    AVG_RTT_COLOR="$RED"
    RTT_LABEL_COLOR="$RED"
  elif (( $(echo "$RTT_AVG > 80" | bc -l) )); then
    AVG_RTT_COLOR="$YELLOW"
    RTT_LABEL_COLOR="$YELLOW"
  fi

  # Color for MAX RTT
  local MAX_RTT_COLOR="$GREEN"
  if (( $(echo "$MAX_RTT > 150" | bc -l) )); then
    MAX_RTT_COLOR="$RED"
  elif (( $(echo "$MAX_RTT > 80" | bc -l) )); then
    MAX_RTT_COLOR="$YELLOW"
  fi

  # Set color for TTL
  local TTL_COLOR="$GREEN"
  if [[ "$TTL" != "0" && "$TTL" != "N/A" ]]; then
    # Only do numeric comparison if TTL is a number
    if [[ "$TTL" =~ ^[0-9]+$ ]]; then
      if (( TTL < 64 )); then
        if (( TTL < 32 )); then
          TTL_COLOR="$RED"
        else
          TTL_COLOR="$YELLOW"
        fi
      fi
    fi
  else
    TTL_COLOR="$CYAN"
  fi
  
  # Add QoS color for MOS/R-factor value based on ITU-T standards
  local MOS_COLOR="$CYAN"
  if [[ "$MOS" != "N/A" ]] && [[ "$R_FACTOR" != "N/A" ]]; then
    # Color based on R-factor (more accurate than MOS coloring)
    # First check that R_FACTOR is a number
    if [[ "$R_FACTOR" =~ ^[0-9]+$ ]]; then
      if (( R_FACTOR >= 81 )); then
        MOS_COLOR="$GREEN"        # Excellent (R ≥ 81)
      elif (( R_FACTOR >= 71 )); then
        MOS_COLOR="$GREEN"        # Good (R 71-80)
      elif (( R_FACTOR >= 61 )); then
        MOS_COLOR="$YELLOW"       # Fair (R 61-70)
      elif (( R_FACTOR >= 51 )); then
        MOS_COLOR="$YELLOW"       # Poor (R 51-60)
      else
        MOS_COLOR="$RED"          # Bad (R < 50)
      fi
    fi
  fi

  # Status label and color
  local STATUS_LABEL
  local COLOR
  if $NETWORK_OK; then
    STATUS_LABEL="[UP] ✅"
    COLOR="$CYAN"

    # Display report only for UP hosts and when we have local connectivity
    # First check if local connectivity is lost
    if [ "$LOCAL_CONNECTIVITY" = "false" ]; then
      # When local connectivity is lost, only show reports in debug mode
      if [ "$SHOW_DEBUG" = "true" ]; then
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}[$IP] $STATUS_LABEL | Report suppressed (Local connectivity lost)${NC}"
      fi
    else
      # Normal report when we have local connectivity
      echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${COLOR}[$IP] $STATUS_LABEL | OK: $OK_PINGS, ${LOSS_COLOR}Lost:${NC} ${LOSS_COLOR}$LOST_PINGS (${LOSS_PERCENT}%)${NC}, ${RTT_LABEL_COLOR}RTT:${NC} ${MIN_RTT_COLOR}${MIN_RTT}${NC}/${AVG_RTT_COLOR}${RTT_AVG}${NC}/${MAX_RTT_COLOR}${MAX_RTT}${NC}, ${TTL_COLOR}TTL:${NC} ${TTL_COLOR}${TTL}${NC}, ${JITTER_COLOR}Jitter:${NC} ${JITTER_COLOR}${JITTER}${NC}, ${MOS_COLOR}MOS:${NC} ${MOS_COLOR}${MOS}${NC}, ${MOS_COLOR}R-factor:${NC} ${MOS_COLOR}${R_FACTOR}${NC}"
    fi

    # Call hook if available - passing metrics as JSON for extensibility
    if type hook_on_status_report &>/dev/null; then
      local status_json
      status_json="{\"ip\":\"$IP\",\"status\":\"up\",\"timestamp\":\"$(date +%s)\",\"metrics\":{\"ok_pings\":$OK_PINGS,\"lost_pings\":$LOST_PINGS,\"loss_percent\":$LOSS_PERCENT,\"rtt\":{\"min\":$MIN_RTT,\"avg\":$RTT_AVG,\"max\":$MAX_RTT},\"ttl\":$TTL,\"jitter\":$JITTER,\"mos\":\"$MOS\",\"r_factor\":\"$R_FACTOR\"}}"
      hook_on_status_report "$IP" "$status_json"
    fi

    # Check if we're in the grace period and need to reset statistics
    if [ "$(date +%s)" -lt "$CONNECTIVITY_GRACE_PERIOD_UNTIL" ]; then
      reset_all_statistics
    fi
  else
    # For DOWN hosts, we don't show regular report, just set metrics to N/A
    # for completeness (though we won't be using them)
    STATUS_LABEL="[DOWN] 🛑"
    COLOR="$RED"
    MIN_RTT="N/A"
    RTT_AVG="N/A"
    MAX_RTT="N/A"
    TTL="N/A"
    JITTER="N/A"
    MOS="N/A"
    R_FACTOR="N/A"
  fi
}

# Helper function to reset all statistics - used during grace period
reset_all_statistics() {
  # Reset all counters
  OK_PINGS=0
  LOST_PINGS=0
  CONSECUTIVE_LOSS=0
  START_TS=$(date +%s)

  # Reset min/max RTT values
  MIN_RTT="9999.9"
  MAX_RTT="0.0"
  RECENT_RTT=()
  JITTER="0.0"

  # If network was marked as down, mark it up again
  if ! $NETWORK_OK; then
    NETWORK_OK=true
    return 1  # Indicate network state changed
  fi

  return 0  # Indicate just counters reset
}

# Function to start monitoring processes from JSON configuration
# Reads targets.json and starts a monitoring process for each target
# Manages PID registration for later cleanup
run_monitors() {
  # Reset arrays to keep track of monitoring processes and fping processes
  MONITOR_PIDS=()
  MONITOR_TARGETS=()
  FPING_PIDS=()
  FPING_TARGETS=()

  # If supporting associative arrays, clear that too
  if [ $BASH_SUPPORTS_ASSOC_ARRAYS -eq 1 ]; then
    # Clearing associative array is different syntax in bash 4+
    declare -A FPING_PROCESSES=()
  fi

  # Clear the screen for a fresh start
  clear

  while IFS= read -r target; do
    local IP
    IP=$(echo "$target" | jq -r '.ip')

    local PING_FREQUENCY
    PING_FREQUENCY=$(echo "$target" | jq -r '.ping_frequency // "1"')

    local LOSS_THRESH
    LOSS_THRESH=$(echo "$target" | jq -r '.consecutive_loss_threshold')

    local LOSS_ALERT
    LOSS_ALERT=$(echo "$target" | jq -r '.loss_threshold_pct')

    local REPORT_INTERVAL
    REPORT_INTERVAL=$(echo "$target" | jq -r '.report_interval // "60"')

    # Check the read values
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo "Target: $IP, Ping Frequency: ${PING_FREQUENCY}s, Loss Threshold: $LOSS_THRESH, Loss Alert: $LOSS_ALERT%, Report Interval: ${REPORT_INTERVAL}s"
    fi

    # Start the monitoring process in the background
    monitor_target "$IP" "$PING_FREQUENCY" "$LOSS_THRESH" "$LOSS_ALERT" "$REPORT_INTERVAL" &
    local pid
    pid=$!
    MONITOR_PIDS+=("$pid")
    MONITOR_TARGETS+=("$IP")

    # Use a short sleep to allow the process to start
    sleep 0.5
  done < <(jq -c '.targets[]' "$TARGET_FILE")

  # Show process information if we have started processes
  if [ ${#MONITOR_PIDS[@]} -gt 0 ]; then
    echo -e "${GREEN}Started ${#MONITOR_PIDS[@]} monitoring processes.${NC}"

    # Always show the process ID to target mapping
    echo -e "${CYAN}=== Monitoring Processes ===${NC}"
    for ((i=0; i<${#MONITOR_PIDS[@]}; i++)); do
      echo -e "  ${YELLOW}Process ${MONITOR_PIDS[$i]}${NC} -> ${GREEN}${MONITOR_TARGETS[$i]}${NC}"
    done
  else
    echo -e "${RED}Error: Could not start any monitoring processes!${NC}"
    exit 1
  fi

  # Wait for all processes to complete
  wait
}