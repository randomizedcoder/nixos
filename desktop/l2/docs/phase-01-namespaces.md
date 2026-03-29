# Phase 1: Namespace Setup

**Goal**: Create isolated test environment with IP forwarding through the DUT.

**Outcome**: `mq-cake-setup` creates the environment; `mq-cake-teardown` removes it; `mq-cake-verify` confirms connectivity.

---

## Scripts Overview

| Script | Purpose |
|--------|---------|
| `mq-cake-setup` | Create namespaces, move interfaces, configure IPs, enable forwarding |
| `mq-cake-teardown` | Remove namespaces, restore interfaces to default namespace |
| `mq-cake-verify` | Test end-to-end connectivity (ping from each namespace to all others) |

---

## Network Topology

```
ns-gen-a (10.1.0.2)                              ns-dut (forwarding)
  X710 p0 ──────────── cable ────────────────▶ 82599ES p0 (10.1.0.1)
                                                        │
                                                        │ ip_forward=1
                                                        │
  X710 p1 ◀──────────── cable ─────────────── 82599ES p1 (10.2.0.1)
ns-gen-b (10.2.0.2)
```

---

## Nix Module

```nix
# mq-cake-test.nix
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.mq-cake-test;

  # Interface configuration
  x710_p0 = "enp35s0f0np0";
  x710_p1 = "enp35s0f1np1";
  ixgbe_p0 = "enp66s0f0";
  ixgbe_p1 = "enp66s0f1";

  # mq-cake-setup: Create namespaces and configure networking
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

      # Configure ns-gen-a
      echo "Configuring ns-gen-a..."
      ip netns exec ns-gen-a bash -c "
        ip link set lo up
        ip link set ${x710_p0} up
        ip addr flush dev ${x710_p0}
        ip addr add 10.1.0.2/24 dev ${x710_p0}
        ip route add default via 10.1.0.1
      "

      # Configure ns-gen-b
      echo "Configuring ns-gen-b..."
      ip netns exec ns-gen-b bash -c "
        ip link set lo up
        ip link set ${x710_p1} up
        ip addr flush dev ${x710_p1}
        ip addr add 10.2.0.2/24 dev ${x710_p1}
        ip route add default via 10.2.0.1
      "

      # Configure ns-dut
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

  # mq-cake-teardown: Remove namespaces and restore interfaces
  teardownScript = pkgs.writeShellApplication {
    name = "mq-cake-teardown";
    runtimeInputs = with pkgs; [ iproute2 ];
    text = ''
      set -euo pipefail

      echo "=== MQ-CAKE Test Environment Teardown ==="

      # Move interfaces back to default namespace
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

  # mq-cake-verify: Test connectivity
  verifyScript = pkgs.writeShellApplication {
    name = "mq-cake-verify";
    runtimeInputs = with pkgs; [ iproute2 iputils ];
    text = ''
      set -euo pipefail

      RED='\033[0;31m'
      GREEN='\033[0;32m'
      NC='\033[0m'

      pass() { echo -e "''${GREEN}PASS''${NC}"; }
      fail() { echo -e "''${RED}FAIL''${NC}"; exit 1; }

      echo "=== MQ-CAKE Environment Verification ==="
      echo ""

      echo -n "1. Namespaces exist (3): "
      [[ $(ip netns list | wc -l) -eq 3 ]] && pass || fail

      echo -n "2. ns-gen-a has interface: "
      ip netns exec ns-gen-a ip link show ${x710_p0} &>/dev/null && pass || fail

      echo -n "3. ns-gen-b has interface: "
      ip netns exec ns-gen-b ip link show ${x710_p1} &>/dev/null && pass || fail

      echo -n "4. ns-dut has both interfaces: "
      ip netns exec ns-dut ip link show ${ixgbe_p0} &>/dev/null && \
      ip netns exec ns-dut ip link show ${ixgbe_p1} &>/dev/null && pass || fail

      echo -n "5. DUT forwarding enabled: "
      [[ $(ip netns exec ns-dut sysctl -n net.ipv4.ip_forward) -eq 1 ]] && pass || fail

      echo -n "6. ns-gen-a -> DUT (10.1.0.1): "
      ip netns exec ns-gen-a ping -c 1 -W 2 10.1.0.1 &>/dev/null && pass || fail

      echo -n "7. ns-gen-b -> DUT (10.2.0.1): "
      ip netns exec ns-gen-b ping -c 1 -W 2 10.2.0.1 &>/dev/null && pass || fail

      echo -n "8. End-to-end A->B (10.2.0.2): "
      ip netns exec ns-gen-a ping -c 1 -W 2 10.2.0.2 &>/dev/null && pass || fail

      echo -n "9. End-to-end B->A (10.1.0.2): "
      ip netns exec ns-gen-b ping -c 1 -W 2 10.1.0.2 &>/dev/null && pass || fail

      echo ""
      echo "=== All Checks Passed ==="
    '';
  };

in
{
  options.services.mq-cake-test = {
    enable = mkEnableOption "MQ-CAKE test environment scripts";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      setupScript
      teardownScript
      verifyScript
    ];

    # Ensure kernel modules are loaded
    boot.kernelModules = [ "sch_cake" "sch_fq_codel" ];
  };
}
```

---

## Usage

```bash
# Enable in NixOS configuration
services.mq-cake-test.enable = true;

# Rebuild
sudo nixos-rebuild switch

# Create test environment
sudo mq-cake-setup

# Verify connectivity
sudo mq-cake-verify

# When done
sudo mq-cake-teardown
```

---

## Verification Checklist

| Check | Command | Expected |
|-------|---------|----------|
| Namespaces exist | `ip netns list` | 3 namespaces |
| Interfaces in DUT | `ip netns exec ns-dut ip link` | 2 interfaces up |
| IP forwarding | `ip netns exec ns-dut sysctl net.ipv4.ip_forward` | 1 |
| End-to-end ping | `ip netns exec ns-gen-a ping 10.2.0.2` | Success |

---

## Troubleshooting

### "Cannot find device" when moving interface

Interface may already be in a namespace. Check:
```bash
ip netns exec ns-gen-a ip link show
```

### Ping fails between generators

1. Check DUT forwarding: `ip netns exec ns-dut sysctl net.ipv4.ip_forward`
2. Check routes: `ip netns exec ns-gen-a ip route show`
3. Check ARP: `ip netns exec ns-gen-a ip neigh show`

### Interface not coming up

Check cable connection and link status:
```bash
ip netns exec ns-dut ethtool enp66s0f0 | grep "Link detected"
```

---

## Next Phase

Once `mq-cake-verify` passes, proceed to [Phase 2: Qdisc Configuration](./phase-02-qdisc.md).
