#
# l2/ethtool-nics.nix
#
# Consolidated ethtool configuration for all 10GbE NICs.
# Generates systemd oneshot services to configure ring buffers, channels,
# and offload features at boot.
#
# =============================================================================
# TUNING RATIONALE
# =============================================================================
#
# Ring buffers (--set-ring rx N tx N):
#   Larger ring buffers reduce packet drops under high load by giving the
#   kernel more time to process packets before the ring overflows. Each NIC
#   is set to its maximum supported value.
#
# Channels (--set-channels combined N):
#   Each channel maps to an RX/TX queue pair with its own MSI-X interrupt.
#   Modern NICs default to one channel per CPU core (24-49 on this system),
#   which creates excessive interrupt overhead and cache contention.
#   Reducing to 8 channels lowers this overhead while still allowing good
#   multi-core distribution via RSS (Receive Side Scaling).
#
# =============================================================================
# OFFLOAD FEATURES
# =============================================================================
#
# rx-udp-gro-forwarding:
#   GRO (Generic Receive Offload) aggregates small packets into larger ones
#   for efficient local processing. However, when forwarding/routing, these
#   aggregated packets must be re-segmented, negating the benefit. This
#   setting allows GRO-aggregated UDP packets to be forwarded directly
#   without re-segmentation, improving forwarding throughput.
#
# ntuple:
#   Enables n-tuple filtering (Flow Director on Intel). Allows steering
#   specific flows (based on IP/port tuples) to specific RX queues/CPUs.
#   This improves cache locality by keeping packets from the same connection
#   on the same CPU. On ixgbe, also enables ATR (Application Targeted Routing)
#   which automatically steers return traffic to match outgoing flows.
#
#   Manual rules can be configured via: ethtool --config-ntuple
#   Use action -1 to drop packets, or action N to steer to queue N.
#
#   IMPORTANT: Intel 82599ES (ixgbe) ntuple support is very limited!
#
#   The 82599 has a "one mask per port" hardware limitation:
#     - The FIRST filter you add establishes which fields can be matched
#     - ALL subsequent filters must match on the SAME fields
#     - You cannot mix dst-port rules with src-ip rules on the same interface
#
#   Since we use dst-port rules first, we are locked to dst-port filtering.
#   IP-based filtering (src-ip, dst-ip) would require removing all port rules
#   and starting fresh with IP-only rules - but then you couldn't filter ports.
#
#   Tested with ./test-ntuple.sh - confirmed working:
#     - tcp4 dst-port only
#     - udp4 dst-port only
#     - Queue steering (action N) with dst-port
#
#   Does NOT work (due to one-mask limitation):
#     - src-port, src-ip, dst-ip (different mask than dst-port)
#     - Combined IP + port rules
#     - flow-type ip4
#     - Subnet masks
#
#   References:
#     - Intel Flow Director Guide: intel.com/content/www/us/en/developer/articles/training/setting-up-intel-ethernet-flow-director.html
#     - E1000-devel mailing list: "the driver only allows one mask per port"
#     - Kernel docs: kernel.org/doc/html/v4.20/networking/ixgbe.html
#
#   Example: Block Windows SMB/NetBIOS ports (drop at hardware level):
#     ethtool -N enp66s0f0 flow-type tcp4 dst-port 135 action -1   # MS-RPC
#     ethtool -N enp66s0f0 flow-type tcp4 dst-port 139 action -1   # NetBIOS
#     ethtool -N enp66s0f0 flow-type tcp4 dst-port 445 action -1   # SMB
#     ethtool -N enp66s0f0 flow-type udp4 dst-port 137 action -1   # NetBIOS NS
#     ethtool -N enp66s0f0 flow-type udp4 dst-port 138 action -1   # NetBIOS DGM
#
#   View rules:    ethtool --show-ntuple enp66s0f0
#   Delete rule:   ethtool --config-ntuple enp66s0f0 delete N
#
#   DEFAULT BEHAVIOR: ntuple rules are exceptions, not a firewall policy.
#   Packets that don't match any rule are processed normally (allowed).
#   No "allow all" rule is needed at the end - unmatched traffic passes through.
#
#   For IP-based blocking, use nftables instead (no hardware limitations).
#
#   For general blocking, nftables/iptables is recommended over ntuple:
#     - Works on all interfaces (ntuple is per-NIC and driver-dependent)
#     - Supports IP filtering, subnets, rate limiting, stateful tracking
#     - Easier to manage and inspect
#   ntuple dst-port drop is useful for high packet rate attacks on known
#   ports, dropping packets before they reach the kernel network stack.
#
# =============================================================================
# NOTES
# =============================================================================
#
# LRO (Large Receive Offload) is intentionally left OFF on all NICs.
# LRO modifies packet headers in ways that break IP forwarding and routing.
# GRO is the forwarding-safe alternative and is enabled by default.
#
# Broadcom BCM57416 NetXtreme-E NICs have excellent defaults already enabled:
#   - rx-gro-hw: Hardware-accelerated GRO for better CPU efficiency
#   - hw-tc-offload: Traffic control offload to hardware (qdiscs, filters)
#   - ntuple-filters: Flow steering already enabled
#
# =============================================================================

{ pkgs, lib, ... }:

let
  # NIC configurations: interface name -> settings
  nicConfigs = {
    # Intel X710 (i40e driver) - 10GbE SFP+
    enp35s0f0np0 = {
      description = "Intel X710 port 0";
      ringRx = 8160;
      ringTx = 8160;
      channels = 8;
      offload = [ "rx-udp-gro-forwarding on" ];
    };
    enp35s0f1np1 = {
      description = "Intel X710 port 1";
      ringRx = 8160;
      ringTx = 8160;
      channels = 8;
      offload = [ "rx-udp-gro-forwarding on" ];
    };

    # Intel 82599ES (ixgbe driver) - 10GbE SFI/SFP+
    enp66s0f0 = {
      description = "Intel 82599ES port 0";
      ringRx = 8192;
      ringTx = 8192;
      channels = 8;
      offload = [ "ntuple on" "rx-udp-gro-forwarding on" ];
      # ntuple filter rules: drop packets in hardware before reaching kernel
      ntupleRules = [
        # Block Windows RPC/SMB - never want these on a Linux server
        "flow-type tcp4 dst-port 135 action -1"   # MS-RPC
        "flow-type tcp4 dst-port 445 action -1"   # SMB
        "flow-type udp4 dst-port 137 action -1"   # NetBIOS NS
        "flow-type udp4 dst-port 138 action -1"   # NetBIOS DGM
        "flow-type tcp4 dst-port 139 action -1"   # NetBIOS
      ];
    };
    enp66s0f1 = {
      description = "Intel 82599ES port 1";
      ringRx = 8192;
      ringTx = 8192;
      channels = 8;
      offload = [ "ntuple on" "rx-udp-gro-forwarding on" ];
      ntupleRules = [
        "flow-type tcp4 dst-port 135 action -1"   # MS-RPC
        "flow-type tcp4 dst-port 445 action -1"   # SMB
        "flow-type udp4 dst-port 137 action -1"   # NetBIOS NS
        "flow-type udp4 dst-port 138 action -1"   # NetBIOS DGM
        "flow-type tcp4 dst-port 139 action -1"   # NetBIOS
      ];
    };

    # Broadcom BCM57416 NetXtreme-E (bnxt_en driver) - 10GbE RDMA
    # Card physically removed due to high idle temps (87°C causing fan noise)
    # enp4s0f0np0 = {
    #   description = "Broadcom BCM57416 NetXtreme-E port 0";
    #   ringRx = 2047;
    #   ringTx = 2047;
    #   channels = 8;
    #   offload = [ "rx-udp-gro-forwarding on" ];
    # };
    # enp4s0f1np1 = {
    #   description = "Broadcom BCM57416 NetXtreme-E port 1";
    #   ringRx = 2047;
    #   ringTx = 2047;
    #   channels = 8;
    #   offload = [ "rx-udp-gro-forwarding on" ];
    # };
  };

  # Generate a systemd service for a single NIC
  mkEthtoolService = iface: cfg: {
    name = "ethtool-${iface}";
    value = {
      description = "Configure ${cfg.description} (${iface})"
        + lib.optionalString (cfg.ntupleRules or [] != [])
          " - show filters: ethtool --show-ntuple ${iface}";
      # Wait for the network device to appear before configuring
      bindsTo = [ "sys-subsystem-net-devices-${iface}.device" ];
      after = [ "sys-subsystem-net-devices-${iface}.device" ];
      # Run before network is considered online
      before = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [
          "${pkgs.ethtool}/bin/ethtool --set-ring ${iface} rx ${toString cfg.ringRx} tx ${toString cfg.ringTx}"
          "${pkgs.ethtool}/bin/ethtool --set-channels ${iface} combined ${toString cfg.channels}"
        ]
        ++ lib.optional (cfg.offload or [] != []) (
          "${pkgs.ethtool}/bin/ethtool --offload ${iface} ${lib.concatStringsSep " " cfg.offload}"
        )
        # ntuple filter rules (hardware packet filtering)
        ++ lib.map (rule:
          "${pkgs.ethtool}/bin/ethtool --config-ntuple ${iface} ${rule}"
        ) (cfg.ntupleRules or []);
      };
    };
  };

in
{
  systemd.services = lib.listToAttrs (
    lib.mapAttrsToList mkEthtoolService nicConfigs
  );
}
