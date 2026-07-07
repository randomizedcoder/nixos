# pi5 test-kernel: series4 byte-identical-descent set (patches 0001-0013 of
# kernel-patches/series4-flowdis-fastpath/) applied onto linux_rpi5 6.18 to
# validate the submission's flow_dissector code on ARM aarch64 / a 6.x base.
#
# All flow_dissector.c hunks apply cleanly across 6.x<->7.2-rc1 (patch absorbs
# the line offsets), incl. the byte-identical vxlan/geneve/gtpu descents.
# EXCLUDED on 6.x:
#   0014 FOU/GUE  - its net/ipv4/fou_core.c hook hunk (RCU-list registration)
#                   differs between 6.18 and 7.2-rc1 (a fou-module change,
#                   outside the stable flow_dissector code); validated on
#                   x86/riscv net-next + KUnit instead.
#   0015 KUnit    - test-only; already 53/53 on x86 UML.
{ nixos-raspberrypi, pkgs, ... }:
let
  basePkgs = nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system};
in
basePkgs.linux_rpi5.override {
  kernelPatches = basePkgs.linux_rpi5.kernelPatches ++ [
    {
      name = "s4-0001-gate-BPF-program-lookup-behind";
      patch = ./series4/v1-0001-net-flow_dissector-gate-BPF-program-lookup-behind.patch;
    }
    {
      name = "s4-0002-opt-in-fast-path-for-eth-IPv-4";
      patch = ./series4/v1-0002-net-flow_dissector-opt-in-fast-path-for-eth-IPv-4.patch;
    }
    {
      name = "s4-0003-add-fast-path-for-single-Eth-V";
      patch = ./series4/v1-0003-net-flow_dissector-add-fast-path-for-single-Eth-V.patch;
    }
    {
      name = "s4-0004-extend-VLAN-fast-path-to-QinQ";
      patch = ./series4/v1-0004-net-flow_dissector-extend-VLAN-fast-path-to-QinQ-.patch;
    }
    {
      name = "s4-0005-add-fast-path-for-PPPoE-sessio";
      patch = ./series4/v1-0005-net-flow_dissector-add-fast-path-for-PPPoE-sessio.patch;
    }
    {
      name = "s4-0006-add-fast-path-for-single-MPLS";
      patch = ./series4/v1-0006-net-flow_dissector-add-fast-path-for-single-MPLS-.patch;
    }
    {
      name = "s4-0007-add-fast-path-for-IP-in-IP-fam";
      patch = ./series4/v1-0007-net-flow_dissector-add-fast-path-for-IP-in-IP-fam.patch;
    }
    {
      name = "s4-0008-add-byte-identical-fast-path-f";
      patch = ./series4/v1-0008-net-flow_dissector-add-byte-identical-fast-path-f.patch;
    }
    {
      name = "s4-0009-per-shape-counters-proc-net-fl";
      patch = ./series4/v1-0009-net-flow_dissector-per-shape-counters-proc-net-fl.patch;
    }
    {
      name = "s4-0010-bound-fast-path-tunnel-recursi";
      patch = ./series4/v1-0010-net-flow_dissector-bound-fast-path-tunnel-recursi.patch;
    }
    {
      name = "s4-0011-descend-into-VXLAN-inner-flow";
      patch = ./series4/v1-0011-net-flow_dissector-descend-into-VXLAN-inner-flow.patch;
    }
    {
      name = "s4-0012-descend-into-Geneve-inner-flow";
      patch = ./series4/v1-0012-net-flow_dissector-descend-into-Geneve-inner-flow.patch;
    }
    {
      name = "s4-0013-descend-into-GTP-U-inner-flow";
      patch = ./series4/v1-0013-net-flow_dissector-descend-into-GTP-U-inner-flow.patch;
    }
  ];
}
