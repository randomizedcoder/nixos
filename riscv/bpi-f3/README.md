# nixos-bpi-f3

NixOS for the [Banana Pi BPI-F3](https://docs.banana-pi.org/en/BPI-F3/BananaPi_BPI-F3) — an octa-core [SpacemiT K1](https://www.spacemit.com/en/key1/) RISC-V SBC (RVA22 + RVV 1.0).

This flake **cross-compiles** a headless NixOS SD-card image from an `x86_64` host to `riscv64`, with the SpacemiT bootloader (U-Boot 2022.10 + OpenSBI) built from source and embedded in the image. The bootloader is Armbian's U-Boot fork (`pyavitz/spacemit-u-boot`) plus its patch set; OpenSBI is the SpacemiT gitee tree. There is no turnkey NixOS image for this board upstream — this is a "roll your own" build, adapted from [nixos-licheepi4a](https://github.com/randomizedcoder/nixos-licheepi4a).

**Status: confirmed booting on real hardware** — NixOS 26.11, mainline kernel 7.0.12, root on the SD card. Working: serial console, SD card + eMMC, both Gigabit Ethernet ports, USB 2.0/3.0, NVMe over PCIe, and SSH. See [Challenges worked around](#challenges-worked-around) and [Limitations](#limitations).

## Quick start

You build on an **`x86_64-linux`** machine; the flake cross-compiles to `riscv64` automatically (it sets `nixpkgs.crossSystem`), so there is nothing special to configure — just `nix build`.

**Prerequisites**

- Nix with flakes enabled. Either use `--extra-experimental-features 'nix-command flakes'` on each command, or add to `~/.config/nix/nix.conf` (or `/etc/nix/nix.conf`):
  ```
  experimental-features = nix-command flakes
  ```
- A fast x86_64 builder with plenty of disk/RAM. Because we target `rv64gcv` (see Scope), the build gets **no** binary-cache hits and compiles the cross toolchain + the whole closure from source — budget a long first build (hours, not minutes) and tens of GB of store.

**Clone, build, flash**

```sh
# 1. Clone
git clone https://github.com/randomizedcoder/nixos-bpi-f3.git
cd nixos-bpi-f3

# 2. Cross-compile the SD image (runs on x86_64, produces a riscv64 image).
#    Tip: add `--log-format internal-json -v |& nom` (nix-output-monitor) to watch progress,
#    or `-j auto` to use all cores.
nix build .#sdImage

# 3. Flash the whole image to an SD card (bootloader blobs are already embedded — see below).
lsblk                                   # find your card, e.g. /dev/sdX  (NOT a partition)
sudo dd if=result/sd-image/nixos-bpi-f3-sd-image-*.img \
        of=/dev/sdX bs=4M conv=fsync status=progress

# 4. Insert the card, connect a USB-UART (115200 8N1), power on, and log in as bpi / bpi-f3.
```

That's it — no manual U-Boot flashing, no separate firmware step. The SpacemiT bootloader is built from source and `dd`'d into the image during the build.

> First time on RISC-V Nix? You don't need a riscv64 machine or QEMU — cross-compilation does it all on x86_64. If a build step is too slow locally, point Nix at a beefier [remote builder](https://nix.dev/manual/nix/stable/advanced-topics/distributed-builds).

## Scope

- **Headless, mainline kernel.** Uses a recent nixpkgs kernel (`linuxPackages_latest`, 7.0.x) with the in-tree `k1-bananapi-f3` device tree. Confirmed working on hardware: serial console, **SD card** and eMMC, both **Gigabit Ethernet** ports, USB 2.0/3.0, **NVMe over PCIe**, and SSH.
- **SD-card slot needs a DT overlay.** Mainline's `k1-bananapi-f3.dtb` only wires up the eMMC; the removable SD slot controller (`mmc@d4280000`) is missing upstream. This flake adds it back via a device-tree overlay (`nix/modules/hardware.nix` + `nix/modules/sd-overlay.dts`), so the kernel can use the card we boot from.
- **No GPU / NPU.** The IMG BXE GPU and the AI accelerator only work on the vendor (Bianbu) kernel. If you need them, you'll have to package that kernel — out of scope here.
- **ISA baseline `rv64gcv` (RVV 1.0 enabled).** The K1's X60 cores implement RVV 1.0. Note this diverges from the riscv64 community binary caches (which target `rv64gc`), so **the whole closure is built locally** — the first build is long and gets no cache hits. Build it on a fast machine.

## Repository layout

`flake.nix` (flake-parts) is intentionally thin; everything substantive is a module/derivation under `nix/`:

```
flake.nix                              # flake-parts: inputs + perSystem (packages/formatter/checks/devShell)
nix/
  cross.nix                            # cross target: riscv64, rv64gcv / lp64d
  overlay.nix                          # exposes the bootloader packages
  modules/
    default.nix                        # aggregator: imports the modules below
    kernel.nix                         # kernel package + forced K1 Kconfig + initrd
    hardware.nix                       # device tree + the SD-card-slot overlay + firmware
    sd-overlay.dts                     # the re-added SD-slot controller node (mmc@d4280000)
    base.nix                           # console/getty, ssh, packages, nix settings, stateVersion
    user-group.nix                     # default user / hostname
    sd-image/
      sd-image.nix                     # patched generic sd-image module (MBR + raw-blob dd hook)
      sd-image-bpi-f3.nix              # board image: extlinux, kernelParams, dd of the boot blobs
  pkgs/
    u-boot/default.nix                 # Armbian U-Boot fork -> FSBL.bin, bootinfo_emmc.bin, u-boot.itb
    u-boot/patches/                    # Armbian's u-boot-spacemit-k1 patch set (vendored)
    opensbi/default.nix                # vendor OpenSBI -> fw_dynamic.itb
```

## Development

```sh
nix fmt           # format (treefmt: nixfmt + deadnix)
nix flake check   # eval + formatting + statix lint gate
nix develop       # shell with nixfmt, deadnix, statix, dtc, nix-output-monitor
```

## Build outputs

The [Quick start](#quick-start) covers the common path (`nix build .#sdImage`). Individual outputs:

```sh
nix build .#sdImage    # default; the full SD image -> result/sd-image/*.img (uncompressed)
nix build .#uboot      # bootloader only: FSBL.bin, bootinfo_emmc.bin, u-boot.itb
nix build .#opensbi    # OpenSBI only: fw_dynamic.itb
```

Building `.#uboot` / `.#opensbi` on their own is handy when iterating on the (highest-risk) vendor bootloader build without rebuilding the kernel and rootfs.

## Flashing

See [Quick start](#quick-start) step 3 for the `dd` command. Two things worth knowing:

- The bootloader blobs are embedded at their raw offsets during the build, so a plain whole-image `dd` is all that's needed — no separate U-Boot flashing.
- The root (ext4) partition **auto-expands** to fill the card on first boot.
- Flashing the same image to **eMMC** should also work (mainline has the eMMC node, and the BootROM tries SD then eMMC) — but this is **untested**; only SD boot is verified.

## Boot flow & on-disk layout

The SpacemiT BootROM reads a small boot-info header at sector 0, then chains through the FSBL (SPL), OpenSBI and U-Boot. These live at fixed raw sector offsets ahead of the first partition (matching Armbian's `write_uboot_platform`):

| Artifact                     | Sector | Byte offset | Source      |
| ---------------------------- | ------ | ----------- | ----------- |
| `bootinfo_emmc.bin`          | 0      | `0x0`       | `.#uboot`   |
| `FSBL.bin` (SPL)             | 1      | `0x200`     | `.#uboot`   |
| `fw_dynamic.itb` (OpenSBI)   | 1280   | `0x140000`  | `.#opensbi` |
| `u-boot.itb` (U-Boot proper) | 2048   | `0x200000`  | `.#uboot`   |

The two partitions (both in the one MBR table, first one starting at 16 MiB) are:

| Part | Filesystem | Label | Contents |
| --- | --- | --- | --- |
| 1 | FAT32 (`vfat`) | `BOOT` | `extlinux.conf` + kernel + DTB + initrd |
| 2 | ext4 | `NIXOS_SD` | root filesystem (auto-expands on first boot) |

### Why the partition table is MBR, not GPT

The on-disk **partition table is MBR** (a.k.a. "msdos"/"dos"). Note this is a _different layer_ from the boot partition's **FAT32 filesystem** — "msdos" as a partition _table_ means MBR, while FAT32 is the _filesystem_ living inside partition 1. They're independent; FAT32 works inside either an MBR or a GPT partition.

We must use MBR because of the raw-sector boot blobs above:

- A **GPT** keeps its primary header at **sector 1 (LBA1)** — exactly where `FSBL.bin` is `dd`'d. Writing the SPL there corrupts the GPT.
- **MBR** keeps all its metadata in **sector 0** only (partition table at byte offset 446). The tiny (~80 byte) `bootinfo_emmc.bin` at offset 0 fits _before_ that table, and sectors 1+ are free for the bootloader. No collision.

This is exactly what Armbian — one of the distros listed on the [BPI-F3 page](https://docs.banana-pi.org/en/BPI-F3/BananaPi_BPI-F3) — does for this board. From `config/sources/families/spacemit.conf`:

```bash
pre_prepare_partitions() {
	declare -g OFFSET="4"                       # first partition at 4 MiB (we use 16 MiB)
	declare -g IMAGE_PARTITION_TABLE="msdos"    # MBR, not GPT
}
```

which Armbian's core turns into an `sfdisk` `label: dos` (MBR) table.

### Boot chain

BootROM → FSBL (SPL) → OpenSBI → U-Boot proper → extlinux → Linux kernel.

## Serial console

Connect a 3.3 V USB-UART to the F3's debug UART header and open it at **115200 8N1**:

```sh
picocom -b 115200 /dev/ttyUSB0         # recommended
```

Kernel console is `ttyS0,115200`, with `earlycon=uart8250,mmio32,0xd4017000` for output from the very first boot stage (`earlycon=sbi` produced nothing on this board).

> Gotcha: **minicom** may silently _not_ apply the baud rate, showing a screen of garbage that looks like a hardware fault — our entire "garbled serial" detour was minicom, not the board. Prefer `picocom`, or capture raw with `stty -F /dev/ttyUSB0 115200 raw -echo; cat /dev/ttyUSB0`.

## Default login

- user: **`bpi`**
- password: **`bpi-f3`**

Change these in `nix/modules/user-group.nix` (regenerate the hash with `mkpasswd -m yescrypt`) before putting the board on an untrusted network.

## First boot

The board's RTC isn't persisted, so the clock starts behind (around the image build date). Until `systemd-timesyncd` syncs over the network, TLS fails — `nix-shell`, channel fetches, etc. error with _"certificate is not yet valid or the system clock is incorrect"_. Wait a few seconds after the NIC comes up, or nudge it:

```sh
timedatectl                              # want 'System clock synchronized: yes'
sudo systemctl restart systemd-timesyncd
```

## Fast storage: root on the NVMe

The SD card is the bottleneck — under a Nix/kernel build it saturates the MMC controller (you'll see `mmc_rescan … blocked for more than 120 seconds` in `dmesg`). The fix is to move `/` (and the whole Nix store) onto the NVMe, which is far faster. Boot **stays on the SD card**: the SpacemiT K1 BootROM has no PCIe driver, so the first-stage bootloader (FSBL → OpenSBI → U-Boot) can only come from SD/eMMC. The kernel + initrd live on the SD's FAT partition, the initrd brings up PCIe (built into the kernel) + NVMe (an initrd module), and root is mounted from the NVMe by label. **Keep the SD card inserted** afterwards.

### How it works

- `nixosConfigurations.bpi-f3-nvme` is the same system as the SD build but with `/` on `by-label/NIXOS_NVME` ([`nix/modules/nvme/root.nix`](./nix/modules/nvme/root.nix)). Its toplevel is shipped **inside** the SD image, so migration needs no network and no on-device compiling.
- [`nix/modules/nvme/provision.nix`](./nix/modules/nvme/provision.nix) adds the `bpi-f3-nvme-install` command and a first-boot service.

### Brand-new device (automatic)

On first boot, if the NVMe is **completely blank**, the system auto-migrates onto it and reboots — you'll see the progress on the serial console. An NVMe that already holds any partition table or filesystem is left untouched. Disable with `bpi-f3.nvme.autoInstall = false;`.

### Manually (or to re-run)

```sh
sudo bpi-f3-nvme-install            # interactive: prompts before erasing the NVMe
sudo bpi-f3-nvme-install --yes      # skip the confirmation
sudo bpi-f3-nvme-install --yes --reboot
```

It partitions + formats the NVMe (`NIXOS_NVME`), clones the running system onto it (`rsync`, preserving all state), points the SD boot config at the NVMe-root system, and reboots. After that, `/` is on the NVMe and on-device `nixos-rebuild`s target the `bpi-f3-nvme` configuration. (The migration **wipes** the NVMe — it refuses to touch a mounted device, but there is no undo.)

### Wiping the NVMe

To erase the NVMe back to blank (e.g. to re-test the auto-install from a clean state):

```sh
sudo bpi-f3-nvme-wipe          # warns, shows the disk, and defaults to aborting
sudo bpi-f3-nvme-wipe --yes    # skip the confirmation
```

It refuses to touch a mounted device, so run it from the SD-booted system (not while `/` is on the NVMe).

### After migration

- **Swap:** the NVMe system creates `/swapfile` sized to RAM at boot (read from `MemTotal`, so it adapts to 4/8/16 GB boards) — headroom against OOM-kills during heavy `make -j` kernel builds.
- **On-device rebuilds:** `nixos-rebuild switch` works directly on the board — the NVMe system installs the kernel/initrd/`extlinux.conf` to the SD's `/boot/firmware` (auto-mounted) where U-Boot reads them, so kernel changes take effect without reflashing.
- **Reboot quirk:** a plain `reboot` sometimes hangs at `reboot: Restarting system` (the vendor OpenSBI/DT doesn't fully wire SBI/PSCI system-reset on this board). If it doesn't come back within a few seconds, **power-cycle** — a cold boot always works.
- The SD slot is pinned `non-removable` in the DT overlay so it stays enumerated under Linux (software card-detect polling otherwise spuriously dropped it, taking `/boot/firmware` with it).

## Challenges worked around

Getting this to boot on real hardware meant solving a chain of non-obvious problems. They're recorded here (and in [`PROGRESS.md`](./PROGRESS.md)) so the config's quirks make sense to whoever reads it next:

- **OpenSBI vs GCC 15 / C23** — the vendor tree has `typedef int bool;`, which GCC 15 (defaulting to `-std=c23`, where `bool` is a keyword) rejects under `-Werror`. Built with `platform-cflags-y=-std=gnu17`.
- **U-Boot fork + patch set** — stock vendor U-Boot's SPL loads OpenSBI/U-Boot only from GPT partitions _named_ `opensbi`/`uboot`, and boots via bespoke env scripts, not extlinux. We build **Armbian's fork** (`pyavitz/spacemit-u-boot`) + its patches: `001` adds the raw-offset SPL fallback (`0x500`/`0x800` = our `dd` sectors 1280/2048), `002`/`004` add the MMC boot target + syslinux/extlinux support.
- **MBR, not GPT** — the SpacemiT FSBL is `dd`'d to sector 1, exactly where a GPT primary header lives. MBR keeps all metadata in sector 0, so the tiny boot-info header coexists and the SPL is safe at sector 1.
- **256-byte kernel cmdline cap** — the vendor U-Boot truncates `bootargs` at 256 bytes; NixOS's long `init=/nix/store/…` path blew past it. Trimmed redundant params (the initrd mounts root by label).
- **`mmc_block` was a module** — `MMC_BLOCK=m` upstream and udev didn't autoload it in the initrd, so no `/dev/mmcblk*` appeared and root timed out. Force-loaded via `boot.initrd.kernelModules`.
- **SD-card slot missing from the mainline DTS** — the headline gap (see Limitations); re-added via a device-tree overlay.
- **`spacemit_sdhci_set_uhs_signaling` panic** — the SD node needed `no-mmc`/`no-sdio`/`no-1-8-v` to skip the eMMC/SDIO `VDD_180` register path the slot faults on.
- **SD mounted read-only** — microSD has no write-protect tab, but the controller's WP sense reads "protected"; `disable-wp` makes it writable (otherwise root mounts ro and boot fails).
- **"Garbled serial"** — minicom silently didn't apply 115200, and `earlycon=sbi` produced nothing; using `picocom` + `earlycon=uart8250,mmio32,0xd4017000` gave clean early output.

## Limitations

This is a **mainline, headless** build — we did **not** do the vendor "custom work" (the closed-driver integration that the Bianbu vendor kernel ships):

- **No display / GPU** (IMG BXE) and **no NPU / AI accelerator.** These only work on the vendor (Bianbu) kernel with proprietary drivers; not attempted here. This board is headless/server/dev-box only.
- **SD-card slot works only via our DT overlay.** Mainline's `k1-bananapi-f3.dtb` wires up just the eMMC; we re-add the slot controller (`spacemit,k1-sdhci` @ `d4280000`, with `no-mmc`/`no-sdio`/`no-1-8-v`/`broken-cd`/`disable-wp`). Drop the overlay if a future kernel adds it upstream.
- **Wi-Fi** — the on-board chip (e.g. `8852bs`) needs an out-of-tree driver; not included.
- **RTC** is not persisted across power cycles — the clock relies on NTP (see [First boot](#first-boot)).
- **Binary caches** — targeting `rv64gcv` diverges from the riscv64 community caches, so there are no cache hits; the first build compiles the whole closure locally.

## References

- BPI-F3 docs: <https://docs.banana-pi.org/en/BPI-F3/BananaPi_BPI-F3>
- U-Boot fork we build (Armbian's): <https://github.com/pyavitz/spacemit-u-boot> (tag `k1-bl-v2.2.9-release`)
- SpacemiT OpenSBI: <https://gitee.com/spacemit-buildroot/opensbi>
- Armbian (BPI-F3 board + spacemit family configs + U-Boot patches): <https://github.com/BPI-SINOVOIP/armbian-build>
- Base flake (Lichee Pi 4A): <https://github.com/randomizedcoder/nixos-licheepi4a>

See [`IMPLEMENTATION.md`](./IMPLEMENTATION.md) for the design and [`PROGRESS.md`](./PROGRESS.md) for status.
