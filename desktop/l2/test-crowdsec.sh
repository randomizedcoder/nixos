#!/bin/bash

# CrowdSec SSH Attack Simulation Test
# This script simulates SSH brute force attacks to test CrowdSec detection

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CROWDSEC_CONFIG="/nix/store/r236yjfapykriw64g52mqih6fz3lis5l-crowdsec.yaml"
ROUTER_IP="192.168.1.1"

echo -e "${BLUE}CrowdSec SSH Attack Simulation Test${NC}"
echo "=========================================="
echo

# Function to print test results
print_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        if [ -n "$details" ]; then
            echo -e "  ${BLUE}Details:${NC} $details"
        fi
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        if [ -n "$details" ]; then
            echo -e "  ${YELLOW}Details:${NC} $details"
        fi
    fi
    echo
}

# Check if CrowdSec is running
echo -e "${BLUE}=== Checking CrowdSec Status ===${NC}"
if systemctl is-active --quiet crowdsec; then
    print_result "CrowdSec Engine" "PASS" "Service is running"
else
    print_result "CrowdSec Engine" "FAIL" "Service is not running"
    exit 1
fi

if systemctl is-active --quiet crowdsec-firewall-bouncer; then
    print_result "CrowdSec Firewall Bouncer" "PASS" "Service is running"
else
    print_result "CrowdSec Firewall Bouncer" "FAIL" "Service is not running"
    exit 1
fi

# Check initial state
echo -e "${BLUE}=== Initial State ===${NC}"
initial_decisions=$(sudo cscli decisions list -c "$CROWDSEC_CONFIG" | wc -l)
print_result "Initial decisions" "INFO" "$initial_decisions active decisions"

# Simulate SSH brute force attack
echo -e "${BLUE}=== Simulating SSH Brute Force Attack ===${NC}"
echo "Attempting 20 SSH connections with invalid credentials..."

for i in $(seq 1 20); do
    echo -n "Attempt $i/20... "
    if timeout 2 ssh -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=yes attacker@"$ROUTER_IP" "exit" 2>/dev/null; then
        echo "FAILED (unexpected success)"
    else
        echo "BLOCKED (expected)"
    fi
    sleep 0.1
done

# Wait for CrowdSec to process the events
echo -e "\n${BLUE}=== Waiting for CrowdSec Processing ===${NC}"
echo "Waiting 10 seconds for CrowdSec to process events..."
sleep 10

# Check if decisions were created
echo -e "${BLUE}=== Checking for Decisions ===${NC}"
final_decisions=$(sudo cscli decisions list -c "$CROWDSEC_CONFIG" | wc -l)
decision_count=$((final_decisions - initial_decisions))

if [ $decision_count -gt 0 ]; then
    print_result "SSH attack detection" "PASS" "CrowdSec detected $decision_count new decisions"

    # Show the decisions
    echo -e "${BLUE}=== Active Decisions ===${NC}"
    sudo cscli decisions list -c "$CROWDSEC_CONFIG"
else
    print_result "SSH attack detection" "FAIL" "No new decisions created"
fi

# Check if IPs were added to blacklist
echo -e "${BLUE}=== Checking nftables Blacklist ===${NC}"
blacklist_entries=$(sudo nft list set inet filter blacklist 2>/dev/null | grep -c "elements" || echo "0")

if [ $blacklist_entries -gt 0 ]; then
    print_result "nftables blacklist" "PASS" "Blacklist contains $blacklist_entries entries"

    # Show blacklist contents
    echo -e "${BLUE}=== Blacklist Contents ===${NC}"
    sudo nft list set inet filter blacklist
else
    print_result "nftables blacklist" "FAIL" "No entries in blacklist"
fi

# Test if the attacking IP is actually blocked
echo -e "${BLUE}=== Testing IP Blocking ===${NC}"
# We can't easily test this from the router itself, but we can check the logs
recent_logs=$(journalctl -u crowdsec --since "2 minutes ago" | grep -c "decision" || echo "0")

if [ $recent_logs -gt 0 ]; then
    print_result "CrowdSec logging" "PASS" "Found $recent_logs recent decision logs"
else
    print_result "CrowdSec logging" "FAIL" "No recent decision logs found"
fi

echo -e "${BLUE}=== Test Summary ===${NC}"
echo "CrowdSec SSH monitoring test completed."
echo "To verify blocking works, test from an external machine:"
echo "  ssh attacker@$ROUTER_IP  # Should be blocked if detection worked"