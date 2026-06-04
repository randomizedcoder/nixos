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
  ];
}
