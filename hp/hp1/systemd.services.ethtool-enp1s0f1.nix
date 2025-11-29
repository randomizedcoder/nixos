{ pkgs, ... }:
{
  systemd.services.ethtool-enp1s0f1 = {
    description = "ethtool-enp1s0f1";
    # Wait for the network interface to be available
    after = [ "network-pre.target" "network.target" "sys-subsystem-net-devices-enp1s0f1.device" ];
    wants = [ "sys-subsystem-net-devices-enp1s0f1.device" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      # Wait for interface to exist before running ethtool
      ExecStartPre = "${pkgs.coreutils}/bin/timeout 30 ${pkgs.bash}/bin/bash -c 'until ${pkgs.iproute2}/bin/ip link show enp1s0f1 >/dev/null 2>&1; do sleep 0.5; done'";
      # Intel Corporation 82571EB/82571GB Gigabit Ethernet Controller D0/D1 (copper applications) (rev 06)
      ExecStart = "${pkgs.ethtool}/bin/ethtool --set-ring enp1s0f1 rx 8192 tx 8192";
      # Restart if the interface comes back up
      Restart = "on-failure";
      RestartSec = "5s";
    };
    # Start when system reaches multi-user target (after network is configured)
    wantedBy = [ "multi-user.target" ];
  };
}