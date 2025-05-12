#!/usr/bin/env bash
set -e

################################################################################
# Network Quality Monitor - Advanced Network Quality Assessment Tool
################################################################################
#
# DESCRIPTION:
#   Script for real-time network monitoring using fping in loop mode.
#   Provides advanced statistics like RTT, jitter, TTL and MOS (Mean Opinion Score)
#   for network quality evaluation. Useful for diagnosing connectivity issues,
#   latency fluctuations, and packet loss.
#
# USAGE:
#   ./ping.sh
#
# REQUIREMENTS:
#   - fping: install via `brew install fping` (MacOS) or `apt install fping` (Linux)
#   - jq: for JSON file processing
#   - bc: for mathematical calculations
#
# CONFIGURATION:
#   - Configuration is done through the targets.json file with the following structure:
#   [
#     {
#       "ip": "1.1.1.1",                   # IP address or hostname to monitor
#       "ping_frequency": 1,               # Ping frequency in seconds
#       "consecutive_loss_threshold": 2,   # How many lost packets for DOWN alert
#       "loss_threshold_pct": 10,          # Loss percentage threshold for LOSS alert
#       "report_interval": 10              # Report interval in seconds
#     }
#   ]
#
# AUTHOR: Cristian O.
# VERSION: 1.2.0
# DATE: 2023-05-11
#
################################################################################

# Default options
TARGET_FILE="targets.json"
SHOW_DEBUG="false"

# Command line parameter processing
show_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help                 Show this help"
  echo "  -f, --file FILENAME        Specify a different config file (default: targets.json)"
  echo "  -d, --debug                Show additional debug information"
  echo "  -v, --version              Show program version"
  echo ""
  echo "Examples:"
  echo "  $0                        Run with targets.json from current directory"
  echo "  $0 -f custom.json         Run with custom.json"
  echo "  $0 --debug                Show detailed debugging information"
  exit 0
}

show_version() {
  echo "Network Quality Monitor v1.2.0"
  echo "Copyright © 2025 Cristian O."
  exit 0
}

# Process command line parameters
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)
      show_help
      ;;
    -f|--file)
      if [ -z "$2" ]; then
        echo "Error: Option -f requires a parameter."
        exit 1
      fi
      TARGET_FILE="$2"
      shift
      ;;
    -d|--debug)
      SHOW_DEBUG="true"
      ;;
    -v|--version)
      show_version
      ;;
    *)
      echo "Unknown option: $1"
      echo "Run '$0 --help' to see available options."
      exit 1
      ;;
  esac
  shift
done
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Collect the PIDs of all subprocesses and store metadata
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
    # Now test if we can actually create one (some systems may report 4+ but not support it)
    if (
      # Try in a subshell to avoid affecting the main script
      set +e  # Don't exit on error
      declare -A test_array 2>/dev/null
      echo $? # Return status
    ) ; then
      BASH_SUPPORTS_ASSOC_ARRAYS=1
      # Actually declare our associative array now
      declare -A FPING_PROCESSES
    fi
  fi
fi

# Debug bash version info
if [ "$SHOW_DEBUG" = "true" ]; then
  echo "Bash version: $BASH_VERSION (major: $BASH_VERSION_MAJOR)"
  echo "Support for associative arrays: $([ $BASH_SUPPORTS_ASSOC_ARRAYS -eq 1 ] && echo "Yes" || echo "No")"
fi

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
      local fping_pids=$(ps -o pid,command | grep "[f]ping.*$target" | awk '{print $1}')

      if [[ -n "$fping_pids" ]]; then
        child_info="fping: $fping_pids"
      else
        # Try to get any children
        local all_children=$(pgrep -P "$pid" 2>/dev/null || echo "")
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

  # Clean up temporary files (named pipes)
  local num_fifos
  num_fifos=$(ls -1 /tmp/fping_fifo_* 2>/dev/null | wc -l)
  if [ "$num_fifos" -gt 0 ]; then
    echo -e "${CYAN}Cleaning up $num_fifos temporary files...${NC}"
    rm -f /tmp/fping_fifo_*
  fi

  # Final verification to make sure all processes are properly terminated
  local remaining_fping=$(ps -o pid,command | grep "[f]ping" | grep -v grep | wc -l)
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

# Simplified function for mathematical calculations using bc with error handling
# $1: mathematical expression to calculate
# $2: optional - "positive" if the result should be positive
# Return: calculation result or 0 in case of error
safe_bc() {
  local expr="$1"
  local result
  result=$(echo "scale=1; $expr" | bc -l 2>/dev/null || echo "0")
  # Remove minus sign from results that should be positive
  if [[ "$result" == -* && "$2" == "positive" ]]; then
    result="${result#-}"
  fi
  echo "$result"
}

# Function to calculate MOS and R-factor according to ITU-T G.107 E-model
# R-factor bands and perceived quality:
# ≥ 81 = Excellent/PSTN-like (Green)
# 71-80 = Good - most users satisfied (Light-green/Yellow)
# 61-70 = Fair - some complaints (Yellow)
# 51-60 = Poor - many users dissatisfied (Orange)
# <50 = Bad - nearly all users dissatisfied (Red)
#
# MOS ranges (converted from R-factor):
# >4.0 = Excellent/Good (Green)
# 3.6-4.0 = Fair (Yellow)
# 3.1-3.5 = Poor (Orange)
# <3.0 = Bad (Red)
#
# $1: latency in ms (one-way estimate from RTT)
# $2: jitter in ms
# Return: MOS score and R-factor in format "MOS:R-factor"
calculate_mos() {
  local rtt="$1"     # RTT in ms
  local jitter="$2"  # Jitter in ms

  # Estimate one-way delay (Ta) from RTT (roughly RTT/2)
  local Ta
  Ta=$(safe_bc "$rtt/2" "positive")

  # Estimate packet loss - since we don't have direct packet loss measurement,
  # we'll use jitter as a proxy (high jitter often correlates with packet loss)
  local Ppl=0  # Packet loss percentage
  local Bpl=10 # Packet loss robustness factor (default for G.711 codec)

  if (( $(echo "$jitter > 30" | bc -l) )); then
    Ppl=2.0  # 2% packet loss
  elif (( $(echo "$jitter > 10" | bc -l) )); then
    Ppl=0.5  # 0.5% packet loss
  fi

  # Calculate R-factor components according to ITU-T G.107
  local R0=93.2      # Default basic signal-to-noise ratio
  local Is=1.4       # Default simultaneous impairment factor

  # Calculate Id (delay impairment)
  # Using simplified Id calculation based on one-way delay (Ta)
  local Id=0
  if (( $(echo "$Ta > 100" | bc -l) )); then
    # Id increases with delay after 100ms threshold
    Id=$(safe_bc "0.024 * $Ta + 0.11 * ($Ta - 177.3) * ($Ta > 177.3)" "positive")
  fi

  # Calculate Ie-eff (effective equipment impairment)
  # Ie-eff = Ie + (95 - Ie) * (Ppl / (Ppl + Bpl))
  local Ie=0         # Base equipment impairment for G.711

  # Calculate Ie-eff with packet loss effects
  local Ie_eff
  if (( $(echo "$Ppl > 0" | bc -l) )); then
    Ie_eff=$(safe_bc "$Ie + (95 - $Ie) * ($Ppl / ($Ppl + $Bpl))" "positive")
  else
    Ie_eff=$Ie
  fi

  # Include jitter effect - each 20ms of jitter approximates to 1 point of Ie-eff
  Ie_eff=$(safe_bc "$Ie_eff + $jitter/20" "positive")

  # A - advantage factor (mobile users are more tolerant of issues)
  local A=0          # For fixed networks (0 for wired, 10 for cellular, 20 for satellite)

  # Calculate R-factor using G.107 formula
  local R
  R=$(safe_bc "$R0 - $Is - $Id - $Ie_eff + $A" "positive")

  # Round R to integer
  R=$(printf "%.0f" "$R")

  # Ensure R is within 0-100 range
  if (( $(echo "$R > 100" | bc -l) )); then
    R=100
  elif (( $(echo "$R < 0" | bc -l) )); then
    R=0
  fi

  # Convert R to MOS using formula from ITU-T G.107
  local mos
  # MOS = 1 + 0.035*R + 7*10^(-6)*R*(R-60)*(100-R)
  mos=$(safe_bc "1 + 0.035*$R + 0.000007*$R*($R-60)*(100-$R)" "positive")
  mos=$(printf "%.1f" "$mos")

  # Ensure MOS is within 1.0-5.0 range
  if (( $(echo "$mos > 5.0" | bc -l) )); then
    mos="5.0"
  elif (( $(echo "$mos < 1.0" | bc -l) )); then
    mos="1.0"
  fi

  # Return both MOS and R-factor as colon-separated values
  echo "${mos}:${R}"
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
  local JITTER_COLOR=$GREEN
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

  # Now that we're in the background process, show PID in a status message
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${YELLOW}Monitor process ${MONITOR_PID}${NC} active for ${GREEN}$IP${NC}"
  
  # Read fping output and process the data
  while read -r line; do
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

        # Display information about successful ping
        if [ "$SHOW_DEBUG" = "true" ]; then
          echo "Successful ping: RTT=$TIME_MS ms, AVG=$AVG_MS ms, TTL=$TTL_VAL"
        fi

        # For debug - write the entire line and what the regex found
        if [ "$SHOW_DEBUG" = "true" ]; then
          echo "Debug - Line: $line"
          echo "Debug - Parsed: RTT=${BASH_REMATCH[1]}, AVG=${BASH_REMATCH[2]}, TTL=${BASH_REMATCH[3]}"
        fi

        # Calculate jitter using the EWMA (Exponential Weighted Moving Average) method
        # RFC 3550 approach with 1/16 gain factor
        if [ "${#RECENT_RTT[@]}" -gt 1 ]; then
          # If we have a previous RTT value, calculate the difference
          local prev_val="${RECENT_RTT[0]}"
          local current_val="${TIME_MS}"

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
            JITTER_COLOR=$RED
          elif (( $(echo "$JITTER > 10.0" | bc -l) )); then
            JITTER_COLOR=$YELLOW
          else
            JITTER_COLOR=$GREEN
          fi
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

        # Extract the failure reason directly from the line
        local failure_reason="Unknown reason"

        # Try to extract the exact error message
        if [[ "$line" =~ :[[:space:]]*(.*) ]]; then
          # This will capture everything after the colon and space
          local error_part="${BASH_REMATCH[1]}"

          # Remove sequence numbers, brackets and clean up the message
          error_part=$(echo "$error_part" | sed 's/\[[0-9]*\],\s*//' | sed 's/([^)]*)//g' | sed 's/\.$//g' | sed 's/from.*//g' | xargs)

          # Capitalize first letter for consistency
          error_part=$(echo "$error_part" | sed 's/^\([a-z]\)/\U\1/')

          if [ -n "$error_part" ]; then
            failure_reason="$error_part"
          fi
        else
          # Fallback categorization if regex extraction fails
          if [[ "$line" == *"unreachable"* ]]; then
            failure_reason="Host unreachable"
          elif [[ "$line" == *"timeout"* || "$line" == *"timed out"* ]]; then
            failure_reason="Timed out"
          elif [[ "$line" == *"Network unreachable"* ]]; then
            failure_reason="Network unreachable"
          elif [[ "$line" == *"No route to host"* ]]; then
            failure_reason="No route to host"
          elif [[ "$line" == *"Network is down"* ]]; then
            failure_reason="Network is down"
          elif [[ "$line" == *"Destination host unreachable"* || "$line" == *"ICMP Host Unreachable"* ]]; then
            failure_reason="ICMP Host Unreachable"
          fi
        fi

        # For debug
        if [ "$SHOW_DEBUG" = "true" ]; then
          echo "Debug - Parsed error: '$failure_reason' from line: '$line'"
        fi

        # Check if network is down
        if "$NETWORK_OK" && [ $CONSECUTIVE_LOSS -ge "$MAX_CONSECUTIVE_LOSS" ]; then
          alert "$RED" "[$IP] [DOWN] 🛑 ${CONSECUTIVE_LOSS} consecutive losses! Reason: $failure_reason"
          NETWORK_OK=false

          # Call hook if available
          if type hook_on_host_down &>/dev/null; then
            hook_on_host_down "$IP" "$CONSECUTIVE_LOSS" "$failure_reason"
          fi
        fi
      fi
      
      # Check if we need to display the report
      if (( NOW_TS - START_TS >= "$REPORT_INTERVAL" )); then
        TOTAL_PINGS=$((OK_PINGS + LOST_PINGS))

        if [ $TOTAL_PINGS -gt 0 ]; then
          LOSS_PERCENT=$(safe_bc "$LOST_PINGS * 100 / $TOTAL_PINGS")
        else
          LOSS_PERCENT="0.0"
        fi

        # Set color for packet loss
        LOSS_COLOR=$GREEN
        if (( $(echo "$LOSS_PERCENT >= $LOSS_ALERT_THRESHOLD" | bc -l) )); then
          LOSS_COLOR=$RED

          # Only show loss alert if network is UP
          # This prevents showing loss alerts for hosts we already know are down
          if $NETWORK_OK; then
            alert "$RED" "[$IP] 📉 [LOSS ALERT] Excessive packet loss in the last ${REPORT_INTERVAL} seconds: ${LOSS_PERCENT}%"

            # Call hook if available
            if type hook_on_loss_alert &>/dev/null; then
              hook_on_loss_alert "$IP" "${LOSS_PERCENT}" "${REPORT_INTERVAL}"
            fi
          fi
        elif (( $(echo "$LOSS_PERCENT > 0" | bc -l) )); then
          LOSS_COLOR=$YELLOW
        fi

        # Set colors for MIN/AVG/MAX RTT values
        RTT_LABEL_COLOR=$GREEN  # Color for the "RTT:" label

        # Color for MIN RTT
        MIN_RTT_COLOR=$GREEN
        if (( $(echo "$MIN_RTT > 150" | bc -l) )); then
          MIN_RTT_COLOR=$RED
        elif (( $(echo "$MIN_RTT > 80" | bc -l) )); then
          MIN_RTT_COLOR=$YELLOW
        fi

        # Color for AVG RTT - this also determines the label color
        AVG_RTT_COLOR=$GREEN
        if (( $(echo "$RTT_AVG > 150" | bc -l) )); then
          AVG_RTT_COLOR=$RED
          RTT_LABEL_COLOR=$RED
        elif (( $(echo "$RTT_AVG > 80" | bc -l) )); then
          AVG_RTT_COLOR=$YELLOW
          RTT_LABEL_COLOR=$YELLOW
        fi

        # Color for MAX RTT
        MAX_RTT_COLOR=$GREEN
        if (( $(echo "$MAX_RTT > 150" | bc -l) )); then
          MAX_RTT_COLOR=$RED
        elif (( $(echo "$MAX_RTT > 80" | bc -l) )); then
          MAX_RTT_COLOR=$YELLOW
        fi

        # Set color for TTL
        TTL_COLOR=$GREEN
        if [[ "$TTL" != "0" && "$TTL" != "N/A" ]]; then
          # Only do numeric comparison if TTL is a number
          if [[ "$TTL" =~ ^[0-9]+$ ]]; then
            if (( TTL < 64 )); then
              if (( TTL < 32 )); then
                TTL_COLOR=$RED
              else
                TTL_COLOR=$YELLOW
              fi
            fi
          fi
        else
          TTL_COLOR=$CYAN
        fi
        
        # Calculate MOS and R-factor if we have valid RTT
        MOS="N/A"
        R_FACTOR="N/A"
        if [[ "$RTT_AVG" != "0.0" ]]; then
          # If jitter is 0, use a minimum value of 0.1 for calculation
          local jitter_value="$JITTER"
          if [[ "$JITTER" == "0.0" ]]; then
            jitter_value="0.1"
          fi
          # Use helper function to calculate MOS and R-factor
          local CALC_RESULT
          CALC_RESULT=$(calculate_mos "$RTT_AVG" "$jitter_value")
          MOS=$(echo "$CALC_RESULT" | cut -d':' -f1)
          R_FACTOR=$(echo "$CALC_RESULT" | cut -d':' -f2)
        fi
        
        # Status label and color
        if $NETWORK_OK; then
          STATUS_LABEL="[UP] ✅"
          COLOR=$CYAN

          # Add QoS color for MOS/R-factor value based on ITU-T standards
          MOS_COLOR=$CYAN
          if [[ "$MOS" != "N/A" ]] && [[ "$R_FACTOR" != "N/A" ]]; then
            # Color based on R-factor (more accurate than MOS coloring)
            # First check that R_FACTOR is a number
            if [[ "$R_FACTOR" =~ ^[0-9]+$ ]]; then
              if (( R_FACTOR >= 81 )); then
                MOS_COLOR=$GREEN        # Excellent (R ≥ 81)
              elif (( R_FACTOR >= 71 )); then
                MOS_COLOR=$GREEN        # Good (R 71-80)
              elif (( R_FACTOR >= 61 )); then
                MOS_COLOR=$YELLOW       # Fair (R 61-70)
              elif (( R_FACTOR >= 51 )); then
                MOS_COLOR=$YELLOW       # Poor (R 51-60)
              else
                MOS_COLOR=$RED          # Bad (R < 50)
              fi
            fi
          fi

          # Loss alert is now handled in the packet loss calculation section

          # Display report only for UP hosts
          echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${COLOR}[$IP] $STATUS_LABEL | OK: $OK_PINGS, ${LOSS_COLOR}Lost:${NC} ${LOSS_COLOR}$LOST_PINGS (${LOSS_PERCENT}%)${NC}, ${RTT_LABEL_COLOR}RTT:${NC} ${MIN_RTT_COLOR}${MIN_RTT}${NC}/${AVG_RTT_COLOR}${RTT_AVG}${NC}/${MAX_RTT_COLOR}${MAX_RTT}${NC}, ${TTL_COLOR}TTL:${NC} ${TTL_COLOR}${TTL}${NC}, ${JITTER_COLOR}Jitter:${NC} ${JITTER_COLOR}${JITTER}${NC}, ${MOS_COLOR}MOS:${NC} ${MOS_COLOR}${MOS}${NC}, ${MOS_COLOR}R-factor:${NC} ${MOS_COLOR}${R_FACTOR}${NC}"

          # Call hook if available - passing metrics as JSON for extensibility
          if type hook_on_status_report &>/dev/null; then
            local status_json
            status_json="{\"ip\":\"$IP\",\"status\":\"up\",\"timestamp\":\"$(date +%s)\",\"metrics\":{\"ok_pings\":$OK_PINGS,\"lost_pings\":$LOST_PINGS,\"loss_percent\":$LOSS_PERCENT,\"rtt\":{\"min\":$MIN_RTT,\"avg\":$RTT_AVG,\"max\":$MAX_RTT},\"ttl\":$TTL,\"jitter\":$JITTER,\"mos\":\"$MOS\",\"r_factor\":\"$R_FACTOR\"}}"
            hook_on_status_report "$IP" "$status_json"
          fi
        else
          # For DOWN hosts, we don't show regular report, just set metrics to N/A
          # for completeness (though we won't be using them)
          STATUS_LABEL="[DOWN] 🛑"
          COLOR=$RED
          MIN_RTT="N/A"
          RTT_AVG="N/A"
          MAX_RTT="N/A"
          TTL="N/A"
          JITTER="N/A"
          MOS="N/A"
          R_FACTOR="N/A"
        fi
        
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

# Check required dependencies for script execution
# Verifies presence of required utilities (fping, jq, bc) and correct configuration
# Displays error messages and installation suggestions if components are missing
check_dependencies() {
  local tools=("jq" "bc")
  # Variable USE_FPING has been removed - we exclusively use fping now

  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo -e "${RED}Error: $tool is missing. Install it with: brew install $tool${NC}"
      exit 1
    fi
  done

  # Check if fping is available
  if command -v "fping" >/dev/null 2>&1; then
    echo -e "${GREEN}Info: fping detected${NC}"

    # Get fping version for diagnostic purposes
    local FPING_VERSION
    FPING_VERSION=$(fping -v 2>&1 | head -n1 | sed 's/.*version \([0-9.]*\).*/\1/')
    echo -e "${GREEN}fping version: ${FPING_VERSION}${NC}"

    # Check if fping version supports the --print-ttl option
    if ! fping --help 2>&1 | grep -q "\-\-print-ttl"; then
      echo -e "${YELLOW}Warning: Your fping version doesn't support the --print-ttl option. Some statistics may be limited.${NC}"
    fi
  else
    echo -e "${RED}Error: fping is missing. This script requires fping.${NC}"
    echo -e "${RED}Install fping with: brew install fping (MacOS) or apt install fping (Linux)${NC}"
    exit 1
  fi

  # Check if the targets.json file exists
  if [ ! -f "$TARGET_FILE" ]; then
    echo -e "${RED}Error: File $TARGET_FILE does not exist.${NC}"
    echo -e "${YELLOW}Create a targets.json file with the following structure:${NC}"
    echo -e '[
  {
    "ip": "1.1.1.1",
    "ping_frequency": 1,
    "consecutive_loss_threshold": 2,
    "loss_threshold_pct": 10,
    "report_interval": 10
  }
]'
    exit 1
  fi

  # Check JSON file structure
  if ! jq empty "$TARGET_FILE" 2>/dev/null; then
    echo -e "${RED}Error: File $TARGET_FILE does not contain valid JSON.${NC}"
    exit 1
  fi
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
  done < <(jq -c '.[]' "$TARGET_FILE")

  # Show process information if we have started processes
  if [ ${#MONITOR_PIDS[@]} -gt 0 ]; then
    echo -e "${GREEN}Started ${#MONITOR_PIDS[@]} monitoring processes.${NC}"

    # Always show the process ID to target mapping
    echo -e "${CYAN}=== Monitoring Processes ===${NC}"
    for ((i=0; i<${#MONITOR_PIDS[@]}; i++)); do
      echo -e "  ${YELLOW}Process ${MONITOR_PIDS[$i]}${NC} -> ${GREEN}${MONITOR_TARGETS[$i]}${NC}"
    done

    # Additional detailed information in debug mode
    if [ "$SHOW_DEBUG" = "true" ]; then
      echo -e "${CYAN}=== Detailed Process Information ===${NC}"

      # Show detailed process tree
      echo -e "${YELLOW}Process tree:${NC}"
      ps -f -p "${MONITOR_PIDS[*]}" || echo "Process information not available"

      # Get child processes (fping instances)
      echo -e "${YELLOW}Child processes:${NC}"
      for pid in "${MONITOR_PIDS[@]}"; do
        local children
        children=$(pgrep -P "$pid" 2>/dev/null || echo "None")
        echo -e "  ${CYAN}$pid${NC} has child processes: ${GREEN}$children${NC}"
      done
    fi
  else
    echo -e "${RED}Error: Could not start any monitoring processes!${NC}"
    exit 1
  fi

  # Wait for all processes to complete
  wait
}

# Load notification hooks if available
if [ -f "hooks.sh" ]; then
  source hooks.sh
  echo -e "${GREEN}Notification hooks loaded${NC}"
fi

# Run dependencies check
check_dependencies

# Display a banner and instructions at the beginning
echo -e "${CYAN}==========================================================${NC}"
echo -e "${GREEN}Network Quality Monitor v1.2.0 - Starting monitoring processes${NC}"
echo -e "${CYAN}==========================================================${NC}"
echo -e "Press ${GREEN}Ctrl+C${NC} to stop all monitoring processes and exit."
echo -e "${CYAN}==========================================================${NC}"

# Start monitoring
run_monitors