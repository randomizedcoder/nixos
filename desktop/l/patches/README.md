# Kernel Patches

## mq-cake-6.18.8 (CURRENT)

Multi-queue CAKE (cake_mq) patches backported from net-next to kernel 6.18.8.
These are the working patches used by `mq-cake-module.nix`.

**Origin**: net-next commits by Toke Høiland-Jørgensen <toke@redhat.com>
- https://patch.msgid.link/20260109-mq-cake-sub-qdisc-v8-1-8d613fece5d8@redhat.com (and subsequent patches)

Patches (apply in order):
1. `01-export-mq-functions.patch` - Export mq functions for reuse (creates sch_priv.h)
2. `02-factor-out-config.patch` - Factor out config variables into separate struct
3. `03-add-cake_mq.patch` - Add cake_mq qdisc for using cake on mq devices
4. `04-share-config.patch` - Share config across cake_mq sub-qdiscs
5. `05-share-shaper-state.patch` - Share shaper state across sub-instances

### Key adaptations made when backporting to 6.18.8:

- **Namespace quoting**: Added quotes around `"NET_SCHED_INTERNAL"` in all
  `EXPORT_SYMBOL_NS_GPL()` and `MODULE_IMPORT_NS()` calls (required by 6.18.x)

- **cobalt_should_drop API**: 6.18.8 uses the new API that returns
  `enum skb_drop_reason` instead of bool. Hunks updated to use:
  ```c
  reason = cobalt_should_drop(...);
  if (reason == SKB_NOT_DROPPED_YET || !flow->head)
  ```

- **SKB freeing**: Uses `kfree_skb_reason(skb, reason)` (6.18.8 API)

## mq-cake-net-next

Raw patches extracted directly from net-next tree (Linux 7.0 development).
These do NOT apply cleanly to 6.18.x without modifications because net-next
has additional changes not present in 6.18.x:
- Uses `qdisc_pkt_segs(skb) > 1` (net-next has this, 6.18.x uses `skb_is_gso()`)
- Uses `qdisc_dequeue_drop()` (net-next API, not in 6.18.x)
- Different code structure in `cake_init()` function
- Different patch context lines due to other net-next changes

The `mq-cake-6.18.8/` patches are the adapted versions of these for 6.18.x.

## mq-cake-6.18-rc6-old

Original patches from mq-cake-selftest branch (based on 6.18-rc6).
These DON'T apply cleanly to 6.18.8 due to changes in cake_enqueue().
Kept for historical reference only.

## mq-cake-6.12-openwrt

Patches from OpenWrt backport-6.12 directory.
Source: https://github.com/openwrt/openwrt/tree/main/target/linux/generic/backport-6.12
Use these for kernel 6.12.x only.

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
nix build .#nixosConfigurations.l.config.system.build.toplevel
```

## Notes

All patch sets implement cake_mq from Linux 7.0.
Once Linux 7.0 is available in NixOS, these patches are no longer needed.
