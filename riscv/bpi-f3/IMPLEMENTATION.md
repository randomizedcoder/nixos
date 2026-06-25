# Implementation Plan: NixOS flake for Banana Pi BPI-F3 (SpacemiT K1, RISC-V)

> Status of execution is tracked in [`PROGRESS.md`](./PROGRESS.md).

## Context

Bring up NixOS on the [Banana Pi BPI-F3](https://docs.banana-pi.org/en/BPI-F3/BananaPi_BPI-F3) (SpacemiT K1 octa-core RISC-V SoC). No turnkey NixOS image exists, so we build one ourselves: a flake that **cross-compiles from x86_64 → riscv64** and produces a flashable SD-card image with the SpacemiT bootloader baked in.

The base is the existing `nixos-licheepi4a` flake (cross-compile + patched `sd-image.nix` + per-board module + `pkgs/` derivations). The Lichee Pi 4A is a T-Head TH1520; the BPI-F3 is a SpacemiT K1, so everything board-specific (kernel, DTS, console, and especially the bootloader layout) is retargeted.

### Decisions (confirmed with the user)

- **Kernel:** mainline, headless. The in-tree `k1-bananapi-f3.dts` exists, so we drop the LP4A custom-kernel machinery and use a recent nixpkgs kernel. No GPU/NPU (vendor-only); serial/SD/eMMC/ethernet work.
- **Bootloader:** build the SpacemiT vendor U-Boot 2022.10 + OpenSBI **from source** as Nix derivations, producing the four boot blobs and `dd`-ing them onto the image.
- **ISA baseline:** `rv64gcv` / `lp64d` — enable RVV 1.0 (the K1 X60 supports it). This diverges from the riscv64 community binary caches (`rv64gc`), so the **entire closure is built locally**. Accepted given the build host (Threadripper).
- **Layout:** keep `flake.nix` thin; put all modules/derivations under `./nix/` ("modular nix").

## Key technical findings (verified against the cloned sources)

**Boot flow (differs fundamentally from LP4A).** The K1 BootROM expects four structured blobs `dd`'d to fixed sector offsets on the _boot medium itself_ (SD card or eMMC) — there is no separate fastboot step. From `armbian-build/config/sources/families/spacemit.conf` `write_uboot_platform()`:

| Blob | Offset | Built by |
| --- | --- | --- |
| `bootinfo_emmc.bin` | sector 0 (`seek=0`) | U-Boot `make` → `build_binary_file.py` + `bootinfo_emmc.json` |
| `FSBL.bin` (SPL, RSA2048-signed) | sector 1 (`seek=1`, 0x200) | U-Boot `make` → `build_binary_file.py` + `fsbl.json` (key in `board/spacemit/k1-x/configs/key`) |
| `fw_dynamic.itb` (OpenSBI) | sector 1280 (`seek=1280`, 0x140000) | OpenSBI vendor build, `PLATFORM=generic PLATFORM_DEFCONFIG=k1_defconfig` |
| `u-boot.itb` (U-Boot FIT) | sector 2048 (`seek=2048`, 0x200000) | U-Boot `make` (`u-boot-nodtb.bin` + dtb via mkimage) |

The bootloader region spans ~0–6 MiB; the first partition must start safely after it. Armbian uses a 4 MiB offset; we use a generous gap (≥16 MiB) for the firmware partition.

**U-Boot build.** `make k1_defconfig && make` in `uboot-2022.10`. Needs `python3`, `dtc`/`mkimage`, and the in-tree signing key. Artifacts land in the source root: `FSBL.bin`, `bootinfo_emmc.bin`, `u-boot.itb`. The defconfig is the generic `k1_defconfig` (`CONFIG_TARGET_SPACEMIT_K1X=y`); the BPI-F3 adds a couple of extra configs (`CONFIG_SD_BOOT`, ext4/btrfs write) per `armbian-build/config/boards/bananapif3.conf`.

**Console / cmdline.** `console=ttyS0,115200 earlycon=sbi` (from the BPI-F3 board config).

**DTS.** `spacemit/k1-bananapi-f3.dtb` — present in mainline (`compatible = "bananapi,bpi-f3","spacemit,k1"`).

**Boot loader on the running system.** U-Boot reads `extlinux.conf` from the FAT firmware partition, so NixOS's `boot.loader.generic-extlinux-compatible` works (same as LP4A).

## Repository structure

`flake.nix` stays small — inputs + a `let` block (cross config, overlay, helper) + outputs wiring. Everything substantive lives under `./nix/`:

```
flake.nix                         # thin: inputs + outputs, imports nix/*
nix/
  cross.nix                       # crossSystemConfig (rv64gcv/lp64d) + pkgs constructors
  overlay.nix                     # custom packages: u-boot blobs, opensbi
  modules/
    bpi-f3.nix                    # board module: kernel pkg, console, deviceTree, firmware, kernelParams, initrd modules, base env/ssh
    user-group.nix                # default user/host (port of LP4A's)
    sd-image/
      sd-image.nix                # patched generic sd-image module (firmwarePartitionOffset + postBuildCommands dd hook)
      sd-image-bpi-f3.nix         # board SD config: extlinux loader, kernelParams, populateFirmwareCommands, postBuildCommands dd of the 4 blobs
  pkgs/
    u-boot/default.nix            # vendor SpacemiT U-Boot 2022.10 → FSBL.bin, bootinfo_emmc.bin, u-boot.itb
    opensbi/default.nix           # vendor SpacemiT OpenSBI → fw_dynamic.itb
README.md                         # rewritten build/flash/serial guide
```

## Implementation steps

0. **In-repo docs first** — `IMPLEMENTATION.md` (this file) + `PROGRESS.md` checklist.
1. **`flake.nix` (thin)** — nixpkgs input (start `nixos-unstable`; pin a fork only if a build needs it); vendor sources as `flake = false` inputs (`uboot-spacemit`, `opensbi-spacemit`, pinned to the `tag:k1-bl-v2.2.9-release`-matching revs); outputs `nixosConfigurations.bpi-f3-cross` and `packages.x86_64-linux.{sdImage,uboot,opensbi}`; `specialArgs = { pkgsKernel = pkgsKernelCross; }`.
2. **`nix/cross.nix`** — `crossSystemConfig = { config = "riscv64-unknown-linux-gnu"; gcc.arch = "rv64gcv"; gcc.abi = "lp64d"; }` and the `pkgsKernelCross` constructor.
3. **`nix/pkgs/opensbi/default.nix`** — override `pkgs.opensbi` with the vendor src; build `PLATFORM=generic PLATFORM_DEFCONFIG=k1_defconfig FW_PIC=y`; install `fw_dynamic.itb`.
4. **`nix/pkgs/u-boot/default.nix`** — `buildUBoot` with vendor src, `defconfig = "k1_defconfig"`, BPI-F3 extra configs; `nativeBuildInputs += [ python3 dtc openssl ]`; `filesToInstall = [ "FSBL.bin" "bootinfo_emmc.bin" "u-boot.itb" ]`. **Highest-risk derivation.**
5. **`nix/overlay.nix`** — expose `bpi-f3-uboot` and `k1-opensbi` via `callPackage`.
6. **`nix/modules/sd-image/sd-image.nix`** — port LP4A patched generic sd-image (firmwarePartitionOffset + postBuildCommands hook + auto-expand postBootCommands).
7. **`nix/modules/sd-image/sd-image-bpi-f3.nix`** — extlinux loader; kernelParams `console=ttyS0,115200 earlycon=sbi root=UUID=… rootfstype=ext4 rootwait rw`; `firmwarePartitionOffset = 16`; `postBuildCommands` dd of the 4 blobs at sectors 0/1/1280/2048.
8. **`nix/modules/bpi-f3.nix`** — mainline `boot.kernelPackages`; `hardware.deviceTree.name = "spacemit/k1-bananapi-f3.dtb"`; `enableRedistributableFirmware`; K1 initrd modules; ssh + base tools; headless (no GPU).
9. **`nix/modules/user-group.nix`** — port LP4A, host `bpi-f3`, default user (documented password).
10. **`README.md`** — rewrite into a real guide (overview, hardware, layout, cross-compile + `rv64gcv` caveat, `nix build .#sdImage`, flashing, serial console, default creds, boot-blob offset table, limitations: PCIe/GPU/NPU status, cache divergence).

## Verification

1. `nix build .#opensbi` → `fw_dynamic.itb` present.
2. `nix build .#uboot` → `FSBL.bin`, `bootinfo_emmc.bin`, `u-boot.itb` present (highest-risk).
3. `nix build .#sdImage` → image built; verify bootloader bytes at sectors 0/1/1280/2048 match the package outputs (`cmp`/`dd`), and partition 1 starts past 16 MiB (`sfdisk -l`/`partx`).
4. `nix flake check`.
5. Hardware bring-up (on-device): flash whole image to SD, attach USB-UART, watch OpenSBI → U-Boot → extlinux → kernel on `ttyS0@115200`; confirm serial login, SD/eMMC, ethernet.

## Open risks

- Vendor U-Boot source build under Nix (python signing tooling, in-tree key, writable-tree assumptions). Fallback: vendor prebuilt blobs and `dd` those (documented in README), then revisit from-source.
- Exact mainline kernel version: pick the lowest nixpkgs kernel shipping `k1-bananapi-f3.dts` with K1 MMC/ethernet drivers; confirm during implementation.
- `rv64gcv` = no community-cache hits; first full build is long but fine on the build host.
