#
# NVIDIA DCGM Prometheus exporter for l2 (Quadro P620, Pascal/sm_61)
#
# Runs `dcgm-exporter` (NVIDIA's official metrics exporter) in embedded
# mode — it spins its own DCGM hostengine inside the process, no
# nv-hostengine systemd service needed. Default port 9400. Binds to
# 0.0.0.0 so `l`'s Prometheus can scrape over the testbed network
# (l reaches l2 via hostname lookup in l/hosts.nix → 172.16.50.46).
#
# Pascal caveat: DCGM 4.x enumerates Pascal GPUs but skips the
# profiling-metrics path (sm_70+ only). You'll get utilization,
# memory, temperature, power; not DCP/SM-activity metrics. That's
# fine for the P620 — it's a 2 GB display/monitor card, not a
# profiling target.
#
# Firewall: l2's nftables firewall (./firewall.nix) is currently
# commented out in configuration.nix for benchmark mode, so port
# 9400 is reachable without any extra rule. When the firewall is
# re-enabled, add 9400/tcp to the LAN-side allow list (or restrict
# to l's IP 172.16.50.x).
#
# Prometheus scrape job lives on `l` in l/prometheus.nix
# (`dcgm_l2` target).
#
{ config, lib, pkgs, ... }:

let
  port = 9400;

  # dcgm-exporter's prerequisite check (internal/pkg/prerequisites/
  # dcgmlib_rule.go) runs `/sbin/ldconfig -p`, scans the output for
  # `libdcgm.so.4`, opens that path, and verifies the ELF arch matches
  # the running binary. If the lib isn't listed, the exporter exits 1
  # before serving any metrics.
  #
  # On Ubuntu the ld.so.cache lists it; NixOS doesn't populate
  # /etc/ld.so.cache at all, so real `ldconfig -p` is empty and the
  # check fails. This shim emits exactly the one line the validator
  # needs (pointing at the nix-store libdcgm.so.4 symlink) and falls
  # through to the real ldconfig for anything else.
  ldconfigShim = pkgs.writeShellScript "ldconfig-dcgm-shim" ''
    if [ "$1" = "-p" ]; then
      printf '1 libs found in cache (nix shim)\n'
      printf '\tlibdcgm.so.4 (libc6,x86-64) => %s\n' \
        ${pkgs.dcgm}/lib/libdcgm.so.4
      exit 0
    fi
    exec ${pkgs.glibc.bin}/bin/ldconfig "$@"
  '';
in
{
  # Install the shim as /sbin/ldconfig. Activation-time symlink (L+
  # overwrites any prior content) so each rebuild repoints at the
  # newest shim store path.
  systemd.tmpfiles.rules = [
    "L+ /sbin/ldconfig - - - - ${ldconfigShim}"
  ];

  # The exporter falls back to /etc/dcgm-exporter/default-counters.csv
  # if no --collectors flag is given, and exits 1 if that file is
  # missing. nixpkgs' prometheus-dcgm-exporter builds the Go binary
  # only — the etc/ directory from upstream isn't installed. Pull the
  # CSV straight from the same fetched source so it stays version-
  # matched to the binary across nixpkgs bumps.
  # Upstream fix tracked at NVIDIA/dcgm-exporter#684.
  environment.etc."dcgm-exporter/default-counters.csv".source =
    "${pkgs.prometheus-dcgm-exporter.src}/etc/default-counters.csv";

  systemd.services.dcgm-exporter = {
    description = "NVIDIA DCGM Prometheus exporter (embedded hostengine)";
    after = [ "network.target" "systemd-modules-load.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.prometheus-dcgm-exporter}/bin/dcgm-exporter --address=0.0.0.0:${toString port}";
      Restart = "on-failure";
      RestartSec = "10s";

      # Needs /dev/nvidia* access; embedded DCGM spawns helper threads
      # that use SysV shared memory.
      User = "root";
      Group = "root";
      DeviceAllow = [
        "/dev/nvidiactl rw"
        "/dev/nvidia-uvm rw"
        "/dev/nvidia0 rw"
      ];

      # Lightweight hardening — keep filesystem/network surface minimal.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}
