# Phase 2: Qdisc Configuration

**Goal**: Flexibly configure qdiscs on the DUT interfaces.

**Prerequisites**: [Phase 1](./phase-01-namespaces.md) complete (end-to-end ping works).

**Outcome**: `mq-cake-qdisc <qdisc>` switches qdisc on both DUT interfaces.

---

## Supported Qdiscs

| Qdisc | Description | Use Case |
|-------|-------------|----------|
| `fq_codel` | Fair Queuing + CoDel AQM (modern default) | Baseline comparison |
| `cake` | Single-queue CAKE | Excellent fairness, may bottleneck at scale |
| `mq-cake` | Multi-queue CAKE | Scales across CPU cores (what we're testing) |

---

## Nix Script

```nix
# Add to mq-cake-test.nix
let
  ixgbe_p0 = "enp66s0f0";
  ixgbe_p1 = "enp66s0f1";

  qdiscScript = pkgs.writeShellApplication {
    name = "mq-cake-qdisc";
    runtimeInputs = with pkgs; [ iproute2 ];
    text = ''
      set -euo pipefail

      QDISC=''${1:-fq_codel}
      BANDWIDTH=''${MQ_CAKE_BANDWIDTH:-10gbit}

      echo "Configuring qdisc: $QDISC (bandwidth: $BANDWIDTH)"

      for iface in ${ixgbe_p0} ${ixgbe_p1}; do
        case "$QDISC" in
          fq_codel)
            ip netns exec ns-dut tc qdisc replace dev "$iface" root fq_codel
            ;;
          cake)
            ip netns exec ns-dut tc qdisc replace dev "$iface" root cake \
              bandwidth "$BANDWIDTH" diffserv4 nat wash split-gso
            ;;
          mq-cake|cake_mq)
            ip netns exec ns-dut tc qdisc replace dev "$iface" root cake_mq \
              bandwidth "$BANDWIDTH" diffserv4 nat wash split-gso
            ;;
          *)
            echo "Unknown qdisc: $QDISC"
            echo "Supported: fq_codel, cake, mq-cake"
            exit 1
            ;;
        esac
        echo "  $iface: $QDISC"
      done

      echo ""
      echo "Current qdisc:"
      ip netns exec ns-dut tc qdisc show dev ${ixgbe_p0} | head -1
    '';
  };
in
{
  environment.systemPackages = [ qdiscScript ];
}
```

---

## Usage

```bash
# Switch to fq_codel (baseline)
sudo mq-cake-qdisc fq_codel

# Switch to single-queue CAKE
sudo mq-cake-qdisc cake

# Switch to multi-queue CAKE (what we're testing)
sudo mq-cake-qdisc mq-cake

# Override bandwidth (default: 10gbit)
MQ_CAKE_BANDWIDTH=1gbit sudo mq-cake-qdisc cake
```

---

## Verify Qdisc Applied

```bash
# Show current qdisc on both interfaces
ip netns exec ns-dut tc qdisc show dev enp66s0f0
ip netns exec ns-dut tc qdisc show dev enp66s0f1
```

**Example output (CAKE)**:
```
qdisc cake 8003: root refcnt 2 bandwidth 10Gbit diffserv4 triple-isolate nat wash split-gso rtt 100ms
```

---

## View Qdisc Statistics

```bash
# Detailed stats including drops
ip netns exec ns-dut tc -s qdisc show dev enp66s0f0
```

**Example output**:
```
qdisc cake 8003: root refcnt 2 bandwidth 10Gbit diffserv4 ...
 Sent 12345 bytes 100 pkt (dropped 0, overlimits 0 requeues 0)
 backlog 0b 0p requeues 0
 memory used: 0b of 4Mb
 capacity estimate: 10Gbit
```

---

## CAKE Options Explained

| Option | Purpose |
|--------|---------|
| `bandwidth 10gbit` | Rate limit (required) |
| `diffserv4` | 4-tier DSCP classification (Bulk, Best Effort, Video, Voice) |
| `nat` | NAT-aware flow hashing |
| `wash` | Clear DSCP marks on egress |
| `split-gso` | Split GSO/TSO packets for better per-flow fairness |

---

## Troubleshooting

### "RTNETLINK answers: No such file or directory"

The qdisc module isn't loaded:
```bash
modprobe sch_cake
# For mq-cake (if built as module):
modprobe sch_cake_mq
```

### "RTNETLINK answers: Invalid argument"

Invalid qdisc parameters. Check:
- Bandwidth format: `10gbit`, `1gbit`, `100mbit`
- Option spelling: `diffserv4` not `diffserve4`

### Verify mq-cake is available

```bash
# Check if cake_mq qdisc exists
ip netns exec ns-dut tc qdisc replace dev enp66s0f0 root cake_mq bandwidth 10gbit 2>&1
# If it fails with "Unknown qdisc", mq-cake is not in your kernel
```

---

## Next Phase

Once you can switch qdiscs without breaking connectivity, proceed to [Phase 3: Load Generation](./phase-03-loadgen.md).
