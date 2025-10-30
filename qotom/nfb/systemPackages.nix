#
# nixos/qotom/nfb/systemPackages.nix
#
# This system is shared by users in the eng team.  Rather than installing packages for each user, install them here.

{ config, pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # $ nix search wget
  environment.systemPackages = with pkgs; [

    psmisc
    vim
    curl
    wget
    tcpdump
    iproute2
    nftables
    # sudo conntrack -L
    conntrack-tools
    lsof
    pciutils
    usbutils
    lshw
    hwloc
    net-tools

    lldpd
    #snmp seems to be needed by lldpd
    net-snmp

    tmux
    screen

    killall

    git
    gnumake42

    file

    neofetch

    tcpdump
    nmap
    iperf2
    flent
    netperf
    ethtool
    inetutils
    sysstat
    netcat
    htop
    btop
    dig

    rsync

    shellcheck

    minicom

    #silly
    cmatrix
    sl
  ];
}