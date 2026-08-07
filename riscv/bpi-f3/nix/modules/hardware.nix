# Hardware wiring for the Banana Pi BPI-F3 (SpacemiT K1).
{ lib, ... }:
{
  hardware = {
    enableRedistributableFirmware = true;

    deviceTree = {
      name = "spacemit/k1-bananapi-f3.dtb";

      # Mainline 7.0.x only wires up the K1 eMMC (mmc@d4281000); the BPI-F3's
      # removable SD-card slot controller (SDH0 @ d4280000) is absent from the DTS,
      # so the kernel can't see the SD card we boot from. Re-add it, mirroring the
      # working eMMC node but with the SDH0 clocks/resets/IRQ. See sd-overlay.dts
      # for the per-property rationale (broken-cd / disable-wp / no-mmc/no-sdio/no-1-8-v).
      overlays = [
        {
          name = "bpi-f3-sdhci0-sdcard";
          filter = "k1-bananapi-f3.dtb";
          dtsText = builtins.readFile ./sd-overlay.dts;
        }
      ];
    };
  };

  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
}
