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
in
{
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
