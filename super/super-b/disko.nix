#
# ~/nixos/super/b/disko.nix — super-b (uniform 4-tier)
#
# FILL the by-id paths from the booted installer:
#   ls -l /dev/disk/by-id | grep -Ei 'samsung|micron|nvme|satadom'
# super-b NVMe = Samsung 980 1 TB.
#
{ ... }:
{
  imports = [
    # Filled 2026-09-05 from the booted installer. VDs identified by exact 90%-OP size
    # (buildout runbook §3): Samsung 870 2TB → 1676 GiB VD; Micron/Intel 1.92TB → 1608 GiB.
    #   sda  ata-SATADOM-SL_3ME_...            60 GiB  boot
    #   sdc  scsi-3600304801a862e0032226380..  1676 GiB VD0 (252:0) = Samsung 870 EVO 2TB
    #   sdd  scsi-3600304801a862e003222639b..  1609 GiB VD1 (252:1) = Micron/Intel 1.92TB
    #   nvme0n1  Samsung 980 1TB
    (import ./disko-super.nix {
      satadom = "/dev/disk/by-id/ata-SATADOM-SL_3ME_20150530AA10081359C6";
      samsung = "/dev/disk/by-id/scsi-3600304801a862e0032226380afd2802c";   # sdc 1676 GiB — LVM sys + ZFS
      micron  = "/dev/disk/by-id/scsi-3600304801a862e003222639bb176e1d1";   # sdd 1609 GiB — ZFS only
      nvme    = "/dev/disk/by-id/nvme-Samsung_SSD_980_1TB_S78HNL0XA30016L"; # Samsung 980 1TB
    })
  ];
}
