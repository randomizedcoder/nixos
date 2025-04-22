{ pkgs, ... }:
{
    systemd.services.ethtool-enp1s0f1 = {
    description = "ethtool-enp1s0f1";
    serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.ethtool}/bin/ethtool --set-ring enp1s0f1 rx 4096 tx 4096";
    };
    # wantedBy = [ "multi-user.target" ];
    # https://systemd.io/NETWORK_ONLINE/
    wantedBy = [ "network-pre.target" ];
    };
}
