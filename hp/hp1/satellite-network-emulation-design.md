# Satellite Network Emulation Design Document

## Overview
This document outlines the design for a network emulation script that simulates a Starlink-like satellite network connection using a bridge configuration with two network interfaces.

## Requirements

### Network Topology
- **Bridge**: `br0` containing two physical interfaces
  - `enp1s0f0` (nic0) - Outbound direction (client → satellite)
  - `enp1s0f1` (nic1) - Inbound direction (satellite → client)
- Traffic flows through the bridge, allowing bidirectional emulation

### Latency Requirements
- **Total RTT**: 130ms
- **One-way delay per direction**: 65ms (130ms / 2)
- **Jitter**: Up to ±5ms total
  - **Per direction**: ±2.5ms (5ms / 2)
- **Distribution**: Normal distribution for jitter
- **Implementation**: Apply delay + jitter on each bridge member interface
  - `enp1s0f0`: 65ms ± 2.5ms (outbound)
  - `enp1s0f1`: 65ms ± 2.5ms (inbound)

### Queue Management Requirements
- **Packet limit**: Configurable limit for netem queue (default: 10000 packets)
  - **Default netem limit**: 1000 packets (insufficient for high-rate traffic with delay)
  - **Risk**: Without sufficient limit, netem will tail-drop packets when queue fills
  - **Solution**: Set `limit 10000` (or configurable value) on netem qdisc
  - **Variable**: `SATNET_QUEUE_LIMIT` (default: `10000`)
  - **Note**: Higher values use more memory but prevent drops during traffic bursts

### Packet Loss Requirements

#### Background Loss
- **Model**: Gilbert-Elliot (gemodel) for burst loss characteristics
- **Parameters** (Starlink-like):
  - `p = 0.01`: Probability of starting bad (lossy) state
  - `r = 0.25`: Probability of exiting bad state
  - `1-H = 0.30`: Loss probability in bad state (30% loss during bursts)
  - `1-K = 0.005`: Loss probability in good state (0.5% background loss)
- **Average loss rate**: ~2-3%

#### Periodic Loss Events (Each Minute)
1. **Large event** (at 1.5-2.5 seconds):
   - Duration: 1000ms (1 second)
   - **Loss pattern**: Ramped (not flat 100%)
     - Ramp up: Loss increases from baseline to peak over ~300ms
     - Peak: Configurable peak loss rate (default: 80%)
     - Ramp down: Loss decreases from peak back to baseline over ~300ms
     - Plateau: Brief period at peak loss (~400ms)
   - **Rationale**: Based on observed traffic patterns showing gradual increase/decrease rather than instant 100% loss
   - **Configurable**: Peak loss rate variable (default: 80%)
   - Simulates: Handoff between satellites or major obstruction

2. **Short events** (4 events):
   - Timing: 12.1s, 27.1s, 42.1s, 57.1s
   - Duration: 70ms each
   - Loss: 100%
   - Simulates: Brief satellite handoffs or atmospheric interference

### Target Traffic
- **UDP port**: 6001 (SRT stream)
- **Scope**: Only apply emulation to UDP port 6001 traffic
- **Other traffic**: Pass through unaffected

## Design Approach

### Architecture
```
[Client] → enp1s0f0 (outbound) → [Bridge br0] → enp1s0f1 (inbound) → [Server]
           ↓ netem delay+loss      ↓              ↓ netem delay+loss
           65ms ± 2.5ms                         65ms ± 2.5ms
           gemodel loss                          gemodel loss
```

### Implementation Strategy

#### 1. Qdisc Structure
For each interface (`enp1s0f0` and `enp1s0f1`):
- **Root**: `prio` qdisc (traffic classification)
- **Class 1:1**: `netem` qdisc for UDP port 6001
  - Delay: 65ms ± 2.5ms
  - Loss: gemodel with Starlink parameters
  - **Limit**: Configurable packet limit (default: 10000 packets)
    - Prevents tail-dropping when queue fills during high-rate traffic
    - Format: `limit <packets>` in netem command
- **Class 1:2, 1:3**: `pfifo` qdiscs for pass-through traffic

#### 2. Traffic Classification
- **Filters**: `u32` filters to match UDP port 6001
  - Match destination port 6001 (outbound)
  - Match source port 6001 (inbound)
- **All other traffic**: Routes to pass-through classes

#### 3. Loss Event Management
- **Synchronization**: Minute-based cycle (synchronized to system clock)
- **Event scheduling**: Background processes for each drop event
- **State management**:
  - Base state: gemodel loss + delay
  - Event state: 100% loss + delay (maintains delay during drops)
  - Automatic restoration after event duration

#### 4. Script Structure
```
simulate-satellite-network.sh
├── Configuration variables
│   ├── Bridge name (br0)
│   ├── Interface names (enp1s0f0, enp1s0f1)
│   ├── UDP port (6001)
│   ├── RTT (130ms)
│   ├── Delay per direction (65ms)
│   ├── Jitter per direction (±2.5ms)
│   └── Gemodel parameters
├── Functions
│   ├── setup_interface_qdisc(interface)
│   ├── build_gemodel_loss()
│   ├── set_ramped_loss(interface, start_ms, duration_ms, peak_loss)
│   ├── set_drop_all(interface, duration_ms)
│   ├── restore_base_qdisc(interface)
│   ├── handle_ramped_event(interface, start_second, duration_ms, peak_loss)
│   ├── handle_drop_event(interface, start_second, duration_ms)
│   ├── wait_until(target_second)
│   └── cleanup()
├── Configuration
│   ├── QUEUE_LIMIT (default: 10000 packets)
│   └── Other parameters...
└── Main loop
    ├── Setup qdiscs on both interfaces
    ├── Minute synchronization
    └── Schedule drop events for both interfaces
```

## Implementation Approaches

### Option 1: Bash + tc netem (Current Approach)
**Pros:**
- Simple to implement and debug
- Well-documented and widely used
- Easy to modify parameters
- No kernel module compilation needed
- Works with existing tools (`tc`, `ip`)

**Cons:**
- Limited precision for ramped loss events (requires frequent qdisc changes)
- Non-atomic operations (brief inconsistencies possible)
- Higher overhead for frequent changes
- Limited to netem capabilities

**Ramped Loss Implementation:**
- Requires multiple `tc qdisc change` commands over time
- Example: Change loss rate every 50-100ms to create ramp
- More complex timing logic needed
- Potential for brief inconsistencies during transitions

### Option 2: eBPF (Extended Berkeley Packet Filter)
**Pros:**
- **True atomicity**: Single program execution per packet
- **High precision**: Can implement exact loss curves with microsecond precision
- **Low overhead**: Runs in kernel, very efficient
- **Flexible**: Can implement complex loss patterns (ramps, curves, etc.)
- **Per-packet control**: Can make decisions based on packet contents, timing, etc.
- **Better for ramped events**: Can calculate loss probability per packet based on time

**Cons:**
- More complex to implement (requires C/BPF code)
- Requires kernel compilation or BTF support
- Debugging is more challenging
- Less portable (kernel version dependencies)
- Requires eBPF toolchain (`clang`, `llvm`, `libbpf`)

**eBPF Implementation Approach:**
- Attach eBPF program to each interface (`enp1s0f0`, `enp1s0f1`)
- Program runs on each packet in kernel space
- Can implement:
  - Precise delay injection (using timestamps)
  - Ramped loss curves (calculate loss probability based on time)
  - Gemodel loss (state machine in eBPF)
  - Jitter (random delay variation)
- Use `tc` with `cls_bpf` or `xdp` (XDP is faster but requires driver support)

**eBPF Program Structure:**
```c
// Pseudo-code structure
SEC("tc")
int handle_packet(struct __sk_buff *skb) {
    // Check if UDP port 6001
    // Get current time (nanoseconds since minute start)
    // Calculate loss probability based on:
    //   - Gemodel state machine
    //   - Event schedule (ramped loss at 1.5-2.5s, etc.)
    // Apply delay (65ms ± jitter)
    // Return TC_ACT_OK or TC_ACT_SHOT (drop)
}
```

**Recommendation:**
- **Start with bash + tc netem** for initial implementation and testing
- **Consider eBPF** if:
  - Ramped loss events need higher precision
  - Atomicity becomes a critical issue
  - Performance overhead of frequent qdisc changes is problematic
  - More complex loss patterns are needed

## Latency vs Loss Application Strategy

### Problem Statement
We need to decide where to apply latency and loss in the network stack:
- **Latency**: Must be applied per-direction (outbound vs inbound)
- **Loss**: Could be applied per-direction or centrally on the bridge
- **Event loss**: Needs to be updated frequently (ramped events), ideally atomically

### Option 1: Everything on Individual NICs (Current Design)
**Configuration:**
- Latency: Applied to `enp1s0f0` and `enp1s0f1` separately
- Background loss (gemodel): Applied to `enp1s0f0` and `enp1s0f1` separately
- Event loss: Applied to both `enp1s0f0` and `enp1s0f1` simultaneously

**Pros:**
- ✅ Simple and consistent architecture
- ✅ Each direction is independent
- ✅ Matches physical reality (each interface has its own delay)
- ✅ Easy to understand and debug
- ✅ Can have different loss rates per direction if needed

**Cons:**
- ❌ Loss events require updating both interfaces (2 `tc qdisc change` commands)
- ❌ Slight non-atomicity between interface updates
- ❌ More commands to execute during ramped events

### Option 2: Latency on NICs, Loss on Bridge
**Configuration:**
- Latency: Applied to `enp1s0f0` and `enp1s0f1` separately
- Background loss (gemodel): Applied to `br0` bridge
- Event loss: Applied to `br0` bridge only

**Pros:**
- ✅ Loss events only need one update (bridge)
- ✅ More atomic (single qdisc change for loss events)
- ✅ Simpler event handling (one interface to manage)
- ✅ Faster ramped loss updates (fewer commands)

**Cons:**
- ❌ Bridge qdiscs work on aggregated traffic (both directions combined)
- ❌ May not accurately model per-direction loss characteristics
- ❌ Bridge qdiscs are less commonly used, less documentation
- ❌ Potential issues with bridge qdisc interaction with member interfaces
- ❌ Loss applied after latency (packets already delayed, then lost)

### Option 3: Background Loss on NICs, Event Loss on Bridge (Hybrid)
**Configuration:**
- Latency: Applied to `enp1s0f0` and `enp1s0f1` separately
- Background loss (gemodel): Applied to `enp1s0f0` and `enp1s0f1` separately
- Event loss: Applied to `br0` bridge only

**Pros:**
- ✅ Background loss per-direction (more realistic)
- ✅ Event loss centralized (easier to manage)
- ✅ Best of both worlds: realistic background + efficient events
- ✅ Event loss updates are atomic (single bridge update)

**Cons:**
- ❌ More complex architecture (loss in two places)
- ❌ Potential interaction between NIC loss and bridge loss
- ❌ Loss rates may compound (background loss + event loss)
- ❌ Harder to debug (need to check both NICs and bridge)

### Option 4: Everything on Bridge
**Configuration:**
- Latency: Applied to `br0` bridge
- Background loss (gemodel): Applied to `br0` bridge
- Event loss: Applied to `br0` bridge

**Pros:**
- ✅ Single point of configuration
- ✅ Most atomic operations
- ✅ Simplest event handling

**Cons:**
- ❌ Bridge latency doesn't model per-direction delay accurately
- ❌ Bridge qdiscs are less well-documented
- ❌ May not work correctly with bridge member interfaces
- ❌ Less realistic (satellite delay is per-direction)

### Technical Considerations

#### Bridge Qdisc Behavior
- Bridge qdiscs operate on the bridge interface itself
- Traffic flows: NIC → Bridge → NIC (for forwarding)
- Bridge qdiscs see aggregated traffic from all member interfaces
- May not distinguish between outbound and inbound traffic easily

#### Netem on Bridge Members
- Netem on member interfaces (`enp1s0f0`, `enp1s0f1`) operates before bridge
- Netem on bridge (`br0`) operates after member interfaces
- Order matters: Member netem → Bridge netem → Physical transmission

#### Loss Rate Compounding
- If loss is applied at both NIC and bridge:
  - Effective loss = 1 - (1 - NIC_loss) × (1 - Bridge_loss)
  - Example: 5% NIC loss + 10% bridge loss = 14.5% effective loss
- This may not be desired behavior

### Recommendation

**Recommended: Option 1 (Everything on NICs)**
- Most realistic emulation (matches physical satellite behavior)
- Easiest to understand and debug
- Well-documented approach
- Slight non-atomicity is acceptable for this use case
- Can optimize by minimizing time between interface updates

**Alternative: Option 3 (Hybrid) if atomicity is critical**
- If ramped loss events need perfect atomicity
- If event update frequency becomes a bottleneck
- Requires careful testing to ensure loss rates don't compound incorrectly

**Not Recommended: Option 2 or 4**
- Bridge qdiscs are less well-documented
- May not accurately model per-direction characteristics
- Potential for unexpected behavior

### Implementation Notes
- If using Option 1: Minimize time between interface updates by:
  - Using background processes that update simultaneously
  - Batching commands where possible
  - Using `tc qdisc replace` instead of `tc qdisc change` if available
- If using Option 3: Ensure loss rates are calculated correctly to avoid compounding

## Technical Considerations

### Bridge vs Individual Interfaces
- **Advantage**: Can apply different delays/loss to each direction
- **Challenge**: Need to ensure events are synchronized across both interfaces
- **Solution**: Apply same event schedule to both interfaces simultaneously

### Qdisc Change Atomicity
- **Concern**: Bash script execution of `tc qdisc change` commands may not be atomic
- **Reality**:
  - Each `tc qdisc change` command is atomic at the kernel level
  - However, multiple commands executed sequentially are NOT atomic as a group
  - Between commands, there may be brief periods where qdisc state is inconsistent
- **Impact**:
  - **Low risk**: For loss event changes (switching between gemodel and 100% loss)
    - Brief inconsistency (< 1ms) is negligible compared to event duration (70-1000ms)
  - **Medium risk**: During initial setup if traffic is already flowing
    - Solution: Setup should occur before traffic starts, or use `tc qdisc replace` where possible
- **Mitigation strategies**:
  1. Use `tc qdisc replace` instead of `tc qdisc change` when possible (atomic replacement)
  2. Minimize time between related qdisc changes
  3. Consider using a single compound command where possible
  4. Document that brief inconsistencies may occur during transitions
- **Recommendation**:
  - Accept minor non-atomicity for simplicity
  - Monitor for any issues during testing
  - If problems occur, consider implementing a C/Python wrapper that uses netlink directly for true atomicity

### Delay Application
- **Why split**: More realistic satellite emulation (propagation delay in both directions)
- **Total RTT**: 65ms (outbound) + 65ms (inbound) = 130ms
- **Jitter**: Independent per direction, but synchronized events

### Loss Event Synchronization
- **Requirement**: Same loss events on both interfaces at same time
- **Implementation**:
  - Single event handler that updates both interfaces
  - Background processes coordinate via shared timing

### Cake Qdisc Interference
- **Issue**: systemd-networkd may create `cake` qdiscs on interfaces
- **Solution**: Remove existing qdiscs before setup (as in original script)

## Configuration Options

### Environment Variables
- `SATNET_BRIDGE`: Bridge name (default: `br0`)
- `SATNET_NIC0`: First interface (default: `enp1s0f0`)
- `SATNET_NIC1`: Second interface (default: `enp1s0f1`)
- `SATNET_UDP_PORT`: UDP port to emulate (default: `6001`)
- `SATNET_RTT_MS`: Total RTT in milliseconds (default: `130`)
- `SATNET_JITTER_MS`: Total jitter in milliseconds (default: `5`)
- `SATNET_QUEUE_LIMIT`: Packet limit for netem queue (default: `10000`)
  - Prevents tail-dropping when queue fills
  - Higher values use more memory but handle bursts better
  - Must be sufficient for: (bandwidth × delay) / packet_size
- `SATNET_PEAK_LOSS`: Peak loss rate for large event (default: `80` = 80%)
  - Only applies to large event (1.5-2.5s)
  - Short events remain at 100% loss

### Gemodel Parameters (configurable)
- `SATNET_GE_P`: Probability of starting bad state (default: `0.01`)
- `SATNET_GE_R`: Probability of exiting bad state (default: `0.25`)
- `SATNET_GE_1H`: Loss in bad state (default: `0.30`)
- `SATNET_GE_1K`: Loss in good state (default: `0.005`)

## Event Schedule (Per Minute)

| Time (seconds) | Duration (ms) | Loss Pattern | Description |
|----------------|---------------|--------------|-------------|
| 1.5 - 2.5      | 1000          | Ramped (0% → 80% → 0%) | Major handoff/obstruction |
|                |               | - Ramp up: ~300ms to peak | |
|                |               | - Plateau: ~400ms at peak | |
|                |               | - Ramp down: ~300ms from peak | |
| 12.1           | 70            | 100% (flat)  | Brief handoff |
| 27.1           | 70            | 100% (flat)  | Brief handoff |
| 42.1           | 70            | 100% (flat)  | Brief handoff |
| 57.1           | 70            | 100% (flat)  | Brief handoff |

## Testing & Validation

### Verification Steps
1. **Bridge status**: `brctl show br0`
2. **Qdisc status**: `tc qdisc show dev enp1s0f0` and `tc qdisc show dev enp1s0f1`
3. **Filter status**: `tc filter show dev enp1s0f0` and `tc filter show dev enp1s0f1`
4. **Delay measurement**: Use `ping` or `traceroute` to verify RTT
5. **Loss measurement**: Monitor packet loss during events
6. **Traffic isolation**: Verify non-UDP-6001 traffic is unaffected

### Expected Behavior
- **Normal operation**: ~2-3% average packet loss, 130ms ± 5ms RTT
- **During events**: 100% packet loss for specified durations
- **After events**: Automatic return to base gemodel loss
- **Other traffic**: No delay or loss applied

## Implementation Notes

### Script Location
- **Path**: `/home/das/nixos/hp/hp1/simulate-satellite-network.sh`
- **Permissions**: Executable, run as root
- **Dependencies**: `tc`, `ip`, `bc`, `bash`

### Cleanup Script
- **Path**: `/home/das/nixos/hp/hp1/clear-satellite-emulation.sh`
- **Function**: Remove all qdiscs and filters from both interfaces
- **Usage**: Run before/after testing to restore normal network

### Status Script
- **Path**: `/home/das/nixos/hp/hp1/show-satellite-status.sh`
- **Function**: Display current qdisc, filter, and interface status
- **Usage**: Debugging and monitoring during testing

## Future Enhancements

### Potential Improvements
1. **Dynamic RTT adjustment**: Vary RTT based on time of day (simulate orbital changes)
2. **Bandwidth limiting**: Add bandwidth constraints to simulate satellite capacity
3. **Asymmetric delays**: Different delays for uplink vs downlink
4. **Event randomization**: Vary event timing slightly for more realism
5. **Configuration file**: YAML/JSON config instead of hardcoded values
6. **Logging**: Detailed logs of events and statistics
7. **Metrics export**: Export statistics to Prometheus/Grafana
8. **eBPF migration**: If bash approach has limitations, migrate to eBPF for:
   - True atomicity
   - Precise ramped loss curves
   - Lower overhead
   - More complex loss patterns

## Questions for Discussion

1. **Event synchronization**: Should events be perfectly synchronized on both interfaces, or slightly offset?
2. **Jitter distribution**: Normal distribution vs uniform distribution?
3. **Bridge priority**: Should we adjust bridge STP priority in the script?
4. **Interface selection**: Should the script auto-detect bridge members, or require explicit configuration?
5. **Error handling**: How should the script handle interface failures or bridge changes?
6. **Performance**: Any concerns about applying netem to both bridge members simultaneously?
7. **Queue limit sizing**: How to calculate optimal queue limit based on bandwidth and delay?
   - Formula: `limit = (bandwidth_bps × delay_seconds) / (packet_size_bits)`
   - Example: 20 Mbps × 0.065s / (1500 bytes × 8) ≈ 108 packets minimum
   - Safety margin: 10x minimum = ~1000-10000 packets
8. **Atomicity acceptance**: Is the brief non-atomicity during qdisc changes acceptable, or should we implement a more atomic solution?
9. **Implementation approach**: Should we start with bash + tc netem, or go directly to eBPF for better precision?
10. **Ramped loss granularity**: How fine-grained should the ramp be? (e.g., update every 50ms, 100ms, or 200ms?)
11. **Ramp curve shape**: Linear ramp, exponential, or custom curve based on observed data?

## Netem Technical Notes

### Parameter Format and Ordering

**Important:** Netem parameter ordering and format can be critical for proper operation.

#### Limit Parameter
- **Format**: `limit PACKETS`
- **Placement**: Can be placed first or last in the command
- **Default**: 1000 packets (insufficient for high-rate traffic with delay)
- **Recommendation**: Place `limit` at the end of the command for better compatibility
- **Example**: `delay 65ms 2.5ms loss gemodel 0.01 0.25 0.30 0.005 limit 10000`

#### Delay Parameter
- **Format**: `delay TIME [ JITTER [ CORRELATION ]]`
- **Time units**: Milliseconds (ms)
- **Jitter**: Optional, also in milliseconds
- **Correlation**: Optional, percentage (0-100) of how much previous delay impacts current value
- **Distribution**: Optional, can use `distribution {uniform|normal|pareto|paretonormal}`
- **Example**: `delay 65ms 2.5ms` (65ms base delay with ±2.5ms jitter)

#### Loss Gemodel Parameter
- **Format**: `loss gemodel PERCENT [ R [ 1-H [ 1-K ]]]`
- **PERCENT**: Probability of starting bad (lossy) state
  - **Format**: Decimal value (e.g., 0.01 = 1%)
  - **Note**: Despite being called "PERCENT", netem accepts decimal values (0.01, not 1%)
- **R**: Probability of exiting bad state (decimal, e.g., 0.25)
- **1-H**: Loss probability in bad state (decimal, e.g., 0.30 = 30% loss during bursts)
- **1-K**: Loss probability in good state (decimal, e.g., 0.005 = 0.5% background loss)
- **Important**: All parameters use decimal format (0.01, 0.25, etc.), NOT percentages with % sign
- **Example**: `loss gemodel 0.01 0.25 0.30 0.005`

#### Loss Random Parameter
- **Format**: `loss random PERCENT [ CORRELATION ]`
- **PERCENT**: Uses percentage format with % sign (e.g., `0.1%` = 0.1% loss)
- **Note**: Different from gemodel - random loss uses % sign, gemodel uses decimals
- **Example**: `loss random 0.1%` or `loss 80%` for 80% loss

### Command Construction Best Practices

1. **Parameter Order**: While netem accepts parameters in any order, recommended order is:
   ```
   delay [jitter] [correlation] [distribution] loss [model] limit [packets]
   ```

2. **Limit Placement**:
   - Can be first or last
   - **Recommendation**: Place at end for better compatibility across netem versions
   - Some versions may have issues with `limit` first

3. **Quoting**: Always quote variables in shell scripts to prevent word splitting:
   ```bash
   tc qdisc add dev eth0 parent 1:1 netem "delay 65ms 2.5ms loss gemodel 0.01 0.25 0.30 0.005 limit 10000"
   ```

4. **Error Messages**: If netem shows "What is..." error, check:
   - Parameter format (decimals vs percentages)
   - Parameter order
   - Missing or extra spaces
   - Variable expansion issues

### Common Pitfalls

1. **Gemodel vs Random Loss Format**:
   - ❌ Wrong: `loss gemodel 1% 25% 30% 0.5%` (using % signs)
   - ✅ Correct: `loss gemodel 0.01 0.25 0.30 0.005` (using decimals)
   - ❌ Wrong: `loss random 0.1` (missing % sign)
   - ✅ Correct: `loss random 0.1%` or `loss 80%` (using % sign)

2. **Limit Parameter**:
   - Default limit (1000 packets) is too small for high-rate traffic with delay
   - Must be sufficient for: `(bandwidth × delay) / packet_size`
   - Example: 20 Mbps × 0.065s / (1500 bytes × 8) ≈ 108 packets minimum
   - Use 10x safety margin: 1000-10000 packets recommended

3. **Delay and Jitter**:
   - Jitter is applied as ± variation around base delay
   - `delay 65ms 2.5ms` means: 65ms ± 2.5ms (range: 62.5ms to 67.5ms)
   - Distribution can be added: `delay 65ms 2.5ms distribution normal`

4. **Qdisc Change vs Replace**:
   - `tc qdisc change`: Modifies existing qdisc (must exist)
   - `tc qdisc replace`: Replaces qdisc (creates if doesn't exist)
   - Use `change` for runtime modifications, `replace` for initial setup

### Testing Netem Commands

Before using in scripts, test commands manually:
```bash
# Test on loopback interface first
sudo tc qdisc add dev lo root netem delay 65ms 2.5ms loss gemodel 0.01 0.25 0.30 0.005 limit 10000

# Verify it worked
tc qdisc show dev lo

# Clean up
sudo tc qdisc del dev lo root
```

### Version Compatibility

- Different netem versions may have slightly different syntax requirements
- Always test on target system before deploying
- Check `tc -Version` to identify netem version
- Some older versions may not support all features (e.g., gemodel, distribution)

## References

- Original `simulate-packet-loss.sh` script
- `tc-netem` man page: https://www.man7.org/linux/man-pages/man8/tc-netem.8.html
- Starlink network characteristics research
- Gilbert-Elliot model documentation

