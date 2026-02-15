#
# mq-cake-module.nix
#
# Multi-queue CAKE (cake_mq) qdisc - kernel patches for scaling CAKE across multiple CPU cores
#
# mq-cake is SLATED FOR LINUX 7.0 - this module applies backport patches.
# Once kernel 7.0 is available in NixOS, this module can be removed and cake_mq used directly.
#
# What is cake_mq?
#   - Multi-queue aware variant of sch_cake that scales across multiple CPUs
#   - Installs a CAKE instance on each hardware TX queue with shared configuration
#   - Enables single global rate limit across all queues for high-speed NICs
#   - Essential for modern multi-queue NICs where single-core CAKE becomes bottleneck
#
# Sources and references:
#   - Upstream net-next commits (by Toke Høiland-Jørgensen):
#     https://patch.msgid.link/20260109-mq-cake-sub-qdisc-v8-1-8d613fece5d8@redhat.com
#   - net-next tree: https://git.kernel.org/pub/scm/linux/kernel/git/netdev/net-next.git
#   - Phoronix announcement: https://www.phoronix.com/news/Linux-7.0-CAKE-MQ
#   - Netdev presentation: https://netdevconf.info/0x19/sessions/talk/mq-cake-scaling-software-rate-limiting-across-cpu-cores.html
#   - OpenWrt backport (6.12): https://github.com/openwrt/openwrt/commit/dd79febbbe94d6b870848ef43573eef02cb0331c
#
# Patches (5 total, must be applied in order):
#   01 - Export mq functions for reuse (creates include/net/sch_priv.h, modifies net/sched/sch_mq.c)
#   02 - Factor out config variables into separate struct (modifies net/sched/sch_cake.c)
#   03 - Add cake_mq qdisc for using cake on mq devices
#   04 - Share config across cake_mq sub-qdiscs
#   05 - Share shaper state across sub-instances
#
# ============================================================================
# PATCH PORTING NOTES (for adapting to new kernel versions)
# ============================================================================
#
# When porting patches to a new kernel version, watch for these API differences:
#
# 1. EXPORT_SYMBOL_NS_GPL / MODULE_IMPORT_NS namespace quoting:
#    - Older kernels: EXPORT_SYMBOL_NS_GPL(func, NET_SCHED_INTERNAL)  (no quotes)
#    - Newer kernels: EXPORT_SYMBOL_NS_GPL(func, "NET_SCHED_INTERNAL") (quoted)
#    - Error symptom: "Assembler messages: junk at end of line, first unrecognized character is 'N'"
#    - Fix: Add quotes around namespace names in all EXPORT_SYMBOL_NS_GPL and MODULE_IMPORT_NS calls
#
# 2. cobalt_should_drop() API:
#    - Old API: returns bool, check with if (!cobalt_should_drop(...))
#    - New API: returns enum skb_drop_reason, check with:
#        reason = cobalt_should_drop(...);
#        if (reason == SKB_NOT_DROPPED_YET || !flow->head)
#    - Affects: patch 02 (hunks around line 2173-2200 in sch_cake.c)
#
# 3. GSO segment counting:
#    - net-next: qdisc_pkt_segs(skb) > 1
#    - 6.18.x:   skb_is_gso(skb)
#
# 4. SKB freeing with drop reason:
#    - net-next: qdisc_dequeue_drop(sch, skb, reason)
#    - 6.18.x:   kfree_skb_reason(skb, reason)
#
# 5. Patch context mismatches:
#    - The cake_init() function structure varies between kernel versions
#    - Check the context lines around sch->limit = 10240 and tin_mode/flow_mode initialization
#    - If patches fail to apply, regenerate from upstream commits against your target kernel
#
# Quick test build (no root needed):
#   nix build .#nixosConfigurations.l2.config.system.build.toplevel
#
# IMPORTANT: With Nix flakes, patch files must be staged in git to be visible:
#   git add patches/mq-cake-6.12-openwrt/*.patch
#
# ============================================================================
#

{ config, lib, pkgs, ... }:

let
  # Use OpenWrt 6.12 backport patches for kernel 6.12.x
  # Source: https://github.com/openwrt/openwrt/tree/main/target/linux/generic/backport-6.12
  patchDir = ./patches/mq-cake-6.12-openwrt;

  mqCakePatches = [
    {
      name = "mq-cake-01-export-mq-functions";
      patch = "${patchDir}/700-01-v7.0-net-sched-Export-mq-functions-for-reuse.patch";
    }
    {
      name = "mq-cake-02-factor-out-config";
      patch = "${patchDir}/700-02-v7.0-net-sched-sch_cake-Factor-out-config-variables-into-.patch";
    }
    {
      name = "mq-cake-03-add-cake_mq";
      patch = "${patchDir}/700-03-v7.0-net-sched-sch_cake-Add-cake_mq-qdisc-for-using-cake-.patch";
    }
    {
      name = "mq-cake-04-share-config";
      patch = "${patchDir}/700-04-v7.0-net-sched-sch_cake-Share-config-across-cake_mq-sub-q.patch";
    }
    {
      name = "mq-cake-05-share-shaper-state";
      patch = "${patchDir}/700-05-v7.0-net-sched-sch_cake-share-shaper-state-across-sub-ins.patch";
    }
    # 700-06 is selftests - skip
    {
      name = "mq-cake-07-avoid-separate-allocation";
      patch = "${patchDir}/700-07-v7.0-net-sched-cake-avoid-separate-allocation-of-struct-c.patch";
    }
  ];

in {
  options.services.mqCake = {
    enable = lib.mkEnableOption "Multi-queue CAKE (cake_mq) qdisc kernel patches";
  };

  config = lib.mkIf config.services.mqCake.enable {
    # Apply kernel patches
    boot.kernelPatches = mqCakePatches;

    # Ensure sch_cake module is loaded (cake_mq is part of the same module)
    boot.kernelModules = [ "sch_cake" ];
  };
}

#
# ============================================================================
# USAGE
# ============================================================================
#
# 1. Add to configuration.nix:
#      imports = [ ./mq-cake-module.nix ];
#      services.mqCake.enable = true;
#
# 2. Rebuild (this will recompile the kernel - takes a while):
#      sudo nixos-rebuild switch --flake .
#
# 3. Reboot to load the new kernel
#
# ============================================================================
# VERIFICATION (after reboot)
# ============================================================================
#
# Check cake_mq qdisc is available:
#   tc qdisc help cake_mq
#   # Should show: Usage: ... cake_mq [ bandwidth RATE | unlimited ]...
#
# Check module aliases:
#   modinfo sch_cake | grep alias
#   # Should show: alias: net-sch-cake_mq
#
# Check cake_mq symbols in module:
#   modinfo sch_cake | grep -E "cake_mq|NET_SCHED"
#
# ============================================================================
# APPLYING cake_mq TO AN INTERFACE
# ============================================================================
#
# Replace existing qdisc with cake_mq:
#   sudo tc qdisc replace dev eth0 root cake_mq bandwidth 1gbit
#
# View statistics:
#   tc -s qdisc show dev eth0
#
# Common options (same as regular cake):
#   sudo tc qdisc replace dev eth0 root cake_mq \
#     bandwidth 1gbit \
#     diffserv4 \
#     nat \
#     wash
#
# For ingress shaping (on IFB device):
#   sudo tc qdisc replace dev ifb0 root cake_mq bandwidth 500mbit ingress
#
# ============================================================================
# TROUBLESHOOTING
# ============================================================================
#
# "RTNETLINK answers: No such file or directory" when adding cake_mq:
#   - Module not loaded. Run: sudo modprobe sch_cake
#   - Or check if kernel has cake_mq: modinfo sch_cake | grep cake_mq
#
# Build fails with assembler errors about "junk at end of line":
#   - Namespace quoting issue. Add quotes around NET_SCHED_INTERNAL in patches.
#   - See PATCH PORTING NOTES above.
#
# Build fails with patch hunk errors:
#   - Kernel API changed. Need to regenerate patches for target kernel version.
#   - Compare your kernel's net/sched/sch_cake.c with patch expectations.
#
# Patches not picked up after editing:
#   - Nix flakes only see staged files. Run: git add patches/mq-cake-*/*.patch
#

# Example output
#
# [das@l2:~]$ uname -a
# Linux l2 6.12.68 #1-NixOS SMP PREEMPT_DYNAMIC Fri Jan 30 09:28:49 UTC 2026 x86_64 GNU/Linux

# [das@l2:~]$ tc qdisc help cake_mq
# Usage: tc qdisc [ add | del | replace | change | show ] dev STRING
#        [ handle QHANDLE ] [ root | ingress | clsact | parent CLASSID ]
#        [ estimator INTERVAL TIME_CONSTANT ]
#        [ stab [ help | STAB_OPTIONS] ]
#        [ ingress_block BLOCK_INDEX ] [ egress_block BLOCK_INDEX ]
#        [ [ QDISC_KIND ] [ help | OPTIONS ] ]

#        tc qdisc { show | list } [ dev STRING ] [ QDISC_ID ] [ invisible ]
# Where:
# QDISC_KIND := { [p|b]fifo | tbf | prio | red | etc. }
# OPTIONS := ... try tc qdisc add <desired QDISC_KIND> help
# STAB_OPTIONS := ... try tc qdisc add stab help
# QDISC_ID := { root | ingress | handle QHANDLE | parent CLASSID }

# [das@l2:~]$ modinfo sch_cake | grep alias
# alias:          net-sch-cake_mq
# alias:          net-sch-cake

# [das@l2:~]$ modinfo sch_cake | grep -E "cake_mq|NET_SCHED"
# import_ns:      NET_SCHED_INTERNAL
# alias:          net-sch-cake_mq

# [das@l2:~]$
