# SpacemiT vendor U-Boot 2022.10 for the K1 (Banana Pi BPI-F3).
#
# The K1 BootROM boot chain expects several structured blobs at fixed sector
# offsets on the boot medium (see modules/sd-image/sd-image-bpi-f3.nix). This
# derivation produces the three that come out of the U-Boot tree:
#
#   FSBL.bin          -> sector 1     (the SPL, wrapped + RSA2048-signed by tools/build_binary_file.py)
#   bootinfo_emmc.bin -> sector 0     (BootROM boot-info header; emitted alongside FSBL.bin)
#   u-boot.itb        -> sector 2048  (U-Boot proper, FIT of u-boot-nodtb.bin + board DTBs)
#
# OpenSBI's fw_dynamic.itb (sector 1280) is built separately (../opensbi); the
# U-Boot FIT does not embed it.
#
# Build recipe mirrors Armbian's spacemit family + bananapif3 board tweaks
# (armbian-build: config/sources/families/spacemit.conf, config/boards/bananapif3.conf):
#   make k1_defconfig && make            # default `all` builds the SPL/FSBL + bootinfo
#   make u-boot.itb                      # FIT assembled from u-boot-nodtb.bin via mkimage
#
# We build Armbian's exact U-Boot (pyavitz/spacemit-u-boot @ k1-bl-v2.2.9-release)
# WITH Armbian's patch set, because the stock vendor U-Boot is unusable for a generic
# distro:
#   - its SPL loads OpenSBI/U-Boot only from GPT partitions *named* "opensbi"/"uboot"
#     (common/spl/spl_mmc.c); 001-MBR-support adds the raw-offset fallback
#     (opensbi -> sector 0x500/1280, uboot -> 0x800/2048) that our MBR image relies on;
#   - BOOT_TARGET_DEVICES only lists QEMU and it boots via bespoke env scripts, not
#     extlinux; 002 adds the mmc boot target + kernel/fdt/ramdisk load addresses and
#     004 adds syslinux/extlinux support, which NixOS's generic-extlinux-compatible needs.
# (005/006 are OrangePi-only; 008 just quiets 001's debug prints.)
#
# `src` is injected by the overlay from the `uboot-spacemit` flake input
# (github.com/pyavitz/spacemit-u-boot, tag k1-bl-v2.2.9-release).
{
  lib,
  buildUBoot,
  src,
}:

buildUBoot {
  version = "2022.10-k1-bl-v2.2.9";
  inherit src;

  defconfig = "k1_defconfig";

  # Armbian's u-boot-spacemit-k1 patch set (vendored from armbian-build), in order.
  extraPatches = [
    ./patches/001-MBR-support.patch
    ./patches/002-SpacemiT-K1X-Fixups.patch
    ./patches/003-SpacemiT-K1X-Defconfig-Fixups.patch
    ./patches/004-Add-syslinux-script-and-uefi-support.patch
    ./patches/007-efi_loader-suppress-error-print-message.patch
    ./patches/008-Quiet-MBR-support.patch
    ./patches/009-Fixup-circular-deps.patch
  ];

  # Extra Kconfig from armbian's post_config_uboot_target__extra_configs_for_bananapi_f3.
  # Appended to .config; `make` runs syncconfig to fold them in.
  extraConfig = ''
    CONFIG_SD_BOOT=y
    CONFIG_EXT4_WRITE=y
    CONFIG_FS_BTRFS=y
    CONFIG_CMD_BTRFS=y
    CONFIG_SPI_FLASH_USE_4K_SECTORS=y
    # Override the Armbian patch's CONFIG_LOCALVERSION=" Armbian" so the U-Boot/SPL
    # banner reads "U-Boot 2022.10 NixOS" instead.
    CONFIG_LOCALVERSION=" NixOS"
  '';

  # Build the default target (SPL -> FSBL.bin + bootinfo_*.bin, plus u-boot proper),
  # then the U-Boot FIT explicitly (it is a standalone Makefile target, not in ALL-y).
  buildFlags = [
    "all"
    "u-boot.itb"
  ];

  extraMeta = {
    description = "U-Boot for the Banana Pi BPI-F3 (SpacemiT K1) — Armbian fork + patches, emits FSBL.bin / bootinfo_emmc.bin / u-boot.itb";
    homepage = "https://github.com/pyavitz/spacemit-u-boot";
    license = lib.licenses.gpl2Plus;
    platforms = [ "riscv64-linux" ];
  };

  filesToInstall = [
    "FSBL.bin"
    "bootinfo_emmc.bin"
    "u-boot.itb"
  ];
}
