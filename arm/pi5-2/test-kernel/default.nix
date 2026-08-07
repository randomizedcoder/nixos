# pi5 test-kernel: series5 STATE RFC (fastpath 0001-0009 + auto controller
# renumbered 0010) on linux_rpi5 6.18. KUnit/docs excluded (test/doc-only).
{ nixos-raspberrypi, pkgs, ... }:
let
  basePkgs = nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system};
in
basePkgs.linux_rpi5.override {
  kernelPatches = basePkgs.linux_rpi5.kernelPatches ++ [
    {
      name = "s5rfc-0001-net-flow_dissector-gate-BPF-program-looku";
      patch = ./series5-rfc/v1-0001-net-flow_dissector-gate-BPF-program-lookup-behind.patch;
    }
    {
      name = "s5rfc-0002-net-flow_dissector-opt-in-fast-path-for-e";
      patch = ./series5-rfc/v1-0002-net-flow_dissector-opt-in-fast-path-for-eth-IPv-4.patch;
    }
    {
      name = "s5rfc-0003-net-flow_dissector-add-fast-path-for-VLAN";
      patch = ./series5-rfc/v1-0003-net-flow_dissector-add-fast-path-for-VLAN-and-Qin.patch;
    }
    {
      name = "s5rfc-0004-net-flow_dissector-add-fast-path-for-PPPo";
      patch = ./series5-rfc/v1-0004-net-flow_dissector-add-fast-path-for-PPPoE-sessio.patch;
    }
    {
      name = "s5rfc-0005-net-flow_dissector-add-fast-path-for-sing";
      patch = ./series5-rfc/v1-0005-net-flow_dissector-add-fast-path-for-single-MPLS-.patch;
    }
    {
      name = "s5rfc-0006-net-flow_dissector-add-fast-path-for-IP-i";
      patch = ./series5-rfc/v1-0006-net-flow_dissector-add-fast-path-for-IP-in-IP-fam.patch;
    }
    {
      name = "s5rfc-0007-net-flow_dissector-add-byte-identical-fas";
      patch = ./series5-rfc/v1-0007-net-flow_dissector-add-byte-identical-fast-path-f.patch;
    }
    {
      name = "s5rfc-0008-net-flow_dissector-per-shape-counters-pro";
      patch = ./series5-rfc/v1-0008-net-flow_dissector-per-shape-counters-proc-net-fl.patch;
    }
    {
      name = "s5rfc-0009-net-flow_dissector-bound-fast-path-tunnel";
      patch = ./series5-rfc/v1-0009-net-flow_dissector-bound-fast-path-tunnel-recursi.patch;
    }
    {
      name = "s5rfc-0010-net-flow_dissector-adaptive-auto-enable-p";
      patch = ./series5-rfc/v1-0010-net-flow_dissector-adaptive-auto-enable-packet-wi.patch;
    }
  ];
}
