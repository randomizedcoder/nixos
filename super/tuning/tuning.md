# super-X CPU / NUMA / NIC / IRQ tuning

> Adapted from the GPU-affine pinning exercise in `~/Downloads/hosts.md`. These nodes have
> **no GPUs**; instead the scarce, latency-critical devices are the **data NIC**, the
> **MegaRAID storage controller**, and the **NVMe ZFS SLOG/L2ARC**. Goal: dedicate cores so
> a Kubernetes cluster running **database-style, p99-sensitive** workloads gets clean,
> NUMA-local cores while host/IRQ/ZFS work is corralled onto a reserved pool.
>
> Data captured read-only under `captures/<host>/` (see `captures/SUMMARY.tsv`).
> This doc **proposes**; it configures nothing until the NixOS section is applied.

## 1. What the hardware is

All three booted nodes (`super-a`, `super-b`, `super-d`) are Supermicro `SYS-2028TP-HC1TR`
sleds. CPU / NUMA / NIC are **identical**; storage differs (see §7). `super-c` is down
(disk fault, on-site) and folds in when it boots.

**CPU / cache** (per node)

- 2× Intel Xeon **E5-2680 v4** (Broadwell-EP), 14 cores / 28 threads per socket →
  **56 logical CPUs, 2 sockets, 2 NUMA nodes**. Base 2.4 GHz, turbo 3.3 GHz.
- Cache: L1d/L1i 32 KB per core · L2 256 KB per core · **L3 35 MB per socket** (20-way).

**NUMA**

| Node | Socket | Logical CPUs | Phys cores | Memory (super-a) |
|---|---|---|---|---|
| 0 | 0 | `0-13,28-41` | 14 | ~128 GB |
| 1 | 1 | `14-27,42-55` | 14 | ~128 GB |

- **Hyperthread siblings pair `k` ↔ `k+28`** (e.g. CPU 6 and CPU 34 are one physical core).
  Every core reservation below takes **both** siblings (whole-core model — a physical core is
  never split between a workload and an IRQ handler).
- NUMA distance 10 (local) / 21 (remote) — a remote-node access costs ≈ 2.1×.
- Memory is **balanced across both nodes** on every host, but capacity/speed differ:
  **super-a 256 GB @ 1866 MT/s** (16×16 GiB, 2DPC), **super-b/d 128 GB @ 2133 MT/s**
  (8×16 GiB, 1DPC, 8 slots free) — see §10. All Samsung DDR4 ECC RDIMM, same part.

**Device → NUMA attachment** (the whole design pivots on this)

| Device | Driver | BDF (a) | NUMA | PCIe link | Notes |
|---|---|---|---|---|---|
| MegaRAID SAS-3 3108 | `megaraid_sas` | `01:00.0` | **0** | 8.0 GT/s ×4 (max ×8) | pool/DB storage |
| Intel X540-AT2 ×2 10GbE | `ixgbe` | `04:00.0/.1` | **0** | 5.0 GT/s ×8 (Gen2, full) | `eno1`+`eno2` bond |
| Samsung NVMe | `nvme` | `81:00.0` | **1** | 8.0 GT/s ×4 | **ZFS SLOG + L2ARC** |

→ **The data NIC and the primary storage controller are both on NUMA 0; the NVMe SLOG/L2ARC
is on NUMA 1.** So host + all storage/network IRQ work concentrates on node 0, with a small
node-1 reservation for the NVMe.

## 2. The core budget

Reserve whole cores in this order (all on the device's own NUMA node):

| Role | Phys cores | Logical CPUs | NUMA | Why |
|---|---|---|---|---|
| Housekeeping (bird, lldpd, sshd, kubelet, runtime, + ZFS ZIO/ARC kthreads) | 2 | `0-1,28-29` | 0 | keep system off the workload cores |
| **NIC IRQ** (bond `eno1`+`eno2`) | 4 | `2-5,30-33` | 0 | 8 ixgbe combined queues, explicitly pinned |
| **MegaRAID IRQ** (managed) | 2 | `6-7,34-35` | 0 | storage completions for DB p99 |
| K8s workload — RAID/NUMA0-local (DB pods) | 6 | `8-13,36-41` | 0 | isolated |
| K8s workload — NUMA1-local / general | 12 | `14-25,42-53` | 1 | isolated |
| **NVMe / ZFS SLOG+L2ARC IRQ** (managed) | 2 | `26-27,54-55` | 1 | sync-write latency path |
| **total** | **28** | `0-55` | | 10 reserved + 18 K8s |

- **Reserved pool** (schedulable; hosts system + all IRQ + ZFS threads) =
  **10 phys cores** = `0-7,26-35,54-55`.
- **Isolated K8s pool** (exclusive, pinned pods) = **18 phys cores** = `8-25,36-53`.

`hosts.md` sizes NIC IRQ cores from link speed (10GbE → 2 combined/NIC). We deliberately go
**wider — 4 combined per NIC (8 total)** — to honor the "4 rx + 4 tx" ask and give the bonded
2×10G headroom. (ixgbe exposes **combined** channels only — each is one rx+tx queue pair on
one IRQ — so "4 rx + 4 tx" maps to 8 combined queues, one IRQ per hyperthread across the 4
NIC-IRQ cores.)

## 3. Managed vs. unmanaged IRQs — the key constraint

The capture (`captures/super-a/irq-affinity.txt`) shows two different IRQ regimes:

- **`ixgbe` (`eno1-TxRx-N`)** carry a **wide affinity *hint*** (`0-13,28-41`) — these are
  **unmanaged**; their `/proc/irq/<n>/smp_affinity_list` is **writable**, so we pin them.
- **`megaraid_sas` (`megasas0-msixN`) and `nvme` (`nvme0qN`)** are **kernel-*managed*** MSI-X
  vectors — blk-mq maps them 1:1 across CPUs at allocation (msix1→CPU14, msix2→CPU15 …, many
  landing on **NUMA 1**, cross-node from the NUMA-0 controller). **Managed-IRQ affinity cannot
  be changed at runtime** — writing `smp_affinity_list` is rejected.

Therefore:

- **NIC IRQs** → pin explicitly onto `2-5,30-33` (works; unmanaged).
- **MegaRAID + NVMe IRQs** → cannot be hand-pinned. Instead use **`isolcpus=managed_irq,…`**
  so the kernel keeps *managed* IRQs **off the isolated workload cores** and steers them onto
  the reserved pool. Their nominal homes (`6-7,34-35` / `26-27,54-55`) are the intended
  landing zone inside that pool, not a hard pin.

This is the important adaptation over `hosts.md` (whose NICs were unmanaged and hand-pinned).

## 4. NIC tuning (ixgbe X540, `eno1`+`eno2`)

Today: `combined = 56` (one queue/CPU → IRQs smeared across the whole socket), rings
**512** of **8192** max.

```sh
# Shrink to 4 combined queues per slave (8 total for the bond).
ethtool -L eno1 combined 4
ethtool -L eno2 combined 4

# Rings: raise off 512 but stay MODERATE for p99 (not the 8192 max) — start at 2048,
# raise toward 4096 only if `ethtool -S | grep rx_.*drop` shows drops under burst.
ethtool -G eno1 rx 2048 tx 2048
ethtool -G eno2 rx 2048 tx 2048

# Pin the (now 8) unmanaged ixgbe IRQs onto the NIC-IRQ cores 2-5,30-33.
for i in eno1 eno2; do
  for irq in $(awk -v d="$i" '$0 ~ d {sub(/:/,"",$1); print $1}' /proc/interrupts); do
    echo 2-5,30-33 > /proc/irq/$irq/smp_affinity_list
  done
done
```

> **Bounce warning:** `ethtool -L` resets the NIC → the bond slave flaps → **BGP briefly
> drops** (same class as the MTU change). Do it at boot / in a maintenance window; it
> self-heals via BGP graceful-restart (hold 9 / keepalive 3). Applying via the `.link` file
> (§8) makes it happen once at device creation, avoiding a separate runtime bounce.

## 5. MegaRAID + NVMe (managed IRQs)

No runtime pin. Confinement is via `isolcpus=managed_irq` (§6): the ~57 `megaraid_sas` and
~17 `nvme` managed vectors are kept off `8-25,36-53` and land on the reserved pool. Optional
extra: reduce `megaraid_sas` MSI-X (`megaraid_sas.msix_vectors=<n>`) so the managed spread
maps onto fewer cores — measure first; the default is usually fine once `managed_irq` is set.

## 6. Kernel cmdline (reboot)

```
isolcpus=managed_irq,domain,8-25,36-53 nohz_full=8-25,36-53 rcu_nocbs=8-25,36-53
```

- `domain` — keep the scheduler from placing other tasks on the workload cores.
- `managed_irq` — keep **managed** storage IRQs (megaraid/nvme) off them too (§3).
- `nohz_full` + `rcu_nocbs` — stop the periodic tick and offload RCU callbacks → removes
  kernel jitter from the pinned DB cores. (Reserved cores `0-7,26-35,54-55` stay full-service
  so ksoftirqd, RCU, and ZFS threads have a home.)
- Optional DB hugepages (workload-dependent): `default_hugepagesz=2M hugepagesz=2M
  hugepages=N` — size N to the DB's shared-buffers, and prefer per-NUMA allocation.

## 7. ZFS resource sizing (SLOG + L2ARC)

The NVMe is the **ZFS ZIL/SLOG (sync-write buffer) + L2ARC (read cache)** in front of the
MegaRAID pool. Implications for this tuning:

- **ZIO/ARC are kernel threads, not pods** — they can't take a cpuset, and `isolcpus` removes
  the isolated cores from their scheduler domain, so they run on the **reserved pool**
  (`0-7,26-35,54-55`, 10 cores). That pool is sized generously precisely so ZIO
  checksum/compression + ARC eviction have room alongside the IRQ handlers.
- **Cap `zfs_arc_max`** so ARC can't starve the DB / K8s pods of RAM — acute on **super-b/d
  at 128 GB** (half of super-a). Pick a hard cap (e.g. 32–48 GB) sized against the DB working
  set; don't leave ARC at the 50%-of-RAM default.
- **Cross-NUMA stack:** pool disks (MegaRAID) are on **node 0**, SLOG/L2ARC (NVMe) on
  **node 1** — the ZFS I/O path straddles both sockets. Unavoidable given the slotting; the
  reserved pool spans both nodes so the completion IRQs stay node-local on each side.
- **Consumer SLOG risk:** the NVMes are **990 EVO Plus / 980 (super-b) — no power-loss
  protection**. A SLOG holds un-flushed sync writes; without PLP a power cut can lose the ZIL.
  Flag for `zfs_design_2025_10_08` (that doc owns pool geometry, `sync=`, SLOG mirroring, and
  ZIO-taskq internals; this doc only reserves the cores).

## 8. NixOS implementation

All declarative, on top of the existing per-node modules (`configuration.nix` imports
`networking.nix` / `routing.nix` / `sysctl.nix`). Add a common `tuning.nix`, copied per node
like `networking.nix`/`sysctl.nix`. The core map is identical on a/b/d; only RAM differs
(`zfs_arc_max` / hugepages), not the pinning.

**The tuning is three complementary layers — none replaces the others:**

| Layer | Governs | Mechanism |
|---|---|---|
| **Slices (cgroup v2 cpuset)** | *userspace* processes — bird, lldpd, sshd, kubelet, containerd, monitoring, pods | `AllowedCPUs=` on a slice; children inherit |
| **Kernel isolation** | *kernel threads* (ZFS ZIO/ARC, ksoftirqd) + scheduler + tick | `isolcpus` / `nohz_full` / `rcu_nocbs` cmdline |
| **IRQ affinity** | *hardirq* handlers | `smp_affinity_list` (ixgbe) + `isolcpus=managed_irq` (megaraid/nvme) |

Slices are the clean way to place daemons (this is what you asked about): pin the **slice**
once and every process in it inherits — no per-service `CPUAffinity=`. But cgroups don't
touch kernel threads or hardirqs, so the other two layers still carry those.

**8.1 CPU partitioning via systemd slices (userspace).** cgroup v2 is live (`cgroup2fs`), and
`bird`/`lldpd` already run in `system.slice`. Confine the standard slices to the **reserved
pool** and every host daemon — bird, lldpd, sshd, kubelet, containerd — is automatically kept
off the workload cores:

```nix
# All system daemons (incl. bird + lldpd) -> reserved pool. One knob, no per-service pinning.
systemd.slices.system.sliceConfig.AllowedCPUs = "0-7,26-35,54-55";
# Interactive/ssh sessions too.
systemd.slices.user.sliceConfig.AllowedCPUs   = "0-7,26-35,54-55";
```

> **Critical nesting gotcha.** cgroup v2 intersects `cpuset` **down** the tree — a child can
> never use a CPU its parent forbids. So **Kubernetes pods must NOT sit under `system.slice`**,
> or this `AllowedCPUs` would clamp them off the isolated cores. Run kubelet with the
> **systemd** cgroup driver so `kubepods.slice` is a **top-level sibling** of `system.slice`
> (under root `-.slice`, which stays all-CPUs); kubelet then manages the pod cpuset itself via
> `--reserved-cpus` (§8.6). Keep the two consistent: `system.slice` `AllowedCPUs` **==**
> kubelet `--reserved-cpus` **==** the reserved pool.

Optionally carve a finer control-plane slice (bird+lldpd onto just the housekeeping cores,
off the NIC/RAID IRQ cores) — low-volume, so usually unnecessary:

```nix
systemd.slices."controlplane".sliceConfig.AllowedCPUs = "0-1,28-29";
systemd.services.bird.serviceConfig.Slice  = "controlplane.slice";
systemd.services.lldpd.serviceConfig.Slice = "controlplane.slice";
```

(Leave `AllowedMemoryNodes` unset on `system.slice` — host work touches devices on **both**
NUMA nodes, so system memory should span both.)

**8.2 NIC channels + rings + IRQ pinning → one oneshot service.**

> **Why not `systemd.network.links`?** A `.link` for channels/rings would be the tidy,
> device-creation-time route — **except** these nodes already set MTU via a NixOS-generated
> `40-eno1.link` (`MTUBytes=9216`, from `networking.interfaces.eno1.mtu`). `.link` files are
> **first-match-wins, not merged**, so a second `10-eno1.link` would sort earlier and
> **shadow the MTU setting**. Rather than duplicate MTU into a combined `.link` (drift risk),
> we do channels + rings + the NIC-IRQ pin in one oneshot, ordered **before `bird`** so the
> channel-reset flap happens once and BGP establishes cleanly after it. IRQ numbers are
> dynamic → resolve them at runtime; only the unmanaged ixgbe vectors are writable, so
> tolerate a failed write (a managed vector) rather than aborting.

```nix
systemd.services.nic-tune = {
  description = "ixgbe (eno1/eno2): combined=4, rings=2048, IRQs pinned to 2-5,30-33";
  wantedBy = [ "multi-user.target" ];
  after = [ "sys-subsystem-net-devices-bond0.401.device" ];
  before = [ "bird.service" ];          # take the reset flap before BGP comes up
  path = [ pkgs.ethtool pkgs.gawk ];
  serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  script = ''
    for i in eno1 eno2; do
      ethtool -L $i combined 4 || true
      ethtool -G $i rx 2048 tx 2048 || true
      for irq in $(awk -v d="$i" '$0 ~ d {sub(/:/,"",$1); print $1}' /proc/interrupts); do
        echo 2-5,30-33 > /proc/irq/$irq/smp_affinity_list 2>/dev/null || true
      done
    done
  '';
};
```

(If a future NixOS exposes channels/rings on `networking.interfaces.<n>`, or the MTU moves
into a hand-authored `.link`, revisit doing this at device-creation instead.)

**8.3 Kernel params + IRQ policy:**

```nix
boot.kernelParams = [
  "isolcpus=managed_irq,domain,8-25,36-53"
  "nohz_full=8-25,36-53"
  "rcu_nocbs=8-25,36-53"
];
services.irqbalance.enable = false;   # explicit: never let it move the NIC pins back
```

(irqbalance is already absent — this just keeps it that way declaratively.)

**8.4 sysctl** — add to the existing `sysctl.nix`:

```nix
"kernel.numa_balancing" = 0;   # autonuma page migration adds jitter to pinned DB pods
```

**8.5 ZFS** (in the node's ZFS module / `zfs_design`):

```nix
boot.extraModprobeConfig = "options zfs zfs_arc_max=34359738368";  # 32 GiB — tune per host RAM
```

**8.6 Kubelet** (forward-looking — K8s not deployed yet). Static CPU + NUMA alignment so
Guaranteed integer-CPU pods land on exclusive, NUMA-local, isolated cores:

```
--cpu-manager-policy=static
--cpu-manager-policy-options=full-pcpus-only=true    # never split HT siblings
--topology-manager-policy=single-numa-node           # CPU+device+mem on one node
--memory-manager-policy=Static
--reserved-cpus=0-7,26-35,54-55                       # the reserved pool (= not isolated)
```

## 9. Verification (after applying on one node)

```sh
ethtool -l eno1 | awk '/Current/{f=1} f&&/Combined/{print;exit}'   # Combined: 4
ethtool -g eno1 | awk '/Current/{f=1} f&&/^RX:/{print}'            # RX: 2048
grep -E 'eno1|eno2' /proc/interrupts | \
  awk '{sub(/:/,"",$1);print $1}' | \
  while read i; do cat /proc/irq/$i/smp_affinity_list; done | sort -u   # only 2-5,30-33
grep -Ec 'megasas|nvme' /proc/interrupts                            # managed count (unchanged)
cat /proc/cmdline | grep -o 'isolcpus=[^ ]*'                        # managed_irq,domain,8-25,36-53
cat /sys/module/zfs/parameters/zfs_arc_max                          # the cap
systemctl show bird.service -p Slice -p AllowedCPUs                 # in system.slice, cpus=0-7,26-35,54-55
cat /sys/fs/cgroup/system.slice/cpuset.cpus.effective              # == reserved pool
# (once K8s is up) cat /sys/fs/cgroup/kubepods.slice/cpuset.cpus.effective  # == isolated pool, NOT clamped
ss -ti / birdc show protocols                                       # BGP 2x Established after NIC bounce
```

Re-measure DB **p99** and east-west throughput before/after; the change is a win only if tail
latency holds or improves. Confirm bond/BGP re-established after the NIC reset.

## 10. Per-host deltas (confirm before rollout — see `captures/SUMMARY.tsv`)

The pinning is identical on a/b/d; storage differs and needs per-host attention:

- **super-a:** 256 GB; MegaRAID in **RAID** mode. **Anomaly:** its MegaRAID PCIe link trained
  to **×4 of ×8** (half bandwidth) — reseat / check the riser. From `storcli`
  (`captures/super-a/storcli-c0-show.txt`): three **RAID0 single-drive** VDs (`data` 1.75 TB
  Micron 5200, `backup` 1.82 TB Samsung 870 EVO, `backup2` 476 GB SK hynix) — **no controller
  redundancy, ZFS must provide it**; mixed enterprise/consumer SATA SSD (the 870 EVO has
  looser tail latency). **CacheVault CVPM02 Optimal** → the controller write-back cache **is**
  power-loss-protected (unlike the NVMe SLOG) — so a BBU-backed writeback RAID partly overlaps
  the SLOG's job; weigh in `zfs_design`. One **failed/unsupported drive** (`252:0` Fanxiang
  HDD, `UBUnsp`) sits in the enclosure — clean up on-site. Memory: **16×16 GiB DDR4 ECC
  RDIMM, all 16 slots filled** (2DPC), balanced 128 GiB/node, but 2DPC dual-rank downclocks
  to **1866 MT/s**.
- **super-b:** **128 GB** (8×16 GiB, **1DPC → full 2133 MT/s** — faster RAM than super-a's
  1866; 8 slots free, expandable to 256 GB but that drops it to 1866); 3108 in **JBOD/HBA**
  mode (AVAGO JBOD passthrough, no HW-RAID VDs); NVMe is a weaker **Samsung 980** (vs 990 EVO
  Plus on a/d); no SATADOM boot device seen — confirm boot media. ZFS layout on b will differ
  from a/d.
- **super-d:** 128 GB (8×16 GiB, 1DPC → 2133 MT/s, 8 slots free — same memory profile as
  super-b); MegaRAID in RAID mode, full ×8.
- **All:** consumer NVMe **without PLP** used as SLOG (see §7).
- **super-c:** deferred until it boots.
