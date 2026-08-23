#
# arm/pi-bob/nix/io-throttle.nix
#
# SD-card protection + interactive responsiveness during heavy writes
# (e.g. an on-Pi `nixos-rebuild`). This is good hygiene for slow SD storage,
# not a stability fix - see the history note below.
#
# ---------------------------------------------------------------------------
# History (so nobody re-derives this the hard way)
# ---------------------------------------------------------------------------
# These knobs were first added while chasing on-Pi rebuild LOCK-UPS. The actual
# cause of those turned out to be an inadequate power supply: under CPU+SD load
# the Pi 5's 5 V rail sagged (~5.04 V -> ~4.86 V, measured with `vcgencmd
# pmic_read_adc EXT5V_V`) and the board browned out. A proper 5 V/5 A (27 W)
# supply fixed the hangs completely. So NONE of this module is load-bearing for
# stability. We keep it because it still earns its place on SD:
#   - it bounds write bursts, leaving the card headroom instead of pinning it at
#     100% (protects the card, cuts the chance of long writeback stalls), and
#   - it keeps a shell responsive while a rebuild churns.
# Drop the whole module on fast/NVMe storage where none of this is needed.
#
{ ... }:

{
  # 1. Bound the dirty page cache. By default the kernel lets dirty pages grow
  #    to a percentage of RAM (dirty_ratio=20 -> ~1.6 GB on 8 GB) before forcing
  #    writeback - far more than a slow SD can flush at once, so writeback turns
  #    into one big deferred stall. Capping the absolute bytes keeps writeback
  #    small and continuous. (Setting the *_bytes knobs disables the
  #    percentage-based *_ratio knobs automatically.)
  boot.kernel.sysctl = {
    "vm.dirty_background_bytes" = 16 * 1024 * 1024; # start flushing at 16 MiB
    "vm.dirty_bytes" = 64 * 1024 * 1024; # block writers once 64 MiB dirty
  };

  # 2. Rate-limit nix's writes to the SD and give interactive sessions I/O
  #    priority. The heavy writer during a rebuild is nix-daemon, so cap its
  #    sustained write bandwidth to leave the card headroom; reads are left
  #    uncapped. The path is resolved to its backing block device (the SD), so
  #    this follows the disk without hard-coding /dev/mmcblk0. 30M is a
  #    conservative protective cap - raise it for faster builds if the card
  #    keeps up, lower it to be gentler.
  #
  #    Requires the cgroup-v2 io controller (the Pi vendor kernel has it). Safe
  #    next to the dirty-bytes cap above: that keeps the writeback backlog small,
  #    so this bandwidth cap can never back up a large buffered-write queue.
  systemd.services.nix-daemon.serviceConfig = {
    IOWeight = 50; # yield to everything else under I/O contention
    IOWriteBandwidthMax = "/nix 30M"; # ~30 MB/s sustained write cap to the SD
  };

  # Interactive user sessions win I/O over background bulk work, so a shell stays
  # usable while a rebuild writes the store.
  systemd.slices.user.sliceConfig.IOWeight = 500;
}
