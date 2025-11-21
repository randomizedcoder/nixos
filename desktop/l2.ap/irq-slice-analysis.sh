#!/bin/bash

# IRQ and Slice Analysis Script for L2 WiFi Access Point
# Analyzes runtime state of IRQ distribution and systemd slice CPU affinity

set -euo pipefail

echo "=== L2 WiFi Access Point - IRQ and Slice Analysis ==="
echo "Generated: $(date)"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "OK") echo -e "${GREEN}✓${NC} $message" ;;
        "WARN") echo -e "${YELLOW}⚠${NC} $message" ;;
        "ERROR") echo -e "${RED}✗${NC} $message" ;;
        "INFO") echo -e "${BLUE}ℹ${NC} $message" ;;
    esac
}

# Check kernel parameters
cmdline=$(cat /proc/cmdline)
isolcpus=$(echo "$cmdline" | grep -o "isolcpus=[^ ]*" | cut -d= -f2 || echo "NOT SET")
print_status "INFO" "Isolated cores: $isolcpus"

# Ethernet IRQ L core distribution
echo ""
echo "=== Ethernet IRQ L Cores ==="
enp1s0_irqs=$(cat /proc/interrupts | grep "enp1s0" | awk '{print $1}' | sed 's/://')
if [ -n "$enp1s0_irqs" ]; then
    l_cores=""
    for irq in $enp1s0_irqs; do
        cpu_dist=$(grep "^ *$irq:" /proc/interrupts | awk '{for(i=2; i<=25; i++) if($i>0) printf "%d ", i-1}')
        for cpu in $cpu_dist; do
            if [ "$cpu" -lt 12 ]; then
                l_core=$cpu
            else
                l_core=$((cpu - 12))
            fi
            l_cores="$l_cores $l_core"
        done
    done
    l_cores=$(echo $l_cores | tr ' ' '\n' | sort -u | tr '\n' ' ')
    echo "enp1s0 IRQs using L cores: $l_cores"
else
    print_status "WARN" "No enp1s0 IRQs found"
fi

# WiFi IRQ L core distribution
echo ""
echo "=== WiFi IRQ L Cores ==="
iwlwifi_irqs=$(cat /proc/interrupts | grep "iwlwifi" | awk '{print $1}' | sed 's/://')
if [ -n "$iwlwifi_irqs" ]; then
    l_cores=""
    for irq in $iwlwifi_irqs; do
        cpu_dist=$(grep "^ *$irq:" /proc/interrupts | awk '{for(i=2; i<=25; i++) if($i>0) printf "%d ", i-1}')
        for cpu in $cpu_dist; do
            if [ "$cpu" -lt 12 ]; then
                l_core=$cpu
            else
                l_core=$((cpu - 12))
            fi
            l_cores="$l_cores $l_core"
        done
    done
    l_cores=$(echo $l_cores | tr ' ' '\n' | sort -u | tr '\n' ' ')
    echo "iwlwifi IRQs using L cores: $l_cores"

    # Check expected cores 4,5,6,7
    for expected in 4 5 6 7; do
        if echo "$l_cores" | grep -q " $expected "; then
            print_status "OK" "L core $expected: used"
        else
            print_status "WARN" "L core $expected: not used"
        fi
    done
else
    print_status "WARN" "No iwlwifi IRQs found"
fi

# Systemd slice CPU affinity
echo ""
echo "=== Systemd Slice L Cores ==="

# Check global systemd CPU affinity
echo "--- Global Systemd CPU Affinity ---"
if [ -f "/etc/systemd/system.conf" ]; then
    global_cpu_affinity=$(grep "^CPUAffinity=" /etc/systemd/system.conf | cut -d= -f2 || echo "not set")
    echo "Global systemd CPUAffinity: $global_cpu_affinity"
else
    echo "Global systemd CPUAffinity: not configured"
fi

# Check main slices
main_slices=("network-services" "system")
for slice in "${main_slices[@]}"; do
    echo "--- $slice.slice ---"
    cgroup_path="/sys/fs/cgroup/system.slice/$slice.slice"

    if systemctl status "$slice.slice" >/dev/null 2>&1; then
        if [ -d "$cgroup_path" ] && [ -f "$cgroup_path/cpuset.cpus" ]; then
            cpu_affinity=$(cat "$cgroup_path/cpuset.cpus")
            print_status "INFO" "CPU affinity: $cpu_affinity"

            # Convert to L cores
            l_cores=""
            for cpu in $(echo $cpu_affinity | tr ',' ' '); do
                if [[ $cpu =~ ^[0-9]+$ ]]; then
                    if [ "$cpu" -lt 12 ]; then
                        l_core=$cpu
                    else
                        l_core=$((cpu - 12))
                    fi
                    l_cores="$l_cores $l_core"
                elif [[ $cpu =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    start=${BASH_REMATCH[1]}
                    end=${BASH_REMATCH[2]}
                    for ((cpu=start; cpu<=end; cpu++)); do
                        if [ "$cpu" -lt 12 ]; then
                            l_core=$cpu
                        else
                            l_core=$((cpu - 12))
                        fi
                        l_cores="$l_cores $l_core"
                    done
                fi
            done
            l_cores=$(echo $l_cores | tr ' ' '\n' | sort -u | tr '\n' ' ')
            echo "  L cores: $l_cores"
        else
            print_status "INFO" "Slice loaded but no cgroup (no active services)"
        fi
    else
        print_status "ERROR" "Slice $slice.slice not found or not active"
    fi
    echo ""
done

# Check per-daemon slices
per_daemon_slices=("kea" "pdns" "radvd" "hostapd")
for slice in "${per_daemon_slices[@]}"; do
    echo "--- $slice.slice ---"
    cgroup_path="/sys/fs/cgroup/system.slice/$slice.slice"

    if systemctl status "$slice.slice" >/dev/null 2>&1; then
        if [ -d "$cgroup_path" ] && [ -f "$cgroup_path/cpuset.cpus" ]; then
            cpu_affinity=$(cat "$cgroup_path/cpuset.cpus")
            print_status "INFO" "CPU affinity: $cpu_affinity"

            # Convert to L cores
            l_cores=""
            for cpu in $(echo $cpu_affinity | tr ',' ' '); do
                if [[ $cpu =~ ^[0-9]+$ ]]; then
                    if [ "$cpu" -lt 12 ]; then
                        l_core=$cpu
                    else
                        l_core=$((cpu - 12))
                    fi
                    l_cores="$l_cores $l_core"
                elif [[ $cpu =~ ^([0-9]+)-([0-9]+)$ ]]; then
                    start=${BASH_REMATCH[1]}
                    end=${BASH_REMATCH[2]}
                    for ((cpu=start; cpu<=end; cpu++)); do
                        if [ "$cpu" -lt 12 ]; then
                            l_core=$cpu
                        else
                            l_core=$((cpu - 12))
                        fi
                        l_cores="$l_cores $l_core"
                    done
                fi
            done
            l_cores=$(echo $l_cores | tr ' ' '\n' | sort -u | tr '\n' ' ')
            echo "  L cores: $l_cores"
        else
            print_status "INFO" "Slice loaded but no cgroup (no active services)"
        fi
    else
        print_status "WARN" "Slice $slice.slice not found or not active"
    fi
    echo ""
done

# Service status summary
echo ""
echo "=== Service Status ==="
services=("hostapd" "kea-dhcp4-server" "pdns-recursor" "radvd")
for service in "${services[@]}"; do
    if systemctl is-active "$service" >/dev/null 2>&1; then
        slice=$(systemctl show "$service" --property=Slice --value 2>/dev/null || echo "unknown")
        nice_value=$(systemctl show "$service" --property=Nice --value 2>/dev/null || echo "0")
        print_status "OK" "$service: active (slice: $slice, nice: $nice_value)"
    else
        print_status "WARN" "$service: not active"
    fi
done

# IRQ affinity service
echo ""
if systemctl is-active irq-affinity >/dev/null 2>&1; then
    print_status "OK" "IRQ affinity service: active"
else
    print_status "WARN" "IRQ affinity service: not active"
fi

echo ""
echo "=== Analysis Complete ==="