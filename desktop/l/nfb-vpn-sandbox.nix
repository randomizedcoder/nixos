# nfb-vpn-sandbox.nix
#
# Runs the NFB Consulting LADC AnyConnect VPN (via OpenConnect) inside a
# systemd-nspawn container so it manipulates routing/DNS in its own network
# namespace without touching the host. Lets it coexist with the NordLayer
# sandbox (10.99.0.0/24) — this one uses 10.98.0.0/24.
#
# You reach NFB devices by SSHing THROUGH the container:
#   ssh 10.201.10.14           (via the ProxyJump nfb-vpn rule in home-ssh-config.nix)
#   ssh spine01-serial         (Opengear serial line, see serial-console notes)
#
# The VPN stays DOWN until you connect it — the container autostarts, but you
# run the expect helper on the host to bring the tunnel up:
#   expect ~/.ssh/nfb-vpn-connect.exp
# which SSHes in and runs `nfb-connect <user>`, answering openconnect's prompt.
#
# The openconnect flags (protocol, --servercert pin, --authgroup) are the proven
# ones from ./openconnect-vpn.nix (the host `vpn-up` command).
#
# Operational notes:
#   sudo machinectl list                       # see the container
#   sudo machinectl shell nfb-vpn              # root shell inside
#   journalctl -M nfb-vpn                      # logs from inside
#   ssh nfb-vpn nfb-disconnect                 # drop the tunnel

{ config, pkgs, lib, ... }:

let
  # Same key authorized for the nordlayer sandbox (mirrors configuration.nix
  # users.users.das.openssh.authorizedKeys).
  jumpAuthorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t";

  # Host↔container veth. Distinct from nordlayer's 10.99.0.0/24 and from every
  # NFB-side subnet (10.220/10.10.250/10.201/10.204/10.207/10.208) and the VPN
  # client pool (10.200.20.0/27).
  hostAddress  = "10.98.0.1";
  guestAddress = "10.98.0.2";

  # SSH port forwarded on the host loopback (fallback path; primary access is
  # the veth address 10.98.0.2 directly, like the nordlayer `vpn-jump`).
  jumpPort = 2223;

  # Networks routed through the tunnel after connect. We authenticate via the
  # MNC-LADC group (LOCAL auth) rather than NFB-LADC (RADIUS-first, which rejects
  # the locally-defined account — see NFB_VPN_Container_Setup.md §2.4). MNC-LADC's
  # split-tunnel only pushes 10.10.250.0/24, so we add the rest of the NFB-LADC
  # split-tunnel set by hand. MNC-LADCPolicy has no vpn-filter, so the ASA still
  # forwards these (verified: con01 10.201.10.134 reachable this way).
  # When dseddon is added to RADIUS (or NFB-LADC is set local-first), switch
  # --authgroup back to NFB-LADC and this route list becomes unnecessary.
  nfbRoutes = [
    "10.201.10.0/24"   # Management LAN — con01 + all devices in devices.txt
    "10.204.10.0/24"   # Hyper-V
    "10.207.10.0/24"   # iSCSI
    "10.208.10.0/24"   # Hyper-V live migration / heartbeat
    "10.220.10.0/24"   # LADC-LAN (default VLAN)
    "10.201.11.0/24"   # ASA management interface
    "10.33.0.0/24"     # LADC-Seddon
    "10.35.0.0/24"     # Seddon-MGMT
    "20.200.10.0/24"   # LADC-MNC-DMZ
    # 10.10.250.0/24 is already pushed by MNC-LADC's own split-tunnel.
    # These are all ASA-connected subnets; MNC-LADCPolicy has no vpn-filter, so
    # the ASA forwards them. A route that the ASA won't NAT-exempt simply won't
    # pass traffic — adding it is harmless.
  ];

  # ── connect / disconnect helpers baked into the container ───────────────
  # nfb-connect reads the password from stdin (--passwd-on-stdin); the host-side
  # driver pipes it in. We do NOT use openconnect's interactive "Password:"
  # prompt: over a PTY it hangs with this ASA's two-form auth, whereas a plain
  # stdin pipe is reliable. openconnect backgrounds on success; we then add the
  # supplemental routes above. (No `exec` — the script keeps running to add them.)
  nfb-connect = pkgs.writeShellScriptBin "nfb-connect" ''
    set -eu
    VPN_USER="''${1:-}"
    if [ -z "$VPN_USER" ]; then
      echo "usage: nfb-connect <vpn-username>   (password is read from stdin)" >&2
      exit 2
    fi
    sudo ${pkgs.openconnect}/bin/openconnect \
      --protocol=anyconnect \
      --background \
      --pid-file=/run/openconnect.pid \
      --script=${pkgs.vpnc-scripts}/bin/vpnc-script \
      --servercert pin-sha256:aNfEKIY9ehZZezYXwvUGYf+9OtI4K4LNlcqRfGPfDn8= \
      --authgroup=MNC-LADC \
      --user="$VPN_USER" \
      --passwd-on-stdin \
      ladcvpn.nfbconsulting.com

    # openconnect --background has daemonised; wait for tun0, then add the
    # supplemental NFB routes (MNC-LADC only pushes 10.10.250.0/24 itself).
    for _ in $(${pkgs.coreutils}/bin/seq 1 20); do
      ${pkgs.iproute2}/bin/ip link show tun0 >/dev/null 2>&1 && break
      sleep 0.5
    done
    for net in ${lib.concatStringsSep " " nfbRoutes}; do
      if sudo ${pkgs.iproute2}/bin/ip route replace "$net" dev tun0; then
        echo "nfb-connect: routed $net via tun0"
      else
        echo "nfb-connect: WARNING could not add route $net" >&2
      fi
    done
  '';

  nfb-disconnect = pkgs.writeShellScriptBin "nfb-disconnect" ''
    if [ -f /run/openconnect.pid ]; then
      sudo kill "$(cat /run/openconnect.pid)" 2>/dev/null && sudo rm -f /run/openconnect.pid
      echo "nfb-vpn: disconnected"
    elif sudo pkill -x openconnect; then
      echo "nfb-vpn: disconnected (by name)"
    else
      echo "nfb-vpn: no openconnect running"
    fi
  '';

  nfb-status = pkgs.writeShellScriptBin "nfb-status" ''
    if [ -f /run/openconnect.pid ] && sudo kill -0 "$(cat /run/openconnect.pid)" 2>/dev/null; then
      echo "nfb-vpn: UP (pid $(cat /run/openconnect.pid))"
      ${pkgs.iproute2}/bin/ip -brief addr show tun0 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip route show dev tun0 2>/dev/null || true
    else
      echo "nfb-vpn: DOWN"
    fi
  '';
in
{
  # ── host-side NAT so the container can reach the internet ─────────────────
  # Same rationale as nordlayer-sandbox.nix: networking.nat no-ops with the
  # firewall disabled, so install the masquerade directly. ip_forward is 1.
  systemd.services.nfb-vpn-sandbox-nat = {
    description = "Masquerade for nfb-vpn container egress (10.98.0.0/24 -> enp1s0)";
    after = [ "network-pre.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "nfb-vpn-sandbox-nat-up" ''
        set -e
        ${pkgs.nftables}/bin/nft -f - <<'EOF'
        table inet nfb-vpn-sandbox-nat {}
        delete table inet nfb-vpn-sandbox-nat
        table inet nfb-vpn-sandbox-nat {
          chain postrouting {
            type nat hook postrouting priority srcnat;
            ip saddr 10.98.0.0/24 oifname "enp1s0" masquerade comment "NAT nfb-vpn egress"
          }
        }
        EOF
      '';
      ExecStop = "${pkgs.nftables}/bin/nft delete table inet nfb-vpn-sandbox-nat 2>/dev/null || true";
    };
  };

  # ── the container ─────────────────────────────────────────────────────────
  containers.nfb-vpn = {
    autoStart      = true;
    privateNetwork = true;
    inherit hostAddress;
    localAddress   = guestAddress;

    # openconnect brings up tun0 — needs /dev/net/tun in the container.
    enableTun = true;

    # nspawn's default capability set omits CAP_NET_ADMIN; openconnect needs it
    # to create the tun device and install split-tunnel routes.
    additionalCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];

    # Expose the container's sshd on the host loopback (fallback path).
    forwardPorts = [{
      protocol      = "tcp";
      hostPort      = jumpPort;
      containerPort = 22;
    }];

    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "25.11";

      # openconnect's vpnc-script rewrites resolv.conf on connect/disconnect.
      # Bootstrap nameservers cover the window before the VPN is up. Reaching
      # devices by IP (devices.txt) needs no DNS anyway.
      networking.useHostResolvConf = lib.mkForce false;
      networking.resolvconf.enable = true;
      networking.nameservers       = [ "1.1.1.1" "9.9.9.9" ];

      # Container is dedicated to VPN traffic; no host LAN exposure. Disable its
      # firewall to avoid double-filtering.
      networking.firewall.enable = false;

      # ── jump user ───────────────────────────────────────────────────────
      users.users.vpn = {
        isNormalUser = true;
        description  = "NFB VPN sandbox jump user";
        extraGroups  = [ "wheel" ];   # passwordless sudo -> run openconnect
        openssh.authorizedKeys.keys = [ jumpAuthorizedKey ];
      };
      security.sudo.wheelNeedsPassword = false;

      # ── sshd (key-only, loopback/veth reachable only) ───────────────────
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin              = "yes";
          PasswordAuthentication       = false;
          KbdInteractiveAuthentication = false;
          GSSAPIAuthentication         = false;
        };
      };
      users.users.root.openssh.authorizedKeys.keys = [ jumpAuthorizedKey ];

      environment.systemPackages = with pkgs; [
        openconnect
        vpnc-scripts
        nfb-connect
        nfb-disconnect
        nfb-status
        openssh
        iproute2
        nftables
        bind      # dig, host
        curl
        less
        vim
      ];
    };
  };
}
