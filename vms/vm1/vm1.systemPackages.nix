{ config, pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    psmisc
    vim
    curl
    tcpdump
    iproute2
    nftables
    pciutils
    lldpd
    #snmp seems to be needed by lldpd
    net-snmp
  ];
}