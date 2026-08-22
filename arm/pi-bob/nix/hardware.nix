#
# arm/pi-bob/nix/hardware.nix
#
# SD-card-only storage layout. Unlike pi5-1 there is NO NVMe /nix backing
# store and NO custom kernel override, so this boots on any Pi 5 with just the
# flashed microSD card (Bob may not have an NVMe drive). The stock linux_rpi5
# from raspberry-pi-5.base is used.
#

{ ... }:

{
  # Run from the SD card you flashed (the installer sd-image layout).
  # Labels confirmed against the installer image: NIXOS_SD + FIRMWARE.
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [ "noatime" ];
    };
    "/boot/firmware" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
      options = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };

  # Match the bootloader the installer sd-image already wrote to the card.
  boot.loader.raspberry-pi.bootloader = "kernel";

  # This SD-card image doesn't use ZFS; adopt the new (26.11+) default
  # explicitly to silence the boot.zfs.forceImportRoot deprecation warning.
  boot.zfs.forceImportRoot = false;
}
