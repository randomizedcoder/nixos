#!/usr/bin/env bash
# Script to show detailed qdisc status, filters, and statistics

set -euo pipefail

# Configuration - can be overridden via environment variables
INTERFACE="${NETEM_INTERFACE:-enp1s0}"  # Network interface (override with NETEM_INTERFACE env var)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Qdisc Status for ${INTERFACE}"
echo "=========================================="
echo ""

# Check if interface exists
if ! ip link show "${INTERFACE}" >/dev/null 2>&1; then
    echo "Error: Interface ${INTERFACE} not found"
    exit 1
fi

# Show interface statistics
echo -e "${BLUE}=== Interface Statistics ===${NC}"
ip -s link show "${INTERFACE}" | grep -A 10 "^[0-9]"
echo ""

# Show root qdisc
echo -e "${BLUE}=== Root Qdisc ===${NC}"
if tc qdisc show dev "${INTERFACE}" root >/dev/null 2>&1; then
    tc -s qdisc show dev "${INTERFACE}" root
else
    echo "  No root qdisc configured"
fi
echo ""

# Show all qdiscs with statistics
echo -e "${BLUE}=== All Qdiscs (with statistics) ===${NC}"
if tc qdisc show dev "${INTERFACE}" >/dev/null 2>&1; then
    tc -s qdisc show dev "${INTERFACE}"
else
    echo "  No qdiscs configured"
fi
echo ""

# Show ingress qdisc
echo -e "${BLUE}=== Ingress Qdisc ===${NC}"
if tc qdisc show dev "${INTERFACE}" ingress >/dev/null 2>&1; then
    tc -s qdisc show dev "${INTERFACE}" ingress
else
    echo "  No ingress qdisc configured"
fi
echo ""

# Show all filters with statistics
echo -e "${BLUE}=== Filters (with statistics) ===${NC}"
if tc filter show dev "${INTERFACE}" >/dev/null 2>&1; then
    tc -s filter show dev "${INTERFACE}"
else
    echo "  No filters configured"
fi
echo ""

# Show ingress filters
echo -e "${BLUE}=== Ingress Filters (with statistics) ===${NC}"
if tc filter show dev "${INTERFACE}" ingress >/dev/null 2>&1; then
    tc -s filter show dev "${INTERFACE}" ingress
else
    echo "  No ingress filters configured"
fi
echo ""

# Check for ifb0 device
if ip link show ifb0 >/dev/null 2>&1; then
    echo -e "${BLUE}=== IFB0 Device Status ===${NC}"
    echo "Interface:"
    ip -s link show ifb0 | grep -A 10 "^[0-9]"
    echo ""
    echo "Qdiscs:"
    if tc qdisc show dev ifb0 >/dev/null 2>&1; then
        tc -s qdisc show dev ifb0
    else
        echo "  No qdiscs on ifb0"
    fi
    echo ""
    echo "Filters:"
    if tc filter show dev ifb0 >/dev/null 2>&1; then
        tc -s filter show dev ifb0
    else
        echo "  No filters on ifb0"
    fi
    echo ""
fi

# Show class statistics if using classful qdiscs
echo -e "${BLUE}=== Class Statistics ===${NC}"
if tc class show dev "${INTERFACE}" >/dev/null 2>&1; then
    tc -s class show dev "${INTERFACE}"
else
    echo "  No classes configured (using classless qdiscs)"
fi
echo ""

# Summary of packet/byte counts
echo -e "${BLUE}=== Summary ===${NC}"
echo "Interface: ${INTERFACE}"
echo ""

# Try to extract packet counts from qdisc statistics
root_stats=$(tc -s qdisc show dev "${INTERFACE}" root 2>/dev/null | grep -E "Sent|bytes|pkt" | head -5 || echo "")
if [ -n "${root_stats}" ]; then
    echo "Root Qdisc Statistics:"
    echo "${root_stats}" | sed 's/^/  /'
    echo ""
fi

# Check for child qdiscs
child_qdiscs=$(tc qdisc show dev "${INTERFACE}" | grep -v "root" | grep -v "^$" || echo "")
if [ -n "${child_qdiscs}" ]; then
    echo "Child Qdiscs:"
    echo "${child_qdiscs}" | while read -r line; do
        handle=$(echo "${line}" | grep -oP 'handle \K[0-9:]+' || echo "")
        if [ -n "${handle}" ]; then
            stats=$(tc -s qdisc show dev "${INTERFACE}" | grep -A 5 "handle ${handle}" | grep -E "Sent|bytes|pkt|drops" | head -3 || echo "")
            echo "  ${line}"
            if [ -n "${stats}" ]; then
                echo "${stats}" | sed 's/^/    /'
            fi
        fi
    done
    echo ""
fi

# Show filter match counts
echo -e "${BLUE}=== Filter Match Counts ===${NC}"
filter_matches=$(tc -s filter show dev "${INTERFACE}" 2>/dev/null | grep -E "filter|match|flowid|Sent|bytes" || echo "")
if [ -n "${filter_matches}" ]; then
    echo "${filter_matches}" | sed 's/^/  /'
else
    echo "  No filter statistics available"
fi
echo ""

# Check for potential issues
echo -e "${YELLOW}=== Potential Issues Check ===${NC}"
issues=0

# Check if ingress is configured (actually check if it has filters, not just if it exists)
ingress_filters=$(tc filter show dev "${INTERFACE}" ingress 2>/dev/null | grep -c "filter" || echo "0")
if [ "${ingress_filters}" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Ingress filters are configured (${ingress_filters} filters)${NC}"
    issues=$((issues + 1))
fi

# Check if ifb0 exists and has traffic
if ip link show ifb0 >/dev/null 2>&1; then
    ifb0_rx=$(ip -s link show ifb0 2>/dev/null | grep -E "^[[:space:]]*RX:" | awk '{print $2}' | head -1 || echo "0")
    ifb0_tx=$(ip -s link show ifb0 2>/dev/null | grep -E "^[[:space:]]*TX:" | awk '{print $2}' | head -1 || echo "0")
    # Check if values are numeric and non-zero
    if [ -n "${ifb0_rx}" ] && [ "${ifb0_rx}" != "0" ] && [ "${ifb0_rx}" -gt 0 ] 2>/dev/null; then
        echo -e "${YELLOW}⚠ IFB0 device has RX traffic: ${ifb0_rx} bytes${NC}"
        issues=$((issues + 1))
    fi
    if [ -n "${ifb0_tx}" ] && [ "${ifb0_tx}" != "0" ] && [ "${ifb0_tx}" -gt 0 ] 2>/dev/null; then
        echo -e "${YELLOW}⚠ IFB0 device has TX traffic: ${ifb0_tx} bytes${NC}"
        issues=$((issues + 1))
    fi
fi

# Check for duplicate filters
filter_count=$(tc filter show dev "${INTERFACE}" 2>/dev/null | grep -c "filter" || echo "0")
if [ "${filter_count}" -gt 4 ]; then
    echo -e "${YELLOW}⚠ High number of filters (${filter_count}) - possible duplicates?${NC}"
    issues=$((issues + 1))
fi

if [ "${issues}" -eq 0 ]; then
    echo -e "${GREEN}✓ No obvious issues detected${NC}"
fi

echo ""
echo "=========================================="
echo "End of Status Report"
echo "=========================================="

