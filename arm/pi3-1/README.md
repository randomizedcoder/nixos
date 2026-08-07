# pi4-2 - Raspberry Pi 4

NixOS config for the Raspberry Pi 4 "pi4-2". Pi-specific support (kernel,
firmware, bootloader, vendor packages) comes from
[nixos-raspberrypi](https://github.com/nvmd/nixos-raspberrypi).

There are two ways to get this config onto the Pi:

1. **Build an SD-card image** and `dd` it to the card (first install).
2. **Deploy over SSH** with `nixos-rebuild --target-host` (updates).

## 1. Build the SD-card image

The image is cross-compiled from x86_64 to aarch64, so it builds on an
ordinary PC with no binfmt/QEMU emulation.

```sh
cd ~/nixos/arm/pi4-2
nix build .#nixosConfigurations.pi4-2-sdimage.config.system.build.sdImage
```

The result is a compressed image under `result/sd-image/`:

```sh
ls -lh result/sd-image/
# *.img.zst
```

The image uses the labels `NIXOS_SD` (root, ext4) and `FIRMWARE` (vfat),
and grows the root partition to fill the card on first boot.

## 2. Flash it to the SD card

Find the SD card device with `lsblk`. Look for the size that matches your
card (e.g. a 32GB card shows as ~29G).

```sh
lsblk
```

**WARNING:** `dd` overwrites the target device completely. Double-check the
device name (`/dev/sdX`) - writing to the wrong disk destroys data.

Decompress and write in one step:

```sh
zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=10MB status=progress conv=fsync
```

Replace `/dev/sdX` with your card (e.g. `/dev/sdb`). Use the whole disk
(`/dev/sdb`), not a partition (`/dev/sdb1`).

When `dd` finishes, eject the card, put it in the Pi, and power on. The root
partition expands to fill the card on the first boot.

## 3. Log in

There are two ways in, split by where you log in from:

- **Console (keyboard + monitor):** log in as `das` with the password `nixos`.
  Password auth is enabled on the local console only. This is how you read the
  IP off a headless box: log in, then run `ip -brief address show`.
- **SSH (over the network):** key only - both `das` and `root` accept the
  `das@t` key. Password auth over SSH is disabled.

```sh
ssh root@pi4-2.local
# or
ssh das@pi4-2.local
```

mDNS is enabled, so `pi4-2.local` should resolve on the LAN. If it does not,
find the Pi's IP from the console (`ip -brief address show`) or your DHCP
server / router and use that instead.

The console password is INSECURE (cleartext in the Nix config, world-readable
in the store). It is meant for an isolated lab network only. Change it via the
`password` line for the `das` user in `configuration.nix`.

## 4. Update over SSH (after first install)

Once the Pi is running you do not need to re-flash for changes. Edit the
config and push a new generation over SSH:

```sh
cd ~/nixos/arm/pi4-2
nixos-rebuild switch --flake .#pi4-2 --target-host root@pi4-2.local
```

## Files

- `flake.nix` - flake inputs and the two outputs (`pi4-2` deploy config,
  `pi4-2-sdimage` image build).
- `configuration.nix` - the machine config (hardware, filesystems, users,
  services).
- `home.nix` - home-manager config for the `das` user.
- `il8n.nix` - locale settings.
- `sshd-INSECURE.nix` - SSH server (root key-only, isolated lab network).
