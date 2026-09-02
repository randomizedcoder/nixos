#
# ~/nixos/super/disko-super.nix
#
# Parameterized disko layout for the NFB super-a..d nodes (nixos-anywhere).
# UNIFORM 4-tier layout only; per-node extras (super-a /backup + Prometheus,
# super-c reserved Intel) are added in the per-node ./disko.nix.
#
# Supersedes zfs_design_2025_10_08 (which predates the on-site SATADOMs and the
# controller-WriteBack/BBU analysis). Differences: ext4 root (NixOS generations
# already give OS rollback; ARC stays 100% for data), boot on the SATADOM, and
# the single NVMe goes entirely to the DATA pool as special+L2ARC (no SLOG —
# redundant with the SAS3108 CVPM02 BBU cache). Good ZFS tuning kept from the
# Oct design: xattr=sa, acltype=posixacl, special_small_blocks=16K,
# redundant_metadata=most, ch-tmp sync=disabled. Full rationale:
# nfb-ladc-asa01/super-node-storage-layout-design.md.
#
# Roles (uniform on every node):
#   satadom  PCH sSATA 64 GB DOM   → GPT: ESP(/boot, vfat)   [UEFI/systemd-boot; boot only]
#   samsung  Samsung 870 90% VD    → GPT split:
#              part os   (600 GB)  → LVM vg 'sys': swap(64G) + /var(300G ext4) + /(rest ext4)
#              part data (rest)    → zpool 'tank' DATA vdev (stripe w/ micron)
#   micron   Micron 5200 90% VD    → zpool 'tank' DATA vdev
#   nvme     NVMe (uniform)        → zpool 'tank': part special(70%) + part cache/L2ARC(30%)
#
# 'tank' = 2-way data stripe (samsung-slice + micron) + special + L2ARC (both on NVMe).
# Datasets: tank/clickhouse, tank/clickhouse-tmp, tank/kafka (ClickHouse + Redpanda).
#
# IMPORTANT before running:
#   * The 90% RAID0 VDs are created FIRST by storcli-90pct-vds.sh, NOT by disko.
#   * The NVMe special vdev is a SINGLE device = SPOF for the WHOLE pool. Accepted.
#   * Pass every device as a STABLE /dev/disk/by-id/... path (read on the booted
#     installer: `ls -l /dev/disk/by-id`). Never /dev/sdX — order isn't stable.
#
{ satadom                 # "/dev/disk/by-id/ata-SATADOM-SL_3ME_..."
, samsung                 # "/dev/disk/by-id/scsi-<samsung-90pct-VD>"
, micron                  # "/dev/disk/by-id/scsi-<micron-90pct-VD>"
, nvme                    # "/dev/disk/by-id/nvme-<model>_..."
, pool        ? "tank"
, osSliceSize ? "600G"    # Samsung part1 = OS (swap+var+root); rest → tank
, swapSize    ? "64G"
, varSize     ? "300G"
, specialSize ? "650G"    # NVMe: special vdev size (~70% of a 931 GiB NVMe); L2ARC = rest.
                          # ABSOLUTE size (not a %) — the target's sgdisk does not honour the
                          # "70%" start/end syntax (parses it as sector 70), so use sizes +
                          # explicit `priority` so `special` is laid down first.
, kafka       ? true      # include tank/kafka (Redpanda). false = ClickHouse only.
}:
{
  disko.devices = {
    disk = {
      # ---- SATADOM: /boot (UEFI ESP, systemd-boot) ----------------------
      satadom = {
        type = "disk";
        device = satadom;
        content = {
          type = "gpt";
          # /boot only. 4 GiB comfortably holds ~15 systemd-boot generations
          # (kernel+initrd). The rest of the 64 GB DOM is left UNPARTITIONED —
          # i.e. the SATADOM is already ~93% spare (host over-provisioning) with
          # zero effort, so no "90% VD" is needed here (that trick is for the
          # otherwise-full MegaRAID data SSDs). ESP size doesn't affect wear;
          # write volume is driven by rebuild frequency, not partition size.
          partitions.ESP = {
            name = "ESP";
            size = "4G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
        };
      };

      # ---- Samsung 90% VD: OS slice (LVM ext4) + tank data slice --------
      samsung = {
        type = "disk";
        device = samsung;
        content = {
          type = "gpt";
          partitions = {
            os = {
              size = osSliceSize;
              content = { type = "lvm_pv"; vg = "sys"; };
            };
            zfs = {
              size = "100%";
              content = { type = "zfs"; pool = pool; };   # tank data vdev (partlabel disk-samsung-zfs)
            };
          };
        };
      };

      # ---- Micron 90% VD: tank data vdev -------------------------------
      micron = {
        type = "disk";
        device = micron;
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = { type = "zfs"; pool = pool; };      # tank data vdev (partlabel disk-micron-zfs)
          };
        };
      };

      # ---- NVMe: tank special (specialSize) + L2ARC cache (rest) -------
      # Both are pool=tank members; their vdev ROLE (special vs cache) is set in
      # the zpool topology below, referenced by GPT partlabel (disk-nvme-<part>).
      # `priority` forces creation order (disko otherwise sorts partitions
      # alphabetically -> "cache" before "special", which with size="100%" would
      # eat the whole disk). special first (takes the start), cache takes the rest.
      nvme = {
        type = "disk";
        device = nvme;
        content = {
          type = "gpt";
          partitions = {
            special = {
              priority = 1;                                # created FIRST
              size = specialSize;
              content = { type = "zfs"; pool = pool; };    # partlabel disk-nvme-special
            };
            cache = {
              priority = 2;                                # created SECOND (remainder)
              size = "100%";
              content = { type = "zfs"; pool = pool; };    # partlabel disk-nvme-cache
            };
          };
        };
      };
    };

    lvm_vg.sys = {
      type = "lvm_vg";
      lvs = {
        swap = {
          size = swapSize;
          content = { type = "swap"; resumeDevice = true; };
        };
        var = {
          size = varSize;
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/var"; };
        };
        root = {
          size = "100%FREE";
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
        };
      };
    };

    zpool.${pool} = {
      type = "zpool";
      # Topology: two single-disk DATA vdevs (samsung-slice + micron) = stripe,
      # plus the NVMe as SPECIAL (metadata/small-blocks) and CACHE (L2ARC).
      # Bare members auto-resolve to /dev/disk/by-partlabel/disk-<name>-zfs;
      # the NVMe roles use full partlabels since one disk holds two partitions.
      mode = {
        topology = {
          type = "topology";
          vdev = [
            { members = [ "samsung" ]; }   # → disk-samsung-zfs
            { members = [ "micron" ]; }    # → disk-micron-zfs
          ];
          special = [ { members = [ "/dev/disk/by-partlabel/disk-nvme-special" ]; } ];
          cache = [ "/dev/disk/by-partlabel/disk-nvme-cache" ];  # L2ARC (listOf str)
        };
      };
      options = { ashift = "12"; autoreplace = "on"; };
      rootFsOptions = {
        mountpoint = "none";           # tank itself isn't mounted; datasets are
        compression = "zstd";
        atime = "off";
        xattr = "sa";
        acltype = "posixacl";
        redundant_metadata = "most";
        special_small_blocks = "16K";  # push metadata + <16K blocks onto the NVMe special
      };
      datasets = {
        # ClickHouse primary data.
        clickhouse = {
          type = "zfs_fs";
          mountpoint = "/var/lib/clickhouse";
          options = {
            recordsize = "1M";
            logbias = "throughput";
            compression = "zstd";
            primarycache = "all";
            secondarycache = "all";        # let L2ARC help CH reads
            special_small_blocks = "16K";
          };
        };
        # ClickHouse tmp/scratch — OK to lose on power loss.
        clickhouse-tmp = {
          type = "zfs_fs";
          mountpoint = "/var/lib/clickhouse/tmp";
          options = {
            recordsize = "1M";
            compression = "lz4";
            sync = "disabled";              # tmp only
            primarycache = "metadata";
            secondarycache = "none";
          };
        };
      } // (if !kafka then { } else {
        # Redpanda (Kafka) log store.
        kafka = {
          type = "zfs_fs";
          mountpoint = "/var/lib/redpanda";
          options = {
            recordsize = "1M";              # large sequential log segments
            compression = "lz4";
            logbias = "throughput";
            sync = "standard";              # let the app/fsync decide durability
            primarycache = "metadata";      # don't pollute ARC with write-only data
            secondarycache = "none";        # keep it out of L2ARC
          };
        };
      });
    };
  };
}
