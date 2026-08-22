# pi-bob - Raspberry Pi 5 NixOS demo card

A NixOS SD-card image for a Raspberry Pi 5, built for **Bob** (the iperf2
maintainer) to try NixOS on his Pi. Pi-specific support (kernel, firmware,
bootloader, vendor packages) comes from
[nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi).

This is a **demo card**. It ships with deliberately weak, obvious-to-change
passwords and password SSH login enabled, so it is easy to get into. **Change
the passwords** (see [§5](#5-change-the-passwords-do-this)) before using it
anywhere that matters.

The config is split into small modules under `nix/`, imported by a thin
`flake.nix` / `nix/configuration.nix`.

## ⚡ Power supply - use a real one (important)

The Raspberry Pi 5 needs a supply that can deliver a **stable 5 V at 5 A
(25 W)**, negotiated over USB-C PD. Use the **official Raspberry Pi 5 27 W
USB-C power supply** (or an equal that genuinely offers the *5 V/5 A* PD
profile), plugged **straight into the wall** with a good cable.

Do **not** power it from a random multi-port GaN "65 W / 100 W / 800 W" charger
or a hub. Those advertise their big wattage at *high* voltages (9/12/20 V); at
**5 V** most cap at 3 A (15 W) and don't offer 5 V/5 A at all, and per-port
current drops further when several ports are in use. The Pi 5 then browns out
under CPU + SD load.

Symptom we hit and diagnosed: under a `nixos-rebuild` the board would **hard-
hang** (dead network, needs a power-cycle). It looked like an SD-card or NixOS
problem, but the actual cause was **undervoltage** - the 5 V rail sagged from
5.04 V at idle to ~4.86 V under load (measured with `vcgencmd pmic_read_adc`),
below the Pi's ~4.63 V trip point. No amount of I/O tuning fixes a volts
problem.

Quick check on the Pi (any non-zero value = the supply isn't keeping up):

```sh
vcgencmd get_throttled                     # 0x0 = ok; 0x10000 = undervoltage since boot
vcgencmd pmic_read_adc EXT5V_V             # input voltage; should stay ~5.0-5.1 V under load
```

(The config still bounds the rebuild's memory/IO pressure - see
`nix/io-throttle.nix` - which lowers peak load, but a proper PSU is the real
fix.)

## Quick start (build, then flash to an SD card)

Build the image, find your SD card, and `dd` the image onto it - three
commands. Full detail and warnings are in [§1](#1-build-the-sd-card-image) and
[§2](#2-flash-it-to-the-sd-card) below; **double-check the `/dev/sdX` device -
`dd` to the wrong disk destroys data.**

```sh
# 1. build (cross-compiled x86_64 -> aarch64; no emulation needed)
cd ~/nixos/arm/pi-bob
nix build .#nixosConfigurations.pi-bob-sdimage.config.system.build.sdImage

# 2. find the SD card (match by size; here we pretend it is /dev/sdX)
lsblk

# 3. decompress + write to the WHOLE disk (not a partition), then sync
zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=10MB status=progress conv=fsync
sync
```

Worked example - a 32 GB card that showed up as `/dev/sdb` in `lsblk`:

```sh
zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdb bs=10MB status=progress conv=fsync
```

Eject the card, put it in the Pi, connect ethernet, power on, then
`ssh bob@pi-bob.local` (password `bob`). The root partition auto-grows to fill
the card on first boot.

## 1. Build the SD-card image

The image is cross-compiled from x86_64 to aarch64, so it builds on an ordinary
PC with no binfmt/QEMU emulation.

```sh
cd ~/nixos/arm/pi-bob
nix build .#nixosConfigurations.pi-bob-sdimage.config.system.build.sdImage
```

The result is a compressed image under `result/sd-image/`:

```sh
ls -lh result/sd-image/   # *.img.zst
```

The image uses the labels `NIXOS_SD` (root, ext4) and `FIRMWARE` (vfat), and
grows the root partition to fill the card on first boot. It is SD-card-only: no
NVMe drive is required.

## 2. Flash it to the SD card

Find the SD card device with `lsblk` (look for the size that matches your card).

**WARNING:** `dd` overwrites the target device completely. Double-check the
device name (`/dev/sdX`) - writing to the wrong disk destroys data.

```sh
lsblk
zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=10MB status=progress conv=fsync
```

Use the whole disk (`/dev/sdb`), not a partition (`/dev/sdb1`). When `dd`
finishes, eject the card, put it in the Pi, connect ethernet, and power on.

## 3. Log in

Plug the Pi into a wired network - it gets an IP over **DHCP**. mDNS is enabled,
so `pi-bob.local` should resolve on the LAN.

| Who       | Password    | SSH               | Notes                              |
|-----------|-------------|-------------------|------------------------------------|
| bob       | `bob`       | password or key   | add your key in `nix/users.nix`    |
| sebastian | `sebastian` | password or key   | German (de_DE) shell locale        |
| das       | `das`       | password or key   | the person who built the card      |
| root      | `root`      | password or key   | **change ASAP**                    |

All three users are in `wheel`, so they can `sudo`.

```sh
ssh bob@pi-bob.local          # password: bob
ssh sebastian@pi-bob.local    # password: sebastian
```

If `pi-bob.local` does not resolve, find the Pi's IP from the console
(`ip -brief address show`) or your router/DHCP server and use that instead.

## 4. Try WiFi (optional)

The Pi defaults to DHCP on the **wired** port. To use WiFi, edit
`nix/networking.nix`, uncomment the two `networking.wireless.*` lines, fill in
your SSID and WPA2 password, then rebuild (see below).

## 5. Change the passwords (do this)

The demo passwords are cleartext in the config and world-readable in the Nix
store. To change them, edit the `password = "...";` lines in `nix/users.nix`
(including the root password), then rebuild:

```sh
cd ~/nixos/arm/pi-bob
sudo nixos-rebuild switch --flake .#pi-bob
```

To move to SSH keys and turn passwords off entirely: add your public key under
your user in `nix/users.nix`, then in `nix/sshd.nix` set
`PasswordAuthentication = false;` (and `PermitRootLogin = "prohibit-password";`)
and rebuild.

## 6. iperf2 service

An iperf2 server runs on boot (built from upstream git master for
`--dual-transport`), listening on TCP/UDP **5001** and **5002**. The firewall is
open for those ports.

The server is gated with a light shared-secret via `--permit-key` (TCP only):
clients must present the same key or the test is refused. The demo key is
**`pleaseChangeMe`** - change it in `nix/iperf2.nix` (it is world-readable in
the Nix store, like the demo passwords). This uses iperf2's "professional
edition" build, enabled via a `--enable-professional` configure flag in that
module; a plain community-edition client can still connect by passing the key.

```sh
systemctl status iperf2                                    # on the Pi
iperf2 -c pi-bob.local -p 5001 --permit-key=pleaseChangeMe  # from another host
```

The full C/autotools toolchain (`gcc`, `autoconf`, `automake`, `libtool`,
`pkg-config`, `gdb`, `valgrind`, ...) is installed so Bob can build and run his
own iperf2 from source too.

## 7. Network performance tuning (dedicated NIC core)

Because Bob works on iperf2, the Pi is tuned to give **clean, repeatable network
numbers** rather than leaving throughput at the mercy of whatever else the box is
doing. See `nix/net-tuning.nix`.

The Pi 5's on-board 1 GbE (`end0`, behind the RP1 south-bridge) is a
**single-queue NIC**: one interrupt, no RSS, and by default all of it is
serviced on **CPU0** - right next to the SD-card controller. Under any other
load that core becomes the bottleneck and results get noisy.

The tuning dedicates **CPU3** to networking:

| CPUs | What runs there                                                     |
|------|---------------------------------------------------------------------|
| 0-2  | everything else: system services, your shell, monitoring, rebuilds  |
| 3    | the NIC (IRQ + rx/tx softirq) **and** the iperf2 server (shielded)  |

- The NIC's interrupt and packet processing (RPS/XPS) are steered onto CPU3.
- The iperf2 server runs in its own `netperf.slice`, pinned to CPU3.
- All other cgroups (`system.slice`, `user.slice`, including Grafana/Prometheus)
  are confined to CPU0-2 via cgroup `AllowedCPUs`, so nothing preempts the NIC.
- `irqbalance` is disabled so the placement sticks.

Check it on the Pi:

```sh
grep end0 /proc/interrupts                     # which CPU column is counting
taskset -cp "$(pgrep -x iperf2 | head -1)"     # iperf2 server -> CPU 3
cat /sys/class/net/end0/queues/rx-0/rps_cpus   # RPS mask -> 8 (i.e. CPU3)
```

Knobs (all in `nix/net-tuning.nix`): change `netCore`; widen the iperf2 slice to
two cores (`AllowedCPUs = "2-3"`) for high-PPS / multi-stream tests; or split the
IRQ (CPU3) and iperf2 (CPU2) onto separate cores for true IRQ/app parallelism.
Trade-off: dedicating a core leaves three for general work, so on-Pi rebuilds run
a little slower - deliberate, since consistent network performance is the point.

Note: a client you launch by hand (`iperf2 -c ...`) runs in `user.slice` on
CPU0-2, not the network core - use `taskset -c 3 iperf2 -c ...` to put it there.

## 8. Monitoring dashboard (Grafana + Prometheus)

For full visibility into the Pi there's a self-contained metrics stack - all on
the box, no cloud or external services. See `nix/monitoring.nix`.

```
node_exporter (:9100)  -->  Prometheus (:9090)  -->  Grafana (:3000)
```

- **node_exporter** exposes host metrics (CPU, memory, disk, network, systemd).
- **Prometheus** scrapes it every 15 s (7-day retention, to be gentle on the SD).
- **Grafana** serves the web UI, is pre-wired to Prometheus as its default data
  source, and auto-loads the **Node Exporter Full** dashboard.

Open it from any browser on the LAN:

```
http://pi-bob.local:3000        (or http://<pi-ip>:3000)
```

Log in as **admin / admin** (demo credentials - change on first login or in
`nix/monitoring.nix`) and open the "Node Exporter Full" dashboard. Prometheus'
own query UI is at `http://pi-bob.local:9090`.

Note: Grafana and Prometheus write to the SD card continuously; retention is kept
short to limit wear. Remove `nix/monitoring.nix` from the imports in
`nix/configuration.nix` if you don't want the stack.

## 9. Edit the config ON the Pi and rebuild

A **writable copy of this config ships on the Pi** at `~/pi-bob` (seeded into
bob's home on first boot). Bob can edit it directly on the Pi and rebuild - no
laptop or re-flash needed:

```sh
cd ~/pi-bob
# edit nix/*.nix or flake.nix, e.g. change a password or add a package
sudo nixos-rebuild switch --flake ~/pi-bob#pi-bob
```

The Pi builds natively (aarch64) - slower than a PC, but the nixos-raspberrypi
binary cache is preconfigured so it won't recompile the kernel. It needs
internet access the first time (to fetch the flake inputs). The seeded copy is
only created if `~/pi-bob` doesn't exist, so edits survive future rebuilds; to
start over, `rm -rf ~/pi-bob` and rebuild once to re-seed a pristine copy.

**Heads-up on build times:** most packages come pre-built from the binary
caches, but anything not cached for aarch64 (e.g. a fresh Grafana/Prometheus, or
a package you bump ahead of Hydra) is compiled **from source on the Pi**, which
can take a long time and thermally throttle the board. When that happens, prefer
building on a real PC and pushing the result - see §11.

## 10. Update over SSH from your PC

Push a new generation to the Pi over SSH from wherever you keep this repo. The
system is **built on your PC**, then only the result is copied to the Pi and
activated (nothing is compiled on the Pi):

```sh
cd ~/nixos/arm/pi-bob
nixos-rebuild switch --flake .#pi-bob --target-host root@pi-bob.local
```

This builds `pi-bob` for aarch64. If your PC is x86_64 it needs aarch64
emulation (binfmt) to build the few uncached packages - which is slow. For a
fast build, use the cross-compiled target instead (§11).

## 11. Cross-compile on your PC, then push (fastest)

The `pi-bob-cross` output is the exact same system as `pi-bob`, but
**cross-compiled from x86_64** - so a powerful PC builds the aarch64 system at
native speed (no emulation) and pushes it to the Pi:

```sh
cd ~/nixos/arm/pi-bob
nixos-rebuild switch --flake .#pi-bob-cross --target-host root@pi-bob.local
```

Use this whenever a package isn't in the aarch64 binary cache (Grafana and
Prometheus currently aren't for this nixpkgs pin), so the Pi never has to
compile it - your PC does, quickly, and copies the finished closure over.

The SD image (`pi-bob-sdimage`, §1) is cross-compiled the same way, so a freshly
flashed card already contains everything (monitoring, tuning, iperf2) with no
first-boot compiling.

## 12. Keep it up to date (newer kernel + packages)

Every version is pinned in `flake.lock`, so builds are reproducible until you
choose to move forward. To pull newer versions of everything - kernel, nixpkgs
packages, home-manager, the Raspberry Pi support - update the flake inputs, then
rebuild:

```sh
cd ~/pi-bob                 # on the Pi (or ~/nixos/arm/pi-bob on your PC)
nix flake update           # rewrite flake.lock to the latest inputs
sudo nixos-rebuild switch --flake ~/pi-bob#pi-bob        # rebuild on the Pi
# ...or cross-compile + push from a PC (fastest, see §11):
#   nixos-rebuild switch --flake .#pi-bob-cross --target-host root@pi-bob.local
```

`nix flake update` only rewrites the lock file; `nixos-rebuild switch` is what
actually builds and activates the new generation. Notes:

- Update a single input instead of all of them: `nix flake update nixpkgs`
  (or `nixos-raspberrypi`, `home-manager`).
- Type-check the config without building anything: `nix flake check`.
- If a rebuild goes wrong, you can always roll back to the previous generation:
  `sudo nixos-rebuild switch --rollback` (or pick one from the boot menu).

## Files

- `flake.nix` - inputs and three outputs: `pi-bob` (native deploy config),
  `pi-bob-cross` (same system cross-compiled from x86_64 for fast PC builds,
  §11), and `pi-bob-sdimage` (the flashable image); wires home-manager for all
  three users.
- `nix/configuration.nix` - thin top-level: imports the modules below + core
  system settings.
- `nix/hardware.nix` - SD-card-only filesystems + bootloader.
- `nix/networking.nix` - hostname, DHCP, mDNS, commented WiFi example.
- `nix/users.nix` - bob / sebastian / das / root (demo passwords).
- `nix/il8n.nix` - locales (en_US default + de_DE generated for Sebastian).
- `nix/sshd.nix` - SSH server (password login on - demo).
- `nix/packages.nix` - system-wide dev / networking / general tools.
- `nix/iperf2.nix` - iperf2 dual-transport server (systemd).
- `nix/net-tuning.nix` - dedicates a CPU core to the NIC IRQ + iperf2 (§7).
- `nix/monitoring.nix` - node_exporter + Prometheus + Grafana metrics stack (§8).
- `nix/io-throttle.nix` - bounds dirty-page/IO pressure so heavy writes stay
  smooth on the SD (SD hygiene, not a stability fix - see the file's header).
- `nix/swap.nix` - zram (RAM-backed) swap, cheap headroom with no SD wear.
- `nix/seed-config.nix` - drops a writable copy of this config into
  `/home/bob/pi-bob` on first boot (so Bob can edit + rebuild on the Pi).
- `nix/home-common.nix` - shared home-manager baseline (a function of the
  per-user parameters).
- `nix/home-bob.nix`, `nix/home-sebastian.nix`, `nix/home-das.nix` - per-user
  home configs; each imports the baseline and can be customised independently.
  Sebastian's sets the German (de_DE) locale.
