{ config, pkgs, ... }:

{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Aligned with ~/nixos/hp/hp1/systemPackages.nix so the diagnostic
  # toolchain is identical across all xdp2 benchmark hosts. Wayland
  # / xwayland / meson / wl-clipboard etc. dropped since this host
  # is now headless.
  environment.systemPackages = with pkgs; [
    psmisc
    vim
    curl
    wget
    tcpdump
    iproute2
    # XDP / parser diagnostics — same set as the hp boxes.
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
    # snmp seems to be needed by lldpd
    net-snmp
    fastfetch
  ];
}
