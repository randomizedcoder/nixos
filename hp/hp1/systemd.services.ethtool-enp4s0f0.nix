{ pkgs, ... }:
{
  systemd.services.ethtool-enp4s0f0 = {
    description = "ethtool-enp4s0f0";
    # Wait for the network interface to be available
    after = [ "network-pre.target" "network.target" "sys-subsystem-net-devices-enp4s0f0.device" ];
    wants = [ "sys-subsystem-net-devices-enp4s0f0.device" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      # Wait for interface to exist before running ethtool
      ExecStartPre = "${pkgs.coreutils}/bin/timeout 30 ${pkgs.bash}/bin/bash -c 'until ${pkgs.iproute2}/bin/ip link show enp4s0f0 >/dev/null 2>&1; do sleep 0.5; done'";
      # Intel Corporation Ethernet Controller 10-Gigabit X540-AT2 (rev 01)
      ExecStart = "${pkgs.ethtool}/bin/ethtool --set-ring enp4s0f0 rx 4096 tx 4096";
      # Restart if the interface comes back up
      Restart = "on-failure";
      RestartSec = "5s";
    };
    # Start when system reaches multi-user target (after network is configured)
    wantedBy = [ "multi-user.target" ];
  };
}