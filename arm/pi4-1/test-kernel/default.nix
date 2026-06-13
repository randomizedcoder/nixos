# Pi 4 series-3-patched kernel.
#
# Path B (kernelPatches overlay) — same as the Pi 5 test-kernel/, but
# with `linux_rpi4` as the base (Cortex-A72, BCM2711) instead of
# `linux_rpi5`. Rationale + risk notes captured in
# arm/pi5-1/test-kernel/default.nix.

{ nixos-raspberrypi
, pkgs
, ...
}:

let
  basePkgs = nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system};
in
basePkgs.linux_rpi4.override {
  kernelPatches = basePkgs.linux_rpi4.kernelPatches ++ [
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
