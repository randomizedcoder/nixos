# Per-NIC ethtool tuning for the X710 port enp1s0f0np0.
#
# Replaces the legacy systemd.services.ethtool-enp3s0f0.nix (interface
# was renamed enp3s0f0 → enp1s0f0np0 when the X710 moved PCIe slots and
# predictable-net-names started emitting the np0/np1 multi-port hint).
#
# Tuning rationale: see xdp2 docs/physical-testbed.md §6 (the values
# below are the standalone equivalent of nixosModules.physical-testbed
# applied to one interface, with conservative defaults — switch to the
# module when CPU isolation is introduced).
#
# Idempotent: every ethtool call ends with `|| true` because returning
# "no change needed" is not an error, and we don't want udev rename
# races to leave the unit in a failed state.
{ pkgs, ... }:
let
  ifc = "enp1s0f0np0";
  # One combined queue per physical core (4c/8t Ryzen 5 PRO 2400G).
  # When CPU isolation is configured, set this to length(isolatedCpus).
  queues = 4;
in
{
  systemd.services."ethtool-${ifc}" = {
    description = "X710 ethtool tuning for ${ifc}";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.ethtool pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -u
      ifc=${ifc}

      # Wait for the interface; udev rename can lag boot.
      for _ in $(seq 1 30); do
        if ip link show "$ifc" >/dev/null 2>&1; then break; fi
        sleep 1
      done
      if ! ip link show "$ifc" >/dev/null 2>&1; then
        echo "ethtool-$ifc: interface never appeared, skipping" >&2
        exit 0
      fi

      # Rings: max-or-4096 RX/TX descriptors (X710 max is 4096).
      ethtool -G "$ifc" rx 4096 tx 4096 || true

      # Combined queues — one per physical core for now.
      ethtool -L "$ifc" combined ${toString queues} || true

      # Offloads off: parser benchmarks need to see real per-packet
      # boundaries. GRO/LRO/TSO/GSO coalesce frames before the parser
      # sees them and would distort measurements.
      ethtool -K "$ifc" gro off lro off tso off gso off || true

      # Flow control off — no PAUSE frames on a back-to-back link.
      ethtool -A "$ifc" rx off tx off autoneg off || true

      # Flow director on, hash on the 5-tuple (source + dest +
      # source-port + dest-port). ntuple-rule programming is left to
      # per-test scripts.
      ethtool -K "$ifc" ntuple on || true
      ethtool -N "$ifc" rx-flow-hash tcp4 sdfn || true
      ethtool -N "$ifc" rx-flow-hash udp4 sdfn || true
      ethtool -N "$ifc" rx-flow-hash tcp6 sdfn || true
      ethtool -N "$ifc" rx-flow-hash udp6 sdfn || true
    '';
  };
}
