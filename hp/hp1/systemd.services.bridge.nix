{ pkgs, config, ... }:
let
  # Configuration variables - can be overridden
  bridgeName = "br0";
  nic0 = "enp1s0f0";
  nic1 = "enp1s0f1";
  bridgePriority = 32768;  # High priority (not preferred as root bridge)
in
{
  systemd.services."bridge" = {
    description = "Create bridge ${bridgeName} for ${nic0} and ${nic1}.  brctl show ${bridgeName}";
    # Wait for ethtool services to complete and interfaces to be available
    after = [
      "network.target"
      "ethtool-${nic0}.service"
      "ethtool-${nic1}.service"
      "sys-subsystem-net-devices-${nic0}.device"
      "sys-subsystem-net-devices-${nic1}.device"
    ];
    wants = [
      "ethtool-${nic0}.service"
      "ethtool-${nic1}.service"
      "sys-subsystem-net-devices-${nic0}.device"
      "sys-subsystem-net-devices-${nic1}.device"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      # Wait for interfaces to exist
      ExecStartPre = pkgs.writeShellScript "bridge-${bridgeName}-pre" ''
        ${pkgs.coreutils}/bin/timeout 30 ${pkgs.bash}/bin/bash -c "until ${pkgs.iproute2}/bin/ip link show ${nic0} >/dev/null 2>&1 && ${pkgs.iproute2}/bin/ip link show ${nic1} >/dev/null 2>&1; do sleep 0.5; done"
      '';
      # Create bridge if it doesn't exist and add interfaces
      ExecStart = pkgs.writeShellScript "bridge-${bridgeName}" ''
        # Create bridge if it doesn't exist
        ${pkgs.iproute2}/bin/ip link show ${bridgeName} >/dev/null 2>&1 || ${pkgs.iproute2}/bin/ip link add name ${bridgeName} type bridge
        # Disable spanning tree protocol
        echo 0 > /sys/class/net/${bridgeName}/bridge/stp_state
        # Set bridge priority to high number (not preferred as root)
        echo ${toString bridgePriority} > /sys/class/net/${bridgeName}/bridge/priority
        # Add interfaces to bridge
        ${pkgs.iproute2}/bin/ip link set ${nic0} master ${bridgeName}
        ${pkgs.iproute2}/bin/ip link set ${nic1} master ${bridgeName}
        # Bring bridge and interfaces up
        ${pkgs.iproute2}/bin/ip link set ${bridgeName} up
        # Bring up member interfaces - needed because networkd has them as Unmanaged
        # so they won't automatically come up when carrier is detected
        ${pkgs.iproute2}/bin/ip link set dev ${nic0} up
        ${pkgs.iproute2}/bin/ip link set dev ${nic1} up
      '';
      # Remove interfaces from bridge and delete bridge on stop
      ExecStop = pkgs.writeShellScript "bridge-${bridgeName}-stop" ''
        ${pkgs.iproute2}/bin/ip link set ${nic0} nomaster 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link set ${nic1} nomaster 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link set ${bridgeName} down 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link delete ${bridgeName} 2>/dev/null || true
      '';
      # Restart if the bridge goes down
      Restart = "on-failure";
      RestartSec = "5s";
    };
    # Start when system reaches multi-user target
    wantedBy = [ "multi-user.target" ];
  };
}
