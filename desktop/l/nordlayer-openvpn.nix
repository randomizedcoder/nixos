# nordlayer-openvpn.nix
#
# Direct OpenVPN connection to NordLayer using the .ovpn config NordLayer
# provides via the admin console. Coexists with the proprietary nordlayer
# daemon (nordlayer-vpn.nix): both can be installed at once, but only one
# should hold the tun device at a time. These services are autoStart=false,
# so the proprietary daemon stays the default unless you explicitly start
# one of these.
#
# Why this exists alongside the proprietary client:
#   - Fully declarative — no `nordlayer login` browser step.
#   - Works on systems where the proprietary daemon misbehaves.
#   - TCP/8443 variant punches through restrictive networks that block
#     UDP/1194.
#
# One-time per-machine setup (the .ovpn from NordLayer contains a
# per-customer tls-crypt-v2 key — that's the only secret bit; the CA cert
# below is public):
#
#   # 1. Save the tls-crypt-v2 client key. Open one of NordLayer's .ovpn
#   #    files (both variants share the same key) and copy ONLY the lines
#   #    between (and including):
#   #        -----BEGIN OpenVPN tls-crypt-v2 client key-----
#   #        -----END OpenVPN tls-crypt-v2 client key-----
#   $EDITOR ~/.ssh/nordlayer-tls-crypt-v2.key
#   chmod 600 ~/.ssh/nordlayer-tls-crypt-v2.key
#
#   # 2. Save credentials as a two-line file: username on line 1, password
#   #    on line 2 (the format OpenVPN's --auth-user-pass expects). This
#   #    module reads ~/.ssh/nordlayer-auth.txt — match that path.
#   install -m 600 /dev/stdin ~/.ssh/nordlayer-auth.txt <<'EOF'
#   YOUR_USERNAME
#   YOUR_PASSWORD
#   EOF
#
# Usage:
#   vpn-nl-up                # default: UDP/1194
#   vpn-nl-up tcp            # TCP/8443 fallback for restrictive networks
#   vpn-nl-down              # stop whichever is running
#   journalctl -u openvpn-nordlayer-udp -f
#
# Or directly:
#   sudo systemctl start openvpn-nordlayer-udp
#   sudo systemctl stop  openvpn-nordlayer-udp

{ config, pkgs, lib, ... }:

let
  # CyberHop Root CA — public, distributed in every NordLayer .ovpn.
  nordlayerCA = ''
    -----BEGIN CERTIFICATE-----
    MIIFMDCCAxigAwIBAgIBATANBgkqhkiG9w0BAQ0FADA7MQswCQYDVQQGEwJWRzER
    MA8GA1UEChMIQ3liZXJIb3AxGTAXBgNVBAMTEEN5YmVySG9wIFJvb3QgQ0EwHhcN
    MTgwMTAxMDAwMDAwWhcNMjgwMTAxMDAwMDAwWjA7MQswCQYDVQQGEwJWRzERMA8G
    A1UEChMIQ3liZXJIb3AxGTAXBgNVBAMTEEN5YmVySG9wIFJvb3QgQ0EwggIiMA0G
    CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDnyzJH2GfoASW2oCRoz7MKUwVUYtMN
    tRCv/vsyd0j+PKE7G2w0sqnBxyO19jXbI7MJGfYVEygxquKs9VopblbcTk//sV8k
    oQ6Zd0vM5OhUE8R2mJQc1+xKMACmNeiKLDtfedWtETwg5x7yrIKbA3zaqIBodZCc
    PQvuXM9hTeFVa+DnL9GG/cClVHJq0KqK95v1XUqaOzbM3KiW8PkYanSmE9beylva
    9JeeDwN9Q+js4VNC90uEsUtWNga0Hu57aRw4ES9WSMuMy8xdx7hibfDCnyRwIINR
    rNYtpMy72iaNE65nsRyy/Saw7WcfvBVpeCVEwJArHr/SAmdeTdmUIb5xRpaYegKO
    1FsKLqJSVvOSh4eFFPofiCW+e3j1bZxtFWdcCCzCPnGlX1ySivQALoTBRVnn/ITh
    3nIaf3TSlnoLnslo4LfFQw0LbhQE6xB9+eNsvzL3UcOxzaSNmDrIvFc8czUjEh4D
    vmGxlaiHwX808ScvcWY0HcrwiqmzZLs4pTWc6FueQSlGVUubBM08EhQjmPNppfmE
    qH9LzDdZlR4Wtt+QxPDgJyW2UsYWqaWENWjBSHYGqzQwZkyNpo90EBWSGquRnl5Q
    3jEp1oK1ISn4SPUIFBy1Bn5BaJH5exbxSEWQaiFQ7+uvhOKuXiHL4+uyTO4m0qrJ
    MDffczlqrJztswIDAQABoz8wPTAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSC
    wju8HeAD+x9KYGTlgKHSXsKmkTALBgNVHQ8EBAMCAQYwDQYJKoZIhvcNAQENBQAD
    ggIBAOBazQYnqhgvDZzo4Ww6TLlBILQ4cEjhbj9gp8puTBeNhoqa4isgb79l4hFi
    wLwiuD/mJp/GmS8L4Ba8RbFSZh+OHYj3Tl+54BhiwX6fCuVNfc/LGL771Ed5J9dG
    g16BAfdj5v+MDpPMyRILwY0p7sX8N3UZ36bhsARVcyhRg7LNjc9yF/dy2dizEjab
    TaY1+lGl0XiwGlXUIJcAODRGSjXLCXPkg0Ev8f5THksNtcdDpJOXmH1EJihbzfNP
    HIh5DuWcEkv5kdyKEpmi3havLsRpLQXjOFcTMlD3IVW2zmERTj3Es88uOZiuFzE0
    mavRwIT+lda/tgE6KqWwujXr148FYN+JiTShxqi26E5t9I+CVI3BNTp++aYre5Rt
    FzijNEiqBH6fwUqNhAF7KU60p9Iy2wUbFRwSE1/eBz+AJk53NFlcb3tQiVPmu50d
    Wd0/uZa1IH20vv3q8lINNKkFqM5CYJmaFPV+ZdM+JApbmaEbTxI4Iv2KLD9fMbyo
    rL3tS/1Zg7zmCD2eEhPW2z3hgcWjyE43qx2Emn4kxp126gFR6xMdjNnwsrvhQy32
    Mp+FWWiCHcVDbmccENmnXTx6VuSoOMo8LbN5+kutg9KAXL7i8zk9EvEZ4euA5R0U
    gbEyQOazQ7LVGzHocQkh+ea89xSD8v+pQsaRBc1PvZOe0vIE
    -----END CERTIFICATE-----
  '';

  # Local files the user provisions out-of-band — see header. The openvpn
  # process runs as root and reads them at connect time; mode 0600 with
  # owner=das is fine (root reads everything).
  tlsCryptKeyPath = "/home/das/.ssh/nordlayer-tls-crypt-v2.key";
  credsPath       = "/home/das/.ssh/nordlayer-auth.txt";

  # Both .ovpn variants in the NordLayer config zip point at this gateway.
  # If NordLayer rotates it, edit here.
  gateway = "88.216.234.79";

  mkConfig = { proto, port }: ''
    client
    dev tun
    proto ${proto}
    remote ${gateway} ${toString port}
    remote-random
    nobind
    tun-mtu 1500
    mssfix 1450
    ping 15
    ping-restart 0
    reneg-sec 0
    remote-cert-tls server
    auth-user-pass ${credsPath}
    ${lib.optionalString (proto == "udp") "explicit-exit-notify"}
    verb 3
    pull
    fast-io
    cipher AES-256-CBC
    auth SHA512
    tls-crypt-v2 ${tlsCryptKeyPath}
    <ca>
    ${nordlayerCA}</ca>
  '';
in
{
  environment.systemPackages = with pkgs; [
    openvpn
    (writeShellScriptBin "vpn-nl-up" ''
      proto="''${1:-udp}"
      case "$proto" in
        udp|tcp) ;;
        *) echo "usage: vpn-nl-up [udp|tcp]" >&2; exit 2;;
      esac
      for f in ${tlsCryptKeyPath} ${credsPath}; do
        if [ ! -s "$f" ]; then
          echo "missing $f — see nordlayer-openvpn.nix header for setup steps" >&2
          exit 1
        fi
      done
      sudo ${pkgs.systemd}/bin/systemctl start "openvpn-nordlayer-$proto.service"
      echo "tail logs: journalctl -u openvpn-nordlayer-$proto -f"
    '')
    (writeShellScriptBin "vpn-nl-down" ''
      sudo ${pkgs.systemd}/bin/systemctl stop \
        openvpn-nordlayer-udp.service \
        openvpn-nordlayer-tcp.service 2>/dev/null || true
    '')
  ];

  # GUI fallback: NetworkManager OpenVPN plugin so you can also import the
  # .ovpn files via GNOME's Settings → VPN → Import from file.
  networking.networkmanager.plugins = with pkgs; [ networkmanager-openvpn ];

  # Both servers are autoStart=false — they don't run unless explicitly
  # started. This avoids fighting with the proprietary nordlayer daemon
  # for the tun device.
  services.openvpn.servers.nordlayer-udp = {
    autoStart = false;
    config = mkConfig { proto = "udp"; port = 1194; };
  };

  services.openvpn.servers.nordlayer-tcp = {
    autoStart = false;
    config = mkConfig { proto = "tcp"; port = 8443; };
  };
}
