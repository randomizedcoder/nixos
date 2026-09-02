#
# ~/nixos/super/zfs.nix
#
# Shared ZFS module for the super-a..d nodes. Root is ext4 (LVM); ZFS is the
# DATA pool `tank` (ClickHouse + Redpanda) — see disko-super.nix + the design
# doc. This module handles ZFS module/userspace, ARC sizing, and pool services.
#
# NOTE: `networking.hostId` is REQUIRED for ZFS and must be UNIQUE per node —
# it lives in each node's ./host.nix, not here.
#
{ config, lib, pkgs, ... }:

{
  boot.supportedFilesystems = [ "zfs" ];
  # Root is ext4, not ZFS — don't force-import a root pool.
  boot.zfs.forceImportRoot = false;
  # Import the data pool at boot (disko also wires the dataset fileSystems).
  boot.zfs.extraPools = [ "tank" ];

  ##############################################################################
  # ARC sizing (uniform 128 GiB assumption; node-A physically has 256 GiB but is
  # treated as 128 GiB, so its extra RAM is simply free). Fixed BYTES, not a %,
  # so the cap is identical on every node regardless of installed RAM.
  #
  #   zfs_arc_max = 32 GiB = 34359738368   (leave ~80 GiB for ClickHouse, ~16 GiB OS)
  #   zfs_arc_min = 16 GiB = 17179869184
  #
  # Tune after observing ClickHouse memory + scan behaviour. Keep ClickHouse's
  # max_server_memory_usage ABSOLUTE (~80G), not the RAM ratio, or node-A's
  # 256 GiB would hand it ~2x and blow the budget.
  ##############################################################################
  boot.extraModprobeConfig = ''
    options zfs zfs_arc_max=34359738368
    options zfs zfs_arc_min=17179869184
    # Cache prefetched (sequential) data in L2ARC — helps OLAP re-scans.
    options zfs l2arc_noprefetch=0
  '';

  # Weekly scrub + periodic TRIM (all-SSD pool behind the SAS3108).
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  # ZFS event daemon (fault handling / notifications).
  services.zfs.zed.settings = {
    ZED_DEBUG_LOG = "/var/log/zed.debug.log";
  };
}
