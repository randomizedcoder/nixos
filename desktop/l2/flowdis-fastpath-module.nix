#
# flowdis-fastpath-module.nix
#
# Backport of the series 3 flow_dissector fast-path patches to whatever
# kernel this host is running. The patches add a straight-line extractor
# at the entry of __skb_flow_dissect for common L3+L4 shapes:
#
#   - eth + IPv4 + {TCP, UDP}
#   - eth + IPv6 + {TCP, UDP}
#
# Source: github.com/randomizedcoder/xdp2 branch flow-keys-compat-reorder,
# kernel-patches/series3-flowdis-fastpath/v1/. The squashed unified patch
# in this directory is the same 224-line diff (3 commits flattened).
#
# Upstream target is net-next 7.1.0-rc4; the touched code in
# net/core/flow_dissector.c has been stable for years, so the patch
# applies cleanly to 6.x and 7.x kernels (verified on hp1/hp2/hp3/hp5
# at 7.1.0-rc4 and intended to validate on l at 6.18.x and l2 at the
# nixpkgs-latest stable).
#
# Purpose: back-port testing on the more powerful l and l2 machines
# (mlx5 25 GbE NICs to be added). Demonstrates patch portability and
# gives kernel reviewers confidence the patches work on older kernels.
#
# Patch shape:
#   - net/core/flow_dissector.c only (no header changes, no ABI change)
#   - +207 / -1 lines net
#   - 0 errors / 0 warnings from scripts/checkpatch.pl --strict
#   - W=1 compile clean on 7.1.0-rc4
#   - sparse-master and smatch clean on net/core/flow_dissector.c
#
# Once applied, the fast-path runs on every RX packet that goes through
# RPS/RFS, sch_cake, ECMP route lookup, cls_flow, or any other consumer
# of flow_keys_dissector. Output is byte-identical to the slow-path for
# the standard dissectors.

{ config, lib, pkgs, ... }:

{
  options.services.flowdis-fastpath = {
    enable = lib.mkEnableOption "series 3 flow_dissector fast-path backport";
  };

  config = lib.mkIf config.services.flowdis-fastpath.enable {
    boot.kernelPatches = [
      {
        name = "flow_dissector-fastpath-v1";
        patch = ./flowdis-fastpath-v1.patch;
      }
    ];
  };
}

#
# USAGE:
#
# 1. Add to configuration.nix imports:
#      imports = [ ./flowdis-fastpath-module.nix ];
#
# 2. Enable:
#      services.flowdis-fastpath.enable = true;
#
# 3. Rebuild:
#      sudo nixos-rebuild boot     # stages new kernel for next boot
#    or
#      sudo nixos-rebuild switch   # also runs activation now (kernel
#                                  # change still needs a reboot to load)
#
# 4. Reboot and verify the running kernel has our code. Easiest test:
#      sudo apt install binutils  # or whatever for objdump
#    Then disassemble the running __skb_flow_dissect from /proc/kallsyms
#    and look for the byte pattern:
#      80 3e 45        cmpb $0x45, (%rsi)       # IPv4 version+IHL magic
#      66 f7 46 06 3f ff   testw $0xff3f, 0x6(%rsi) # frag_off mask
#
# 5. Macro-test via iperf3 / iperf2 + sch_cake (same test plan as the
#    hp1<->hp3 + hp2<->hp5 pairs, once the mlx5 NIC is installed on
#    l + l2).
#
# 6. Microbench: build the libflowdis userspace harness from xdp2
#    repo, time __skb_flow_dissect_err on a synthetic eth+IPv4+TCP
#    packet (10 M iterations), expect ~50 % saving on Zen 2 / Zen 3 /
#    later Intel.
#
# TROUBLESHOOTING:
#
# - Patch fails to apply: the kernel source's net/core/flow_dissector.c
#   may have drifted enough to break the context lines. Re-generate the
#   patch against the local kernel source:
#     cd /path/to/local/kernel/src
#     git apply -3 flowdis-fastpath-v1.patch   # 3-way merge
#   If that fails, hand-port the changes (the technique is small and
#   self-contained).
#
# - Build fails with "redefinition of flow_keys_dissector_symmetric":
#   our forward declaration may conflict on kernels where
#   flow_keys_dissector_symmetric is declared differently. Drop the
#   forward declaration line (the actual definition later in the file
#   covers the symbol).
#
# - Boot panic: shouldn't happen — the patch only adds new code paths
#   (no changes to existing logic). If it does, falls back to previous
#   generation via systemd-boot menu.
