{ config, pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  nixpkgs.config.nvidia.acceptLicense = true;

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
    #nvidia
    vdpauinfo             # sudo vainfo
    libva-utils           # sudo vainfo
    # https://discourse.nixos.org/t/nvidia-open-breaks-hardware-acceleration/58770/2
    nvidia-vaapi-driver
  ];
}