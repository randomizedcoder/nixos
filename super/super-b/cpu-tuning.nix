#
# /etc/nixos/cpu-tuning.nix  —  identical on every super-* node
#
# CPU core dedication for the Kubernetes/DB workload (see super/tuning/tuning.md).
# These E5-2680 v4 nodes are 2 sockets x 14c/28t = 56 logical CPUs, 2 NUMA nodes.
# HT siblings pair k <-> k+28. We split the machine into two pools:
#
#   reserved  (10 phys cores) = host + all IRQ handling + ZFS ZIO/ARC kthreads
#   isolated  (18 phys cores) = exclusive, pinned container workloads
#
# The data NIC (ixgbe) and the MegaRAID controller are both on NUMA 0; the NVMe
# ZFS SLOG/L2ARC is on NUMA 1 — so the reserved pool spans both nodes (housekeeping
# + NIC/RAID IRQ on node 0; NVMe IRQ on node 1), and the isolated pool is the rest.
#
# This file owns the CPU MAP as a single source of truth (the let-block below) and
# applies it three ways: kernel isolation (cmdline), userspace confinement (systemd
# slices), and NUMA-balancer off. NIC/RAID/NVMe IRQ affinity is handled separately:
#   - ixgbe (unmanaged)      -> pinned in nic-tune.nix
#   - megaraid_sas / nvme    -> MANAGED MSI-X, can't be repinned; the isolcpus
#                               `managed_irq` flag below keeps them off the workload cores.
#
{ config, lib, ... }:

let
  # ---- THE CPU MAP (keep in sync with tuning.md §2/§4) ----
  # Reserved / schedulable: 2 housekeeping + 4 NIC-IRQ + 2 RAID-IRQ (node0) + 2 NVMe-IRQ (node1).
  reservedCpus = "0-7,26-35,54-55";   # 10 physical cores (20 threads)
  # Isolated / exclusive workload pool: node0 8-13 (RAID-local) + node1 14-25, with HT siblings.
  isolatedCpus = "8-25,36-53";        # 18 physical cores (36 threads)
in
{
  # --- Kernel isolation (takes effect on REBOOT) ---
  # domain      : keep the scheduler's load-balancer off the workload cores.
  # managed_irq : keep MANAGED IRQs (megaraid_sas, nvme) off them too — the only lever
  #               that works for managed MSI-X (their smp_affinity is not writable).
  # nohz_full + rcu_nocbs : stop the tick + offload RCU callbacks -> remove kernel jitter.
  boot.kernelParams = [
    "isolcpus=managed_irq,domain,${isolatedCpus}"
    "nohz_full=${isolatedCpus}"
    "rcu_nocbs=${isolatedCpus}"
  ];

  # --- Userspace confinement via systemd slices (cgroup v2 cpuset; takes effect on SWITCH) ---
  # Pin the SLICE once; every unit in it (bird, lldpd, sshd, kubelet, containerd, monitoring)
  # inherits -> no per-service CPUAffinity. cgroup v2 intersects cpusets downward, so
  # Kubernetes pods MUST live in a top-level `kubepods.slice` (systemd cgroup driver),
  # NOT nested under system.slice, or this would clamp them off the isolated cores.
  systemd.slices.system.sliceConfig.AllowedCPUs = reservedCpus;
  systemd.slices.user.sliceConfig.AllowedCPUs   = reservedCpus;

  # irqbalance must stay OFF or it would drag the NIC pins (nic-tune.nix) back across cores.
  # (Already absent on these nodes; declared here so it can't silently return.)
  services.irqbalance.enable = false;

  # AutoNUMA page migration adds jitter to pinned, NUMA-local DB pods — disable it.
  boot.kernel.sysctl."kernel.numa_balancing" = 0;

  # --- Forward-looking: Kubernetes kubelet (NOT enabled yet — uncomment at K8s bring-up) ---
  # Keep reserved-cpus == the reserved pool above so the two agree. Static CPU + single-NUMA
  # topology managers give Guaranteed integer-CPU pods exclusive, NUMA-aligned isolated cores.
  #
  # services.kubernetes.kubelet.extraOpts = lib.concatStringsSep " " [
  #   "--cpu-manager-policy=static"
  #   "--cpu-manager-policy-options=full-pcpus-only=true"   # never split HT siblings
  #   "--topology-manager-policy=single-numa-node"
  #   "--memory-manager-policy=Static"
  #   "--reserved-cpus=${reservedCpus}"
  # ];
}
