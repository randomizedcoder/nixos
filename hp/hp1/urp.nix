# hp/hp1/urp.nix — design 32 real-hardware RoCEv2 integration (ACCEPTOR side).
#
# hp1 is the RDMA *acceptor* (listener). It binds the ConnectX-4 Lx port on
# link A (10.10.2.1, enp1s0f0np0); the bind IP selects the RDMA device via
# RDMA-CM (no --rdma-device needed). The `.#urp-hw-matrix` runner drives the
# bench listener behind the acceptor's --connect-path UDS per cell; the RDMA
# session establishes at `urp add` regardless of a backend being present.
#
# Peer: hp3 initiator (10.10.2.3), see hp/hp3/urp.nix. Port 4791 = RoCEv2.
{ ... }:

{
  services.urp = {
    enable = true;

    endpoints.pair_acceptor = {
      role = "acceptor";
      connectPath = "/run/urp-echo.sock";  # runner's bench --listen lives here
      bind = "10.10.2.1:4791";             # link A; IP picks mlx5 device via CM
    };
  };
}
