{
  config,
  pkgs,
  ...
}:
{
  # set at flake.nix level
  nixpkgs.config.allowUnfree = true;

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
    iptables
    pciutils
    usbutils
    iw
    wirelesstools
    wpa_supplicant
    lldpd
    #snmp seems to be needed by lldpd
    net-snmp
    neofetch
    libxml2  # Added for bazel/clang development

    clinfo
    lact

    hostapd
    bridge-utils
    wireless-regdb
    linux-firmware

  ];
}
