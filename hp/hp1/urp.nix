# hp/hp1/urp.nix — design 32 real-hardware RoCEv2 integration (ACCEPTOR side).
#
# hp1 is the RDMA *acceptor* (listener) for the standing hp1<->hp3 edge. It
# binds the ConnectX-4 Lx port that now cables to hp3 (enp1s0f0np0, 10.10.13.1
# after the 2026-08-31 mesh re-cable); the bind IP selects the RDMA device via
# RDMA-CM (no --rdma-device needed). The `.#urp-hw-matrix` / reorder / bw
# runners drive the bench behind the acceptor's --connect-path UDS per cell;
# the RDMA session establishes at `urp add` regardless of a backend present.
#
# This is the ONE standing endpoint so the classic 2-host runners keep working
# unmodified on hp1<->hp3. The hp1<->hp2 edge and all concurrent-mesh scenarios
# are driven by `.#urp-mesh-matrix`, which creates its own per-run endpoints.
#
# Peer: hp3 initiator (10.10.13.3), see hp/hp3/urp.nix. Port 4791 = RoCEv2.
{ ... }:

{
  services.urp = {
    enable = true;

    endpoints.pair_acceptor = {
      role = "acceptor";
      connectPath = "/run/urp-echo.sock";  # runner's bench --listen lives here
      bind = "10.10.13.1:4791";            # -> hp3; IP picks mlx5 device via CM
    };
  };

  # design 39: Prometheus exporter for the urp counters. Exposed on the trusted
  # lab mgmt LAN (0.0.0.0 + openFirewall) so l's Prometheus scrapes hp1:9975
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
