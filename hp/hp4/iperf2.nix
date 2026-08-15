#
# hp/hp4/iperf2.nix
#
# iperf2 network-test server, supervised by systemd.
#
# Nix-ified / systemd-ified version of the friend's shell script:
#   ./src/iperf --server -p 5001 -V -e --dual-transport
# (the ufw port juggling is replaced by networking.firewall below).
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
  # --dual-transport is only in upstream git master, not the released 2.2.1 tarball
  # that nixpkgs builds on every channel, so pin the src to master here.
  # The git tree ships configure.ac / bootstrap.sh (no generated ./configure),
  # hence autoreconfHook (the one addition vs. building the tarball).
  # Base on unstable's iperf2: it's the modern 2.2.x package definition (structured
  # for a 2.2.x build and carries meta.mainProgram = "iperf2"); stable 24.11 is the
  # older 2.1.4-era definition without mainProgram.
  iperf2Git = pkgs.unstable.iperf2.overrideAttrs (old: {
    version = "2.2.1-unstable-2026-08-14";
    __intentionallyOverridingVersion = true; # we point a stock pname at a git-master src

    src = pkgs.fetchgit {
      url = "https://git.code.sf.net/p/iperf2/code";
      rev = "7856ae7ea42c726627e96103b1ed5f384159dbeb"; # master HEAD as of 2026-08-14
      hash = "sha256-8G92dWfHUQulf3wf6/cBTj0FJ0sMuceMVz5eKPBCfk8=";
    };
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.autoreconfHook ];
  });
in
{
  systemd.services.iperf2 = {
    description = "iperf2 server (TCP+UDP dual-transport)";
    wantedBy = [ "multi-user.target" ];
    after    = [ "network-online.target" ];
    wants    = [ "network-online.target" ];
    serviceConfig = {
      # mirrors: --server -p 5001 -V -e --dual-transport
      ExecStart  = "${iperf2Git}/bin/iperf2 --server --port 5001 --enhanced --ipv6_domain --dual-transport";
      Type       = "exec"; # iperf2 --server runs in the foreground, does not fork
      Restart    = "on-failure";
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

  # --dual-transport uses the port AND the adjacent port (5001 + 5002), TCP and UDP.
  # (firewall.nix currently has enable = false, so this is cosmetic today, but follows
  # the per-module convention used by pdns-recursor.nix / blackbox.nix.)
  networking.firewall.allowedTCPPorts = [ 5001 5002 ];
  networking.firewall.allowedUDPPorts = [ 5001 5002 ];
}
