# t's series-3-patched kernel.
#
# Instead of the heavier hp3 pattern (linuxKernel.manualConfig with
# a custom net-next src + a reconciled .config), this overlay just
# takes pkgs.linuxPackages_latest.kernel and applies the 3 series-3
# patches on top:
#
#   1ddc620812be  net: flow_dissector: add fast-path entry-point skeleton
#   080196491134  net: flow_dissector: add eth+IPv4+{TCP,UDP} fast-path
#   eeca3eb493b8  net: flow_dissector: add eth+IPv6+{TCP,UDP} fast-path
#
# Patches are pinned copies of
#   xdp2/kernel-patches/series3-flowdis-fastpath/v1-netdev/000{1,2,3}-*.patch
# (the send-ready variant). They were drafted against net-next
# c0aa5f13826d (7.1.0-rc4 base); they apply cleanly to recent
# linuxPackages_latest because net/core/flow_dissector.c has not
# diverged in the affected hunks.
#
# Why this lives in laptops/t/ rather than alongside hp3:
#   t is the high-end Intel Comet Lake-H data point and the only
#   second-vendor confirmation of the series 3 microbench win
#   (xdp2 perf-results/2026-06-04-series3-phase3-t/results.md).
#   Boot-clean validation on Comet Lake-H + a libflowdis result on
#   the same uarch makes t the cleanest single-host story.
#
# Usage:
#   { pkgs, ... }:
#   let customKernel = pkgs.callPackage ./test-kernel { };
#   in { boot.kernelPackages = pkgs.linuxPackagesFor customKernel; }
#
# Revert: change configuration.nix's boot.kernelPackages back to
# pkgs.linuxPackages_latest. The stock kernel generation stays in
# systemd-boot until garbage collected.

{ linuxPackages_latest, ... }:

linuxPackages_latest.kernel.override {
  kernelPatches = linuxPackages_latest.kernel.kernelPatches ++ [
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
