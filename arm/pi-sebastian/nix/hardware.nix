#
# arm/pi-sebastian/nix/hardware.nix
#
# SD-card-only storage layout. Unlike pi4-1 there is NO custom kernel override,
# so this boots on any Pi 4 with just the flashed microSD card (Sebastian may
# not have any other storage). The stock linux_rpi4 from raspberry-pi-4.base is
# used.
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
  # The Pi 4 uses u-boot (the raspberry-pi-4.base default), unlike the Pi 5's
  # "kernel" bootloader.
  boot.loader.raspberry-pi.bootloader = "uboot";

  # This SD-card image doesn't use ZFS; adopt the new (26.11+) default
  # explicitly to silence the boot.zfs.forceImportRoot deprecation warning.
  boot.zfs.forceImportRoot = false;
}
