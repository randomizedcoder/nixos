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
    fastfetch
    #neofetch is no more

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
    perf

    clinfo
    lact

    # GPU monitoring (supports AMD and NVIDIA)
    nvtopPackages.full

    # 2026-06-14: CUDA 12 toolkit system-wide for the Quadro P620.
    # Pinned to cudaPackages_12 because cudaPackages_13 dropped sm_61
    # (Pascal). After rebuild: `nvcc --version`, `nvidia-smi`.
    # nixpkgs metapackage `cudatoolkit` bundles nvcc + libs + samples
    # (~3 GB); if disk is tight, swap to the per-component picks
    # below (nvcc + cudart only is ~600 MB).
    cudaPackages_12.cudatoolkit
    #cudaPackages_12.cuda_nvcc
    #cudaPackages_12.cuda_cudart

    rdma-core # ibv_devinfo, rdma
    mstflint  # Mellanox firmware tools (mstconfig to allow third-party SFPs)
    pciutils
    libpciaccess

    # # Blackmagic DeckLink
    # blackmagic-desktop-video

    # # Video tools
    # v4l-utils    # v4l2-ctl
    # ffmpeg-full

    # # GStreamer with DeckLink support
    # gst_all_1.gstreamer
    # gst_all_1.gst-plugins-base
    # gst_all_1.gst-plugins-good
    # gst_all_1.gst-plugins-bad   # includes decklink plugin
    # gst_all_1.gst-plugins-ugly
  ];
}

# end
