#
# arm/pi-bob/nix/swap.nix
#
# Compressed RAM-backed swap (zram). This Pi 5 has 8 GB, which is plenty for
# NixOS - it builds fine on far less - so this is NOT required for normal
# operation. It is cheap insurance/headroom for the occasional memory spike
# (e.g. a large `nix` evaluation during an on-Pi `nixos-rebuild`), and unlike a
# swap file on the SD card it causes no flash wear.
#
{ ... }:

{
  zramSwap = {
    enable = true;
    memoryPercent = 50; # up to ~4 GB of RAM used to back compressed swap
    priority = 100;
  };
}
