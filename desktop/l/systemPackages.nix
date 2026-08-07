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
    sysstat
    psmisc
    vim
    curl
    wget
    tcpdump
    iperf3  # series-3 flow_dissector test orchestrators drive iperf3
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
    mstflint  # Mellanox firmware tools (mstconfig to allow third-party SFPs)
    pciutils
    libpciaccess
  ];
}
