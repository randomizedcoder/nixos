# hp/hp3/urp.nix — design 32 real-hardware RoCEv2 integration (INITIATOR side).
#
# hp3 is the RDMA *initiator* (connector) for the standing hp1<->hp3 edge. It
# listens on a local UDS (/run/urp.sock) for app connections and tunnels them
# over RoCEv2 to the hp1 acceptor at 10.10.13.1:4791 (the port that cables to
# hp1 after the 2026-08-31 mesh re-cable is hp3's enp1s0f1np1). The runners
# drive the bench generator into --listen-path per cell.
#
# This is the ONE standing endpoint so the classic 2-host runners keep working
# unmodified on hp1<->hp3. The hp2<->hp3 edge and all concurrent-mesh scenarios
# are driven by `.#urp-mesh-matrix`, which creates its own per-run endpoints.
#
# Peer: hp1 acceptor (10.10.13.1), see hp/hp1/urp.nix. Port 4791 = RoCEv2.
{ ... }:

{
  services.urp = {
    enable = true;

    endpoints.pair_initiator = {
      role = "initiator";
      listenPath = "/run/urp.sock";  # runner's bench --connect lives here
      peer = "10.10.13.1:4791";      # hp1 acceptor, -> hp1 edge
    };
  };

  # design 39: Prometheus exporter for the urp counters. Exposed on the trusted
  # lab mgmt LAN (0.0.0.0 + openFirewall) so l's Prometheus scrapes hp3:9975
  # directly — same posture as dcgm_l2. Read-only counters; the localhost-only
  # default (§39.3 rule 7) is overridden deliberately for the trusted-fabric
  # case. CPUQuota 10% / MemoryMax 64M defaults keep it off the data path.
  services.urp-exporter = {
    enable = true;
    listenAddress = "0.0.0.0";
    openFirewall = true;
  };
}
