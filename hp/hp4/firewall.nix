{ config, pkgs, ... }:

{
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # https://nixos.wiki/wiki/Firewall
  # https://scvalex.net/posts/54/
  # sudo nft --stateless list table filter
  # sudo sudo iptables-save
  networking.firewall = {
    enable = false;
    allowedTCPPorts = [
      #22     # ssh
      3000   # grafana
      3128   # TrafficServer Forward Proxy
      #5000  # opened by services.nix-serve.openFirewall = true;
      5001   # iperf2
      8080   # Nginx reverse proxy
      8443   # Nginx reverse proxy TLS
      8888   # athens
      9090   # prometheus
      # 9100 is opened by services.prometheus.exporters.node.openFirewall = true;
      # 9113 is opened by services.prometheus.exporters.nginx.openFirewall = true;
    ];
    allowedUDPPorts = [
      161    # SNMP (No openFirewall option in definition)
    ];
    #   allowedTCPPorts = [ 22 5001 ];
    #   #allowedUDPPortRanges = [
    #   #  { from = 4000; to = 4007; }
    #   #  { from = 8000; to = 8010; }
    #   #];
    # NixOS automagically creates stateful connection tracking, which we don't want
    # for performance reasons
    # extraCommands = ''
    # iptables --delete nixos-fw -m conntrack --ctstate RELATED,ESTABLISHED -j nixos-fw-accept || true
    # '';
  };
  # networking.firewall.interfaces."eth0".allowedTCPPorts = [ 80 443 ];
}