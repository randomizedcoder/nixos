{ config, pkgs, ... }:

{
  # Network interface optimizations for Atlantic NIC
  # Run before network-online.target to avoid driver reinitialization
  systemd.services.network-optimization = {
    description = "Optimize network interface settings";
    wantedBy = [ "multi-user.target" ];
    before = [ "network-online.target" ];
    after = [ "network-pre.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        # Ring buffer optimizations
        ${pkgs.ethtool}/bin/ethtool -G enp1s0 rx 8184 tx 8184

        # Feature optimizations
        ${pkgs.ethtool}/bin/ethtool -K enp1s0 lro on
        ${pkgs.ethtool}/bin/ethtool -K enp1s0 tx-checksum-ipv4 on
        ${pkgs.ethtool}/bin/ethtool -K enp1s0 tx-tcp-ecn-segmentation on
        ${pkgs.ethtool}/bin/ethtool -K enp1s0 rx-gro-list on

        # Interrupt coalescing optimizations for WiFi access point
        # Reduce interrupt frequency for better performance with multiple clients
        # Defaults: rx-usecs=256 rx-frames=0 tx-usecs=1022 tx-frames=0
        # Changes: rx-usecs=512 rx-frames=32 tx-usecs=1024 tx-frames=32
        ${pkgs.ethtool}/bin/ethtool -C enp1s0 rx-usecs 512 rx-frames 32
        ${pkgs.ethtool}/bin/ethtool -C enp1s0 tx-usecs 1024 tx-frames 32
      '';
      RemainAfterExit = true;
    };
  };
}