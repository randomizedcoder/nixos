{
  config,
  pkgs,
  ...
}:
{
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
    pciutils
    virt-manager
    pkgs.gnomeExtensions.appindicator
    iw
    wirelesstools
    wpa_supplicant
    #wpa_supplicant_ro_ssids
    lldpd
    #snmp seems to be needed by lldpd
    net-snmp
    unstable.neofetch

    # https://wiki.nixos.org/wiki/Flameshot
    #(flameshot.override { enableWlrSupport = true; })

    # hyprland
    unstable.hyprland
    swww # for wallpapers
    xdg-desktop-portal-gtk
    xdg-desktop-portal-hyprland
    xwayland
    meson
    wayland-protocols
    wayland-utils
    wl-clipboard
    wlroots

    # #
    # #nvidia
    # unstable.vdpauinfo             # sudo vainfo
    # unstable.libva-utils           # sudo vainfo
    # # https://discourse.nixos.org/t/nvidia-open-breaks-hardware-acceleration/58770/2
    # #
    # unstable.ffmpeg-full
    # #
    # # https://nixos.wiki/wiki/CUDA
    # unstable.cudatoolkit
    # unstable.linuxPackages.nvidia_x11
    # unstable.libGLU
    # unstable.libGL
  ];
}