#!/usr/bin/env bash
# Script to simulate Starlink-like satellite network conditions
# - Applies delay and loss to both bridge interfaces (bidirectional emulation)
# - Background loss: Gilbert-Elliot (gemodel) loss model
# - Periodic loss events: 1 ramped event + 4 short events per minute
#
# Based on satellite-network-emulation-design.md

set -euo pipefail

# Configuration - can be overridden via environment variables
BRIDGE="${SATNET_BRIDGE:-br0}"
NIC0="${SATNET_NIC0:-enp1s0f0}"      # First bridge interface (outbound)
NIC1="${SATNET_NIC1:-enp1s0f1}"      # Second bridge interface (inbound)
UDP_PORT0="${SATNET_UDP_PORT0:-6001}"  # First UDP port to apply emulation to
UDP_PORT1="${SATNET_UDP_PORT1:-6002}"  # Second UDP port to apply emulation to
RTT_MS=130                            # Total RTT in milliseconds
DELAY_MS=65                           # One-way delay (RTT/2) per direction
JITTER_MS=2.5                         # Jitter per direction (±2.5ms = ±5ms total)
QUEUE_LIMIT="${SATNET_QUEUE_LIMIT:-100000}"  # Packet limit for netem queue (100k packets)
PEAK_LOSS="${SATNET_PEAK_LOSS:-80}"  # Peak loss rate for large event (percentage)

# Starlink gemodel parameters
GE_P=0.01   # Probability of starting bad (lossy) state
GE_R=0.25   # Probability of exiting bad state
GE_1H=0.30  # Loss probability in bad state (30% loss during bursts)
GE_1K=0.005 # Loss probability in good state (0.5% background loss)

# Ramped loss event parameters
RAMP_UP_MS=300    # Time to ramp up to peak loss
RAMP_DOWN_MS=300  # Time to ramp down from peak loss
PLATEAU_MS=400    # Time at peak loss
RAMP_UPDATE_INTERVAL_MS=50  # Update loss rate every 50ms during ramp

# Function to get current delay based on minute in hour (0-59ms) - optional feature
get_current_delay_ms() {
    local current_minute
    current_minute=$(date +%M)
    current_minute=$((10#${current_minute}))
    echo "${current_minute}"
}

# Function to build gemodel loss string for Starlink emulation
build_gemodel_loss() {
    local delay_ms
    # Use base delay (can enable dynamic delay later by uncommenting next line)
    delay_ms=${DELAY_MS}
    # delay_ms=$(get_current_delay_ms)  # Uncomment to enable dynamic delay based on minute

    # Note: According to netem man page, gemodel format is:
    #   gemodel PERCENT [ R [ 1-H [ 1-K ]]]
    #   PERCENT = probability of starting bad state
    #   R, 1-H, 1-K = probabilities
    # Based on original working script, using decimal values directly (0.01, 0.25, etc.)
    # Note: Try limit at the end - some netem versions may require specific order
    echo "delay ${delay_ms}ms ${JITTER_MS}ms loss gemodel ${GE_P} ${GE_R} ${GE_1H} ${GE_1K} limit ${QUEUE_LIMIT}"
}

# Function to setup base qdisc with Starlink gemodel loss and delay for an interface
setup_interface_qdisc() {
    local interface=$1
    local loss_model
    loss_model=$(build_gemodel_loss)

    echo "[$(date +%H:%M:%S.%3N)] Setting up qdisc on ${interface} with Starlink gemodel loss and ${DELAY_MS}ms±${JITTER_MS}ms delay"
    echo "  Parameters: p=${GE_P}, r=${GE_R}, 1-H=${GE_1H} (bad state loss), 1-K=${GE_1K} (good state loss)"
    echo "  Queue limit: ${QUEUE_LIMIT} packets"

    # Remove existing qdiscs if present
    # First try to remove any cake qdiscs under mq parent (from systemd-networkd)
    echo "  Removing existing qdiscs..."
    if tc qdisc show dev "${interface}" root 2>/dev/null | grep -q "mq"; then
        echo "    Found mq root qdisc, removing cake qdiscs first..."
        # Remove cake qdiscs from each queue first
        tc qdisc show dev "${interface}" 2>/dev/null | grep "cake" | grep -oP 'parent \K[0-9:]+' | sort -u | while read -r parent; do
            if [ -n "${parent}" ]; then
                echo "      Removing cake qdisc with parent ${parent}..."
                cmd="tc qdisc del dev ${interface} parent ${parent}"
                echo "[$(date +%H:%M:%S.%3N)]        Running: ${cmd}"
                ${cmd} 2>/dev/null || echo "        Warning: Failed to remove cake qdisc with parent ${parent}"
            fi
        done
        # Then remove mq root
        echo "    Removing mq root qdisc..."
        cmd="tc qdisc del dev ${interface} root"
        echo "      Running: ${cmd}"
        if ! ${cmd} 2>/dev/null; then
            echo "    Warning: Failed to remove mq root qdisc, continuing anyway..."
        fi
    else
        echo "    Removing existing root qdisc..."
        cmd="tc qdisc del dev ${interface} root"
        echo "[$(date +%H:%M:%S.%3N)]      Running: ${cmd}"
        if ! ${cmd} 2>/dev/null; then
            echo "    No existing root qdisc found (this is OK)"
        fi
    fi

    # === EGRESS (outgoing) configuration ===
    # Create a priority qdisc as root (parent)
    echo "  Creating priority qdisc..."
    local cmd
    cmd="tc qdisc add dev ${interface} root handle 1: prio"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    if ! ${cmd}; then
        echo "    Error: Failed to create priority qdisc on ${interface}"
        return 1
    fi

    # Create netem qdisc for UDP port 6001 (class 1:1) with delay and loss
    echo "  Creating netem qdisc with delay and loss..."
    cmd="tc qdisc add dev ${interface} parent 1:1 handle 10: netem ${loss_model}"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    if ! ${cmd}; then
        echo "    Error: Failed to create netem qdisc on ${interface}"
        echo "    Loss model string was: ${loss_model}"
        return 1
    fi

    # Create pass-through qdisc for all other traffic (class 1:2)
    echo "  Creating pass-through qdiscs..."
    cmd="tc qdisc add dev ${interface} parent 1:2 handle 20: pfifo"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    if ! ${cmd}; then
        echo "    Warning: Failed to create pfifo for class 1:2"
    fi

    # Create pass-through qdisc for default traffic (class 1:3)
    cmd="tc qdisc add dev ${interface} parent 1:3 handle 30: pfifo"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    if ! ${cmd}; then
        echo "    Warning: Failed to create pfifo for class 1:3"
    fi

    # Add filters for UDP ports 6001 and 6002, and ICMP echo request/reply
    echo "  Adding filters for UDP ports ${UDP_PORT0}, ${UDP_PORT1} and ICMP echo..."

    # Match UDP packets with destination port UDP_PORT0
    cmd="tc filter add dev ${interface} protocol ip parent 1:0 prio 1 u32 match ip protocol 17 0xff match ip dport ${UDP_PORT0} 0xffff flowid 1:1"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    if ! tc filter add dev "${interface}" protocol ip parent 1:0 prio 1 u32 \
        match ip protocol 17 0xff \
        match ip dport "${UDP_PORT0}" 0xffff \
        flowid 1:1; then
        echo "    Error: Failed to add filter for destination port ${UDP_PORT0}"
        return 1
    fi

    # Match UDP packets with source port UDP_PORT0
    cmd="tc filter add dev ${interface} protocol ip parent 1:0 prio 2 u32 match ip protocol 17 0xff match ip sport ${UDP_PORT0} 0xffff flowid 1:1"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    if ! tc filter add dev "${interface}" protocol ip parent 1:0 prio 2 u32 \
        match ip protocol 17 0xff \
        match ip sport "${UDP_PORT0}" 0xffff \
        flowid 1:1; then
        echo "    Error: Failed to add filter for source port ${UDP_PORT0}"
        return 1
    fi

    # Match UDP packets with destination port UDP_PORT1
    cmd="tc filter add dev ${interface} protocol ip parent 1:0 prio 3 u32 match ip protocol 17 0xff match ip dport ${UDP_PORT1} 0xffff flowid 1:1"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    if ! tc filter add dev "${interface}" protocol ip parent 1:0 prio 3 u32 \
        match ip protocol 17 0xff \
        match ip dport "${UDP_PORT1}" 0xffff \
        flowid 1:1; then
        echo "    Error: Failed to add filter for destination port ${UDP_PORT1}"
        return 1
    fi

    # Match UDP packets with source port UDP_PORT1
    cmd="tc filter add dev ${interface} protocol ip parent 1:0 prio 4 u32 match ip protocol 17 0xff match ip sport ${UDP_PORT1} 0xffff flowid 1:1"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    if ! tc filter add dev "${interface}" protocol ip parent 1:0 prio 4 u32 \
        match ip protocol 17 0xff \
        match ip sport "${UDP_PORT1}" 0xffff \
        flowid 1:1; then
        echo "    Error: Failed to add filter for source port ${UDP_PORT1}"
        return 1
    fi

    # Match ICMP echo request (type 8) - for ping requests
    # ICMP type is at offset 0 of the ICMP header, which is at offset 20 (IP header length) of the IP packet
    # We match IP protocol 1 (ICMP) and then the ICMP type byte at offset 20
    cmd="tc filter add dev ${interface} protocol ip parent 1:0 prio 5 u32 match ip protocol 1 0xff match u8 8 0xff at 20 flowid 1:1"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    if ! tc filter add dev "${interface}" protocol ip parent 1:0 prio 5 u32 \
        match ip protocol 1 0xff \
        match u8 8 0xff at 20 \
        flowid 1:1; then
        echo "    Error: Failed to add filter for ICMP echo request"
        return 1
    fi

    # Match ICMP echo reply (type 0) - for ping replies
    # ICMP type is at offset 0 of the ICMP header, which is at offset 20 (IP header length) of the IP packet
    cmd="tc filter add dev ${interface} protocol ip parent 1:0 prio 6 u32 match ip protocol 1 0xff match u8 0 0xff at 20 flowid 1:1"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    if ! tc filter add dev "${interface}" protocol ip parent 1:0 prio 6 u32 \
        match ip protocol 1 0xff \
        match u8 0 0xff at 20 \
        flowid 1:1; then
        echo "    Error: Failed to add filter for ICMP echo reply"
        return 1
    fi

    echo "[$(date +%H:%M:%S.%3N)] Qdisc configured on ${interface}:"
    echo "  UDP ports ${UDP_PORT0}, ${UDP_PORT1} and ICMP echo -> ${DELAY_MS}ms±${JITTER_MS}ms delay + gemodel loss, all other traffic -> pass-through"
}

# Function to set qdisc to specific loss rate (for ramped events)
set_loss_rate() {
    local interface=$1
    local loss_percent=$2
    local delay_ms
    delay_ms=${DELAY_MS}  # Use base delay, not dynamic

    # Keep the delay and jitter but set loss to specified percentage
    local cmd
    cmd="tc qdisc change dev ${interface} parent 1:1 netem delay ${delay_ms}ms ${JITTER_MS}ms loss ${loss_percent}% limit ${QUEUE_LIMIT}"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    ${cmd}
}

# Function to set qdisc to drop all packets (100% loss)
set_drop_all() {
    local interface=$1
    local delay_ms
    delay_ms=${DELAY_MS}  # Use base delay, not dynamic

    # Keep the delay and jitter but set loss to 100%
    local cmd
    cmd="tc qdisc change dev ${interface} parent 1:1 netem delay ${delay_ms}ms ${JITTER_MS}ms loss 100% limit ${QUEUE_LIMIT}"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    ${cmd}
}

# Function to restore base qdisc with gemodel loss
restore_base_qdisc() {
    local interface=$1
    local loss_model
    loss_model=$(build_gemodel_loss)

    local cmd
    cmd="tc qdisc change dev ${interface} parent 1:1 netem ${loss_model}"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    ${cmd}
}

# Function to apply loss rate to both interfaces
set_loss_rate_both() {
    local loss_percent=$1
    set_loss_rate "${NIC0}" "${loss_percent}"
    set_loss_rate "${NIC1}" "${loss_percent}"
}

# Function to apply 100% loss to both interfaces
set_drop_all_both() {
    set_drop_all "${NIC0}"
    set_drop_all "${NIC1}"
}

# Function to restore base qdisc on both interfaces
restore_base_qdisc_both() {
    restore_base_qdisc "${NIC0}"
    restore_base_qdisc "${NIC1}"
}

# Function to wait until a specific second (with millisecond precision)
wait_until() {
    local target_second=$1
    local target_ms
    local current_ms
    local now_second
    local now_ms

    # Convert target_second (e.g., 1.5) to milliseconds
    target_ms=$(echo "scale=0; ${target_second} * 1000 / 1" | bc)

    while true; do
        now_second=$(date +%S)
        now_ms=$(date +%3N)
        current_ms=$((10#${now_second} * 1000 + 10#${now_ms}))

        if [ "${current_ms}" -ge "${target_ms}" ]; then
            break
        fi
        # Sleep for a small fraction to avoid busy-waiting
        sleep 0.005  # Sleep 5ms
    done
}

# Function to handle ramped loss event
handle_ramped_event() {
    local start_second=$1
    local duration_ms=$2
    local peak_loss=$3

    wait_until "${start_second}"

    local start_time
    start_time=$(date +%s.%3N)
    local ramp_up_end
    ramp_up_end=$(echo "scale=3; ${start_time} + ${RAMP_UP_MS} / 1000" | bc)
    local plateau_end
    plateau_end=$(echo "scale=3; ${ramp_up_end} + ${PLATEAU_MS} / 1000" | bc)
    local event_end
    event_end=$(echo "scale=3; ${plateau_end} + ${RAMP_DOWN_MS} / 1000" | bc)

    echo "[$(date +%H:%M:%S.%3N)] Starting ramped loss event: 0% → ${peak_loss}% → 0% over ${duration_ms}ms"

    # Ramp up phase
    local ramp_steps=$((RAMP_UP_MS / RAMP_UPDATE_INTERVAL_MS))
    local loss_step
    loss_step=$(echo "scale=2; ${peak_loss} / ${ramp_steps}" | bc)
    local current_loss=0

    while true; do
        local current_time
        current_time=$(date +%s.%3N)
        if (( $(echo "${current_time} >= ${ramp_up_end}" | bc -l) )); then
            break
        fi

        # Calculate current loss rate
        current_loss=$(echo "scale=2; ${current_loss} + ${loss_step}" | bc)
        if (( $(echo "${current_loss} > ${peak_loss}" | bc -l) )); then
            current_loss=${peak_loss}
        fi

        set_loss_rate_both "${current_loss}"
        sleep "$(echo "scale=3; ${RAMP_UPDATE_INTERVAL_MS} / 1000" | bc)"
    done

    # Plateau phase at peak loss
    set_loss_rate_both "${peak_loss}"
    echo "[$(date +%H:%M:%S.%3N)] At peak loss: ${peak_loss}%"

    while true; do
        local current_time
        current_time=$(date +%s.%3N)
        if (( $(echo "${current_time} >= ${plateau_end}" | bc -l) )); then
            break
        fi
        sleep 0.05
    done

    # Ramp down phase
    current_loss=${peak_loss}
    while true; do
        local current_time
        current_time=$(date +%s.%3N)
        if (( $(echo "${current_time} >= ${event_end}" | bc -l) )); then
            break
        fi

        # Calculate current loss rate
        current_loss=$(echo "scale=2; ${current_loss} - ${loss_step}" | bc)
        if (( $(echo "${current_loss} < 0" | bc -l) )); then
            current_loss=0
        fi

        set_loss_rate_both "${current_loss}"
        sleep "$(echo "scale=3; ${RAMP_UPDATE_INTERVAL_MS} / 1000" | bc)"
    done

    # Restore base qdisc
    restore_base_qdisc_both
    echo "[$(date +%H:%M:%S.%3N)] Ramped loss event complete, restored base qdisc"

    # Calculate time until next event (for logging only)
    local current_second
    current_second=$(date +%S)
    current_second=$((10#${current_second}))
    local next_event_time
    if [ "${current_second}" -lt 12 ]; then
        next_event_time=12.1
    elif [ "${current_second}" -lt 27 ]; then
        next_event_time=27.1
    elif [ "${current_second}" -lt 42 ]; then
        next_event_time=42.1
    elif [ "${current_second}" -lt 57 ]; then
        next_event_time=57.1
    else
        # All events done, next is at start of next minute
        next_event_time=61.5
    fi
    local time_until_next
    if (( $(echo "${next_event_time} > 60" | bc -l) )); then
        # Next event is in next minute
        time_until_next=$(echo "scale=2; 60 - ${current_second} + 1.5" | bc)
    else
        time_until_next=$(echo "scale=2; ${next_event_time} - ${current_second}" | bc)
    fi
    # Only print if time is positive and reasonable (avoid negative times from timing issues)
    if (( $(echo "${time_until_next} > 0 && ${time_until_next} < 60" | bc -l) )); then
        echo "[$(date +%H:%M:%S.%3N)] Next event in ${time_until_next} seconds"
    fi
}

# Function to handle flat 100% drop event
handle_drop_event() {
    local start_second=$1
    local duration_ms=$2

    wait_until "${start_second}"
    local duration_sec
    duration_sec=$(echo "scale=3; ${duration_ms} / 1000" | bc)

    echo "[$(date +%H:%M:%S.%3N)] Setting 100% loss on both interfaces for ${duration_sec}s"
    set_drop_all_both

    # Sleep for the duration
    sleep "${duration_sec}"

    restore_base_qdisc_both
    echo "[$(date +%H:%M:%S.%3N)] Drop event complete, restored base qdisc"

    # Calculate time until next event (for logging only)
    local current_second
    current_second=$(date +%S)
    current_second=$((10#${current_second}))
    local next_event_time
    if [ "${current_second}" -lt 12 ]; then
        next_event_time=12.1
    elif [ "${current_second}" -lt 27 ]; then
        next_event_time=27.1
    elif [ "${current_second}" -lt 42 ]; then
        next_event_time=42.1
    elif [ "${current_second}" -lt 57 ]; then
        next_event_time=57.1
    else
        # All events done, next is at start of next minute
        next_event_time=61.5
    fi
    local time_until_next
    if (( $(echo "${next_event_time} > 60" | bc -l) )); then
        # Next event is in next minute
        time_until_next=$(echo "scale=2; 60 - ${current_second} + 1.5" | bc)
    else
        time_until_next=$(echo "scale=2; ${next_event_time} - ${current_second}" | bc)
    fi
    # Only print if time is positive and reasonable (avoid negative times from timing issues)
    if (( $(echo "${time_until_next} > 0 && ${time_until_next} < 60" | bc -l) )); then
        echo "[$(date +%H:%M:%S.%3N)] Next event in ${time_until_next} seconds"
    fi
}

# Cleanup function
cleanup() {
    echo ""
    echo "[$(date +%H:%M:%S.%3N)] Cleaning up qdiscs on both interfaces..."

    # Remove root qdisc from both interfaces (this removes all child qdiscs and filters)
    cmd="tc qdisc del dev ${NIC0} root"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    ${cmd} 2>/dev/null || true
    cmd="tc qdisc del dev ${NIC1} root"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    ${cmd} 2>/dev/null || true

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

# Check if interfaces exist
for interface in "${NIC0}" "${NIC1}"; do
    if ! ip link show "${interface}" >/dev/null 2>&1; then
        echo "Error: Interface ${interface} not found"
        echo "Available interfaces:"
        ip link show | grep -E '^[0-9]+:' | awk '{print $2}' | sed 's/://'
        exit 1
    fi
done

# Check if bridge exists
if ! ip link show "${BRIDGE}" >/dev/null 2>&1; then
    echo "Warning: Bridge ${BRIDGE} not found, but continuing anyway"
fi

# Check if bc is available
if ! command -v bc >/dev/null 2>&1; then
    echo "Error: 'bc' command not found. Please install it."
    exit 1
fi

echo "Starting satellite network emulation"
echo "Bridge: ${BRIDGE}"
echo "Interfaces: ${NIC0} (outbound), ${NIC1} (inbound)"
echo "Target: UDP ports ${UDP_PORT0}, ${UDP_PORT1} and ICMP echo (all other traffic passes through unaffected)"
echo "Delay: ${DELAY_MS}ms±${JITTER_MS}ms per direction (total RTT ${RTT_MS}ms)"
echo "Queue limit: ${QUEUE_LIMIT} packets"
echo "Background loss: Starlink gemodel (Gilbert-Elliot burst loss model)"
echo "  p = ${GE_P} (probability of starting bad state)"
echo "  r = ${GE_R} (probability of exiting bad state)"
echo "  1-H = ${GE_1H} (loss probability in bad state = $(echo "scale=0; ${GE_1H} * 100" | bc)%)"
echo "  1-K = ${GE_1K} (loss probability in good state = $(echo "scale=0; ${GE_1K} * 100" | bc)%)"
echo "Loss events (each minute, UDP ports ${UDP_PORT0}, ${UDP_PORT1} and ICMP echo):"
echo "  - 1.5-2.5s: Ramped loss 0% → ${PEAK_LOSS}% → 0% (1000ms duration)"
echo "  - 12.1s: 100% loss for 70ms"
echo "  - 27.1s: 100% loss for 70ms"
echo "  - 42.1s: 100% loss for 70ms"
echo "  - 57.1s: 100% loss for 70ms"
echo "Press Ctrl+C to stop"
echo ""

# Setup initial qdiscs on both interfaces
echo "Setting up qdisc on ${NIC0}..."
if ! setup_interface_qdisc "${NIC0}"; then
    echo "Error: Failed to setup qdisc on ${NIC0}"
    exit 1
fi

echo ""
echo "Setting up qdisc on ${NIC1}..."
if ! setup_interface_qdisc "${NIC1}"; then
    echo "Error: Failed to setup qdisc on ${NIC1}"
    echo "Cleaning up ${NIC0}..."
    cmd="tc qdisc del dev ${NIC0} root"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    ${cmd} 2>/dev/null || true
    exit 1
fi
echo ""

# Function to determine which events should run based on current second
# Returns: space-separated list of event times that should be scheduled
get_remaining_events() {
    local current_second=$1
    local events=""

    # Event 1: 1.5-2.5s (ramped loss)
    if (( $(echo "${current_second} < 2.5" | bc -l) )); then
        events="${events} ramped:1.5"
    fi

    # Event 2: 12.1s (70ms drop)
    if (( $(echo "${current_second} < 12.17" | bc -l) )); then
        events="${events} drop:12.1"
    fi

    # Event 3: 27.1s (70ms drop)
    if (( $(echo "${current_second} < 27.17" | bc -l) )); then
        events="${events} drop:27.1"
    fi

    # Event 4: 42.1s (70ms drop)
    if (( $(echo "${current_second} < 42.17" | bc -l) )); then
        events="${events} drop:42.1"
    fi

    # Event 5: 57.1s (70ms drop)
    if (( $(echo "${current_second} < 57.17" | bc -l) )); then
        events="${events} drop:57.1"
    fi

    echo "${events}"
}

# Main loop - runs each minute
while true; do
    # Get current second within the minute
    current_second=$(date +%S)
    current_ms=$(date +%3N)
    current_second_decimal=$(echo "scale=2; ${current_second} + ${current_ms} / 1000" | bc)

    # Get current delay for this minute (optional dynamic delay feature)
    current_delay=$(get_current_delay_ms)
    current_time=$(date +%H:%M)

    # Determine which events should run
    remaining_events=$(get_remaining_events "${current_second_decimal}")

    if [ -n "${remaining_events}" ]; then
        echo "[$(date +%H:%M:%S.%3N)] Starting/continuing minute cycle (${current_time}, delay = ${current_delay}ms, current second = ${current_second_decimal})"
        echo "[$(date +%H:%M:%S.%3N)] Scheduling remaining events:${remaining_events}"
    else
        # All events for this minute have passed, wait until next minute
        seconds_until_next_minute=$(echo "scale=2; 60 - ${current_second_decimal}" | bc)
        echo "[$(date +%H:%M:%S.%3N)] All events for this minute complete. Waiting ${seconds_until_next_minute} seconds until next minute cycle"

        # Wait until next minute starts
        if (( $(echo "${seconds_until_next_minute} > 1" | bc -l) )); then
            # Sleep most of the time, then use precise wait
            sleep_seconds=$(echo "scale=3; ${seconds_until_next_minute} - 0.1" | bc)
            if (( $(echo "${sleep_seconds} > 0" | bc -l) )); then
                sleep "${sleep_seconds}"
            fi
        fi
        # Wait precisely for second 0
        wait_until 0
        current_second_decimal=0
        remaining_events=$(get_remaining_events "0")
        echo "[$(date +%H:%M:%S.%3N)] Starting new minute cycle (${current_time}, delay = ${current_delay}ms)"
    fi

    # Update qdiscs with current delay for this minute
    loss_model=$(build_gemodel_loss)
    cmd="tc qdisc change dev ${NIC0} parent 1:1 netem ${loss_model}"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    ${cmd} 2>/dev/null || true
    cmd="tc qdisc change dev ${NIC1} parent 1:1 netem ${loss_model}"
    echo "[$(date +%H:%M:%S.%3N)]    Running: ${cmd}"
    ${cmd} 2>/dev/null || true

    # Schedule remaining events in background
    for event in ${remaining_events}; do
        event_type=$(echo "${event}" | cut -d: -f1)
        event_time=$(echo "${event}" | cut -d: -f2)

        if [ "${event_type}" = "ramped" ]; then
            (handle_ramped_event "${event_time}" 1000 "${PEAK_LOSS}") &
        elif [ "${event_type}" = "drop" ]; then
            (handle_drop_event "${event_time}" 70) &
        fi
    done

    # Wait for all background jobs to complete
    wait

    # Check if we need to continue with more events or wait for next minute
    current_second=$(date +%S)
    current_ms=$(date +%3N)
    current_second_decimal=$(echo "scale=2; ${current_second} + ${current_ms} / 1000" | bc)

    # If we're past second 58, we're done with this minute
    if (( $(echo "${current_second_decimal} >= 58" | bc -l) )); then
        seconds_until_next_minute=$(echo "scale=2; 60 - ${current_second_decimal}" | bc)
        echo "[$(date +%H:%M:%S.%3N)] All events complete. Next minute cycle in ${seconds_until_next_minute} seconds"
    fi
done

