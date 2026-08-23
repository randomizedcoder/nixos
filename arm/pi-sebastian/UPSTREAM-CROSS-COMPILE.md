# Cross-compiling the nixos-raspberrypi kernel (upstream PR notes)

Status: **the local workaround in `flake.nix` (`crossModule`) already gives us a
fully cross-compiled image.** This document only describes what a *proper
upstream fix* in `nixos-raspberrypi` would require, so it can be turned into a PR
(fork: `github:randomizedcoder/nixos-raspberrypi`, branch `develop` →
`github:nvmd/nixos-raspberrypi` `main`).

## The problem

Building a Pi image on an x86_64 machine should cross-compile (native x86 gcc
emitting aarch64 code — fast). Instead, the **kernel and all its modules build
under QEMU/binfmt emulation** (aarch64 gcc run instruction-by-instruction under
`qemu-aarch64`), which is ~10–20× slower regardless of how fast the build host
is. For a Pi model whose kernel isn't already in the `nixos-raspberrypi.cachix.org`
cache (e.g. the Pi 4 / `bcm2711` kernel at the time of writing), this means a
full emulated kernel+modules compile.

Setting `nixpkgs.buildPlatform = "x86_64-linux"` on the system is **not enough**:
it cross-compiles ordinary nixpkgs packages, but the Pi kernel bypasses it (see
root cause below), so the kernel stays native-aarch64 → emulated.

### How to observe it

```sh
# The kernel derivation the image actually uses:
nix eval --raw .#nixosConfigurations.<cfg>.config.boot.kernelPackages.kernel.drvPath
nix derivation show <that .drv> | grep -oE '"system":"[^"]*"'
```

- Emulated (bad):  `"system":"aarch64-linux"`, drv name `linux_rpi-bcm2711-<ver>`,
  `CROSS_COMPILE=""` in `makeFlags`. During the build: `pgrep -c qemu-aarch64`
  is in the hundreds.
- Cross (good):    `"system":"x86_64-linux"`, drv name
  `linux_rpi-bcm2711-aarch64-unknown-linux-gnu-<ver>`. `pgrep -c qemu-aarch64` = 0.

## Root cause (in the nixos-raspberrypi source)

Two design points combine to force a native (emulated) kernel:

1. **The Pi model modules hardcode the kernel to a per-system flake output.**
   `modules/raspberry-pi-4.nix` (and the `-5` / `-3` / `-02` equivalents):

   ```nix
   boot.kernelPackages = lib.mkDefault
     nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system}.linuxPackages_rpi4;
   ```

   `hostPlatform.system` is `aarch64-linux` (forced in `lib/internal.nix`), so this
   is `nixos-raspberrypi.packages.aarch64-linux.linuxPackages_rpi4` — a **prebuilt
   native-aarch64 flake package**. Flake `packages.<system>` are by definition
   built *for/on* `<system>`, so nothing about the consuming system's
   `buildPlatform` can turn it into a cross build.

2. **The `pkgs.rpi` package set is re-imported natively.**
   `modules/nixpkgs-rpi.nix`:

   ```nix
   rpi = import nixos-raspberrypi.inputs.nixpkgs {
     inherit (prev.stdenv.hostPlatform) system;   # ← only `system`; no localSystem/crossSystem
     ...
   };
   ```

   Even the overlay-provided path re-imports nixpkgs with just `system =
   aarch64-linux`, i.e. a native set, discarding any cross intent.

Note that `overlays/linux-and-firmware.nix` *does* define the kernel on the
outer (potentially-cross) pkgs as `pkgs.linuxPackages_rpi4 =
final.linuxPackagesFor linux_rpi4`. That path **does** honour `buildPlatform` —
it is exactly what the local workaround uses.

## The local workaround (what we ship today)

In `arm/pi-sebastian/flake.nix`, applied only to the PC-built `-cross` and
`-sdimage` variants (NOT the on-Pi native `pi-sebastian` output, which should
keep the cached prebuilt kernel):

```nix
crossModule = { pkgs, lib, ... }: {
  nixpkgs.buildPlatform = "x86_64-linux";
  boot.kernelPackages   = lib.mkForce pkgs.linuxPackages_rpi4;  # overlay kernel → real cross build
};
```

This needs no fork. Downside: the cross-built kernel has a different store hash
than the cached aarch64 kernel, so it is not fetched from cachix (it is built —
but natively/fast, not emulated). That is the correct trade only when the native
kernel isn't cached anyway (the Pi 4 case). For the Pi 5, whose kernel *is*
cached, we deliberately leave the default in place so the build just substitutes.

## What an upstream fix would require

Goal: when a consumer sets `nixpkgs.buildPlatform ≠ hostPlatform`, the Pi kernel
and firmware should cross-compile automatically, without the consumer having to
override `boot.kernelPackages`.

### Option A — make the model modules use the overlay kernel (small, localized)

In `modules/raspberry-pi-{4,5,3,02}.nix`, source the kernel/firmware from the
overlay on the consumer's own pkgs instead of the per-system flake output:

```nix
# before
boot.kernelPackages = lib.mkDefault
  nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system}.linuxPackages_rpi4;
# after
boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_rpi4;
```

- Pro: tiny diff; `pkgs.linuxPackages_rpi4` already exists via
  `overlays/linux-and-firmware.nix` and respects `buildPlatform`.
- Con/risk: for the common **native aarch64** build, `pkgs.linuxPackages_rpi4`
  must resolve to the *same* derivation currently published to cachix, or every
  existing user loses their kernel cache hit. This has to be verified
  (`nix eval` the drv path both ways on aarch64 and diff) before proposing it.
  If they differ, cachix's `nix-build-to-cachix` job list must be updated to
  push the overlay kernel too.

### Option B — make `pkgs.rpi` cross-aware (more correct, larger blast radius)

In `modules/nixpkgs-rpi.nix`, pass `localSystem`/`crossSystem` when the outer
stdenv is cross, mirroring the standard nixpkgs cross idiom (this is the pattern
used by e.g. the xdp2 `nix/microvms` flake to cross-build riscv64 without
binfmt):

```nix
rpi = import nixos-raspberrypi.inputs.nixpkgs (
  {
    config   = { inherit (prev.config) allowUnfree allowUnfreePredicate; };
    overlays = [ /* unchanged */ ];
  }
  // (if prev.stdenv.buildPlatform.system != prev.stdenv.hostPlatform.system
      then {
        localSystem = prev.stdenv.buildPlatform.system;
        crossSystem = prev.stdenv.hostPlatform.system;
      }
      else { inherit (prev.stdenv.hostPlatform) system; })
);
```

- Pro: fixes cross for *everything* in `pkgs.rpi`, not just the kernel.
- Con: the model modules (Option A's `boot.kernelPackages`) still point at the
  per-system flake output, so Option B alone doesn't change what the image uses
  unless combined with Option A. The two are complementary: **B makes the
  overlay kernel cross-correct; A makes the modules actually consume it.**
- Con: the per-system `packages.<system>` flake outputs remain native-only. If
  cross flake outputs are also wanted, the flake would need a
  `packages.x86_64-linux.<cross kernel>` style output (a `buildSystem`
  parameter), which is a bigger change.

### Recommended PR shape

1. Land **Option A** guarded so native builds are provably unchanged (diff the
   resolved kernel drv on aarch64 before/after; keep cachix hits).
2. Optionally add **Option B** so the whole `pkgs.rpi` set cross-compiles.
3. Add a CI matrix entry that builds an `sdImage` with
   `nixpkgs.buildPlatform = "x86_64-linux"` and asserts `pgrep qemu-aarch64` = 0
   / the kernel drv `system` is `x86_64-linux`.

## Verification checklist (either the workaround or an upstream fix)

```sh
# 1. kernel drv is a cross build
nix eval --raw .#nixosConfigurations.<cfg>.config.boot.kernelPackages.kernel.drvPath
#    → name contains 'aarch64-unknown-linux-gnu', system = x86_64-linux

# 2. nothing native-aarch64 left to build (no emulation) in the plan
nix build .#nixosConfigurations.<cfg>.config.system.build.sdImage --dry-run 2>&1 \
  | grep -E 'will be built' -A999 | grep -E 'aarch64-linux' && echo "STILL EMULATING" || echo "all cross"

# 3. during the real build, no emulator runs
watch -n2 'pgrep -c qemu-aarch64'   # must stay 0
```
