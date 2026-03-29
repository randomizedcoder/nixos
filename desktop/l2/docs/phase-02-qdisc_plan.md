# Phase 2: Qdisc Configuration - Implementation Plan

**Design Reference**: [phase-02-qdisc.md](./phase-02-qdisc.md)

**Prerequisites**: Phase 1 complete (`mq-cake-verify` passes)

**Overview**: Implement qdisc switching on DUT interfaces with support for fq_codel, cake, and mq-cake.

**Log File**: [phase-02-qdisc_log.md](./phase-02-qdisc_log.md) (update on completion of each sub-phase)

---

## Sub-Phase 2.1: Add Qdisc Script Skeleton

### Steps

1. **Add `qdiscScript`** to `mq-cake-test.nix` in the let block:
   ```nix
   qdiscScript = pkgs.writeShellApplication {
     name = "mq-cake-qdisc";
     runtimeInputs = with pkgs; [ iproute2 ];
     text = ''
       set -euo pipefail

       QDISC=''${1:-fq_codel}

       echo "=== MQ-CAKE Qdisc Configuration ==="
       echo "Qdisc: $QDISC"

       case "$QDISC" in
         fq_codel|cake|mq-cake|cake_mq)
           echo "Valid qdisc"
           ;;
         *)
           echo "Unknown qdisc: $QDISC"
           echo "Supported: fq_codel, cake, mq-cake"
           exit 1
           ;;
       esac
     '';
   };
   ```

2. **Add to systemPackages**:
   ```nix
   environment.systemPackages = [
     setupScript
     teardownScript
     verifyScript
     qdiscScript   # Add this
   ];
   ```

3. **Rebuild and test**:
   ```bash
   sudo nixos-rebuild switch
   mq-cake-qdisc fq_codel
   mq-cake-qdisc invalid  # Should fail
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 2.1.1 | `which mq-cake-qdisc` | Path returned |
| 2.1.2 | `mq-cake-qdisc fq_codel` | Exit 0, "Valid qdisc" |
| 2.1.3 | `mq-cake-qdisc cake` | Exit 0, "Valid qdisc" |
| 2.1.4 | `mq-cake-qdisc mq-cake` | Exit 0, "Valid qdisc" |
| 2.1.5 | `mq-cake-qdisc invalid` | Exit 1, error message |

### Definition of Done

- [ ] `mq-cake-qdisc` command available
- [ ] Validates qdisc argument
- [ ] Rejects invalid qdisc names
- [ ] Log file updated

---

## Sub-Phase 2.2: Implement fq_codel Configuration

### Steps

1. **Update `qdiscScript`** to apply fq_codel:
   ```nix
   qdiscScript = pkgs.writeShellApplication {
     name = "mq-cake-qdisc";
     runtimeInputs = with pkgs; [ iproute2 ];
     text = ''
       set -euo pipefail

       QDISC=''${1:-fq_codel}
       BANDWIDTH=''${MQ_CAKE_BANDWIDTH:-10gbit}

       echo "=== MQ-CAKE Qdisc Configuration ==="
       echo "Qdisc: $QDISC"
       echo "Bandwidth: $BANDWIDTH"
       echo ""

       apply_fq_codel() {
         local iface=$1
         ip netns exec ns-dut tc qdisc replace dev "$iface" root fq_codel
         echo "  $iface: fq_codel applied"
       }

       case "$QDISC" in
         fq_codel)
           apply_fq_codel ${ixgbe_p0}
           apply_fq_codel ${ixgbe_p1}
           ;;
         *)
           echo "Qdisc $QDISC not yet implemented"
           exit 1
           ;;
       esac

       echo ""
       echo "Current qdisc on ${ixgbe_p0}:"
       ip netns exec ns-dut tc qdisc show dev ${ixgbe_p0} | head -1
     '';
   };
   ```

2. **Test fq_codel application**:
   ```bash
   sudo mq-cake-setup
   sudo mq-cake-qdisc fq_codel
   ip netns exec ns-dut tc qdisc show dev enp66s0f0
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 2.2.1 | `sudo mq-cake-qdisc fq_codel` | Exit 0 |
| 2.2.2 | `ip netns exec ns-dut tc qdisc show dev enp66s0f0` | Shows "fq_codel" |
| 2.2.3 | `ip netns exec ns-dut tc qdisc show dev enp66s0f1` | Shows "fq_codel" |
| 2.2.4 | `sudo mq-cake-verify` | Still passes (ping works) |

### Definition of Done

- [ ] fq_codel applied to both DUT interfaces
- [ ] tc qdisc show confirms fq_codel
- [ ] Ping still works after qdisc change
- [ ] Log file updated

---

## Sub-Phase 2.3: Implement cake Configuration

### Steps

1. **Add cake case** to `qdiscScript`:
   ```nix
   apply_cake() {
     local iface=$1
     ip netns exec ns-dut tc qdisc replace dev "$iface" root cake \
       bandwidth "$BANDWIDTH" diffserv4 nat wash split-gso
     echo "  $iface: cake applied (bandwidth=$BANDWIDTH)"
   }

   case "$QDISC" in
     fq_codel)
       apply_fq_codel ${ixgbe_p0}
       apply_fq_codel ${ixgbe_p1}
       ;;
     cake)
       apply_cake ${ixgbe_p0}
       apply_cake ${ixgbe_p1}
       ;;
     *)
       echo "Qdisc $QDISC not yet implemented"
       exit 1
       ;;
   esac
   ```

2. **Test cake application**:
   ```bash
   sudo mq-cake-qdisc cake
   ip netns exec ns-dut tc qdisc show dev enp66s0f0
   # Should show: qdisc cake ... bandwidth 10Gbit diffserv4 ...
   ```

3. **Test bandwidth override**:
   ```bash
   MQ_CAKE_BANDWIDTH=1gbit sudo mq-cake-qdisc cake
   ip netns exec ns-dut tc qdisc show dev enp66s0f0
   # Should show: bandwidth 1Gbit
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 2.3.1 | `sudo mq-cake-qdisc cake` | Exit 0 |
| 2.3.2 | `ip netns exec ns-dut tc qdisc show dev enp66s0f0` | Shows "cake" with options |
| 2.3.3 | `ip netns exec ns-dut tc qdisc show dev enp66s0f0 \| grep 10Gbit` | Bandwidth correct |
| 2.3.4 | `MQ_CAKE_BANDWIDTH=1gbit sudo mq-cake-qdisc cake && tc show \| grep 1Gbit` | Override works |
| 2.3.5 | `sudo mq-cake-verify` | Still passes |

### Definition of Done

- [ ] cake applied to both DUT interfaces
- [ ] Bandwidth parameter works (default 10gbit)
- [ ] MQ_CAKE_BANDWIDTH env var override works
- [ ] CAKE options visible in tc output (diffserv4, nat, wash, split-gso)
- [ ] Log file updated

---

## Sub-Phase 2.4: Implement mq-cake Configuration

### Steps

1. **Determine mq-cake availability**:
   ```bash
   # Check if cake_mq is in kernel
   modprobe sch_cake_mq 2>&1
   # If not found, need kernel patches or fallback
   ```

2. **Add mq-cake case** to `qdiscScript`:
   ```nix
   apply_mq_cake() {
     local iface=$1
     # Try cake_mq (mq-cake kernel module name)
     if ip netns exec ns-dut tc qdisc replace dev "$iface" root cake_mq \
         bandwidth "$BANDWIDTH" diffserv4 nat wash split-gso 2>/dev/null; then
       echo "  $iface: mq-cake (cake_mq) applied"
     else
       echo "  WARNING: cake_mq not available, falling back to mq + cake child"
       # Fallback: mq with cake per-queue (less optimal but functional)
       ip netns exec ns-dut tc qdisc replace dev "$iface" root mq
       # Get queue count
       local queues
       queues=$(ip netns exec ns-dut ls /sys/class/net/"$iface"/queues/ | grep tx- | wc -l)
       for ((i=0; i<queues; i++)); do
         ip netns exec ns-dut tc qdisc replace dev "$iface" parent :$((i+1)) cake \
           bandwidth "$BANDWIDTH" diffserv4 nat wash split-gso
       done
       echo "  $iface: mq + cake child qdiscs applied ($queues queues)"
     fi
   }

   case "$QDISC" in
     fq_codel)
       apply_fq_codel ${ixgbe_p0}
       apply_fq_codel ${ixgbe_p1}
       ;;
     cake)
       apply_cake ${ixgbe_p0}
       apply_cake ${ixgbe_p1}
       ;;
     mq-cake|cake_mq)
       apply_mq_cake ${ixgbe_p0}
       apply_mq_cake ${ixgbe_p1}
       ;;
     *)
       echo "Unknown qdisc: $QDISC"
       echo "Supported: fq_codel, cake, mq-cake"
       exit 1
       ;;
   esac
   ```

3. **Test mq-cake**:
   ```bash
   sudo mq-cake-qdisc mq-cake
   ip netns exec ns-dut tc qdisc show dev enp66s0f0
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 2.4.1 | `sudo mq-cake-qdisc mq-cake` | Exit 0 (with or without fallback) |
| 2.4.2 | `ip netns exec ns-dut tc qdisc show dev enp66s0f0` | Shows mq-cake or mq+cake |
| 2.4.3 | `ip netns exec ns-dut tc -s qdisc show dev enp66s0f0` | Shows stats without error |
| 2.4.4 | `sudo mq-cake-verify` | Still passes |
| 2.4.5 | `ip netns exec ns-gen-a ping -c 10 10.2.0.2` | 0% loss with mq-cake |

### Definition of Done

- [ ] mq-cake or fallback applied to both interfaces
- [ ] Script handles missing cake_mq gracefully
- [ ] tc shows correct qdisc configuration
- [ ] Connectivity maintained after qdisc switch
- [ ] Log file updated

---

## Sub-Phase 2.5: Add Qdisc Statistics Script

### Steps

1. **Create `mq-cake-stats`** script in `mq-cake-test.nix`:
   ```nix
   statsScript = pkgs.writeShellApplication {
     name = "mq-cake-stats";
     runtimeInputs = with pkgs; [ iproute2 ];
     text = ''
       set -euo pipefail

       IFACE=''${1:-${ixgbe_p0}}

       echo "=== Qdisc Statistics: $IFACE ==="
       echo ""

       echo "--- Qdisc Configuration ---"
       ip netns exec ns-dut tc qdisc show dev "$IFACE"
       echo ""

       echo "--- Qdisc Statistics ---"
       ip netns exec ns-dut tc -s qdisc show dev "$IFACE"
       echo ""

       echo "--- Class Statistics (if any) ---"
       ip netns exec ns-dut tc -s class show dev "$IFACE" 2>/dev/null || echo "No classes"
     '';
   };
   ```

2. **Add to systemPackages**:
   ```nix
   environment.systemPackages = [
     setupScript teardownScript verifyScript qdiscScript statsScript
   ];
   ```

3. **Test stats collection**:
   ```bash
   sudo mq-cake-qdisc cake
   sudo mq-cake-stats
   sudo mq-cake-stats enp66s0f1
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 2.5.1 | `which mq-cake-stats` | Path returned |
| 2.5.2 | `sudo mq-cake-stats` | Shows stats for enp66s0f0 |
| 2.5.3 | `sudo mq-cake-stats enp66s0f1` | Shows stats for enp66s0f1 |
| 2.5.4 | Stats show: Sent bytes, packets, drops | Output includes these fields |

### Definition of Done

- [ ] `mq-cake-stats` command available
- [ ] Shows qdisc configuration
- [ ] Shows packet/byte counters
- [ ] Shows drop counters
- [ ] Log file updated

---

## Sub-Phase 2.6: Add Qdisc Reset Script

### Steps

1. **Create `mq-cake-reset`** script:
   ```nix
   resetScript = pkgs.writeShellApplication {
     name = "mq-cake-reset";
     runtimeInputs = with pkgs; [ iproute2 ];
     text = ''
       set -euo pipefail

       echo "=== Resetting Qdiscs to Default ==="

       for iface in ${ixgbe_p0} ${ixgbe_p1}; do
         echo "Resetting $iface..."
         ip netns exec ns-dut tc qdisc del dev "$iface" root 2>/dev/null || true
         # Kernel will use pfifo_fast or fq_codel as default
       done

       echo ""
       echo "Current qdiscs:"
       ip netns exec ns-dut tc qdisc show dev ${ixgbe_p0} | head -1
       ip netns exec ns-dut tc qdisc show dev ${ixgbe_p1} | head -1
     '';
   };
   ```

2. **Add to systemPackages**

3. **Test reset**:
   ```bash
   sudo mq-cake-qdisc cake
   ip netns exec ns-dut tc qdisc show dev enp66s0f0  # Shows cake
   sudo mq-cake-reset
   ip netns exec ns-dut tc qdisc show dev enp66s0f0  # Shows default
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 2.6.1 | `which mq-cake-reset` | Path returned |
| 2.6.2 | Set cake, then `sudo mq-cake-reset` | Qdisc changes |
| 2.6.3 | `sudo mq-cake-verify` after reset | Still passes |

### Definition of Done

- [ ] `mq-cake-reset` command available
- [ ] Removes custom qdisc from both interfaces
- [ ] Connectivity maintained after reset
- [ ] Log file updated

---

## Sub-Phase 2.7: Integration Test

### Steps

1. **Fresh environment**:
   ```bash
   sudo mq-cake-teardown
   sudo mq-cake-setup
   sudo mq-cake-verify
   ```

2. **Cycle through all qdiscs**:
   ```bash
   for qdisc in fq_codel cake mq-cake; do
     echo "=== Testing $qdisc ==="
     sudo mq-cake-qdisc $qdisc
     sudo mq-cake-stats
     ip netns exec ns-gen-a ping -c 5 10.2.0.2
     echo ""
   done
   ```

3. **Verify qdisc switching is atomic**:
   ```bash
   # While running ping flood in background
   ip netns exec ns-gen-a ping -f 10.2.0.2 &
   PID=$!
   sleep 1
   sudo mq-cake-qdisc cake
   sudo mq-cake-qdisc fq_codel
   sudo mq-cake-qdisc mq-cake
   kill $PID
   # Should have minimal packet loss during switches
   ```

4. **Record baseline latency per qdisc**:
   ```bash
   for qdisc in fq_codel cake mq-cake; do
     sudo mq-cake-qdisc $qdisc
     echo "$qdisc:"
     ip netns exec ns-gen-a ping -c 20 -i 0.1 10.2.0.2 | tail -1
   done
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 2.7.1 | Cycle through fq_codel → cake → mq-cake | All succeed |
| 2.7.2 | `mq-cake-stats` shows different config per qdisc | Config matches |
| 2.7.3 | Ping during qdisc switch | Minimal loss (<5%) |
| 2.7.4 | Baseline RTT similar for all qdiscs | RTT within 0.5ms |
| 2.7.5 | `sudo mq-cake-verify` after all switches | Passes |

### Definition of Done

- [ ] All three qdiscs can be applied
- [ ] Switching between qdiscs is reliable
- [ ] Stats script works for all qdiscs
- [ ] Reset returns to default state
- [ ] Baseline latency recorded for each qdisc
- [ ] Log file updated with performance data

---

## Phase 2 Complete Checklist

Before proceeding to Phase 3, verify:

- [ ] `mq-cake-qdisc fq_codel` works
- [ ] `mq-cake-qdisc cake` works with bandwidth parameter
- [ ] `mq-cake-qdisc mq-cake` works (native or fallback)
- [ ] `mq-cake-stats` shows qdisc statistics
- [ ] `mq-cake-reset` returns to default
- [ ] Bandwidth override via MQ_CAKE_BANDWIDTH works
- [ ] Connectivity maintained across all qdisc switches
- [ ] Baseline latency recorded per qdisc
- [ ] Log file complete with all sub-phase timestamps

---

## Design Reference Summary

From [phase-02-qdisc.md](./phase-02-qdisc.md):

- **Qdiscs**: fq_codel (baseline), cake (single-queue), mq-cake (multi-queue)
- **CAKE Options**: bandwidth, diffserv4, nat, wash, split-gso
- **Bandwidth**: Default 10gbit, configurable via MQ_CAKE_BANDWIDTH
- **Target Interfaces**: enp66s0f0 (DUT ingress), enp66s0f1 (DUT egress)

---

## Next Phase

Proceed to [Phase 3: Load Generation](./phase-03-loadgen_plan.md) once all checks pass.
