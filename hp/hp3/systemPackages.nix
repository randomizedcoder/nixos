{ config, pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # $ nix search wget
  environment.systemPackages = with pkgs; [
  #  vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
  #  wget
    psmisc
    vim
    curl
    wget
    tcpdump
    iproute2
    # Mellanox 25 GbE + XDP diagnostics — required by the xdp2 nic-tune
    # systemd services and used by xdp2 docs/physical-testbed.md
    # procedures. Same tooling as the hp2/hp5 (i40e) pair so the
    # automation wrapper is identical across testbeds.
    ethtool
    bpftools
    nftables
    iptables
    pciutils
    usbutils
    iw
    wirelesstools
    wpa_supplicant
    lldpd
    #snmp seems to be needed by lldpd
    net-snmp
    fastfetch
    #
    ffmpeg-full
    # PPPoE testing for series3-flowdis-fastpath v4 netconf-pppoe.nix
    ppp
    rp-pppoe
    # design 32 real-hardware RoCEv2 integration: RDMA userspace (ibv_devices,
    # show_gids), raw-verbs baselines (qperf rc_bw/rc_lat over verbs), PTP CLI
    # (pmc/phc_ctl), and ConnectX firmware/GID tools (mstflint). rdma-core is
    # also pulled in by services.urp, listed here so it is present even with
    # the module disabled.
    rdma-core
    qperf
    linuxptp
    mstflint
  ];
}
