# SD/eMMC image configuration for the Banana Pi BPI-F3 (SpacemiT K1).
#
# Builds on the patched generic sd-image.nix. The vendor U-Boot uses extlinux
# (Distro Boot): it reads /extlinux/extlinux.conf from the FAT firmware
# partition, which generic-extlinux-compatible populates along with the kernel,
# DTB and initrd.
#
# The SpacemiT bootloader blobs are dd'd to fixed raw sector offsets in the gap
# ahead of partition 1 (postBuildCommands below), matching Armbian's
# write_uboot_platform() in config/sources/families/spacemit.conf.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Stable UUID for the ext4 root filesystem, referenced from the kernel cmdline.
  rootPartitionUUID = "0a3b4c5d-6e7f-4a8b-9c0d-1e2f3a4b5c6d";

  uboot = pkgs.bpi-f3-uboot; # FSBL.bin, bootinfo_emmc.bin, u-boot.itb
  opensbi = pkgs.k1-opensbi; # fw_dynamic.itb
in
{
  imports = [ ./sd-image.nix ];

  boot = {
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };

    # Keep this list short: the vendor U-Boot caps the kernel command line at 256
    # bytes ("bootarg overflow ... > 256"), and NixOS already prepends a long
    # init=/nix/store/...-nixos-system-.../init plus root=fstab/loglevel/lsm. The
    # initrd mounts root by the NIXOS_SD label (via the generated fstab), so
    # root=UUID/rootfstype are redundant here; console=tty1 is pointless headless.
    kernelParams = [
      # Direct UART0 earlycon (0xd4017000, reg-shift=2/io-width=4 -> mmio32). Prints
      # from the very start; earlycon=sbi produced nothing on this board.
      "earlycon=uart8250,mmio32,0xd4017000"
      "console=ttyS0,115200"
      "rootwait"
      "rw"
    ];
  };

  fileSystems = lib.mkForce {
    "/boot/firmware" = {
      device = "/dev/disk/by-label/${config.sdImage.firmwarePartitionName}";
      fsType = "vfat";
      options = [
        "nofail"
        "noauto"
      ];
    };
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
    };
  };

  sdImage = {
    inherit rootPartitionUUID;

    imageBaseName = "nixos-bpi-f3-sd-image";
    compressImage = false; # leave uncompressed so it can be dd'd directly

    firmwarePartitionName = "BOOT";
    # The firmware partition holds the kernel + initrd + DTB + extlinux.conf,
    # so give it room.
    firmwareSize = 256;
    # Gap before partition 1, in MiB. Must clear the bootloader blobs, the
    # largest of which (u-boot.itb) starts at sector 2048 (1 MiB). 16 MiB is
    # comfortably clear and leaves headroom.
    firmwarePartitionOffset = 16;

    populateFirmwareCommands = ''
      # extlinux.conf + kernel + DTB + initrd onto the FAT firmware partition.
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} -d ./firmware
    '';

    populateRootCommands = ''
      mkdir -p ./files/boot
    '';

    # dd the SpacemiT bootloader blobs into the raw gap ahead of partition 1.
    # Offsets (512-byte sectors) match Armbian's write_uboot_platform():
    #   bootinfo_emmc.bin -> 0     (BootROM boot-info header; tiny, coexists with MBR table)
    #   FSBL.bin          -> 1     (the SPL)
    #   fw_dynamic.itb    -> 1280  (OpenSBI, 0x140000)
    #   u-boot.itb        -> 2048  (U-Boot proper, 0x200000)
    postBuildCommands = ''
      dd if=${uboot}/bootinfo_emmc.bin of=$img bs=512 seek=0    conv=notrunc
      dd if=${uboot}/FSBL.bin          of=$img bs=512 seek=1    conv=notrunc
      dd if=${opensbi}/fw_dynamic.itb  of=$img bs=512 seek=1280 conv=notrunc
      dd if=${uboot}/u-boot.itb        of=$img bs=512 seek=2048 conv=notrunc
    '';
  };
}
