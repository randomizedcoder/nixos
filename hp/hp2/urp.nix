# hp/hp2/urp.nix — design 32 real-hardware RoCEv2 integration (MESH node hp2).
#
# hp2 is the third node in the hp1/hp3 full mesh (added 2026-08-31). It sits on
# TWO edges — hp1 (via enp1s0f0np0, 10.10.12.2) and hp3 (via enp1s0f1np1,
# 10.10.23.2) — and takes BOTH roles depending on the run. Rather than pin a
# standing acceptor/initiator pair (like hp1/hp3 do for their legacy edge),
# hp2 is deliberately ENABLE-ONLY: the `.#urp-mesh-matrix` runner creates
# uniquely-named per-run endpoints on the fly (the urp-f2-matrix model), so the
# standing config just needs to build + load urp.ko and install the CLI.
#
# `services.urp.endpoints` defaults to {} (see uds-rdma-proxy nix/nixos-module.nix),
# so `enable = true` alone is a valid, endpoint-free deployment.
{ ... }:

{
  services.urp.enable = true;

  # design 39: Prometheus exporter for the urp counters. Exposed on the trusted
  # lab mgmt LAN (0.0.0.0 + openFirewall) so l's Prometheus scrapes hp2:9975
  # directly — same posture as dcgm_l2. Read-only counters; the localhost-only
  # default (§39.3 rule 7) is overridden deliberately for the trusted-fabric
  # case. CPUQuota 10% / MemoryMax 64M defaults keep it off the data path.
  services.urp-exporter = {
    enable = true;
    listenAddress = "0.0.0.0";
    openFirewall = true;
    perStream = true; # populate the reorder-depth + live-credits dashboard panels
  };
}
