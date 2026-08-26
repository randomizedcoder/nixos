# hp/hp1/roce-mtu.nix
#
# Persistent jumbo MTU on the 25 GbE RoCEv2 links (uds-rdma-proxy design 37
# throughput work). The ConnectX-4 Lx driver reports maxmtu 9978; NVIDIA's
# practical max for this NIC (MT27710) is 9700. A large L2 MTU lifts the RoCE
# path MTU (ibv active_mtu) from 1024 to its 4096 ceiling — the real RDMA win —
# and also raises the single-stream TCP baseline.
#
# Set via a systemd-udevd .link file so it applies at device appearance,
# independent of the imperative xdp2.testbed NIC wiring (whose `jumbo` option
# would only hardcode 9000). A 10-* prefix sorts ahead of the empty
# 40-<iface>.link, so this is the matching .link for these ports.
#
# Verify after `nixos-rebuild switch` + reboot:
#   ip -d link show enp1s0f0np0        # mtu 9700
#   ibv_devinfo | grep active_mtu      # 4096 (was 1024)
#   ping -M do -s 9672 10.10.2.3       # jumbo path passes end-to-end
# If the path cannot pass 9700 (switch/peer limit), drop MTUBytes to "9000".
{ ... }:

{
  systemd.network.links."10-roce-jumbo" = {
    matchConfig.OriginalName = "enp1s0f0np0 enp1s0f1np1";
    linkConfig.MTUBytes = "9700";
  };
}
