#
# arm/pi-bob/nix/iperf2.nix
#
# iperf2 network-test server, supervised by systemd. Ported from
# ~/nixos/hp/hp4/iperf2.nix (Bob is the iperf2 maintainer, so his demo Pi runs
# the same service).
#
# Nix-ified / systemd-ified version of the upstream shell invocation:
#   ./src/iperf --server -p 5001 -V -e --dual-transport
#
# Long-form arg mapping (verified against `iperf2 --help`):
#   --server         run in server mode                 (was --server)
#   --port 5001      listen port                         (was -p 5001)
#   --enhanced       enhanced tcp/udp reports            (was -e)
#   --ipv6_domain    enable IPv6 reception, dual-stack   (was -V, NOT a version flag)
#   --dual-transport also listen for the other transport on the adjacent port
#                    (5001 TCP -> 5002 UDP)              (was --dual-transport)
#
{ config, pkgs, lib, ... }:
let
  # --dual-transport is only in upstream git master, not the released 2.2.1
  # tarball that nixpkgs builds, so pin the src to master here. The git tree
  # ships configure.ac / bootstrap.sh (no generated ./configure), hence
  # autoreconfHook (the one addition vs. building the tarball).
  #
  # Unlike hp4 (which based this on pkgs.unstable.iperf2), we override the
  # flake's OWN pkgs.iperf2 (nixos-25.11). That keeps flake.nix minimal (no
  # extra nixpkgs-unstable input/overlay) and keeps cross-compilation working,
  # since it's the same pkgs set the rest of the image is built from.
  iperf2Git = pkgs.iperf2.overrideAttrs (old: {
    version = "2.2.1-unstable-2026-08-14";
    __intentionallyOverridingVersion = true; # we point a stock pname at a git-master src

    src = pkgs.fetchgit {
      url = "https://git.code.sf.net/p/iperf2/code";
      rev = "7856ae7ea42c726627e96103b1ed5f384159dbeb"; # master HEAD as of 2026-08-14
      hash = "sha256-8G92dWfHUQulf3wf6/cBTj0FJ0sMuceMVz5eKPBCfk8=";
    };
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.autoreconfHook ];

    # Server-side --permit-key (the light shared-secret auth below) is a
    # "professional edition" feature: a community-edition build hard-ERRORs and
    # refuses to start when --permit-key is given on the server. nixpkgs builds
    # the community edition by default (no configure flags), so opt in here.
    # --enable-professional is a pure feature toggle (no extra dependencies);
    # the permit-key is a plain shared string, not crypto.
    configureFlags = (old.configureFlags or [ ]) ++ [ "--enable-professional" ];
  });
in
{
  systemd.services.iperf2 = {
    description = "iperf2 server (TCP+UDP dual-transport)";
    wantedBy = [ "multi-user.target" ];
    after    = [ "network-online.target" ];
    wants    = [ "network-online.target" ];
    serviceConfig = {
      # mirrors: --server -p 5001 -V -e --dual-transport, plus light auth.
      #
      # --permit-key=<value> gates the (TCP) test on a shared secret: the
      # server only runs a client's test if the client passes the SAME
      # --permit-key value. It is a lightweight best-effort auth (TCP only; the
      # UDP side of --dual-transport is not gated), NOT transport encryption.
      #
      #   >>> CHANGE THIS KEY <<<  "pleaseChangeMe" is a placeholder and, like
      #   the demo passwords, is world-readable in the Nix store. Pick your own.
      #
      # Clients connect with, e.g.:
      #   iperf2 -c pi-bob.local -p 5001 --permit-key=pleaseChangeMe
      # (a plain community-edition iperf2 client can pass a key; only the
      # SERVER needs the professional build enabled above.)
      #
      # --permit-key-timeout also bounds the listener's own lifetime (its
      # default is only 20s, which would stop the server accepting after 20s),
      # so set it large (30 days) for a persistent responder; Restart=always
      # brings the listener back when that window finally elapses.
      ExecStart  = "${iperf2Git}/bin/iperf2 --server --port 5001 --enhanced --ipv6_domain --dual-transport --permit-key=pleaseChangeMe --permit-key-timeout 2592000";
      Type       = "exec"; # iperf2 --server runs in the foreground, does not fork
      Restart    = "always"; # persistent responder (also restart after the permit-key-timeout window)
      RestartSec = "5s";

      # iperf2 on port 5001 needs no privileges and writes no state -> lock it down.
      DynamicUser             = true;
      NoNewPrivileges         = true;
      CapabilityBoundingSet   = "";
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      ProtectSystem           = "strict";
      ProtectHome             = true;
      PrivateTmp              = true;
      PrivateDevices          = true;
      ProtectKernelTunables   = true;
      ProtectKernelModules    = true;
      ProtectControlGroups    = true;
      RestrictNamespaces      = true;
      RestrictRealtime        = true;
      LockPersonality         = true;
      MemoryDenyWriteExecute  = true;
      SystemCallArchitectures = "native";

      LimitNOFILE = 65536; # many concurrent test sockets
      # Deliberately NO CPUQuota / MemoryMax: this is a throughput benchmark;
      # capping CPU/mem would skew the measured bandwidth.
    };
  };

  # --dual-transport uses the port AND the adjacent port (5001 + 5002), TCP and
  # UDP. On pi-bob the NixOS firewall is enabled by default, so these openings
  # actually take effect.
  networking.firewall.allowedTCPPorts = [ 5001 5002 ];
  networking.firewall.allowedUDPPorts = [ 5001 5002 ];
}
