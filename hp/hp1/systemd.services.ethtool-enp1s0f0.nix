{ pkgs, ... }:
{
  systemd.services.ethtool-enp1s0f0 = {
    description = "ethtool-enp1s0f0";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      # Intel Corporation 82571EB/82571GB Gigabit Ethernet Controller D0/D1 (copper applications) (rev 06)
      ExecStart = "${pkgs.ethtool}/bin/ethtool --set-ring enp1s0f0 rx 8192 tx 8192";
    };
    # wantedBy = [ "multi-user.target" ];
    # https://systemd.io/NETWORK_ONLINE/
    wantedBy = [ "network-pre.target" ];
  };
}