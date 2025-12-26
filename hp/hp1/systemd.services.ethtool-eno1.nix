{ pkgs, ... }:
{
  systemd.services.ethtool-eno1 = {
    description = "ethtool-eno1";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      # Realtek Semiconductor Co., Ltd. RTL8111/8168/8211/8411 PCI Express Gigabit Ethernet Controller (rev 0e)
      ExecStart = "${pkgs.ethtool}/bin/ethtool --set-ring eno1 rx 256 tx 256";
    };
    # wantedBy = [ "multi-user.target" ];
    # https://systemd.io/NETWORK_ONLINE/
    wantedBy = [ "network-pre.target" ];
  };
}