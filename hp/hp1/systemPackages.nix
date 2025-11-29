{
  config,
  pkgs,
  ...
}:
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
    nftables
    iptables
    pciutils
    usbutils
    iw
    wirelesstools
    wpa_supplicant
    #wpa_supplicant_ro_ssids
    lldpd
    #snmp seems to be needed by lldpd
    net-snmp
    neofetch
    #
    ffmpeg-full
    radeontop  # GPU monitoring tool
    # https://nixos.wiki/wiki/AMD_GPU#OpenCL
    clinfo
    #
    bridge-utils
  ];
}
