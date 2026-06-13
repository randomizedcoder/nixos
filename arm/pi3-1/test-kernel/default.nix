# Pi 3 series-3-patched kernel.
#
# Path B (kernelPatches overlay) — same shape as pi4-1's test-kernel
# (linux_rpi4 base) just swapping in `linux_rpi3` (BCM2837, Cortex-A53).
# Same series-3 patch payload as the other ARM hosts; deployed via
# the cross-compiled SD-card image cycle on the workstation, not by
# nixos-rebuild on the Pi 3 itself (894 MB of RAM and an SD-card-only
# /nix is too tight to build the kernel locally — `cc1plus` OOMs).
#
# Build via:
#   nix build path:/home/das/nixos/arm/pi3-1#nixosConfigurations.pi3-1-sdimage.config.system.build.sdImage
# Output: result/sd-image/nixos-image-rpi3-uboot.img.zst (flashable).

{ nixos-raspberrypi
, pkgs
, ...
}:

let
  basePkgs = nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system};
in
basePkgs.linux_rpi3.override {
  kernelPatches = basePkgs.linux_rpi3.kernelPatches ++ [
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
