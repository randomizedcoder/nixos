#
# /etc/nixos/nic-tune.nix  —  identical on every super-* node
#
# Data-NIC (Intel X540, ixgbe: eno1 + eno2, bonded -> bond0.401) queue/ring/IRQ tuning
# for the K8s/DB workload (see super/tuning/tuning.md §4/§8.2). Pairs with cpu-tuning.nix,
# which reserves the CPU pools this pins into.
#
# What it does, once at boot:
#   - combined channels 56 -> 4 per slave (8 total for the bond). ixgbe is combined-only
#     (one rx+tx queue + one IRQ per channel); 4/slave honors "4 rx + 4 tx" with headroom.
#   - RX/TX rings 512 -> 2048 (moderate: burst headroom without the tail-latency cost of
#     the 8192 max — this is a p99-sensitive workload; raise toward 4096 only if drops show).
#   - pin the (now 8) UNMANAGED ixgbe IRQs onto the NIC-IRQ cores 2-5,30-33 (NUMA 0, local
#     to the X540). megaraid/nvme IRQs are managed and handled via isolcpus (cpu-tuning.nix).
#
# NOTE: this is a oneshot service, NOT a systemd.link .link file — a .link for channels
# would sort ahead of and SHADOW the NixOS-generated MTU .link (40-eno1.link, MTUBytes=9216),
# because .link files are first-match-wins, not merged. Doing it in a service avoids that.
# `ethtool -L` resets the NIC -> the bond slave flaps -> BGP briefly drops; we order this
# BEFORE bird.service so the flap happens once and BGP establishes cleanly after it
# (self-heals via graceful-restart regardless).
#
{ config, pkgs, ... }:

let
  nicIrqCpus = "2-5,30-33";   # NIC-IRQ cores (must sit inside cpu-tuning.nix reserved pool)
in
{
  systemd.services.nic-tune = {
    description = "ixgbe (eno1/eno2): combined=4, rings=2048, IRQs pinned to ${nicIrqCpus}";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-subsystem-net-devices-bond0.401.device" ];
    before = [ "bird.service" ];          # take the channel-reset flap before BGP comes up
    path = [ pkgs.ethtool pkgs.gawk ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      for i in eno1 eno2; do
        ethtool -L "$i" combined 4 || true
        ethtool -G "$i" rx 2048 tx 2048 || true
        # Resolve this NIC's IRQ numbers at runtime (they're dynamic) and pin the
        # writable (unmanaged) ones; tolerate a rejected write in case one is managed.
        for irq in $(awk -v d="$i" '$0 ~ d {sub(/:/,"",$1); print $1}' /proc/interrupts); do
          echo ${nicIrqCpus} > /proc/irq/"$irq"/smp_affinity_list 2>/dev/null || true
        done
      done
    '';
  };
}
