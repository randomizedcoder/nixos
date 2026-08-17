# hp/hp3/urp.nix — design 32 real-hardware RoCEv2 integration (INITIATOR side).
#
# hp3 is the RDMA *initiator* (connector). It listens on a local UDS
# (/run/urp.sock) for app connections and tunnels them over RoCEv2 to the
# hp1 acceptor at 10.10.2.1:4791 (link A). The `.#urp-hw-matrix` runner drives
# the bench generator into --listen-path per cell.
#
# Peer: hp1 acceptor (10.10.2.1), see hp/hp1/urp.nix. Port 4791 = RoCEv2.
{ ... }:

{
  services.urp = {
    enable = true;

    endpoints.pair_initiator = {
      role = "initiator";
      listenPath = "/run/urp.sock";  # runner's bench --connect lives here
      peer = "10.10.2.1:4791";       # hp1 acceptor over link A
    };
  };
}
