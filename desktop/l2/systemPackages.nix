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

    # Wayland support
    xwayland
    meson
    wayland-protocols
    wayland-utils
    wl-clipboard

    xscreensaver

    clinfo
    lact

    hostapd

    # https://wiki.nixos.org/wiki/Flameshot
    #(flameshot.override { enableWlrSupport = true; })
  ];
}
