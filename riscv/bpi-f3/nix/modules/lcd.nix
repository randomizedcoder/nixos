# USB character-LCD status panel (LCD2USB, USB 0403:c630).
#
# Drives the small HD44780 panel plugged into the board's USB with a live
# system summary — hostname, IP, CPU, memory, disk, load, uptime.
#
# Architecture:
#   * LCDd (lcdproc server) talks to the panel via the `hd44780` driver with
#     `ConnectionType=lcd2usb` (LCD2USB is an hd44780 connection backend, not a
#     standalone driver — hd44780.so carries the lcd2usb/libusb support). The
#     upstream `services.hardware.lcd` module runs LCDd and installs the udev
#     rule that grants the panel's USB node group-write access.
#   * A small custom client (./lcd-client.py) feeds the summary over the LCDd
#     socket protocol. We use our own client rather than the stock `lcdproc`
#     one because the built-in screens have no hostname/IP display, and because
#     ours reads the panel geometry from the LCDd handshake and adapts its
#     layout (rotating pages on the 2-row 1602, one static screen on >=4 rows).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # LCD2USB adapter (Till Harbaum), USB vendor:product 0403:c630.
  usbVid = "0403";
  usbPid = "c630";

  # Physical panel geometry (cols x rows). The hardware here is a 1602 (16x2).
  # The client reads the *actual* geometry from LCDd's handshake, so this value
  # only needs to match the panel for LCDd's own wrapping — change it if you
  # swap the panel.
  panelSize = "16x2";

  # The client is now a small native Rust binary (./lcd-client.rs) instead of a
  # python3Minimal script — a fraction of the store closure and runtime RAM.
  # The Python version (./lcd-client.py) is kept in the tree for reference and
  # for the `--selftest` parity check that proved the two render identically.
  #
  # lcdClient = pkgs.writeScriptBin "bpi-f3-lcd-client" ''
  #   #!${pkgs.python3Minimal}/bin/python3
  #   ${builtins.readFile ./lcd-client.py}
  # '';
  lcdClient = pkgs.callPackage ./lcd-client-rust.nix { };

  # LLDP dumper for the split-privilege switch/port page (see the service
  # below). Atomic tmp+rename so the client never reads a half-written file.
  lldpDump = pkgs.writeShellApplication {
    name = "bpi-f3-lcd-lldp-dump";
    runtimeInputs = [
      pkgs.lldpd
      pkgs.coreutils
    ];
    text = ''
      lldpcli show neighbors -f keyvalue > /run/lcd/lldp.kv.tmp
      mv -f /run/lcd/lldp.kv.tmp /run/lcd/lldp.kv
    '';
  };
in
{
  # LCDd + the lcd2usb driver, plus the udev rule granting the panel's USB node
  # group-write (default group `dialout`) so the DynamicUser LCDd can drive it.
  services.hardware.lcd = {
    server = {
      enable = true;
      usbPermissions = true;
      inherit usbVid usbPid;
      extraConfig = ''
        Driver=hd44780

        [hd44780]
        ConnectionType=lcd2usb
        Size=${panelSize}
      '';
    };
    # Ship our own client (the systemd service below), not the stock one.
    client.enable = false;
  };

  # LCDd loses a boot-time race: it can start before udev has applied the
  # panel's group-write rule (USB enumerates several seconds into boot on this
  # board), fail to open the device, and hit systemd's default 5-in-10s start
  # limit — leaving LCDd dead until a manual restart. Disable the burst limit
  # and back off a couple of seconds so it simply retries until the panel is
  # ready. (LCDd already has Restart=on-failure from the upstream module.)
  systemd.services.lcdd = {
    startLimitIntervalSec = 0;
    serviceConfig.RestartSec = 2;
  };

  environment.systemPackages = [ lcdClient ];

  systemd.services.bpi-f3-lcd-client = {
    description = "BPI-F3 LCD system-status client (LCD2USB)";
    # If LCDd restarts, our socket breaks and we exit non-zero; Restart brings
    # us back and we re-handshake. `wants` (not `requires`) keeps us decoupled.
    after = [ "lcdd.service" ];
    wants = [ "lcdd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${lcdClient}/bin/bpi-f3-lcd-client";
      Restart = "on-failure";
      RestartSec = "5";

      # --- Hardening -----------------------------------------------------
      # This client needs almost nothing: a loopback TCP socket to LCDd and
      # read access to /proc (stats) + one SIOCGIFADDR ioctl (its IP). It never
      # touches the LCD device (LCDd owns that), writes no files, and needs no
      # privileges — so we strip essentially everything else. Verify with
      # `systemd-analyze security bpi-f3-lcd-client.service`.
      DynamicUser = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";

      # Filesystem: read-only /nix + /proc, private everything else, no /dev
      # nodes (PrivateDevices leaves only null/zero/full/random/urandom/tty —
      # enough for the Python runtime's getrandom fallback).
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      PrivateMounts = true;
      ProtectProc = "invisible";
      ProcSubset = "all"; # we read /proc/meminfo, /proc/stat, /proc/net/route
      ProtectControlGroups = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      RemoveIPC = true;
      UMask = "0077";

      # Network: loopback only (LCDd on 127.0.0.1:13666). The IP lookup is a
      # local ioctl, so no traffic ever needs to leave. The client never
      # listens, so deny binding entirely.
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_UNIX"
      ];
      IPAddressDeny = "any";
      IPAddressAllow = "localhost";
      SocketBindDeny = "any";

      # Syscalls: a plain userspace service; drop privileged + resource-control
      # families and reject anything outside @system-service.
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "~@resources"
      ];
      SystemCallErrorNumber = "EPERM";

      # --- Resource caps -------------------------------------------------
      # The Rust client idles at ~1.7 MB RSS and wakes once a second to read a
      # few /proc files and push ~2 lines to LCDd — it needs almost nothing.
      # Cap memory hard (well above steady state, so a leak trips a restart
      # rather than eating the board) with no swap, and hand it a thin CPU
      # slice. It spawns no threads, so a low task ceiling is plenty.
      MemoryHigh = "12M";
      MemoryMax = "24M";
      MemorySwapMax = "0";
      CPUQuota = "5%";
      TasksMax = 16;
    };
  };

  # LLDP neighbour dump for the LCD client. The client is locked down (see
  # above): it runs as a DynamicUser with no access to lldpd's _lldpd-only
  # control socket and no right to exec anything. So a separate, minimal helper
  # queries lldpd and drops a keyvalue file into /run/lcd that the client only
  # ever *reads* — the switch/port page works without widening the client's
  # sandbox at all. The split is the whole point: the thing that touches lldpd
  # is not the thing on the network-facing display loop.
  # Shared group + world-readable dir bridging the two halves: the LLDP helper
  # (member of `lcd`) writes /run/lcd/lldp.kv; the client just reads it.
  users.groups.lcd = { };
  systemd.tmpfiles.rules = [ "d /run/lcd 2775 root lcd -" ];

  systemd.services.bpi-f3-lcd-lldp = {
    description = "Dump LLDP neighbours to /run/lcd/lldp.kv for the LCD client";
    after = [ "lldpd.service" ];
    wants = [ "lldpd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lldpDump}/bin/bpi-f3-lcd-lldp-dump";

      # Write into /run/lcd, a persistent world-readable dir created by tmpfiles
      # (below) owned by the shared `lcd` group. We can't use RuntimeDirectory
      # here: with DynamicUser + ProtectSystem=strict systemd relocates it under
      # /run/private (0700 root) and symlinks /run/lcd to it, which the
      # locked-down client can't traverse. Instead we punch just this one path
      # writable through ProtectSystem=strict; the client only ever reads it.
      ReadWritePaths = [ "/run/lcd" ];

      # A throwaway user in only the _lldpd group (to reach lldpd's control
      # socket) and the `lcd` group (to write the dump dir) — never root.
      DynamicUser = true;
      SupplementaryGroups = [
        "_lldpd"
        "lcd"
      ];

      # Hardening: it execs lldpcli and talks a Unix socket, so it can't be as
      # sealed as the client, but strip everything else.
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectProc = "invisible";
      ProtectControlGroups = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "~@resources"
      ];
      SystemCallErrorNumber = "EPERM";
      UMask = "0022";
    };
  };

  systemd.timers.bpi-f3-lcd-lldp = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "20s";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
    };
  };
}
