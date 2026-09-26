# Overlay exposing the board's bootloader packages.
#
# Takes the flake's non-flake vendor source inputs and wires them into the
# package derivations as `src`. Applied to the cross pkgset so everything is
# built for riscv64.
inputs: final: prev: {
  # SpacemiT vendor OpenSBI -> fw_dynamic.itb
  k1-opensbi = final.callPackage ./pkgs/opensbi {
    src = inputs.opensbi-spacemit;
  };

  # SpacemiT vendor U-Boot 2022.10 -> FSBL.bin, bootinfo_emmc.bin, u-boot.itb
  bpi-f3-uboot = final.callPackage ./pkgs/u-boot {
    src = inputs.uboot-spacemit;
  };

  # lcdproc (drives the USB LCD2USB panel, see nix/modules/lcd.nix). 0.5.9
  # predates AM_PROG_AR, so automake bakes an unprefixed `AR = ar` into the
  # Makefile; in a cross build only the target-prefixed archiver is on PATH, so
  # building the static libLCDstuff.a dies with "ar: command not found". Pass
  # the cross ar/ranlib explicitly (a no-op prefix on a native build).
  lcdproc = prev.lcdproc.overrideAttrs (old: {
    makeFlags = (old.makeFlags or [ ]) ++ [
      "AR=${final.stdenv.cc.targetPrefix}ar"
      "RANLIB=${final.stdenv.cc.targetPrefix}ranlib"
    ];
  });
}
