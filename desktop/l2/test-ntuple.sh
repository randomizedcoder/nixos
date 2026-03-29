#!/usr/bin/env bash
#
# Test what ntuple filter types are supported by ixgbe (82599ES)
#

IFACE="${1:-enp66s0f0}"

echo "Testing ntuple filter support on $IFACE"
echo "========================================="
echo

# Function to test a rule
test_rule() {
    local desc="$1"
    local rule="$2"

    printf "%-50s " "$desc"

    if output=$(ethtool --config-ntuple "$IFACE" $rule 2>&1); then
        # Extract rule ID and delete it
        rule_id=$(echo "$output" | grep -oP 'ID \K[0-9]+')
        echo "OK (rule $rule_id)"
        if [ -n "$rule_id" ]; then
            ethtool --config-ntuple "$IFACE" delete "$rule_id" 2>/dev/null
        fi
    else
        echo "FAILED: $output"
    fi
}

echo "Port-based filters:"
echo "-------------------"
test_rule "tcp4 dst-port only" "flow-type tcp4 dst-port 12345 action -1"
test_rule "tcp4 src-port only" "flow-type tcp4 src-port 12345 action -1"
test_rule "udp4 dst-port only" "flow-type udp4 dst-port 12345 action -1"
test_rule "udp4 src-port only" "flow-type udp4 src-port 12345 action -1"
test_rule "tcp4 src+dst port" "flow-type tcp4 src-port 1111 dst-port 2222 action -1"

echo
echo "IP-based filters:"
echo "-----------------"
test_rule "tcp4 src-ip only" "flow-type tcp4 src-ip 1.2.3.4 action -1"
test_rule "tcp4 dst-ip only" "flow-type tcp4 dst-ip 1.2.3.4 action -1"
test_rule "tcp4 src-ip + dst-ip" "flow-type tcp4 src-ip 1.2.3.4 dst-ip 5.6.7.8 action -1"
test_rule "udp4 src-ip only" "flow-type udp4 src-ip 1.2.3.4 action -1"

echo
echo "Combined IP + port filters:"
echo "---------------------------"
test_rule "tcp4 src-ip + dst-port" "flow-type tcp4 src-ip 1.2.3.4 dst-port 443 action -1"
test_rule "tcp4 dst-ip + dst-port" "flow-type tcp4 dst-ip 1.2.3.4 dst-port 443 action -1"
test_rule "tcp4 src-ip + dst-ip + dst-port" "flow-type tcp4 src-ip 1.2.3.4 dst-ip 5.6.7.8 dst-port 443 action -1"

echo
echo "Raw IP (no protocol):"
echo "---------------------"
test_rule "ip4 src-ip only" "flow-type ip4 src-ip 1.2.3.4 action -1"
test_rule "ip4 dst-ip only" "flow-type ip4 dst-ip 1.2.3.4 action -1"

echo
echo "Queue steering (action 0 = queue 0):"
echo "------------------------------------"
test_rule "tcp4 dst-port to queue 0" "flow-type tcp4 dst-port 12345 action 0"

echo
echo "Current rules:"
echo "--------------"
ethtool --show-ntuple "$IFACE"
