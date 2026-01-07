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
    below
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

    clinfo
    lact

    rdma-core # ibv_devinfo, rdma
    pciutils
    libpciaccess

    # Blackmagic DeckLink
    blackmagic-desktop-video

    # Video tools
    v4l-utils    # v4l2-ctl
    ffmpeg-full

    # GStreamer with DeckLink support
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad   # includes decklink plugin
    gst_all_1.gst-plugins-ugly
  ];
}

# end
