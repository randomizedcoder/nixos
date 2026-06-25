# SpacemiT vendor OpenSBI for the K1 (BPI-F3).
#
# Produces fw_dynamic.itb — the OpenSBI firmware FIT that the SpacemiT FSBL hands
# control to. On the SD/eMMC image it is dd'd to sector 1280 (0x140000).
#
# Build recipe mirrors Armbian's spacemit family (config/sources/families/spacemit.conf):
#   make PLATFORM=generic PLATFORM_DEFCONFIG=k1_defconfig
#   -> build/platform/generic/firmware/fw_dynamic.itb
#
# `src` is injected by the overlay from the `opensbi-spacemit` flake input
# (gitee.com/spacemit-buildroot/opensbi, tag k1-bl-v2.2.10-release).
{
  lib,
  stdenv,
  src,
  python3,
  ubootTools, # provides mkimage, used to assemble fw_dynamic.itb from fw_dynamic.its
  dtc,
}:

stdenv.mkDerivation {
  pname = "k1-opensbi";
  version = "k1-bl-v2.2.10";

  inherit src;

  nativeBuildInputs = [
    python3
    ubootTools
    dtc
  ];

  postPatch = ''
    patchShebangs ./scripts || true
  '';

  makeFlags = [
    "PLATFORM=generic"
    "PLATFORM_DEFCONFIG=k1_defconfig"
    # Be explicit about the cross toolchain prefix; the OpenSBI Makefile assigns
    # CC = $(CROSS_COMPILE)gcc with `=`, which would otherwise shadow stdenv's $CC.
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
    # This vendor tree predates C23. GCC 15 defaults to -std=c23, where `bool` is
    # a keyword, so its `typedef int bool;` in sbi_types.h fails to compile (and
    # -Werror turns the warning fatal). platform-cflags-y is folded into the
    # global CFLAGS (Makefile line ~353), so this applies to lib/sbi too.
    "platform-cflags-y=-std=gnu17"
  ];

  enableParallelBuilding = true;

  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall
    install -Dm444 build/platform/generic/firmware/fw_dynamic.itb $out/fw_dynamic.itb
    # The raw payload is handy for debugging / alternative packaging.
    install -Dm444 build/platform/generic/firmware/fw_dynamic.bin $out/fw_dynamic.bin
    runHook postInstall
  '';

  meta = {
    description = "SpacemiT vendor OpenSBI (K1) — fw_dynamic.itb for the Banana Pi BPI-F3";
    homepage = "https://gitee.com/spacemit-buildroot/opensbi";
    license = lib.licenses.bsd2;
    platforms = [ "riscv64-linux" ];
  };
}
