#!/usr/bin/env bash
#
# verify-dualpi2.sh - Verify DualPI2 L4S AQM configuration
#

echo "=== DualPI2 L4S Verification ==="
echo "Timestamp: $(date)"
echo "Kernel: $(uname -r)"
echo

echo "--- Kernel Module ---"
if lsmod | grep -q dualpi2; then
    echo "✓ sch_dualpi2 module loaded"
    lsmod | grep dualpi2
else
    echo "✗ sch_dualpi2 module NOT loaded"
fi
echo

echo "--- Default Qdisc ---"
default_qdisc=$(cat /proc/sys/net/core/default_qdisc)
if [ "$default_qdisc" = "dualpi2" ]; then
    echo "✓ default_qdisc = $default_qdisc"
else
    echo "✗ default_qdisc = $default_qdisc (expected: dualpi2)"
fi
echo

echo "--- ECN (Explicit Congestion Notification) ---"
tcp_ecn=$(cat /proc/sys/net/ipv4/tcp_ecn)
case $tcp_ecn in
    0) echo "✗ tcp_ecn = $tcp_ecn (disabled)" ;;
    1) echo "✓ tcp_ecn = $tcp_ecn (enabled, request ECN)" ;;
    2) echo "✓ tcp_ecn = $tcp_ecn (enabled, request and accept ECN)" ;;
    *) echo "? tcp_ecn = $tcp_ecn (unknown)" ;;
esac
echo

echo "--- TCP Congestion Control ---"
current_cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control)
available_cc=$(cat /proc/sys/net/ipv4/tcp_available_congestion_control)
echo "Current: $current_cc"
echo "Available: $available_cc"
# Check for L4S-compatible CCs
if echo "$available_cc" | grep -q prague; then
    echo "✓ TCP Prague available (L4S-native)"
else
    echo "ℹ TCP Prague not available (requires AccECN kernel patches)"
fi
if echo "$available_cc" | grep -q bbr3; then
    echo "✓ BBRv3 available (L4S team's improved BBR)"
elif echo "$available_cc" | grep -q bbr; then
    echo "ℹ BBR (v1) available"
fi
echo

echo "--- Interface Qdiscs ---"
for iface in enp1s0 br0 wlan_2g wlan_5g; do
    echo "[$iface]"
    if ip link show "$iface" > /dev/null 2>&1; then
        tc qdisc show dev "$iface" 2>&1 | head -3
    else
        echo "  Interface not found"
    fi
    echo
done

echo "--- Service Status ---"
systemctl status dualpi2-qdisc --no-pager 2>&1 | head -10
echo

echo "--- Service Log ---"
if [ -f /tmp/dualpi2-qdisc.log ]; then
    cat /tmp/dualpi2-qdisc.log
else
    echo "No log file found at /tmp/dualpi2-qdisc.log"
fi

