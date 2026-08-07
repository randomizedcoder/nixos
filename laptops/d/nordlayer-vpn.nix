# nordlayer-vpn.nix
#
# Official NordLayer Linux client (proprietary daemon + CLI), repackaged from
# the upstream .deb in nordlayer-package.nix.
#
# CLI usage (after rebuild):
#   nordlayer login                         # interactive — opens a browser flow
#   nordlayer connect                       # connect to the default gateway
#   nordlayer connect <city|country|group>  # connect to a specific gateway
#   nordlayer disconnect
#   nordlayer status
#
# Diagnostics:
#   systemctl status nordlayer
#   journalctl -u nordlayer -f
#   nordlayer-diagtool                      # collects logs for support
#
# Notes:
#   - The package is proprietary; allowUnfreePredicate must permit "nordlayer".
#   - The daemon runs as user `nordlayer` with ambient capabilities granted by
#     systemd (no setcap on the binary itself, which wouldn't survive /nix/store).
#   - `nordlayer-resolvconf` is wrapped via security.wrappers as setuid (group
#     nordlayer-resolve, mode 4750) — matches what the upstream .deb sets up.
#   - Helper binaries are symlinked from $out/libexec/nordlayer to
#     /usr/libexec/nordlayer because the daemon expects them at those paths.
#   - Your user `das` is added to the `nordlayer` group so the CLI can talk
#     to /run/nordlayer/nordlayer.sock without sudo.

{ config, pkgs, lib, ... }:

let
  nordlayer = pkgs.callPackage ./nordlayer-package.nix { };
in
{
  # Allow the proprietary nordlayer package.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "nordlayer" ];

  environment.systemPackages = [ nordlayer ];

  # ── users & groups ──────────────────────────────────────────────────────
  users.groups.nordlayer = { };
  users.groups.nordlayer-resolve = { };

  users.users.nordlayer = {
    isSystemUser = true;
    description = "NordLayer daemon";
    group = "nordlayer";
    extraGroups = [ "nordlayer-resolve" ];
    home = "/run/nordlayer";
    # No `shell` set — system users default to nologin via the user-management
    # module. Hardcoding `/run/current-system/sw/bin/nologin` is fragile.
  };

  # Add `das` to nordlayer group so the CLI can use the socket without sudo.
  # NOTE: `das` must log out and back in (or run `newgrp nordlayer`) after the
  # first activation that adds them to this group; existing sessions keep the
  # old supplementary-group set.
  users.users.das.extraGroups = [ "nordlayer" ];

  # ── filesystem layout ───────────────────────────────────────────────────
  # The daemon hardcodes /usr/libexec/nordlayer/ for its helpers. We use
  # tmpfiles `L+` rules instead of an activation script so the symlinks are
  # declarative, idempotent, and ordered before service start.
  systemd.tmpfiles.rules = [
    "d /run/nordlayer         0750 nordlayer nordlayer -"
    "d /var/lib/nordlayer     0700 nordlayer nordlayer -"
    "d /usr/libexec/nordlayer 0755 root      root      -"
    "L+ /usr/libexec/nordlayer/nordlayer-openvpn    - - - - ${nordlayer}/libexec/nordlayer/nordlayer-openvpn"
    "L+ /usr/libexec/nordlayer/nordlayer-resolvconf - - - - /run/wrappers/bin/nordlayer-resolvconf"
  ];

  # CA certs and config the daemon expects at /etc/nordlayer/.
  environment.etc."nordlayer/config.hcl".source = "${nordlayer}/etc/nordlayer/config.hcl";
  environment.etc."nordlayer/cacerts/cyberhop.pem".source =
    "${nordlayer}/etc/nordlayer/cacerts/cyberhop.pem";

  # Polkit rules from the upstream package.
  environment.etc."polkit-1/rules.d/90-com.nordlayer.VPN.rules".source =
    "${nordlayer}/share/polkit-1/rules.d/90-com.nordlayer.VPN.rules";

  # ── security.wrappers ───────────────────────────────────────────────────
  # nordlayer-resolvconf manipulates /etc/resolv.conf — needs to be setuid root.
  # The daemon (group nordlayer-resolve via the user's extraGroups) invokes it.
  security.wrappers.nordlayer-resolvconf = {
    source = "${nordlayer}/libexec/nordlayer/nordlayer-resolvconf";
    owner = "root";
    group = "nordlayer-resolve";
    setuid = true;
    permissions = "u+rx,g+rx";
  };

  # The CLI calls capset() during startup (see main.SetCapabilities in the
  # binary). Upstream's .deb postinst runs `setcap` on /usr/bin/nordlayer to
  # supply the permitted set, but file caps don't survive /nix/store
  # (read-only), so capset() returns EPERM and the binary exits 77 with
  # "Error while running application: operation not permitted" for every
  # invocation — including `--help`. Wrapping it here restores the caps via
  # /run/wrappers/bin/nordlayer (ahead of /run/current-system/sw/bin in PATH).
  # Mode 0550 root:nordlayer matches the .deb's restriction to group members.
  security.wrappers.nordlayer = {
    source = "${nordlayer}/bin/nordlayer";
    owner = "root";
    group = "nordlayer";
    capabilities = "cap_net_bind_service,cap_net_admin,cap_net_raw,cap_ipc_lock=ep";
    permissions = "u+rx,g+rx";
  };

  # nordlayer-diagtool has the same SetCapabilities path — wrap it too so
  # `nordlayer-diagtool` works without sudo when collecting support bundles.
  security.wrappers.nordlayer-diagtool = {
    source = "${nordlayer}/bin/nordlayer-diagtool";
    owner = "root";
    group = "nordlayer";
    capabilities = "cap_net_bind_service,cap_net_admin,cap_net_raw,cap_ipc_lock=ep";
    permissions = "u+rx,g+rx";
  };

  # ── systemd units ───────────────────────────────────────────────────────
  systemd.sockets.nordlayer = {
    description = "NordLayer daemon socket";
    partOf = [ "nordlayer.service" ];
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "/run/nordlayer/nordlayer.sock";
      SocketUser = "nordlayer";
      SocketGroup = "nordlayer";
      SocketMode = "0660";
      RemoveOnStop = true;
      ReceiveBuffer = "1M";
      SendBuffer = "1M";
    };
  };

  systemd.services.nordlayer = {
    description = "NordLayer secure network access";
    documentation = [ "https://nordlayer.com/" ];
    after = [ "network-online.target" "nordlayer.socket" ];
    wants = [ "network-online.target" ];
    requires = [ "nordlayer.socket" ];
    wantedBy = [ "multi-user.target" ];

    # The daemon shells out to these binaries via `nordlayer-openvpn` and
    # the OpenVPN runtime. Without these on PATH, `exec` calls fail with
    # "Link not found" / "exec: openvpn: not found" in the journal.
    # `path` appends to the default unit PATH (coreutils/findutils/grep/sed/systemd).
    path = with pkgs; [
      openvpn
      iproute2
      iptables
      nftables
      procps
      gawk
    ];

    serviceConfig = {
      ExecStart = "${nordlayer}/sbin/nordlayerd -config /etc/nordlayer/config.hcl";
      WorkingDirectory = "/run/nordlayer";
      User = "nordlayer";
      Group = "nordlayer";
      Restart = "always";
      RestartSec = 2;
      TimeoutSec = 15;

      # Capabilities the daemon needs (replaces file caps from the .deb postinst).
      AmbientCapabilities = "CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW CAP_IPC_LOCK";
      CapabilityBoundingSet = "CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW CAP_IPC_LOCK";

      # Hardening (subset that should be safe; relax if the daemon misbehaves).
      NoNewPrivileges = false; # needs to spawn nordlayer-openvpn with caps
      PrivateTmp = true;
      ProtectSystem = "strict";
      # On this host /etc/resolv.conf is a real writable file owned by
      # root:resolvconf (systemd-resolved is inactive, NM uses resolvconf).
      # nordlayer-resolvconf writes to it directly during connect/disconnect.
      ReadWritePaths = [ "/var/lib/nordlayer" "/run/nordlayer" "/etc/resolv.conf" ];
    };
  };

  # The OpenVPN service we set up earlier (services.openvpn.servers.nordlayer)
  # is no longer needed — the official client manages OpenVPN itself via
  # nordlayer-openvpn. If it's still defined elsewhere, that's harmless: it has
  # autoStart = false so it just sits idle. (Remove it if you want a clean
  # systemctl list-units output.)
}
