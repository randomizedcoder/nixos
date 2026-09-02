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
    (import ./disko-super.nix {
      satadom = "/dev/disk/by-id/REPLACE-b-satadom";
      samsung = "/dev/disk/by-id/REPLACE-b-samsung-90pct-VD";   # 252:0
      micron  = "/dev/disk/by-id/REPLACE-b-micron-90pct-VD";     # 252:1
      nvme    = "/dev/disk/by-id/REPLACE-b-nvme";                # Samsung 980 1TB
    })
  ];
}
