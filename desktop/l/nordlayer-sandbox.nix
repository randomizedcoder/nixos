# nordlayer-sandbox.nix
#
# Runs the NordLayer VPN daemon inside a systemd-nspawn container so it can
# manipulate routing/firewall/DNS in its own network namespace without
# affecting the host. The user reaches the VPN by SSHing into the container
# (`ssh -J vpn-jump@127.0.0.1:2222 user@remote.vpn.host`); the final hop
# traverses nlx0 inside the container.
#
# Sketch:
#   host:127.0.0.1:2222 ─port-fwd─► container:22 (sshd)
#   container:eth0 (10.99.0.2/24) ─veth─► host:ve-nordlayer-vpn (10.99.0.1)
#                                  ─NAT through enp1s0─► internet
#   nordlayerd in the container brings up nlx0 and installs its own
#   nft/ip-rule mess inside the container's netns — host is untouched.
#
# Operational notes:
#   sudo machinectl list                            # see the container
#   sudo machinectl shell nordlayer-vpn             # root shell inside
#   sudo nixos-container run nordlayer-vpn -- cmd   # run a command inside
#   journalctl -M nordlayer-vpn                     # logs from inside
#   journalctl -u container@nordlayer-vpn           # nspawn unit on host

{ config, pkgs, lib, ... }:

let
  # The SSH key authorized to log into the sandbox. Mirrors the one in
  # configuration.nix for `users.users.das.openssh.authorizedKeys`.
  jumpAuthorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t";

  # Network range for the host↔container link. Pick a /24 that doesn't
  # collide with any LAN, Docker bridge (172.17.0.0/16), or VPN range.
  hostAddress  = "10.99.0.1";
  guestAddress = "10.99.0.2";

  # SSH port forwarded on the loopback of the host into the container.
  jumpPort = 2222;
in
{
  # ── host-side NAT so the container can reach the internet ─────────────
  # We can't use `networking.nat.enable = true` on this host: with
  # `networking.firewall.enable = false`, NixOS's nat module no-ops on
  # recent unstable (it's wired through the firewall/nftables framework).
  # Install the masquerade rule directly via our own nft table instead.
  # `net.ipv4.ip_forward` is already 1 via sysctl.
  systemd.services.nordlayer-sandbox-nat = {
    description = "Masquerade for nordlayer-vpn container egress (10.99.0.0/24 -> enp1s0)";
    after = [ "network-pre.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "nordlayer-sandbox-nat-up" ''
        set -e
        ${pkgs.nftables}/bin/nft -f - <<'EOF'
        table inet nordlayer-sandbox-nat {}
        delete table inet nordlayer-sandbox-nat
        table inet nordlayer-sandbox-nat {
          chain postrouting {
            type nat hook postrouting priority srcnat;
            ip saddr 10.99.0.0/24 oifname "enp1s0" masquerade comment "NAT container egress"
          }
        }
        EOF
      '';
      ExecStop = "${pkgs.nftables}/bin/nft delete table inet nordlayer-sandbox-nat 2>/dev/null || true";
    };
  };

  # ── the container ─────────────────────────────────────────────────────
  containers.nordlayer-vpn = {
    autoStart      = true;
    privateNetwork = true;
    inherit hostAddress;
    localAddress   = guestAddress;

    # nordlayerd brings up nlx0 — we need /dev/net/tun in the container.
    enableTun = true;

    # systemd-nspawn's default capability set does NOT include CAP_NET_ADMIN.
    # nordlayer needs it to set routes, fwmarks, and nft tables.
    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
      "CAP_IPC_LOCK"
    ];

    # Expose the sandbox's sshd on the host's loopback only.
    forwardPorts = [{
      protocol      = "tcp";
      hostPort      = jumpPort;
      containerPort = 22;
    }];

    # ── the container's NixOS config ────────────────────────────────────
    config = { config, pkgs, lib, ... }: {
      imports = [
        ./nordlayer-daemon.nix
        # Apply the same fwmark + type=route bypass inside the container
        # so the host (10.99.0.1) can still reach the container (10.99.0.2)
        # over the host↔container veth once nordlayer is connected and
        # has installed its killswitch + policy routing in this netns.
        ./nordlayer-lan-bypass.nix
      ];
      services.nordlayerLanBypass.lanRanges = [ "10.99.0.0/24" ];

      # Match the host's release for predictability. Bump together.
      system.stateVersion = "25.11";

      # nordlayer fork-execs a dynamically-linked helper from a memfd at
      # /proc/self/fd/<n>; without nix-ld, NixOS's stub /lib64/ld-linux-*.so.2
      # rejects it with "Could not start dynamically linked executable".
      # Mirrors the host's programs.nix-ld setup in configuration.nix.
      programs.nix-ld = {
        enable = true;
        libraries = with pkgs; [
          stdenv.cc.cc.lib
          zlib
          libxml2
        ];
      };
      services.envfs.enable = true;

      # We don't run NetworkManager inside the container; use openresolv
      # so nordlayer-resolvconf can rewrite /etc/resolv.conf when it
      # connects/disconnects. Bootstrap nameservers cover the moment
      # before the VPN is up.
      networking.useHostResolvConf = lib.mkForce false;
      networking.resolvconf.enable = true;
      networking.nameservers       = [ "1.1.1.1" "9.9.9.9" ];

      # The container's own firewall is irrelevant — nordlayer installs its
      # own kill-switch and that's exactly what we WANT this time, since the
      # container is dedicated to VPN traffic. Disable the NixOS firewall to
      # avoid double-filtering.
      networking.firewall.enable = false;

      # ── jump user ────────────────────────────────────────────────────
      users.users.vpn = {
        isNormalUser = true;
        description  = "VPN sandbox jump user";
        # Needs nordlayer group to talk to /run/nordlayer/nordlayer.sock
        # via the CLI without sudo. `wheel` lets the user `sudo` interactively
        # if they want to run e.g. `nordlayer-diagtool` or inspect state.
        extraGroups  = [ "wheel" "nordlayer" ];
        openssh.authorizedKeys.keys = [ jumpAuthorizedKey ];
      };
      # No password required for wheel sudo inside the sandbox — convenience,
      # and the only entry path is key-based SSH from the host loopback.
      security.sudo.wheelNeedsPassword = false;

      # ── sshd ─────────────────────────────────────────────────────────
      # Root login is allowed here because this sandbox is a local-only
      # container reachable only from `l`'s host netns (no inbound LAN
      # exposure). It lets us / Claude debug nordlayer-side issues without
      # `sudo` round-trips.
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin        = "yes";
          PasswordAuthentication = false;

          # ── Bastion concurrency tuning ─────────────────────────────
          # Default MaxStartups is 10:30:100 — meaning random drop with
          # ~30% probability starts at the 11th concurrent unauthenticated
          # connection and ramps to 100% at the 100th. Observed during
          # fleet-scale snapshot.exp runs at -P 20: 6/100 sporadic
          # "ssh eof before prompt" failures, matching the MaxStartups
          # drop-probability ramp for that concurrency.
          #
          # Raising the floor to 100 lets all 100 connections through
          # without random drops; full of 200 sets the hard ceiling
          # well above any realistic fleet-walk burst.
          MaxStartups               = "100:30:200";

          # Default LoginGraceTime is 2m: a stuck unauthenticated
          # connection holds a MaxStartups slot for two whole minutes.
          # Our handshakes complete in ~3-5 s, so 30 s is plenty and
          # recycles wedged slots much faster.
          LoginGraceTime            = "30s";

          # We're key-only. Telling sshd this explicitly skips offering
          # KbdInteractive prompts during the auth phase (trims a few
          # round-trips per connection).
          KbdInteractiveAuthentication = false;

          # Note: UseDns is already false-by-default in NixOS sshd; not
          # pinning here because NixOS uses `UseDns` (lowercase "ns") as
          # the option name and writing it as `UseDNS` collides on the
          # generated sshd_config dedup check.

          # Kerberos auth isn't used here; skip negotiating it.
          GSSAPIAuthentication      = false;
        };
      };
      users.users.root.openssh.authorizedKeys.keys = [ jumpAuthorizedKey ];

      # Convenience packages inside the sandbox shell.
      environment.systemPackages = with pkgs; [
        openssh
        iproute2
        nftables
        bind     # dig, host
        curl
        less
        vim
      ];
    };
  };
}
