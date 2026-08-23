#
# arm/pi-sebastian/nix/swap.nix
#
# Compressed RAM-backed swap (zram). NixOS builds fine on the Pi 4's RAM (2-8 GB
# depending on model), so this is NOT required for normal operation. It is cheap
# insurance/headroom for the occasional memory spike
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
