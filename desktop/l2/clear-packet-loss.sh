#!/usr/bin/env bash
# Script to clear all netem qdiscs and restore network interface to defaults

set -euo pipefail

INTERFACE="enp1s0"

# Cleanup function
cleanup() {
    echo "[$(date +%H:%M:%S.%3N)] Cleaning up qdiscs on ${INTERFACE}..."

    # Remove root qdisc (this removes all child qdiscs and filters)
    if tc qdisc show dev "${INTERFACE}" root >/dev/null 2>&1; then
        echo "  Removing root qdisc..."
        tc qdisc del dev "${INTERFACE}" root 2>/dev/null || true
    else
        echo "  No root qdisc found"
    fi

    # Remove ingress qdisc
    if tc qdisc show dev "${INTERFACE}" ingress >/dev/null 2>&1; then
        echo "  Removing ingress qdisc..."
        tc qdisc del dev "${INTERFACE}" ingress 2>/dev/null || true
    else
        echo "  No ingress qdisc found"
    fi

    # Clean up ifb0 device if it exists
    if ip link show ifb0 >/dev/null 2>&1; then
        echo "  Cleaning up ifb0 device..."
        # Remove all qdiscs from ifb0 (including cake) - try multiple times to ensure removal
        for i in 1 2 3; do
            tc qdisc del dev ifb0 root 2>/dev/null || true
            tc qdisc del dev ifb0 ingress 2>/dev/null || true
        done
        # Remove all filters from ifb0
        tc filter del dev ifb0 root 2>/dev/null || true
        tc filter del dev ifb0 ingress 2>/dev/null || true
        # Verify removal
        if tc qdisc show dev ifb0 2>/dev/null | grep -q "qdisc"; then
            echo "  WARNING: Some qdiscs may still exist on ifb0"
            tc qdisc show dev ifb0
        else
            echo "  ifb0 qdiscs and filters removed (device left in place)"
        fi
    else
        echo "  No ifb0 device found"
    fi

    # Also check for and remove any cake qdiscs on the main interface
    # These may be from systemd-networkd and are under mq (multi-queue) parent
    if tc qdisc show dev "${INTERFACE}" 2>/dev/null | grep -q "cake"; then
        echo "  Removing cake qdiscs from ${INTERFACE}..."
        # Extract all parent queue numbers (like :1, :2, :3, etc.) and remove cake qdiscs
        tc qdisc show dev "${INTERFACE}" 2>/dev/null | grep "cake" | grep -oP 'parent \K[0-9:]+' | sort -u | while read -r parent; do
            if [ -n "${parent}" ]; then
                echo "    Removing cake qdisc with parent ${parent}..."
                tc qdisc del dev "${INTERFACE}" parent "${parent}" 2>/dev/null || true
            fi
        done
        # Also try to remove mq root if it exists
        if tc qdisc show dev "${INTERFACE}" root 2>/dev/null | grep -q "mq"; then
            echo "  Attempting to remove mq root qdisc..."
            tc qdisc del dev "${INTERFACE}" root 2>/dev/null || true
        fi
    fi

    # Note about systemd-networkd managed qdiscs
    if tc qdisc show dev "${INTERFACE}" 2>/dev/null | grep -q "cake"; then
        echo ""
        echo "  WARNING: Some cake qdiscs are still present and may be managed by systemd-networkd"
        echo "  These will be recreated automatically. To permanently disable them:"
        echo "  1. Modify systemd-networkd configuration (e.g., hostapd-multi.nix)"
        echo "  2. Restart systemd-networkd: sudo systemctl restart systemd-networkd"
    fi

    echo "[$(date +%H:%M:%S.%3N)] Cleanup complete"
    echo ""
    echo "Current qdisc status:"
    tc qdisc show dev "${INTERFACE}" 2>/dev/null || echo "  No qdiscs configured (default state)"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Check if interface exists
if ! ip link show "${INTERFACE}" >/dev/null 2>&1; then
    echo "Error: Interface ${INTERFACE} not found"
    exit 1
fi

echo "Clearing all netem qdiscs on ${INTERFACE}..."
echo ""

cleanup

echo ""
echo "Interface ${INTERFACE} has been restored to default state."

