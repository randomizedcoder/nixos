{
  config,
  pkgs,
  ...
}:
{
  # nixpkgs.config.allowUnfree is set at flake.nix level

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

    # Screen capture and PipeWire debugging
    grim
    slurp
    wf-recorder
    pipewire
    xdg-desktop-portal-gnome

    xscreensaver

    clinfo
    lact

    # https://wiki.nixos.org/wiki/Flameshot
    #(flameshot.override { enableWlrSupport = true; })

    # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/hardware/fancontrol.nix
    lm_sensors
    liquidctl
    jq

    rdma-core # ibv_devinfo, rdma
    pciutils
    libpciaccess
  ];
}
