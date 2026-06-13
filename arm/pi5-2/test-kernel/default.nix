# Pi 5 series-3-patched kernel.
#
# Path B (kernelPatches overlay) — same approach as the hp/* and
# laptops/t test-kernel/ dirs, just with `linux_rpi5` from
# nixos-raspberrypi as the base instead of pkgs.linuxPackages_latest.
#
# Why this works: nixos-raspberrypi's `raspberry-pi-5.base` module
# sets `boot.kernelPackages = lib.mkDefault linuxPackages_rpi5;`, so
# we can swap at normal priority. The `linux_rpi5` package itself
# accepts `kernelPatches` via `.override`, identical to upstream
# nixpkgs's kernel.
#
# Series 3 patches (pinned copies in this directory; identical to the
# v1-netdev/ files used for hp1/2/3/5 and t):
#
#   net: flow_dissector: add opt-in fast-path entry-point skeleton
#   net: flow_dissector: add eth+IPv4+{TCP,UDP} fast-path
#   net: flow_dissector: add eth+IPv6+{TCP,UDP} fast-path
#
# Risk: the patches were drafted against net-next 7.1.0-rc4 and apply
# cleanly to linuxPackages_latest 7.0.x. linux_rpi5 currently ships
# 6.12.87. If a patch context line has drifted in
# net/core/sysctl_net_core.c, Documentation/admin-guide/sysctl/net.rst,
# or include/net/flow_dissector.h between 6.12 and 7.0, patch 1 may
# reject — we'll know at build time. Fallback is a hand-edited
# 0001-series3.rpi612.patch.
#
# Revert: change configuration.nix's boot.kernelPackages line back to
# the default (drop the override). The stock kernel generation stays
# selectable in systemd-boot until garbage collected.

{ nixos-raspberrypi
, pkgs
, ...
}:

let
  basePkgs = nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system};
in
basePkgs.linux_rpi5.override {
  kernelPatches = basePkgs.linux_rpi5.kernelPatches ++ [
    {
      name = "series3-flowdis-fastpath-skeleton";
      patch = ./0001-series3.patch;
    }
    {
      name = "series3-flowdis-fastpath-ipv4";
      patch = ./0002-series3.patch;
    }
    {
      name = "series3-flowdis-fastpath-ipv6";
      patch = ./0003-series3.patch;
    }
  ];
}
