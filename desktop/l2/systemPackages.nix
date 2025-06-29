#
# l2/systemPackages.nix
#
{
  config,
  pkgs,
  ...
}:
{
  # $ nix search wget
  environment.systemPackages = with pkgs; [

    # Basic system tools
    psmisc
    vim
    curl
    wget
    tcpdump
    iproute2
    nftables
    #iptables
    pciutils
    usbutils
    iw
    wirelesstools
    #wpa_supplicant
    lldpd
    #snmp seems to be needed by lldpd
    net-snmp
    neofetch


    hostapd
    bridge-utils
    wireless-regdb
    linux-firmware

    # Network testing and performance tools
    iperf2
    flent
    netperf
    ethtool
    sysstat
    htop
    iftop
    nethogs
    nload
    speedtest-cli
    mtr
    traceroute
    nmap
    tshark
    perf-tools
    linuxPackages_latest.perf
  ];
}

# end