# nordlayer-daemon.nix
#
# Reusable NordLayer daemon module: the daemon, the CLI security wrappers,
# tmpfiles, polkit rules, systemd socket+service. Does NOT add any specific
# user to the `nordlayer` group — callers do that:
#   - On the host, nordlayer-vpn.nix adds `das`.
#   - In the container sandbox, nordlayer-sandbox.nix adds the sandbox user.
#
# Identical daemon behaviour to the previous (host-only) nordlayer-vpn.nix.

{ config, pkgs, lib, ... }:

let
  nordlayer = pkgs.callPackage ./nordlayer-package.nix { };
in
{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "nordlayer" ];

  environment.systemPackages = [ nordlayer ];

  users.groups.nordlayer = { };
  users.groups.nordlayer-resolve = { };

  users.users.nordlayer = {
    isSystemUser = true;
    description = "NordLayer daemon";
    group = "nordlayer";
    extraGroups = [ "nordlayer-resolve" ];
    home = "/run/nordlayer";
  };

  systemd.tmpfiles.rules = [
    "d /run/nordlayer         0750 nordlayer nordlayer -"
    "d /var/lib/nordlayer     0700 nordlayer nordlayer -"
    "d /usr/libexec/nordlayer 0755 root      root      -"
    "L+ /usr/libexec/nordlayer/nordlayer-openvpn    - - - - ${nordlayer}/libexec/nordlayer/nordlayer-openvpn"
    "L+ /usr/libexec/nordlayer/nordlayer-resolvconf - - - - /run/wrappers/bin/nordlayer-resolvconf"
  ];

  environment.etc."nordlayer/config.hcl".source =
    "${nordlayer}/etc/nordlayer/config.hcl";
  environment.etc."nordlayer/cacerts/cyberhop.pem".source =
    "${nordlayer}/etc/nordlayer/cacerts/cyberhop.pem";
  environment.etc."polkit-1/rules.d/90-com.nordlayer.VPN.rules".source =
    "${nordlayer}/share/polkit-1/rules.d/90-com.nordlayer.VPN.rules";

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
  security.wrappers.nordlayer = {
    source = "${nordlayer}/bin/nordlayer";
    owner = "root";
    group = "nordlayer";
    capabilities = "cap_net_bind_service,cap_net_admin,cap_net_raw,cap_ipc_lock=ep";
    permissions = "u+rx,g+rx";
  };
  security.wrappers.nordlayer-diagtool = {
    source = "${nordlayer}/bin/nordlayer-diagtool";
    owner = "root";
    group = "nordlayer";
    capabilities = "cap_net_bind_service,cap_net_admin,cap_net_raw,cap_ipc_lock=ep";
    permissions = "u+rx,g+rx";
  };

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

    path = with pkgs; [ openvpn iproute2 iptables nftables procps gawk ];

    serviceConfig = {
      ExecStart = "${nordlayer}/sbin/nordlayerd -config /etc/nordlayer/config.hcl";
      WorkingDirectory = "/run/nordlayer";
      User = "nordlayer";
      Group = "nordlayer";
      Restart = "always";
      RestartSec = 2;
      TimeoutSec = 15;

      AmbientCapabilities       = "CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW CAP_IPC_LOCK";
      CapabilityBoundingSet     = "CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW CAP_IPC_LOCK";

      NoNewPrivileges = false;   # needs to spawn nordlayer-openvpn with caps
      PrivateTmp      = true;
      ProtectSystem   = "strict";
      ReadWritePaths  = [ "/var/lib/nordlayer" "/run/nordlayer" "/etc/resolv.conf" ];
    };
  };
}
