#!/usr/bin/env bash
# Script to simulate packet loss on enp1s0 interface
# - Background loss: Gilbert-Elliot (gemodel) loss model configured for Starlink emulation
#   - p = 0.02: probability of starting bad (lossy) state
#   - r = 0.20: probability of exiting bad state
#   - 1-H = 0.40: loss probability in bad state (40% loss during bursts)
#   - 1-K = 0.01: loss probability in good state (1% background loss)
# - Periodic drop-all events at specific times each minute

set -euo pipefail

# Configuration - can be overridden via environment variables
INTERFACE="${NETEM_INTERFACE:-enp1s0}"  # Network interface (override with NETEM_INTERFACE env var)
UDP_PORT="${NETEM_UDP_PORT:-6001}"      # UDP port to apply loss/latency to (override with NETEM_UDP_PORT env var)
DROP_LOSS="100%"
RTT_MS=130     # Total RTT in milliseconds (simulated by delay on both machines)
DELAY_MS=65    # One-way delay (RTT/2) in milliseconds - applied on egress only
JITTER_MS=5    # Random jitter in milliseconds
# Note: Since script runs on both machines, each applies DELAY_MS on egress
# Total RTT = DELAY_MS (machine 1) + DELAY_MS (machine 2) = RTT_MS

# Starlink gemodel parameters
# Format: loss gemodel PERCENT R 1-H 1-K
# Where PERCENT is probability of starting bad state, R is probability of exiting bad state
# Original values: p=0.02, r=0.20, 1-H=0.40, 1-K=0.01
# Adjusted for lower average loss rate
GE_P=0.01   # Probability of starting bad (lossy) state (reduced from 0.02)
GE_R=0.25   # Probability of exiting bad state (increased from 0.20 for shorter bursts)
GE_1H=0.30  # Loss probability in bad state (reduced from 0.40)
GE_1K=0.005 # Loss probability in good state (reduced from 0.01)

# Function to get current delay based on minute in hour (0-59ms)
# 00:00 = 0ms, 00:01 = 1ms, 00:25 = 25ms, 00:59 = 59ms
get_current_delay_ms() {
    local current_minute=$(date +%M)
    # Remove leading zero if present (e.g., "01" -> "1")
    current_minute=$((10#${current_minute}))
    echo "${current_minute}"
}

# Function to build gemodel loss string for Starlink emulation
# Delay is dynamically calculated based on current minute (0-59ms)
build_gemodel_loss() {
    local delay_ms=$(get_current_delay_ms)
    echo "delay ${delay_ms}ms loss gemodel ${GE_P} ${GE_R} ${GE_1H} ${GE_1K}"
}

# Function to setup base qdisc with Starlink gemodel loss and delay (only for UDP port 6001)
setup_base_qdisc() {
    local delay_ms=$(get_current_delay_ms)
    local loss_model=$(build_gemodel_loss)
    echo "[$(date +%H:%M:%S.%3N)] Setting up qdisc with Starlink gemodel loss and dynamic delay for UDP port ${UDP_PORT}"
    echo "  NOTE: Delay is dynamically set based on minute in hour (0-59ms)"
    echo "  Parameters: p=${GE_P}, r=${GE_R}, 1-H=${GE_1H} (bad state loss), 1-K=${GE_1K} (good state loss)"
    echo "  Current delay: ${delay_ms}ms (minute $(date +%M) of hour, will increase each minute up to 59ms)"

    # Remove existing qdiscs if present
    # First try to remove any cake qdiscs under mq parent (from systemd-networkd)
    if tc qdisc show dev "${INTERFACE}" root 2>/dev/null | grep -q "mq"; then
        echo "  Removing existing mq root qdisc (may contain cake from systemd-networkd)..."
        # Remove cake qdiscs from each queue first
        tc qdisc show dev "${INTERFACE}" 2>/dev/null | grep "cake" | grep -oP 'parent \K[0-9:]+' | sort -u | while read -r parent; do
            if [ -n "${parent}" ]; then
                tc qdisc del dev "${INTERFACE}" parent "${parent}" 2>/dev/null || true
            fi
        done
        # Then remove mq root
        tc qdisc del dev "${INTERFACE}" root 2>/dev/null || true
    else
        tc qdisc del dev "${INTERFACE}" root 2>/dev/null || true
    fi

    # === EGRESS (outgoing) configuration ===
    # Create a priority qdisc as root (parent)
    # This allows us to classify traffic and apply netem only to specific flows
    tc qdisc add dev "${INTERFACE}" root handle 1: prio

    # Create netem qdisc for UDP port 6001 (class 1:1) with delay and loss
    tc qdisc add dev "${INTERFACE}" parent 1:1 handle 10: netem ${loss_model}

    # Create pass-through qdisc for all other traffic (class 1:2)
    tc qdisc add dev "${INTERFACE}" parent 1:2 handle 20: pfifo

    # Create pass-through qdisc for default traffic (class 1:3)
    tc qdisc add dev "${INTERFACE}" parent 1:3 handle 30: pfifo

    # Add filter to match UDP port 6001 and send to class 1:1 (netem with loss and delay)
    # Match UDP packets with destination port 6001 (outgoing packets TO port 6001)
    tc filter add dev "${INTERFACE}" protocol ip parent 1:0 prio 1 u32 \
        match ip protocol 17 0xff \
        match ip dport ${UDP_PORT} 0xffff \
        flowid 1:1

    # Also match UDP packets with source port 6001 (outgoing packets FROM port 6001)
    # Note: Using prio 2 to avoid conflicts
    tc filter add dev "${INTERFACE}" protocol ip parent 1:0 prio 2 u32 \
        match ip protocol 17 0xff \
        match ip sport ${UDP_PORT} 0xffff \
        flowid 1:1

    local delay_ms=$(get_current_delay_ms)
    echo "[$(date +%H:%M:%S.%3N)] Qdisc configured:"
    echo "  Egress: UDP port ${UDP_PORT} -> ${delay_ms}ms delay + Starlink gemodel loss, all other traffic -> pass-through"
    echo "  Note: Delay will automatically increase each minute (0-59ms) to find bandwidth doubling threshold"
}

# Function to set qdisc to drop all packets (only for UDP port 6001)
set_drop_all() {
    local duration_ms=$1
    local duration_sec=$(echo "scale=3; ${duration_ms} / 1000" | bc)
    local delay_ms=$(get_current_delay_ms)
    echo "[$(date +%H:%M:%S.%3N)] Setting qdisc to drop all packets for UDP port ${UDP_PORT} (100% loss) for ${duration_sec}s"
    # Keep current dynamic delay but set loss to 100%
    tc qdisc change dev "${INTERFACE}" parent 1:1 netem delay ${delay_ms}ms loss "${DROP_LOSS}"
}

# Function to restore base qdisc with gemodel loss and dynamic delay
restore_base_qdisc() {
    local delay_ms=$(get_current_delay_ms)
    local loss_model=$(build_gemodel_loss)
    echo "[$(date +%H:%M:%S.%3N)] Restoring base qdisc with ${delay_ms}ms delay + Starlink gemodel loss for UDP port ${UDP_PORT}"
    tc qdisc change dev "${INTERFACE}" parent 1:1 netem ${loss_model}
}


# Function to show current qdisc status
show_qdisc_status() {
    echo "[$(date +%H:%M:%S.%3N)] Current qdisc status:"
    tc qdisc show dev "${INTERFACE}" || echo "  No qdisc configured"
}

# Function to wait until a specific second (with millisecond precision)
# Handles minute rollover (e.g., waiting from 59.9s to 0.0s)
wait_until() {
    local target_second=$1
    local target_ms
    local current_ms
    local now_second
    local now_ms
    local initial_second

    # Convert target_second (e.g., 1.5) to milliseconds
    target_ms=$(echo "scale=0; ${target_second} * 1000 / 1" | bc)

    # Get initial second to detect rollover
    initial_second=$(date +%S)

    while true; do
        now_second=$(date +%S)
        now_ms=$(date +%3N)
        current_ms=$((10#${now_second} * 1000 + 10#${now_ms}))

        # Handle minute rollover: if target is early in minute (e.g., 0.0) and we're late (e.g., 59.x)
        # or if we've crossed the minute boundary
        if [ "${target_ms}" -lt 1000 ] && [ "${current_ms}" -gt 50000 ]; then
            # We're waiting for next minute (e.g., 0.0), and we're still in current minute (e.g., 59.x)
            # Continue waiting
            :
        elif [ "${current_ms}" -ge "${target_ms}" ]; then
            # Normal case: we've reached or passed the target
            break
        fi
        # Sleep for a small fraction to avoid busy-waiting
        sleep 0.01  # Sleep 10ms
    done
}

# Function to handle drop event
handle_drop_event() {
    local start_second=$1
    local duration_ms=$2

    wait_until "${start_second}"
    set_drop_all "${duration_ms}"

    # Sleep for the duration
    sleep "$(echo "scale=3; ${duration_ms} / 1000" | bc)"

    restore_base_qdisc
}

# Cleanup function
cleanup() {
    echo ""
    echo "[$(date +%H:%M:%S.%3N)] Cleaning up qdiscs..."
    tc qdisc del dev "${INTERFACE}" root 2>/dev/null || true
    echo "[$(date +%H:%M:%S.%3N)] Cleanup complete"
    exit 0
}

# Trap signals for cleanup
trap cleanup SIGINT SIGTERM

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root (use sudo)"
    exit 1
fi

# Check if interface exists
if ! ip link show "${INTERFACE}" >/dev/null 2>&1; then
    echo "Error: Interface ${INTERFACE} not found"
    echo "Available interfaces:"
    ip link show | grep -E "^[0-9]+:" | awk '{print $2}' | sed 's/:$//' | grep -v lo
    echo ""
    echo "To use a different interface, set NETEM_INTERFACE environment variable:"
    echo "  NETEM_INTERFACE=eth0 sudo ./simulate-packet-loss.sh"
    exit 1
fi

# Check if bc is available
if ! command -v bc >/dev/null 2>&1; then
    echo "Error: 'bc' command not found. Please install it."
    exit 1
fi

echo "Starting packet loss simulation on ${INTERFACE}"
echo "Target: UDP port ${UDP_PORT} only (all other traffic passes through unaffected)"
echo "Dynamic delay: Based on minute in hour (0-59ms)"
echo "  - At 00:00, delay = 0ms"
echo "  - At 00:01, delay = 1ms"
echo "  - At 00:25, delay = 25ms"
echo "  - At 00:59, delay = 59ms"
echo "  - Delay automatically increases each minute to find bandwidth doubling threshold"
echo "Background loss: Starlink gemodel (Gilbert-Elliot burst loss model)"
echo "  p = ${GE_P} (probability of starting bad state)"
echo "  r = ${GE_R} (probability of exiting bad state)"
echo "  1-H = ${GE_1H} (loss probability in bad state = $(echo "scale=0; ${GE_1H} * 100" | bc)%)"
echo "  1-K = ${GE_1K} (loss probability in good state = $(echo "scale=0; ${GE_1K} * 100" | bc)%)"
echo "Drop events (each minute, UDP port ${UDP_PORT} only):"
echo "  - 1.5-2.5s: 100% loss for 1 second"
echo "  - 12.1s: 100% loss for 70ms"
echo "  - 27.1s: 100% loss for 70ms"
echo "  - 42.1s: 100% loss for 70ms"
echo "  - 57.1s: 100% loss for 70ms"
echo "Press Ctrl+C to stop"
echo ""

# Setup initial qdisc
setup_base_qdisc
show_qdisc_status
echo ""

# Main loop - runs each minute
while true; do
    # Get current second within the minute
    current_second=$(date +%S)
    current_ms=$(date +%3N)

    # Calculate how long to wait until the start of the next minute (second 0.0)
    current_total_ms=$((10#${current_second} * 1000 + 10#${current_ms}))

    if [ "${current_total_ms}" -gt 50 ]; then
        # We're not at the start of a minute, wait until next minute
        ms_until_next_minute=$((60000 - current_total_ms))
        echo "[$(date +%H:%M:%S.%3N)] Waiting ${ms_until_next_minute}ms until next minute (currently at second ${current_second}.${current_ms})"

        # Sleep most of the time, then use precise wait
        if [ "${ms_until_next_minute}" -gt 200 ]; then
            sleep_ms=$((ms_until_next_minute - 100))
            sleep "$(echo "scale=3; ${sleep_ms} / 1000" | bc)"
        fi
        # Wait precisely for second 0
        wait_until 0
    fi

    # Get current delay for this minute
    current_delay=$(get_current_delay_ms)
    current_time=$(date +%H:%M)
    echo "[$(date +%H:%M:%S.%3N)] Starting new minute cycle (${current_time}, delay = ${current_delay}ms)"

    # Update qdisc with new delay for this minute (in case it changed)
    loss_model=$(build_gemodel_loss)
    tc qdisc change dev "${INTERFACE}" parent 1:1 netem ${loss_model} 2>/dev/null || true

    # Schedule all drop events in background
    # Event 1: 1.5-2.5s (1000ms duration)
    (handle_drop_event 1.5 1000) &

    # Event 2: 12.1s (70ms duration)
    (handle_drop_event 12.1 70) &

    # Event 3: 27.1s (70ms duration)
    (handle_drop_event 27.1 70) &

    # Event 4: 42.1s (70ms duration)
    (handle_drop_event 42.1 70) &

    # Event 5: 57.1s (70ms duration)
    (handle_drop_event 57.1 70) &

    # Wait for all background jobs to complete (they should finish by second 58)
    wait

    # Wait until near the end of the minute before starting the next cycle
    # Wait until 59.5 seconds to give a small buffer
    wait_until 59.5
done

