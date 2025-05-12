#!/usr/bin/env bash
#
# Network Quality Monitor - Metrics Calculation Module
#
# This module provides functions for calculating network quality metrics
# including MOS, R-factor, and other VoIP quality indicators.
#
# Author: Cristian O.
# Version: 1.2.0
#

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
# $1: latency in ms (RTT)
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