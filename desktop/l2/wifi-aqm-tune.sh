#!/usr/bin/env bash
#
# wifi-aqm-tune.sh - View and tune mac80211 WiFi AQM parameters
#
# Requires: CONFIG_MAC80211_DEBUGFS=y in kernel
#

set -e

DEBUGFS="/sys/kernel/debug/ieee80211"

echo "=== WiFi AQM Tuning ==="
echo "Timestamp: $(date)"
echo

# Check if debugfs is available
if [ ! -d "$DEBUGFS" ]; then
    echo "ERROR: ieee80211 debugfs not available at $DEBUGFS"
    echo "Make sure CONFIG_MAC80211_DEBUGFS=y is enabled in kernel"
    exit 1
fi

# List available PHYs
echo "--- Available PHYs ---"
ls -la "$DEBUGFS/" 2>/dev/null || echo "Cannot list debugfs (need root?)"
echo

# Function to show AQM info for a PHY
show_phy_aqm() {
    local phy=$1
    local phy_path="$DEBUGFS/$phy"

    echo "=== $phy ==="

    if [ -f "$phy_path/airtime_flags" ]; then
        echo "Airtime flags: $(cat "$phy_path/airtime_flags")"
    fi

    if [ -f "$phy_path/aql_txq_limit" ]; then
        echo "AQL TXQ limit: $(cat "$phy_path/aql_txq_limit")"
    fi

    if [ -f "$phy_path/aql_pending" ]; then
        echo "AQL pending: $(cat "$phy_path/aql_pending")"
    fi

    # Per-station AQL limits
    if [ -d "$phy_path/netdev:wlan_2g" ]; then
        echo "--- wlan_2g stations ---"
        for sta in "$phy_path/netdev:wlan_2g/stations/"*; do
            if [ -d "$sta" ]; then
                sta_name=$(basename "$sta")
                echo "  Station: $sta_name"
                [ -f "$sta/aql" ] && echo "    AQL: $(cat "$sta/aql")"
                [ -f "$sta/airtime" ] && echo "    Airtime: $(cat "$sta/airtime")"
            fi
        done
    fi

    if [ -d "$phy_path/netdev:wlan_5g" ]; then
        echo "--- wlan_5g stations ---"
        for sta in "$phy_path/netdev:wlan_5g/stations/"*; do
            if [ -d "$sta" ]; then
                sta_name=$(basename "$sta")
                echo "  Station: $sta_name"
                [ -f "$sta/aql" ] && echo "    AQL: $(cat "$sta/aql")"
                [ -f "$sta/airtime" ] && echo "    Airtime: $(cat "$sta/airtime")"
            fi
        done
    fi

    echo
}

# Show AQM info for all PHYs
for phy in "$DEBUGFS"/phy*; do
    if [ -d "$phy" ]; then
        show_phy_aqm "$(basename "$phy")"
    fi
done

echo "--- Available tunables ---"
echo "Note: mac80211's fq_codel target/interval are hardcoded (20ms/100ms)"
echo "But you can tune:"
echo "  - AQL limits (Airtime Queue Limits)"
echo "  - Airtime fairness flags"
echo
echo "Examples (run as root):"
echo "  # Set AQL TXQ limit for phy0"
echo "  echo 24000 > $DEBUGFS/phy0/aql_txq_limit"
echo
echo "  # Toggle airtime flags (bitfield)"
echo "  # Bit 0: Airtime deficit accounting"
echo "  # Bit 1: Transmit AQL limits"
echo "  echo 3 > $DEBUGFS/phy0/airtime_flags"


