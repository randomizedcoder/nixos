#
# ~/nixos/super/a/disko.nix — super-a (cluster monitoring host)
#
# Uniform 4-tier layout (./disko-super.nix) + super-a's two extra SAS3108 SSDs:
#   2nd Samsung 870 (90% VD) → single-disk ZFS pool 'backup' (zstd) → /backup
#   SK hynix 512 GB (90% VD) → ext4 → /var/lib/prometheus  (super-a runs fleet Prometheus)
#
# FILL the by-id paths from the booted installer:
#   ls -l /dev/disk/by-id | grep -Ei 'samsung|micron|nvme|satadom|hynix'
# There are TWO Samsungs on super-a — match by serial (drive-inventory doc):
#   OS/tank Samsung = 252:0 (S8HSNS0L500297W);  backup Samsung = 252:5 (S753NS0Y710021P)
#
{ ... }:
{
  imports = [
    (import ./disko-super.nix {
      satadom = "/dev/disk/by-id/REPLACE-a-satadom";
      samsung = "/dev/disk/by-id/REPLACE-a-samsung-os-90pct-VD";   # 252:0
      micron  = "/dev/disk/by-id/REPLACE-a-micron-90pct-VD";        # 252:1
      nvme    = "/dev/disk/by-id/REPLACE-a-nvme";
    })
  ];

  # ---- super-a extras --------------------------------------------------
  disko.devices.disk.samsung2 = {
    type = "disk";
    device = "/dev/disk/by-id/REPLACE-a-samsung-backup-90pct-VD";   # 252:5
    content = {
      type = "gpt";
      partitions.backup = {
        size = "100%";
        content = { type = "zfs"; pool = "backup"; };
      };
    };
  };

  disko.devices.disk.skhynix = {
    type = "disk";
    device = "/dev/disk/by-id/REPLACE-a-skhynix-90pct-VD";           # 252:2
    content = {
      type = "gpt";
      partitions.prom = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/var/lib/prometheus";
        };
      };
    };
  };

  disko.devices.zpool.backup = {
    type = "zpool";
    mode = "";
    options = { ashift = "12"; };
    rootFsOptions = {
      mountpoint = "none";
      compression = "zstd";   # compress ClickHouse dumps as they land
      atime = "off";
    };
    datasets.backup = {
      type = "zfs_fs";
      mountpoint = "/backup";
    };
  };
}
