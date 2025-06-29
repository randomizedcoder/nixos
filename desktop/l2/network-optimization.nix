#
# l2/network-optimization.nix
#

# Network interface optimizations for Atlantic NIC in WiFi access point configuration
#
# Ring Buffer Optimizations:
#   - Increase RX/TX ring buffers to maximum (8184) for better throughput
#
# Feature Optimizations:
#   - LRO (Large Receive Offload): Combine multiple packets for better CPU efficiency
#   - IPv4 checksum offload: Hardware handles checksum calculation
#   - TCP ECN segmentation: Better handling of ECN-marked packets
#   - GRO list: Generic Receive Offload with list support
#
# Interrupt Coalescing Optimizations:
#   - Defaults: rx-usecs=256 rx-frames=0 tx-usecs=1022 tx-frames=0
#   - Changes: rx-usecs=512 rx-frames=32 tx-usecs=1024 tx-frames=32
#   - Purpose: Reduce interrupt frequency for better performance with multiple WiFi clients
#   - Benefits: Fewer CPU context switches, better batch processing
#

{ config, pkgs, ... }:

let
  # Create a shell script for network optimizations
  networkOptimizationScript = pkgs.writeShellScript "network-optimization.sh" ''
    #!/bin/sh
    # Network interface optimizations for Atlantic NIC

    # Ring buffer optimizations
    ${pkgs.ethtool}/bin/ethtool -G enp1s0 rx 8184 tx 8184

    # Feature optimizations
    ${pkgs.ethtool}/bin/ethtool -K enp1s0 lro on
    ${pkgs.ethtool}/bin/ethtool -K enp1s0 tx-checksum-ipv4 on
    ${pkgs.ethtool}/bin/ethtool -K enp1s0 tx-tcp-ecn-segmentation on
    ${pkgs.ethtool}/bin/ethtool -K enp1s0 rx-gro-list on

    # Interrupt coalescing optimizations
    # Defaults: rx-usecs=256 rx-frames=0 tx-usecs=1022 tx-frames=0
    # Changes: rx-usecs=512 rx-frames=32 tx-usecs=1024 tx-frames=32
    ${pkgs.ethtool}/bin/ethtool -C enp1s0 rx-usecs 512 rx-frames 32
    ${pkgs.ethtool}/bin/ethtool -C enp1s0 tx-usecs 1024 tx-frames 32

    # Save verification output to /tmp (cleaned up on reboot)
    echo "=== Network Optimization Results ===" > /tmp/network-optimization.log
    echo "Timestamp: $(date)" >> /tmp/network-optimization.log
    echo "" >> /tmp/network-optimization.log

    echo "=== Ring Buffer Settings ===" >> /tmp/network-optimization.log
    ${pkgs.ethtool}/bin/ethtool --show-ring enp1s0 >> /tmp/network-optimization.log 2>&1
    echo "" >> /tmp/network-optimization.log

    echo "=== Feature Settings ===" >> /tmp/network-optimization.log
    ${pkgs.ethtool}/bin/ethtool --show-features enp1s0 >> /tmp/network-optimization.log 2>&1
    echo "" >> /tmp/network-optimization.log

    echo "=== Interrupt Coalescing Settings ===" >> /tmp/network-optimization.log
    ${pkgs.ethtool}/bin/ethtool --show-coalesce enp1s0 >> /tmp/network-optimization.log 2>&1
    echo "" >> /tmp/network-optimization.log

    echo "=== Driver Information ===" >> /tmp/network-optimization.log
    ${pkgs.ethtool}/bin/ethtool --driver enp1s0 >> /tmp/network-optimization.log 2>&1
  '';

in {
  # Network interface optimizations for Atlantic NIC
  # Run before network-online.target to avoid driver reinitialization
  systemd.services.network-optimization = {
    description = "Optimize network interface settings";
    wantedBy = [ "multi-user.target" ];
    before = [ "network-online.target" ];
    after = [ "network-pre.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = networkOptimizationScript;
      RemainAfterExit = true;
    };
  };
}