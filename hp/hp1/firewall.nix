{ config, pkgs, ... }:

{
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # https://nixos.wiki/wiki/Firewall
  # https://scvalex.net/posts/54/
  # Use nftables instead of legacy iptables
  # The default firewall uses iptables. To use the newer nftables instead,
  # set networking.nftables.enable = true
  # Note: nftables will only be active when networking.firewall.enable = true
  # When firewall is disabled, nftables won't create any rules
  # Commands to check nftables (when firewall is enabled):
  #   sudo nft list tables
  #   sudo nft list ruleset
  #   sudo nft list table inet filter
  networking.nftables.enable = true;

  networking.firewall = {
    enable = true;
    # Allow all outbound connections (default behavior, but explicitly documented)
    # Outbound connections are allowed by default in NixOS firewall
    allowedTCPPorts = [
      22     # ssh
      5001   # iperf2
      3000   # grafana
      9090   # prometheus
      19000   # node-exporter (configured in nodeExporter.nix)
    ];
    #   allowedTCPPorts = [ 22 5001 ];
    #   #allowedUDPPortRanges = [
    #   #  { from = 4000; to = 4007; }
    #   #  { from = 8000; to = 8010; }
    #   #];
    # NixOS automagically creates stateful connection tracking, which we don't want
    # for performance reasons
    # extraCommands = ''
    # nft delete rule inet filter nixos-fw nixos-fw-accept || true
    # '';
  };

  # Allow all traffic on bridge interfaces (for satellite network emulation)
  # Trusted interfaces bypass the firewall completely - all traffic is allowed
  # This includes input, output, and forwarding traffic
  networking.firewall.trustedInterfaces = [
    "enp1s0f0"  # Bridge member interface
    "enp1s0f1"  # Bridge member interface
    "br0"       # Bridge itself
    #"enp4s0f0"  # 10GE interface (for manual configuration)
    #"enp4s0f1"  # 10GE interface (for manual configuration)
  ];

  # Disable reverse path filtering for bridge interfaces
  # This is needed for bridged traffic to work properly
  # Reverse path filtering can drop packets on bridges when source/dest are on different interfaces
  # According to the firewall module docs, this can be true, false, "strict", or "loose"
  networking.firewall.checkReversePath = false;

  # Enable forwarding filter (only works with nftables)
  # This allows the firewall to filter forwarded traffic, which is needed for bridge forwarding rules
  # When enabled, the firewall module will create a forward chain that we can extend
  networking.firewall.filterForward = true;

  # Add explicit forwarding rules for bridge interfaces using nftables
  # Equivalent to: iptables -A FORWARD -m physdev --physdev-in <interface> -j ACCEPT
  # In nftables, we use iifname (input interface name) to match the physical interface
  # Note: When both firewall module and custom nftables ruleset are used, the ruleset
  # is merged with the firewall module's rules. The trustedInterfaces should handle
  # input/output, but we need explicit forward rules for forwarding traffic.
  #
  # IMPORTANT: The forward chain must already exist (created by filterForward = true)
  # We're adding rules to the existing chain, not creating a new one
  networking.nftables.ruleset = ''
    # Allow forwarding from bridge member interfaces
    # These rules ensure traffic can be forwarded between bridge interfaces
    # The iifname match is the nftables equivalent of iptables physdev match
    table inet filter {
      chain forward {
        # Allow forwarding from bridge member interfaces (equivalent to physdev-in)
        # These rules are added to the forward chain created by the firewall module
        iifname "enp1s0f0" accept comment "Allow forwarding from bridge member enp1s0f0"
        iifname "enp1s0f1" accept comment "Allow forwarding from bridge member enp1s0f1"
        # Allow forwarding from the bridge itself
        iifname "br0" accept comment "Allow forwarding from bridge br0"
        ## Allow forwarding from 10GE interfaces
        #iifname "enp4s0f0" accept comment "Allow forwarding from 10GE interface enp4s0f0"
        #iifname "enp4s0f1" accept comment "Allow forwarding from 10GE interface enp4s0f1"
      }
    }
  '';
}