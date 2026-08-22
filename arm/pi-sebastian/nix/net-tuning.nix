#
# arm/pi-sebastian/nix/net-tuning.nix
#
# Network-performance tuning: give the on-board NIC a dedicated CPU core.
#
# This box runs an iperf2 server for network testing, so it should deliver
# clean, repeatable numbers. The Pi 4's built-in 1 GbE (`eth0`, the on-SoC
# bcmgenet MAC) is effectively a single-queue NIC and by default its interrupt
# lands on CPU0, next to the SD-card controller. Under any other load that core
# becomes the bottleneck and throughput/latency get noisy.
#
# Strategy (Pi 4 = 4 cores):
#   CPU 0-2 : system.slice + user.slice + everything else (monitoring, rebuilds)
#   CPU 3   : the NIC (IRQ + rx/tx softirq) and the iperf2 server, shielded
#
# We (a) steer the NIC's interrupt + packet processing onto the network core,
# (b) confine all other cgroups to the remaining cores so nothing preempts it,
# and (c) run the iperf2 server on the network core.
#
# To retune: change `nic`/`netCore`, widen `netperf.slice` AllowedCPUs (e.g.
# "2-3" to give iperf2 two cores for high-PPS/multi-stream), or move iperf2 to
# CPU2 and keep only the IRQ on CPU3 for true IRQ/app parallelism.
#
# NB: `nic` is the wired interface name. On the Pi 4 it is normally `eth0`; if
# `ip -brief link` on your board shows something else, change it here.
#
{ config, pkgs, lib, ... }:

let
  # Wired NIC to pin, and the core dedicated to it + iperf2.
  nic = "eth0";
  netCore = 3;
  otherCores = "0-${toString (netCore - 1)}"; # "0-2"
  # CPU affinity mask (hex, no 0x) for a single core: 2^netCore. Nix has no
  # exponent/shift operator, so fold a multiply. CPU3 -> 8.
  pow2 = n: lib.foldl' (acc: _: acc * 2) 1 (lib.range 1 n);
  netMaskHex = lib.toHexString (pow2 netCore); # CPU3 -> "8"
  nicDevUnit = "sys-subsystem-net-devices-${nic}.device";
in
{
  # Don't let a balancer undo our explicit IRQ placement.
  services.irqbalance.enable = lib.mkDefault false;

  # --- shield the network core ---------------------------------------------
  # Confine general work to the other cores. cgroup-v2 cpuset is hierarchical,
  # so services in these slices (incl. Grafana/Prometheus/node_exporter and
  # nix-daemon) can never run on the network core.
  systemd.slices.system.sliceConfig.AllowedCPUs = otherCores;
  systemd.slices.user.sliceConfig.AllowedCPUs = otherCores;

  # A dedicated slice for the network core; the iperf2 server lives here.
  systemd.slices.netperf = {
    description = "Shielded core for NIC IRQ + network apps";
    sliceConfig.AllowedCPUs = toString netCore; # "3"
  };
  systemd.services.iperf2.serviceConfig.Slice = "netperf.slice";

  # --- steer the NIC onto the network core ---------------------------------
  systemd.services.pin-nic-irq = {
    description = "Pin ${nic} NIC IRQ + RPS/XPS to the dedicated network core";
    # Run on every boot/activation, ordered after the interface exists. (Keying
    # wantedBy on the .device alone misses activations where the NIC is already
    # up and the device unit isn't restarted.)
    after = [ nicDevUnit ];
    bindsTo = [ nicDevUnit ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.gawk pkgs.coreutils ];
    script = ''
      set -u
      NIC=${nic}
      CORE=${toString netCore}
      MASK=${netMaskHex}

      # (a) Hard IRQ affinity. The Pi 4's bcmgenet IRQs are GIC-level and
      #     normally settable; if the kernel rejects a change (EIO) the RPS
      #     steering below still moves the actual packet-processing work.
      for irq in $(awk -F: -v n="$NIC" '$0 ~ n { gsub(/ /,"",$1); print $1 }' /proc/interrupts); do
        if echo "$CORE" > /proc/irq/"$irq"/smp_affinity_list 2>/dev/null; then
          echo "pinned hard IRQ $irq ($NIC) -> CPU$CORE"
        else
          echo "could not set hard affinity for IRQ $irq; relying on RPS"
        fi
      done

      # (b) RPS (receive) + XPS (transmit) steering to the network core. This
      #     is the reliable lever for a single-queue NIC: the rx/tx softirq
      #     work runs on CPU$CORE even if the hard IRQ stays on CPU0.
      for q in /sys/class/net/"$NIC"/queues/rx-*/rps_cpus; do
        [ -e "$q" ] && echo "$MASK" > "$q" 2>/dev/null && echo "RPS $q -> $MASK"
      done
      for q in /sys/class/net/"$NIC"/queues/tx-*/xps_cpus; do
        [ -e "$q" ] && echo "$MASK" > "$q" 2>/dev/null && echo "XPS $q -> $MASK"
      done
      true
    '';
  };

  # --- modest socket-buffer headroom for high-throughput tests -------------
  # Lets iperf2 open large windows when asked; harmless on a LAN.
  boot.kernel.sysctl = {
    "net.core.rmem_max" = 16777216; # 16 MiB
    "net.core.wmem_max" = 16777216; # 16 MiB
    "net.core.netdev_max_backlog" = 5000;
  };
}
