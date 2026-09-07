#
# ~/nixos/super/d/disko.nix — super-d (uniform 4-tier; NEW board ZM16CS046074)
#
# By-ids re-read after the RAID-Mode reprovision (2026-09-06), MegaRAID SAS3108
# now in *RAID-Mode* with two 90%-OP RAID0 WriteBack (NRWBD) VDs — matches super-b:
#   satadom  ata-SATADOM-SL_3IE3_V2_...   PCH sSATA DOM, 59.6 G  (AHCI, unchanged)
#   samsung  scsi-3600304801b28a402...    VD0 "system" RAID0 NRWBD, 1.636 TB (Samsung 90%)
#   micron   scsi-3600304801b28a402...    VD1 "data"   RAID0 NRWBD, 1.570 TB (Micron 90%)
#   nvme     nvme-Samsung_SSD_990_EVO...   931 G (unchanged)
#
# HISTORY (super-d): originally installed 2026-08-30 in JBOD-Mode (VDs couldn't use
# the controller write cache: "Support JBOD Write cache = No"). Flipped to RAID-Mode
# 2026-09-05 (personality change is DEFERRED/reboot-required — staged from the running
# OS, applied at POST; see memory megaraid-personality-flip). VDs then rebuilt as
# 90% RAID0 with battery-backed WriteBack (CVPM02 CacheVault Optimal; "Cache When BBU
# Bad = Off" → plain WB fails safe to WriteThrough). Both SSDs full-drive blkdiscard'd
# before VD create so the 10% OP is genuinely free. A future RAID-Mode VD recreate
# WILL change these scsi-* ids again → update this file + reinstall.
#
{ ... }:
{
  imports = [
    (import ./disko-super.nix {
      satadom = "/dev/disk/by-id/ata-SATADOM-SL_3IE3_V2_YCA12006100200143";
      samsung = "/dev/disk/by-id/scsi-3600304801b28a402ff00071d6cdc864e";  # VD0 "system" (Samsung 90% RAID0 NRWBD)
      micron  = "/dev/disk/by-id/scsi-3600304801b28a402ff0007346e39ce57";  # VD1 "data"   (Micron 90% RAID0 NRWBD)
      nvme    = "/dev/disk/by-id/nvme-Samsung_SSD_990_EVO_Plus_1TB_S7U5NJ1Y702621E";
    })
  ];
}
