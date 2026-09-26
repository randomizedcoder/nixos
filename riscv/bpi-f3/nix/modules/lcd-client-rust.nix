# bpi-f3-lcd-client, built from a single std-only Rust source with a bare
# `rustc` invocation — no Cargo.toml, no Cargo.lock, no vendoring (same idiom
# as the repo's claude-statusline). See ./lcd-client.rs.
#
# This is callPackage'd from ./lcd.nix, where `pkgs` is the riscv64 cross set,
# so `stdenv` is the cross stdenv and `rustc` in nativeBuildInputs splices to
# the build-host compiler that emits riscv64. We pass the target triple and the
# cross cc (which rustc shells out to for the final link) explicitly.
{
  runCommandLocal,
  rustc,
  stdenv,
}:
runCommandLocal "bpi-f3-lcd-client"
  {
    nativeBuildInputs = [
      rustc
      stdenv.cc
    ];
  }
  ''
    mkdir -p $out/bin
    rustc --edition 2021 -C opt-level=3 -C lto=fat -C codegen-units=1 \
          -C strip=symbols -C panic=abort \
          --target ${stdenv.hostPlatform.rust.rustcTarget} \
          -C linker=$CC \
          -o $out/bin/bpi-f3-lcd-client ${./lcd-client.rs}
  ''
