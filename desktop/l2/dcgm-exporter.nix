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
in
{
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
