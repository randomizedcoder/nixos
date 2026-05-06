{ config, pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  #nixpkgs.config.nvidia.acceptLicense = true;

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
    # X710 + XDP diagnostics — required by the ethtool-* services and
    # used by xdp2 docs/physical-testbed.md procedures (2026-04-20).
    ethtool
    bpftools
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
    fastfetch
    #
    #nvidia
    #vdpauinfo             # sudo vainfo
    #libva-utils           # sudo vainfo
    # https://discourse.nixos.org/t/nvidia-open-breaks-hardware-acceleration/58770/2
    #
    ffmpeg-full
    #
    # https://nixos.wiki/wiki/CUDA
    #cudatoolkit
    #linuxPackages.nvidia_x11
    #libGLU
    #libGL
  ];
}
