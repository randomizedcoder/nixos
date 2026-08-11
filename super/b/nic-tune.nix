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
#
# BOOT ORDERING (learned the hard way): at boot the eno1/eno2 devices don't exist when a
# naive `After=...bond0.401.device` fires — every ethtool call hit "netlink: No such device"
# and the tuning silently no-op'd (worked on `switch` only because the NICs were already up).
# Following the house pattern (~/nixos/hp/hp2): order after `network-online.target` AND have the
# script WAIT for each NIC to appear (the wait loop is the real safety net — udev rename / bond
# assembly can lag `network-online`). `ethtool -L` resets the NIC -> bond slave flaps -> BGP
# briefly drops; ordering BEFORE bird takes that flap before BGP comes up (self-heals via
# graceful-restart regardless).
#
{ config, pkgs, lib, ... }:

let
  nicIrqCpus = "2-5,30-33";   # NIC-IRQ cores (must sit inside cpu-tuning.nix reserved pool)

  nicTune = pkgs.writeShellApplication {
    name = "nic-tune";
    runtimeInputs = [ pkgs.ethtool ];   # ethtool is the only external tool; parsing is pure bash
    text = ''
      for dev in eno1 eno2; do
        # Wait for the NIC to appear (udev rename / bond assembly can lag network-online).
        # Use the sysfs node directly — no need to shell out to `ip`.
        n=0
        while [[ ! -e "/sys/class/net/$dev" ]]; do
          n=$((n + 1))
          if [[ "$n" -ge 60 ]]; then break; fi   # ~30s
          sleep 0.5
        done
        if [[ ! -e "/sys/class/net/$dev" ]]; then
          echo "nic-tune: $dev did not appear, skipping" >&2
          continue
        fi

        ethtool -L "$dev" combined 4 || true
        ethtool -G "$dev" rx 2048 tx 2048 || true

        # Pin this NIC's UNMANAGED IRQs onto the NIC-IRQ cores. Parse /proc/interrupts with
        # bash builtins (no awk): match lines mentioning the NIC, take the field before the
        # first ':' as the IRQ number. Tolerate a rejected write (a managed IRQ).
        while read -r line; do
          [[ "$line" == *"$dev"* ]] || continue
          irq="''${line%%:*}"          # everything before the first colon
          irq="''${irq// /}"           # strip the leading padding
          [[ "$irq" =~ ^[0-9]+$ ]] || continue
          echo ${nicIrqCpus} > "/proc/irq/$irq/smp_affinity_list" 2>/dev/null || true
        done < /proc/interrupts
      done
    '';
  };
in
{
  systemd.services.nic-tune = {
    description = "ixgbe (eno1/eno2): combined=4, rings=2048, IRQs pinned to ${nicIrqCpus}";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = [ "bird.service" ];                          # take the channel-reset flap before BGP
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe nicTune;
    };
  };
}
