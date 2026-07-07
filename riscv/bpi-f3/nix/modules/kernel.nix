# Kernel + initrd for the Banana Pi BPI-F3 (SpacemiT K1).
#
# 2026-07-06: net-next v7.2-rc1 + the series4 flow_dissector fast-path framework
# (series4-rfc-tail-v2: 15 landable patches incl. the 5 UDP-tunnel inner
# descents now byte-identical + KUnit, plus the auto-enable RFC), mirroring l2 —
# the RISC-V data point for series4. Built by overriding nixpkgs linux_testing so
# the config machinery is reused; the SpacemiT K1 drivers are still force-on via
# structuredExtraConfig (all K1 symbols confirmed present in 7.2-rc1). Cross-
# compiled x86_64 -> riscv64. All gates default off.
{ lib, pkgs, ... }:
let
  netNextSeries4 = builtins.fetchGit {
    url = "file:///home/das/Downloads/net-next";
    ref = "series4-rfc-tail-v2";
    rev = "a208f86be2ce6dc7e38c240386b30c92417d859e";
  };
in
{
  boot = {
    kernelPackages = pkgs.linuxPackagesFor (pkgs.linux_testing.override {
      argsOverride = {
        version = "7.2-rc1";
        modDirVersion = "7.2.0-rc1";
        src = netNextSeries4;
        # linux_testing's structured config requests a few options net-next
        # 7.2-rc1 dropped (CRYPTO_DRBG_CTR/HASH, RANDOM_KMALLOC_CACHES).
        ignoreConfigErrors = true;
      };
    });

    # Storage/clock/pinctrl/serial built in (=yes) so the board reaches its rootfs
    # without relying on initrd module ordering. Symbol names verified against the
    # mainline riscv defconfig (all still present in net-next 7.2-rc1).
    #
    # The old spacemit-p1-reboot-cell.patch is DROPPED: net-next 7.2-rc1
    # registers the "spacemit-p1-reboot" MFD cell upstream (see
    # drivers/mfd/simple-mfd-i2c.c spacemit_p1_cells[]), so reboot/poweroff work
    # without the local patch. The series-3 flow_dissector patches are DROPPED
    # too: series4 (series4-rfc-tail-v2) is baked into the net-next src above.
    kernelPatches = [
      {
        name = "spacemit-k1";
        patch = null;
        structuredExtraConfig = with lib.kernel; {
          ARCH_SPACEMIT = yes;
          SPACEMIT_K1_CCU = yes; # clock controller
          SPACEMIT_CCU = yes;
          PINCTRL_SPACEMIT_K1 = yes;
          GPIO_SPACEMIT_K1 = yes;

          # UART0 debug console
          SERIAL_8250 = yes;
          SERIAL_8250_CONSOLE = yes;
          SERIAL_8250_DW = yes;

          # SD / eMMC host controllers (builtin). The block layer (MMC_BLOCK) is
          # =m upstream; rather than rebuild the kernel to make it builtin, we
          # force-load mmc_block in the initrd (initrd.kernelModules below).
          MMC_SDHCI = yes;
          MMC_SDHCI_PLTFM = yes;
          MMC_SDHCI_OF_K1 = yes;
          MMC_SDHCI_OF_DWCMSHC = yes;

          # Gigabit Ethernet
          NET_VENDOR_SPACEMIT = yes;
          SPACEMIT_K1_EMAC = module;
        };
      }
    ];

    initrd = {
      availableKernelModules = lib.mkForce [
        "ext4"
        "sd_mod"
        "mmc_block"
        "xhci_hcd"
        "usbhid"
        "hid_generic"
        # Root-on-NVMe (see nix/modules/nvme). The K1 PCIe controller is built
        # into the kernel (CONFIG_PCIE_SPACEMIT_K1=y / PHY_SPACEMIT_K1_PCIE=y),
        # so the bus is enumerated during kernel init and udev autoloads the
        # NVMe driver in stage-1. Only BLK_DEV_NVME is modular (=m upstream),
        # so it must be made available to the initrd here; nvme_core and the
        # rest of the closure are pulled in automatically.
        "nvme"
      ];

      # MMC_BLOCK is =m upstream and udev didn't autoload it in the initrd (root
      # on the SD card then timed out). Force-load it early so /dev/mmcblk* appears.
      kernelModules = [ "mmc_block" ];

      # Let us into a root shell in the initrd if root isn't found, so failures are
      # debuggable (dmesg, ls /dev/mmc*) instead of a locked emergency console.
      systemd.emergencyAccess = true;
    };

    supportedFilesystems = lib.mkForce [
      "vfat"
      "ext4"
      "btrfs"
    ];
  };
}
