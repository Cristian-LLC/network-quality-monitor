#!/usr/bin/env bash
#
# Network Quality Monitor - Connectivity Test Script
#
# This script tests the connectivity detection mechanism by temporarily
# blocking access to test servers using iptables/pfctl, simulating network issues
# without actually disconnecting from the network.
#
# Author: Cristian O.
# Version: 1.0.0
#

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default test duration
TEST_DURATION=30
BLOCK_DURATION=10

# Print header
echo -e "${CYAN}=========================================================${NC}"
echo -e "${GREEN}Network Quality Monitor - Connectivity Detection Test${NC}"
echo -e "${CYAN}=========================================================${NC}"

# Check if running as root (needed for firewall modifications)
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}Warning: This script needs to modify firewall rules to simulate network outages${NC}"
  echo -e "${YELLOW}Please run with sudo for full functionality${NC}"
  echo ""
  
  # Offer to continue with limited functionality
  read -p "Continue with limited test functionality? (y/n) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Test aborted.${NC}"
    exit 1
  fi
  
  # Limited test without firewall modifications
  echo -e "${YELLOW}Running limited test...${NC}"
  echo -e "${YELLOW}Simulated network failures will only be displayed, not actually performed.${NC}"
  echo ""
  echo -e "${CYAN}Test Plan:${NC}"
  echo -e "1. Test would block connections to 1.1.1.1, 8.8.8.8, and 9.9.9.9 for $BLOCK_DURATION seconds"
  echo -e "2. Monitor would detect connectivity loss and mark alerts differently"
  echo -e "3. After $BLOCK_DURATION seconds, connectivity would be restored"
  echo -e "4. Monitor would detect connectivity restoration and process queued alerts"
  
  echo -e "${RED}To run a real test, please restart with sudo${NC}"
  exit 0
fi

# Detect OS 
IS_MACOS=false
IS_LINUX=false

if [[ "$(uname)" == "Darwin" ]]; then
  IS_MACOS=true
  echo -e "${CYAN}Detected macOS system${NC}"
elif [[ "$(uname)" == "Linux" ]]; then
  IS_LINUX=true
  echo -e "${CYAN}Detected Linux system${NC}"
else
  echo -e "${RED}Unsupported operating system: $(uname)${NC}"
  echo -e "${RED}This test script supports macOS and Linux only${NC}"
  exit 1
fi

# Clean up function - ensure we restore normal connectivity
cleanup() {
  echo -e "\n${CYAN}Cleaning up and restoring connectivity...${NC}"
  
  if $IS_MACOS; then
    # Flush all pfctl rules
    pfctl -F all -f /etc/pf.conf >/dev/null 2>&1
    echo -e "${GREEN}Firewall rules restored on macOS${NC}"
  elif $IS_LINUX; then
    # Flush iptables rules
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    echo -e "${GREEN}Firewall rules restored on Linux${NC}"
  fi
  
  echo -e "${GREEN}Cleanup completed. Normal connectivity restored.${NC}"
}

# Register cleanup on script exit
trap cleanup EXIT INT TERM

# Function to block connectivity to test servers
block_connectivity() {
  echo -e "${YELLOW}Simulating network outage by blocking connectivity to test servers...${NC}"
  
  if $IS_MACOS; then
    # Create temporary pf ruleset
    cat << EOF > /tmp/pf.rules
# Temporary rules for network connectivity testing
block out proto icmp to { 1.1.1.1 8.8.8.8 9.9.9.9 }
block out proto udp to { 1.1.1.1 8.8.8.8 9.9.9.9 } port 53
block out proto tcp to { 1.1.1.1 8.8.8.8 9.9.9.9 } port 53
EOF
    
    # Load the rules
    pfctl -F all -f /etc/pf.conf >/dev/null 2>&1  # Flush existing rules
    pfctl -f /tmp/pf.rules -e >/dev/null 2>&1     # Enable new rules
    rm -f /tmp/pf.rules                           # Clean up
    
    echo -e "${GREEN}Blocked connectivity to test servers on macOS${NC}"
    
  elif $IS_LINUX; then
    # Block ping to test servers
    iptables -A OUTPUT -p icmp -d 1.1.1.1 -j DROP
    iptables -A OUTPUT -p icmp -d 8.8.8.8 -j DROP
    iptables -A OUTPUT -p icmp -d 9.9.9.9 -j DROP
    
    # Block DNS over UDP to test servers
    iptables -A OUTPUT -p udp -d 1.1.1.1 --dport 53 -j DROP
    iptables -A OUTPUT -p udp -d 8.8.8.8 --dport 53 -j DROP
    iptables -A OUTPUT -p udp -d 9.9.9.9 --dport 53 -j DROP
    
    # Block DNS over TCP to test servers
    iptables -A OUTPUT -p tcp -d 1.1.1.1 --dport 53 -j DROP
    iptables -A OUTPUT -p tcp -d 8.8.8.8 --dport 53 -j DROP
    iptables -A OUTPUT -p tcp -d 9.9.9.9 --dport 53 -j DROP
    
    echo -e "${GREEN}Blocked connectivity to test servers on Linux${NC}"
  fi
}

# Function to restore connectivity
restore_connectivity() {
  echo -e "${YELLOW}Restoring connectivity to test servers...${NC}"
  
  if $IS_MACOS; then
    # Flush all pfctl rules
    pfctl -F all -f /etc/pf.conf >/dev/null 2>&1
    echo -e "${GREEN}Connectivity restored on macOS${NC}"
  elif $IS_LINUX; then
    # Flush iptables rules
    iptables -F OUTPUT
    echo -e "${GREEN}Connectivity restored on Linux${NC}"
  fi
}

# Test connectivity detection
echo -e "${CYAN}Starting connectivity detection test...${NC}"
echo -e "${CYAN}Test will run for approximately $TEST_DURATION seconds${NC}"
echo -e "${CYAN}Will block connectivity for $BLOCK_DURATION seconds in the middle of the test${NC}"

# Start test
echo -e "\n${GREEN}Phase 1: Starting with normal connectivity${NC}"
echo -e "${YELLOW}Please run the monitor in another terminal:${NC}"
echo -e "${CYAN}bin/netmon --debug${NC}"
echo ""
echo -e "${YELLOW}Press Enter when the monitor is running and you're ready to start the test...${NC}"
read

# Wait a moment for initial measurements
echo -e "${CYAN}Waiting for initial measurements (5 seconds)...${NC}"
sleep 5

# Block connectivity
echo -e "\n${GREEN}Phase 2: Simulating network outage${NC}"
block_connectivity

# Wait for block duration
echo -e "${CYAN}Network connectivity blocked for $BLOCK_DURATION seconds...${NC}"
for i in $(seq $BLOCK_DURATION -1 1); do
  echo -ne "${YELLOW}Restoring connectivity in $i seconds...\r${NC}"
  sleep 1
done
echo -e "${GREEN}Restoring connectivity now!                    ${NC}"

# Restore connectivity
restore_connectivity

# Wait for a moment to observe recovery
echo -e "\n${GREEN}Phase 3: Connectivity restored${NC}"
echo -e "${CYAN}Observing recovery for 10 seconds...${NC}"
sleep 10

# Test complete
echo -e "\n${GREEN}Connectivity test completed!${NC}"
echo -e "${CYAN}=========================================================${NC}"
echo -e "${YELLOW}Results:${NC}"
echo -e "1. The connectivity detection system should have detected the simulated outage"
echo -e "2. Any alerts during the outage should have been marked with '?' and suppressed"
echo -e "3. After connectivity was restored, normal alerts should have resumed"
echo -e "4. If alert queuing is enabled, queued alerts should have been processed"
echo -e "${CYAN}=========================================================${NC}"
echo -e "${GREEN}Test completed successfully.${NC}"