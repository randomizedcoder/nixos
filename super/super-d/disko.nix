#
# ~/nixos/super/d/disko.nix — super-d (uniform 4-tier; NEW board ZM16CS046074)
#
# By-ids read from the live installer (2026-08-30), MegaRAID SAS3108 in
# *JBOD-Mode* personality (see note below):
#   satadom  ata-SATADOM-SL_3IE3_V2_...   PCH sSATA DOM, 59.6 G  (AHCI)
#   samsung  ata-Samsung_SSD_870_EVO_2TB  252:0 JBOD passthrough, 1.819 TB (full)
#   micron   scsi-3600304801b28a602...    252:1 VD239 RAID0, 1.745 TB (full)
#   nvme     nvme-Samsung_SSD_990_EVO...   931 G
#
# STORAGE NOTE (super-d only, 2026-08-30): the swapped SAS3108 is in JBOD-Mode,
# where VDs *cannot* use the controller write cache ("Support JBOD Write cache =
# No" → AWB set failed). Switching to RAID-Mode to enable BBU-backed WriteBack
# needs a controller reboot, which would drop the *manually-configured, non-
# persistent* installer network → loss of remote access. So super-d installs on
# the current topology: Samsung = JBOD passthrough (full size, but TRIM passes,
# so ZFS autotrim keeps the consumer TLC healthy), Micron = VD239 WriteThrough
# (full size; enterprise drive has factory OP + tolerates no-TRIM). The
# CVPM02 CacheVault IS present + Optimal, so WriteBack + 90% VDs (Samsung split,
# Micron recreate) are a DEFERRED optimization: redo once, from the installed
# (persistently-networked) system, where a reboot into RAID-Mode is safe.
# by-id paths are unchanged by that future rework only if the VDs are kept — a
# RAID-Mode recreate WILL change scsi-* ids and needs this file updated + reinstall.
#
{ ... }:
{
  imports = [
    (import ./disko-super.nix {
      satadom = "/dev/disk/by-id/ata-SATADOM-SL_3IE3_V2_YCA12006100200143";
      samsung = "/dev/disk/by-id/ata-Samsung_SSD_870_EVO_2TB_S8HSNS0L500293H";
      micron  = "/dev/disk/by-id/scsi-3600304801b28a602308ffb141b96e53b";
      nvme    = "/dev/disk/by-id/nvme-Samsung_SSD_990_EVO_Plus_1TB_S7U5NJ1Y702621E";
    })
  ];
}
