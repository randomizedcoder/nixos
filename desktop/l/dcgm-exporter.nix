#
# NVIDIA DCGM Prometheus exporter for l (RTX 3070, Ampere/sm_86)
#
# Runs `dcgm-exporter` (NVIDIA's official metrics exporter) in embedded
# mode — it spins its own DCGM hostengine inside the process, no
# nv-hostengine systemd service needed. Default port 9400. Binds to
# localhost because Prometheus scrapes from the same host on `l`.
#
# Prometheus scrape job is added in ./prometheus.nix.
#
# Notes:
#   - nixpkgs ships `prometheus-dcgm-exporter` v4.3.1-4.4.0 paired with
#     `dcgm` v4.3.1. RTX 3070 (sm_86) is first-class supported.
#   - The package uses autoAddDriverRunpath + patchelf to find
#     libnvidia-ml.so under /run/opengl-driver/lib at runtime, so no
#     LD_LIBRARY_PATH gymnastics required.
#   - Runs as root because it touches /dev/nvidia* and DCGM's shared
#     memory segment. Hardening below restricts the namespace to what
#     it actually needs.
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
      ExecStart = "${pkgs.prometheus-dcgm-exporter}/bin/dcgm-exporter --address=127.0.0.1:${toString port}";
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
