# Kernel Patches (l2)

## mq-cake-6.12-openwrt (CURRENT)

OpenWrt backport patches for kernel 6.12.x.
Source: https://github.com/openwrt/openwrt/tree/main/target/linux/generic/backport-6.12

**This is used by l2 which runs kernel 6.12.68 (stable).**

Patches (apply in order):
1. `700-01-*` - Export mq functions for reuse (creates sch_priv.h)
2. `700-02-*` - Factor out config variables into separate struct
3. `700-03-*` - Add cake_mq qdisc for using cake on mq devices
4. `700-04-*` - Share config across cake_mq sub-qdiscs
5. `700-05-*` - Share shaper state across sub-instances
6. `700-06-*` - Selftests (skipped in mq-cake-module.nix)
7. `700-07-*` - Avoid separate allocation optimization

## mq-cake-6.18.8

Multi-queue CAKE (cake_mq) patches backported from net-next to kernel 6.18.8.
Use these for kernel 6.18.x (used by machine `l`).

**Origin**: net-next commits by Toke Høiland-Jørgensen <toke@redhat.com>
- https://patch.msgid.link/20260109-mq-cake-sub-qdisc-v8-1-8d613fece5d8@redhat.com

### Key adaptations made when backporting to 6.18.8:

- **Namespace quoting**: Added quotes around `"NET_SCHED_INTERNAL"` in all
  `EXPORT_SYMBOL_NS_GPL()` and `MODULE_IMPORT_NS()` calls (required by 6.18.x)

- **cobalt_should_drop API**: 6.18.8 uses the new API that returns
  `enum skb_drop_reason` instead of bool

- **SKB freeing**: Uses `kfree_skb_reason(skb, reason)` (6.18.8 API)

## Porting to New Kernel Versions

When adapting patches for a new kernel version:

1. **Check EXPORT_SYMBOL_NS_GPL quoting** - newer kernels require quotes
2. **Check cobalt_should_drop() return type** - bool vs enum skb_drop_reason
3. **Check GSO helpers** - skb_is_gso() vs qdisc_pkt_segs()
4. **Check SKB free functions** - kfree_skb_reason() vs qdisc_dequeue_drop()
5. **Verify patch context** - cake_init() structure varies between versions

Quick test build:
```bash
git add patches/mq-cake-*/*.patch  # Stage patches for nix flakes
nix build .#nixosConfigurations.l2.config.system.build.toplevel
```

## Notes

All patch sets implement cake_mq from Linux 7.0.
Once Linux 7.0 is available in NixOS, these patches are no longer needed.
