#
# ~/nixos/super/c/disko.nix — super-c (uniform 4-tier)
#
# The lone Intel D3-S4510 is a RESERVED SPARE: create its 90% VD in storcli so
# it's ready, but leave it OUT of disko (unlisted here) so disko never touches
# it — it stays unformatted/unmounted until we assign a purpose.
#
# FILL the by-id paths from the booted installer:
#   ls -l /dev/disk/by-id | grep -Ei 'samsung|micron|nvme|satadom'
#
{ ... }:
{
  imports = [
    (import ./disko-super.nix {
      satadom = "/dev/disk/by-id/REPLACE-c-satadom";
      samsung = "/dev/disk/by-id/REPLACE-c-samsung-90pct-VD";   # 252:0
      micron  = "/dev/disk/by-id/REPLACE-c-micron-90pct-VD";     # 252:1
      nvme    = "/dev/disk/by-id/REPLACE-c-nvme";
    })
  ];
  # Intel D3-S4510 (252:2) → reserved spare: intentionally not listed.
}
