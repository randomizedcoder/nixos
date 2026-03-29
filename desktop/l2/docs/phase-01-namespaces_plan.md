# Phase 1: Namespace Setup - Implementation Plan

**Design Reference**: [phase-01-namespaces.md](./phase-01-namespaces.md)

**Overview**: Create isolated network namespaces for testing MQ-CAKE qdisc performance.

**Log File**: [phase-01-namespaces_log.md](./phase-01-namespaces_log.md) (update on completion of each sub-phase)

---

## Sub-Phase 1.1: Create Nix Module Skeleton

### Steps

1. **Create file** `mq-cake-test.nix` in repository root:
   ```
   /home/das/nixos/desktop/l2/mq-cake-test.nix
   ```

2. **Add module structure**:
   ```nix
   { config, lib, pkgs, ... }:

   with lib;

   let
     cfg = config.services.mq-cake-test;
   in
   {
     options.services.mq-cake-test = {
       enable = mkEnableOption "MQ-CAKE test environment scripts";
     };

     config = mkIf cfg.enable {
       environment.systemPackages = [ ];
       boot.kernelModules = [ "sch_cake" "sch_fq_codel" ];
     };
   }
   ```

3. **Import module** in `configuration.nix`:
   ```nix
   imports = [
     ./mq-cake-test.nix
   ];
   ```

4. **Enable service** in `configuration.nix`:
   ```nix
   services.mq-cake-test.enable = true;
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 1.1.1 | `nix-instantiate --parse mq-cake-test.nix` | No syntax errors |
| 1.1.2 | `sudo nixos-rebuild dry-build` | Build succeeds |
| 1.1.3 | `lsmod \| grep sch_cake` | Module present after rebuild switch |

### Definition of Done

- [ ] `mq-cake-test.nix` exists and parses without errors
- [ ] Module imported in `configuration.nix`
- [ ] `services.mq-cake-test.enable = true` set
- [ ] `nixos-rebuild dry-build` succeeds
- [ ] Log file updated with completion timestamp

---

## Sub-Phase 1.2: Define Interface Constants

### Steps

1. **Add let bindings** to `mq-cake-test.nix` (inside `let` block):
   ```nix
   # X710 interfaces (load generators)
   x710_p0 = "enp35s0f0np0";  # ns-gen-a (client)
   x710_p1 = "enp35s0f1np1";  # ns-gen-b (server)

   # 82599ES interfaces (DUT)
   ixgbe_p0 = "enp66s0f0";    # DUT ingress
   ixgbe_p1 = "enp66s0f1";    # DUT egress
   ```

2. **Verify interface names exist** on system:
   ```bash
   ip link show enp35s0f0np0
   ip link show enp35s0f1np1
   ip link show enp66s0f0
   ip link show enp66s0f1
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 1.2.1 | `ip link show enp35s0f0np0` | Interface exists |
| 1.2.2 | `ip link show enp35s0f1np1` | Interface exists |
| 1.2.3 | `ip link show enp66s0f0` | Interface exists |
| 1.2.4 | `ip link show enp66s0f1` | Interface exists |
| 1.2.5 | `nix-instantiate --parse mq-cake-test.nix` | No syntax errors |

### Definition of Done

- [ ] All four interface constants defined
- [ ] All four interfaces verified to exist on system
- [ ] Module still parses correctly
- [ ] Log file updated

---

## Sub-Phase 1.3: Implement `mq-cake-setup` Script

### Steps

1. **Add `setupScript`** to `mq-cake-test.nix` let block:
   ```nix
   setupScript = pkgs.writeShellApplication {
     name = "mq-cake-setup";
     runtimeInputs = with pkgs; [ iproute2 procps ];
     text = ''
       set -euo pipefail

       echo "=== MQ-CAKE Test Environment Setup ==="

       # Create namespaces
       echo "Creating namespaces..."
       ip netns add ns-gen-a 2>/dev/null || true
       ip netns add ns-gen-b 2>/dev/null || true
       ip netns add ns-dut 2>/dev/null || true

       # Move interfaces to namespaces
       echo "Moving interfaces..."
       ip link set ${x710_p0} netns ns-gen-a 2>/dev/null || true
       ip link set ${x710_p1} netns ns-gen-b 2>/dev/null || true
       ip link set ${ixgbe_p0} netns ns-dut 2>/dev/null || true
       ip link set ${ixgbe_p1} netns ns-dut 2>/dev/null || true

       # Configure ns-gen-a (client)
       echo "Configuring ns-gen-a..."
       ip netns exec ns-gen-a bash -c "
         ip link set lo up
         ip link set ${x710_p0} up
         ip addr flush dev ${x710_p0}
         ip addr add 10.1.0.2/24 dev ${x710_p0}
         ip route add default via 10.1.0.1
       "

       # Configure ns-gen-b (server)
       echo "Configuring ns-gen-b..."
       ip netns exec ns-gen-b bash -c "
         ip link set lo up
         ip link set ${x710_p1} up
         ip addr flush dev ${x710_p1}
         ip addr add 10.2.0.2/24 dev ${x710_p1}
         ip route add default via 10.2.0.1
       "

       # Configure ns-dut (forwarding router)
       echo "Configuring ns-dut..."
       ip netns exec ns-dut bash -c "
         ip link set lo up
         ip link set ${ixgbe_p0} up
         ip link set ${ixgbe_p1} up
         ip addr flush dev ${ixgbe_p0}
         ip addr flush dev ${ixgbe_p1}
         ip addr add 10.1.0.1/24 dev ${ixgbe_p0}
         ip addr add 10.2.0.1/24 dev ${ixgbe_p1}
         sysctl -qw net.ipv4.ip_forward=1
       "

       echo ""
       echo "=== Setup Complete ==="
       echo "  ns-gen-a: 10.1.0.2/24 (client)"
       echo "  ns-gen-b: 10.2.0.2/24 (server)"
       echo "  ns-dut:   10.1.0.1/24, 10.2.0.1/24 (forwarding)"
       echo ""
       echo "Verify with: sudo mq-cake-verify"
     '';
   };
   ```

2. **Add to systemPackages**:
   ```nix
   config = mkIf cfg.enable {
     environment.systemPackages = [ setupScript ];
     # ...
   };
   ```

3. **Rebuild and test**:
   ```bash
   sudo nixos-rebuild switch
   sudo mq-cake-setup
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 1.3.1 | `which mq-cake-setup` | Path returned |
| 1.3.2 | `sudo mq-cake-setup` | Exits 0, prints "Setup Complete" |
| 1.3.3 | `ip netns list` | Shows ns-gen-a, ns-gen-b, ns-dut |
| 1.3.4 | `ip netns exec ns-gen-a ip addr show` | Shows 10.1.0.2/24 |
| 1.3.5 | `ip netns exec ns-gen-b ip addr show` | Shows 10.2.0.2/24 |
| 1.3.6 | `ip netns exec ns-dut ip addr show` | Shows 10.1.0.1/24 and 10.2.0.1/24 |
| 1.3.7 | `ip netns exec ns-dut sysctl net.ipv4.ip_forward` | Returns 1 |

### Definition of Done

- [ ] `mq-cake-setup` command available after rebuild
- [ ] Running setup creates 3 namespaces
- [ ] Interfaces moved to correct namespaces
- [ ] IP addresses assigned correctly
- [ ] IP forwarding enabled in ns-dut
- [ ] Log file updated

---

## Sub-Phase 1.4: Implement `mq-cake-teardown` Script

### Steps

1. **Add `teardownScript`** to `mq-cake-test.nix` let block:
   ```nix
   teardownScript = pkgs.writeShellApplication {
     name = "mq-cake-teardown";
     runtimeInputs = with pkgs; [ iproute2 ];
     text = ''
       set -euo pipefail

       echo "=== MQ-CAKE Test Environment Teardown ==="

       # Move interfaces back to default namespace (PID 1)
       echo "Restoring interfaces..."
       ip netns exec ns-gen-a ip link set ${x710_p0} netns 1 2>/dev/null || true
       ip netns exec ns-gen-b ip link set ${x710_p1} netns 1 2>/dev/null || true
       ip netns exec ns-dut ip link set ${ixgbe_p0} netns 1 2>/dev/null || true
       ip netns exec ns-dut ip link set ${ixgbe_p1} netns 1 2>/dev/null || true

       # Delete namespaces
       echo "Deleting namespaces..."
       ip netns delete ns-gen-a 2>/dev/null || true
       ip netns delete ns-gen-b 2>/dev/null || true
       ip netns delete ns-dut 2>/dev/null || true

       # Bring interfaces back up in default namespace
       ip link set ${x710_p0} up 2>/dev/null || true
       ip link set ${x710_p1} up 2>/dev/null || true
       ip link set ${ixgbe_p0} up 2>/dev/null || true
       ip link set ${ixgbe_p1} up 2>/dev/null || true

       echo "Teardown complete."
     '';
   };
   ```

2. **Add to systemPackages**:
   ```nix
   environment.systemPackages = [ setupScript teardownScript ];
   ```

3. **Test teardown cycle**:
   ```bash
   sudo nixos-rebuild switch
   sudo mq-cake-setup
   ip netns list  # Should show 3 namespaces
   sudo mq-cake-teardown
   ip netns list  # Should be empty
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 1.4.1 | `which mq-cake-teardown` | Path returned |
| 1.4.2 | `sudo mq-cake-setup && sudo mq-cake-teardown` | Both exit 0 |
| 1.4.3 | `ip netns list` (after teardown) | Empty or no namespaces |
| 1.4.4 | `ip link show enp35s0f0np0` (after teardown) | Interface in default namespace |
| 1.4.5 | `ip link show enp66s0f0` (after teardown) | Interface in default namespace |

### Definition of Done

- [ ] `mq-cake-teardown` command available after rebuild
- [ ] Teardown removes all 3 namespaces
- [ ] Interfaces returned to default namespace
- [ ] Interfaces brought back up
- [ ] Idempotent (can run multiple times without error)
- [ ] Log file updated

---

## Sub-Phase 1.5: Implement `mq-cake-verify` Script

### Steps

1. **Add `verifyScript`** to `mq-cake-test.nix` let block:
   ```nix
   verifyScript = pkgs.writeShellApplication {
     name = "mq-cake-verify";
     runtimeInputs = with pkgs; [ iproute2 iputils ];
     text = ''
       set -euo pipefail

       RED='\033[0;31m'
       GREEN='\033[0;32m'
       NC='\033[0m'

       FAILED=0

       pass() { echo -e "''${GREEN}PASS''${NC}"; }
       fail() { echo -e "''${RED}FAIL''${NC}"; FAILED=1; }

       echo "=== MQ-CAKE Environment Verification ==="
       echo ""

       echo -n "1. Namespaces exist (3): "
       [[ $(ip netns list | wc -l) -eq 3 ]] && pass || fail

       echo -n "2. ns-gen-a has ${x710_p0}: "
       ip netns exec ns-gen-a ip link show ${x710_p0} &>/dev/null && pass || fail

       echo -n "3. ns-gen-b has ${x710_p1}: "
       ip netns exec ns-gen-b ip link show ${x710_p1} &>/dev/null && pass || fail

       echo -n "4. ns-dut has ${ixgbe_p0}: "
       ip netns exec ns-dut ip link show ${ixgbe_p0} &>/dev/null && pass || fail

       echo -n "5. ns-dut has ${ixgbe_p1}: "
       ip netns exec ns-dut ip link show ${ixgbe_p1} &>/dev/null && pass || fail

       echo -n "6. DUT forwarding enabled: "
       [[ $(ip netns exec ns-dut sysctl -n net.ipv4.ip_forward) -eq 1 ]] && pass || fail

       echo -n "7. ns-gen-a -> DUT (10.1.0.1): "
       ip netns exec ns-gen-a ping -c 1 -W 2 10.1.0.1 &>/dev/null && pass || fail

       echo -n "8. ns-gen-b -> DUT (10.2.0.1): "
       ip netns exec ns-gen-b ping -c 1 -W 2 10.2.0.1 &>/dev/null && pass || fail

       echo -n "9. End-to-end A->B (10.2.0.2): "
       ip netns exec ns-gen-a ping -c 1 -W 2 10.2.0.2 &>/dev/null && pass || fail

       echo -n "10. End-to-end B->A (10.1.0.2): "
       ip netns exec ns-gen-b ping -c 1 -W 2 10.1.0.2 &>/dev/null && pass || fail

       echo ""
       if [[ $FAILED -eq 0 ]]; then
         echo "=== All Checks Passed ==="
         exit 0
       else
         echo "=== Some Checks Failed ==="
         exit 1
       fi
     '';
   };
   ```

2. **Add to systemPackages**:
   ```nix
   environment.systemPackages = [ setupScript teardownScript verifyScript ];
   ```

3. **Full verification test**:
   ```bash
   sudo nixos-rebuild switch
   sudo mq-cake-teardown  # Clean slate
   sudo mq-cake-setup
   sudo mq-cake-verify
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 1.5.1 | `which mq-cake-verify` | Path returned |
| 1.5.2 | `sudo mq-cake-setup && sudo mq-cake-verify` | Exit 0, "All Checks Passed" |
| 1.5.3 | `sudo mq-cake-teardown && sudo mq-cake-verify` | Exit 1 (expected failure) |
| 1.5.4 | Run verify with cable unplugged | Ping checks fail, others pass |

### Definition of Done

- [ ] `mq-cake-verify` command available after rebuild
- [ ] Verify checks all 10 conditions
- [ ] Returns exit 0 on success, exit 1 on failure
- [ ] Color output works (PASS=green, FAIL=red)
- [ ] Full cycle works: teardown → setup → verify passes
- [ ] Log file updated

---

## Sub-Phase 1.6: Add Kernel Module Configuration

### Steps

1. **Ensure kernel modules load** in `mq-cake-test.nix`:
   ```nix
   config = mkIf cfg.enable {
     environment.systemPackages = [ setupScript teardownScript verifyScript ];

     boot.kernelModules = [
       "sch_cake"      # CAKE qdisc
       "sch_fq_codel"  # FQ-CoDel qdisc
       # sch_cake_mq is not yet mainline - Phase 2 will address
     ];
   };
   ```

2. **Rebuild and verify modules**:
   ```bash
   sudo nixos-rebuild switch
   lsmod | grep sch_cake
   lsmod | grep sch_fq_codel
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 1.6.1 | `lsmod \| grep sch_cake` | Module loaded |
| 1.6.2 | `lsmod \| grep sch_fq_codel` | Module loaded |
| 1.6.3 | `modinfo sch_cake` | Module info displayed |

### Definition of Done

- [ ] `sch_cake` module loads at boot
- [ ] `sch_fq_codel` module loads at boot
- [ ] `modinfo` returns valid info for both
- [ ] Log file updated

---

## Sub-Phase 1.7: Integration Test

### Steps

1. **Clean environment**:
   ```bash
   sudo mq-cake-teardown
   ```

2. **Full setup**:
   ```bash
   sudo mq-cake-setup
   ```

3. **Verify all checks pass**:
   ```bash
   sudo mq-cake-verify
   ```

4. **Test ping throughput**:
   ```bash
   ip netns exec ns-gen-a ping -c 100 -i 0.01 10.2.0.2
   ```

5. **Check for packet loss**:
   ```bash
   # Should show 0% packet loss
   ```

6. **Test bidirectional**:
   ```bash
   ip netns exec ns-gen-b ping -c 100 -i 0.01 10.1.0.2
   ```

7. **Clean teardown**:
   ```bash
   sudo mq-cake-teardown
   ```

8. **Verify clean state**:
   ```bash
   ip netns list  # Should be empty
   ip link show   # All 4 interfaces in default namespace
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 1.7.1 | `sudo mq-cake-verify` | Exit 0 |
| 1.7.2 | `ip netns exec ns-gen-a ping -c 100 -i 0.01 10.2.0.2` | 0% loss |
| 1.7.3 | `ip netns exec ns-gen-b ping -c 100 -i 0.01 10.1.0.2` | 0% loss |
| 1.7.4 | `ip netns exec ns-gen-a ping -c 1 10.2.0.2 \| grep time=` | RTT < 1ms |
| 1.7.5 | Cycle: teardown → setup → verify → teardown | All succeed |

### Definition of Done

- [ ] Full setup/verify/teardown cycle works
- [ ] End-to-end ping with 0% packet loss
- [ ] Baseline RTT < 1ms (physical cable connection)
- [ ] Bidirectional traffic works
- [ ] Clean teardown leaves no leftover state
- [ ] Log file updated with final status

---

## Phase 1 Complete Checklist

Before proceeding to Phase 2, verify:

- [ ] `mq-cake-test.nix` module complete and imported
- [ ] `mq-cake-setup` creates 3 namespaces with correct IPs
- [ ] `mq-cake-teardown` cleanly removes all state
- [ ] `mq-cake-verify` passes all 10 checks
- [ ] Kernel modules `sch_cake` and `sch_fq_codel` loaded
- [ ] End-to-end ping works A→B and B→A
- [ ] RTT baseline < 1ms
- [ ] 0% packet loss on 100-packet ping test
- [ ] Log file complete with all sub-phase timestamps

---

## Design Reference Summary

From [phase-01-namespaces.md](./phase-01-namespaces.md):

- **Topology**: ns-gen-a (client) ↔ ns-dut (router) ↔ ns-gen-b (server)
- **IP Scheme**: 10.1.0.0/24 (A-side), 10.2.0.0/24 (B-side)
- **Traffic Flow**: 10.1.0.2 → 10.1.0.1 (DUT) → 10.2.0.1 → 10.2.0.2
- **Hardware**: X710 (generators), 82599ES (DUT)

---

## Next Phase

Proceed to [Phase 2: Qdisc Configuration](./phase-02-qdisc_plan.md) once all checks pass.
