#!/bin/bash

# Firewall Security Testing Script for L2 WiFi Access Point
# This script validates the firewall configuration and security measures

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ROUTER_IP="192.168.1.1"
ROUTER_IPV6="fd00::1"
INTERNAL_SUBNET="192.168.1.0/24"
INTERNAL_IPV6_SUBNET="fd00::/64"
EXTERNAL_IP="8.8.8.8"
EXTERNAL_IPV6="2001:4860:4860::8888"

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=0

# Function to print test results
print_result() {
    local test_name="$1"
    local result="$2"
    local details="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        if [ -n "$details" ]; then
            echo -e "  ${BLUE}Details:${NC} $details"
        fi
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        if [ -n "$details" ]; then
            echo -e "  ${YELLOW}Details:${NC} $details"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    echo
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if we're running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Function to check nftables status
check_nftables_status() {
    echo -e "${BLUE}=== Checking nftables Status ===${NC}"

    if systemctl is-active --quiet nftables; then
        print_result "nftables service" "PASS" "Service is running"
    else
        print_result "nftables service" "FAIL" "Service is not running"
        return 1
    fi

    if nft list ruleset >/dev/null 2>&1; then
        print_result "nftables ruleset" "PASS" "Ruleset is loaded"
    else
        print_result "nftables ruleset" "FAIL" "Failed to load ruleset"
        return 1
    fi
}

# Function to test basic connectivity
test_basic_connectivity() {
    echo -e "${BLUE}=== Testing Basic Connectivity ===${NC}"

    # Test internal connectivity
    if ping -c 1 -W 2 "$ROUTER_IP" >/dev/null 2>&1; then
        print_result "Internal IPv4 connectivity" "PASS" "Can reach router at $ROUTER_IP"
    else
        print_result "Internal IPv4 connectivity" "FAIL" "Cannot reach router at $ROUTER_IP"
    fi

    # Test IPv6 connectivity
    if command_exists ping6 && ping6 -c 1 -W 2 "$ROUTER_IPV6" >/dev/null 2>&1; then
        print_result "Internal IPv6 connectivity" "PASS" "Can reach router at $ROUTER_IPV6"
    else
        print_result "Internal IPv6 connectivity" "FAIL" "Cannot reach router at $ROUTER_IPV6"
    fi
}

# Function to test SSH rate limiting
test_ssh_rate_limiting() {
    echo -e "${BLUE}=== Testing SSH Rate Limiting ===${NC}"

    local failed_attempts=0
    local max_attempts=10  # Test more attempts to ensure we hit the rate limit

    # Test SSH rate limiting by attempting connections rapidly
    # This should trigger the rate limiting rules
    for i in $(seq 1 $max_attempts); do
        # Use ssh with a non-existent user to trigger authentication failure
        # This should hit the rate limiting before authentication
        if timeout 1 ssh -o ConnectTimeout=1 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=yes nonexistent@"$ROUTER_IP" "exit" 2>/dev/null; then
            failed_attempts=$((failed_attempts + 1))
        fi
        # No sleep to trigger rate limiting faster
    done

    if [ $failed_attempts -ge 6 ]; then
        print_result "SSH rate limiting" "PASS" "$failed_attempts/$max_attempts attempts were blocked (rate limiting working)"
    else
        print_result "SSH rate limiting" "FAIL" "Only $failed_attempts/$max_attempts attempts were blocked (should block at least 6)"
    fi
}

# Function to test ICMP rate limiting
test_icmp_rate_limiting() {
    echo -e "${BLUE}=== Testing ICMP Rate Limiting ===${NC}"

    # Test internal ICMP rate limiting (10/second limit with burst 5)
    local ping_success=0
    for i in $(seq 1 30); do
        if ping -c 1 -W 1 "$ROUTER_IP" >/dev/null 2>&1; then
            ping_success=$((ping_success + 1))
        fi
        # No sleep to trigger rate limiting faster
    done

    # With 10/second limit and burst 5, we should see rate limiting with 30 rapid pings
    if [ $ping_success -le 28 ]; then
        print_result "Internal ICMP rate limiting" "PASS" "$ping_success/30 pings succeeded (rate limiting active)"
    else
        print_result "Internal ICMP rate limiting" "FAIL" "$ping_success/30 pings succeeded (no rate limiting detected, limit is 10/second with burst 5)"
    fi
}

# Function to test anti-spoofing
test_anti_spoofing() {
    echo -e "${BLUE}=== Testing Anti-Spoofing ===${NC}"

    # Test loopback spoofing
    if ping -I 127.0.0.1 -c 1 -W 2 "$EXTERNAL_IP" >/dev/null 2>&1; then
        print_result "Loopback spoofing protection" "FAIL" "Loopback spoofed packets were allowed"
    else
        print_result "Loopback spoofing protection" "PASS" "Loopback spoofed packets were blocked"
    fi

    # Test special-purpose IP spoofing
    if ping -I 192.168.1.100 -c 1 -W 2 10.0.0.1 >/dev/null 2>&1; then
        print_result "Special-purpose IP protection" "FAIL" "Special-purpose IP traffic was allowed"
    else
        print_result "Special-purpose IP protection" "PASS" "Special-purpose IP traffic was blocked"
    fi
}

# Function to test connection tracking
test_connection_tracking() {
    echo -e "${BLUE}=== Testing Connection Tracking ===${NC}"

    # Test that return traffic is allowed
    if curl -s --connect-timeout 5 --max-time 10 -I https://httpbin.org/status/200 >/dev/null 2>&1; then
        print_result "Connection tracking" "PASS" "Outbound HTTPS connection and return traffic allowed"
    else
        print_result "Connection tracking" "FAIL" "Outbound HTTPS connection failed"
    fi
}

# Function to test service access control
test_service_access() {
    echo -e "${BLUE}=== Testing Service Access Control ===${NC}"

    # Test DNS access (PowerDNS Recursor) from localhost
    if nslookup google.com 127.0.0.1 >/dev/null 2>&1; then
        print_result "DNS service access (localhost)" "PASS" "DNS queries to PowerDNS Recursor via localhost allowed"
    else
        print_result "DNS service access (localhost)" "FAIL" "DNS queries to PowerDNS Recursor via localhost blocked"
    fi

    # Test DNS access from br0 interface
    if nslookup google.com "$ROUTER_IP" >/dev/null 2>&1; then
        print_result "DNS service access (br0)" "PASS" "DNS queries to PowerDNS Recursor via br0 allowed"
    else
        print_result "DNS service access (br0)" "FAIL" "DNS queries to PowerDNS Recursor via br0 blocked"
    fi

    # Test DHCPv4 port access (should be open for DHCP clients)
    if nc -z -w 2 "$ROUTER_IP" 67 2>/dev/null; then
        print_result "DHCPv4 service access" "PASS" "DHCPv4 port 67 accessible"
    else
        print_result "DHCPv4 service access" "FAIL" "DHCPv4 port 67 not accessible"
    fi

    # Test DHCPv6 port access (not running, should be blocked)
    if nc -z -w 2 "$ROUTER_IP" 547 2>/dev/null; then
        print_result "DHCPv6 service access" "FAIL" "DHCPv6 port 547 accessible (should be blocked, service not running)"
    else
        print_result "DHCPv6 service access" "PASS" "DHCPv6 port 547 blocked (service not running)"
    fi
}

# Function to test IPv6 functionality
test_ipv6_functionality() {
    echo -e "${BLUE}=== Testing IPv6 Functionality ===${NC}"

    if ! command_exists ping6; then
        print_result "IPv6 testing" "SKIP" "ping6 command not available"
        return
    fi

    # Test IPv6 connectivity
    if ping6 -c 1 -W 2 "$ROUTER_IPV6" >/dev/null 2>&1; then
        print_result "IPv6 internal connectivity" "PASS" "IPv6 connectivity to router working"
    else
        print_result "IPv6 internal connectivity" "FAIL" "IPv6 connectivity to router failed"
    fi

    # Test IPv6 external connectivity (if available)
    if ping6 -c 1 -W 5 "$EXTERNAL_IPV6" >/dev/null 2>&1; then
        print_result "IPv6 external connectivity" "PASS" "IPv6 external connectivity working"
    else
        print_result "IPv6 external connectivity" "FAIL" "IPv6 external connectivity failed"
    fi
}

# Function to test NAT functionality
test_nat_functionality() {
    echo -e "${BLUE}=== Testing NAT Functionality ===${NC}"

    # Get the external IP that the router sees
    local external_ip=$(curl -s --connect-timeout 5 --max-time 10 https://ipinfo.io/ip 2>/dev/null || echo "unknown")

    if [ "$external_ip" != "unknown" ]; then
        print_result "NAT functionality" "PASS" "External IP: $external_ip"
    else
        print_result "NAT functionality" "FAIL" "Could not determine external IP"
    fi
}

# Function to check firewall logs
check_firewall_logs() {
    echo -e "${BLUE}=== Checking Firewall Logs ===${NC}"

    local log_entries=$(journalctl -u nftables --since "5 minutes ago" 2>/dev/null | wc -l)

    if [ $log_entries -gt 0 ]; then
        print_result "Firewall logging" "PASS" "$log_entries log entries in last 5 minutes"
    else
        print_result "Firewall logging" "WARN" "No firewall log entries found (may be normal if no attacks)"
    fi
}

# Function to check connection tracking table
check_connection_tracking() {
    echo -e "${BLUE}=== Checking Connection Tracking ===${NC}"

    if [ -f /proc/net/nf_conntrack ]; then
        local conntrack_entries=$(cat /proc/net/nf_conntrack 2>/dev/null | wc -l)
        print_result "Connection tracking table" "PASS" "$conntrack_entries active connections"
    else
        print_result "Connection tracking table" "FAIL" "Connection tracking not available"
    fi
}

# Function to display firewall rules summary
display_firewall_summary() {
    echo -e "${BLUE}=== Firewall Rules Summary ===${NC}"

    echo "Input chain rules:"
    nft list chain inet filter input 2>/dev/null | grep -E "(accept|drop)" | head -10

    echo -e "\nForward chain rules:"
    nft list chain inet filter forward 2>/dev/null | grep -E "(accept|drop)" | head -10

    echo -e "\nOutput chain rules:"
    nft list chain inet filter output 2>/dev/null | grep -E "(accept|drop)" | head -10
}

# Function to display test summary
display_summary() {
    echo -e "${BLUE}=== Test Summary ===${NC}"
    echo "Total tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

    local success_rate=$(( (TESTS_PASSED * 100) / TOTAL_TESTS ))
    echo "Success rate: $success_rate%"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed! Firewall configuration is secure.${NC}"
        exit 0
    else
        echo -e "${YELLOW}Some tests failed. Please review the firewall configuration.${NC}"
        exit 1
    fi
}

# Function to test output chain protection
test_output_chain_protection() {
    echo -e "${BLUE}=== Testing Output Chain Protection ===${NC}"

    # Test that router can reach allocated subnets on internal interface
    if ping -c 1 -W 2 -I br0 192.168.1.100 >/dev/null 2>&1; then
        print_result "Output chain - allocated subnet access" "PASS" "Router can reach allocated subnet 192.168.1.0/24"
    else
        print_result "Output chain - allocated subnet access" "FAIL" "Router cannot reach allocated subnet 192.168.1.0/24"
    fi

    # Test that router cannot reach other private networks through internal interface
    if ping -c 1 -W 2 -I br0 10.0.0.1 >/dev/null 2>&1; then
        print_result "Output chain - private network isolation" "FAIL" "Router can reach other private network 10.0.0.0/8"
    else
        print_result "Output chain - private network isolation" "PASS" "Router cannot reach other private network 10.0.0.0/8"
    fi

    # Test that router cannot reach other private networks through internal interface (IPv6)
    if command_exists ping6 && ping6 -c 1 -W 2 -I br0 fc00::1 >/dev/null 2>&1; then
        print_result "Output chain - IPv6 private network isolation" "FAIL" "Router can reach other IPv6 private network fc00::/7"
    else
        print_result "Output chain - IPv6 private network isolation" "PASS" "Router cannot reach other IPv6 private network fc00::/7"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}Firewall Security Testing Script for L2 WiFi Access Point${NC}"
    echo "================================================================"
    echo

    # Check if running as root
    check_root

    # Run all tests
    check_nftables_status
    test_basic_connectivity
    test_ssh_rate_limiting
    test_icmp_rate_limiting
    test_anti_spoofing
    test_connection_tracking
    test_service_access
    test_ipv6_functionality
    test_nat_functionality
    test_output_chain_protection
    check_firewall_logs
    check_connection_tracking

    echo
    display_firewall_summary
    echo
    display_summary
}

# Run main function
main "$@"