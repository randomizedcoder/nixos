# hp* series-3-patched kernel.
#
# Path B (kernelPatches overlay) supersedes the prior Path A
# (linuxKernel.manualConfig with a custom net-next src + reconciled
# .config). Rationale captured in the t laptop's test-kernel/
# default.nix (laptops/t/test-kernel/default.nix); short version:
# `net/core/flow_dissector.c` has not changed in the hunks the 3
# series-3 patches touch between 7.0.x and 7.1.0-rc4, so applying
# them as a kernelPatches overlay against pkgs.linuxPackages_latest
# is correct and far less elaborate than the manualConfig pattern.
#
# Migration history:
#   - 2026-05-27..28  Path A used for series 3 v1 RFC Phase 1-4
#                     testing on hp1/hp2/hp3/hp5 (built from
#                     /home/das/Downloads/net-next at branch
#                     flowdis-fastpath-rfc, HEAD eeca3eb493b8;
#                     shipped hp5-kernel.config reconciled to
#                     7.1.0-rc4 via make olddefconfig).
#   - 2026-06-04..05  Path B validated end-to-end on t (Comet
#                     Lake-H), then propagated here. All four hp
#                     hosts have identical test-kernel/ contents,
#                     so this single file is byte-identical across
#                     hp1/hp2/hp3/hp5.
#
# Functional impact of the migration: same 3 patches applied; the
# base kernel switches from net-next at c0aa5f13826d (7.1.0-rc4) to
# pkgs.linuxPackages_latest (currently 7.0.10). The patched
# flow_dissector.c code is byte-identical between the two builds;
# everything else in the kernel (drivers, scheduler, fs, mm) is the
# upstream stable 7.0.10 instead of net-next development tip. The
# Phase 4 macro-test results captured under the 7.1.0-rc4 build
# remain valid as a one-time data point for the net-next tip; new
# measurements under this build can be cross-referenced.
#
# Series 3 patches (from xdp2 kernel-patches/series3-flowdis-fastpath/
# v1-netdev/, pinned copies live in this directory):
#
#   1ddc620812be  net: flow_dissector: add fast-path entry-point skeleton
#   080196491134  net: flow_dissector: add eth+IPv4+{TCP,UDP} fast-path
#   eeca3eb493b8  net: flow_dissector: add eth+IPv6+{TCP,UDP} fast-path
#
# Revert: change configuration.nix's boot.kernelPackages back to
# `pkgs.linuxPackages_latest`. The stock kernel generation stays
# selectable in systemd-boot until garbage collected.

{ linuxPackages_latest, ... }:

linuxPackages_latest.kernel.override {
  kernelPatches = linuxPackages_latest.kernel.kernelPatches ++ [
    # v3 of the series, taken from github.com/randomizedcoder/xdp2
    # kernel-patches/series3-flowdis-fastpath/v3-namespace/.
    # Supersedes the prior 6 patches (parent series3 + 3 extensions).
    # All four ship per-shape sysctls under /proc/sys/net/flow_dissector/.
    {
      name = "v3-flow_dissector-eth-ip";
      patch = ./0001-v3-eth-ip.patch;
    }
    {
      name = "v3-flow_dissector-vlan";
      patch = ./0002-v3-vlan.patch;
    }
    {
      name = "v3-flow_dissector-qinq";
      patch = ./0003-v3-qinq.patch;
    }
    {
      name = "v3-flow_dissector-vxlan-inner-RFC-EXPERIMENT";
      patch = ./0004-v3-vxlan-inner.patch;
    }
  ];
}
