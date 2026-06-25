# Overlay exposing the board's bootloader packages.
#
# Takes the flake's non-flake vendor source inputs and wires them into the
# package derivations as `src`. Applied to the cross pkgset so everything is
# built for riscv64.
inputs: final: _prev: {
  # SpacemiT vendor OpenSBI -> fw_dynamic.itb
  k1-opensbi = final.callPackage ./pkgs/opensbi {
    src = inputs.opensbi-spacemit;
  };

  # SpacemiT vendor U-Boot 2022.10 -> FSBL.bin, bootinfo_emmc.bin, u-boot.itb
  bpi-f3-uboot = final.callPackage ./pkgs/u-boot {
    src = inputs.uboot-spacemit;
  };
}
