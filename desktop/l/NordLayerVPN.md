# NordLayer VPN

Two ways to connect this machine to NordLayer are wired up. They coexist
(only one should hold the tun device at a time) and are intended for
different situations.

## TL;DR

| Method                        | When to use                                                            | 2FA?                | Module                                     |
| ----------------------------- | ---------------------------------------------------------------------- | ------------------- | ------------------------------------------ |
| Proprietary client (default)  | Day-to-day. You have an account with 2FA on the portal.                | Yes — browser flow  | `nordlayer-vpn.nix` + `nordlayer-package.nix` |
| Direct OpenVPN                | Backup; declarative auto-connect; networks that block UDP need TCP/8443.| **No**, requires NordLayer *Service Credentials* (separate from portal account). | `nordlayer-openvpn.nix` |

If you have only the portal account with 2FA enabled, **use Method 1**.
Method 2 will fail with `AUTH_FAILED` against a 2FA-protected account
because the .ovpn config NordLayer issues has no `static-challenge`
directive — there's no way to feed in the rotating TOTP at connect time.

---

## Method 1 — Proprietary NordLayer client

### What this gives you

- The official Go-based `nordlayerd` daemon + `nordlayer` CLI.
- Browser-based login flow (`nordlayer login`) that handles 2FA / SSO
  natively — token is persisted in `/var/lib/nordlayer/nordlayer.db` so
  subsequent `nordlayer connect` calls don't re-prompt until the token
  expires.
- City / country / group selection (`nordlayer connect <target>`).

### How the nix works

Two files:

- `nordlayer-package.nix` — `stdenv.mkDerivation` that fetches the
  upstream `nordlayer_latest_amd64.deb` from
  `downloads.nordlayer.com`, unpacks it with `dpkg-deb`, runs
  `autoPatchelfHook` against `libcap-ng`, and installs binaries into
  `$out/{bin,sbin,libexec/nordlayer,etc/nordlayer,share}`.
  - The SRI `hash` attribute is the integrity check (no public versioned
    URL is available, so `latest` + pinned hash is what we get).
  - To bump: change `version`, set `hash = lib.fakeHash;`, run a build,
    paste the hash from the error message.

- `nordlayer-vpn.nix` — wires the package into NixOS:
  - Allows the unfree `nordlayer` package via
    `nixpkgs.config.allowUnfreePredicate`.
  - Creates `users.users.nordlayer` (system user) + groups `nordlayer`
    and `nordlayer-resolve`. Adds `das` to `nordlayer` so the CLI can
    talk to the daemon socket without sudo.
  - `systemd.tmpfiles` symlinks `/usr/libexec/nordlayer/{nordlayer-openvpn,nordlayer-resolvconf}`
    to the helpers in the Nix store, because the daemon hardcodes those
    paths.
  - `security.wrappers.nordlayer-resolvconf` — setuid root, group
    `nordlayer-resolve`. Replaces the file caps the .deb postinst would
    have set (file caps don't survive the read-only Nix store).
  - `systemd.sockets.nordlayer` listens on
    `/run/nordlayer/nordlayer.sock` (mode 0660, group `nordlayer`).
  - `systemd.services.nordlayer` runs `${nordlayer}/sbin/nordlayerd
    -config /etc/nordlayer/config.hcl` as the `nordlayer` user with
    ambient caps `CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW
    CAP_IPC_LOCK`. Adds `openvpn`, `iproute2`, `iptables`, `nftables`,
    `procps`, `gawk` to the unit's PATH (the daemon shells out to
    these).

### Use

```bash
nordlayer status                  # should say "Not connected"
nordlayer login                   # one-time per token lifetime — opens a browser, do 2FA there
nordlayer connect                 # connect to the default gateway
nordlayer connect <city|country|group>
nordlayer disconnect
nordlayer status
```

`das` must be in the `nordlayer` group for the CLI to reach the socket
without sudo. The first activation that adds `das` to that group
requires a logout/login (or `newgrp nordlayer`) before existing shells
see it.

### Verify

```bash
systemctl status nordlayer.service                   # active (running), no recent restarts
ss -lxn | grep /run/nordlayer/nordlayer.sock         # socket exists
ip -br addr show | grep -E 'tun|nordlayer'           # tun device when connected
curl -s https://ifconfig.me; echo                    # egress IP changes when connected
```

When connected, `ip route` shows the default route pushed via the tun
device, and `/etc/resolv.conf` has been rewritten by
`nordlayer-resolvconf` to push DNS through the tunnel.

### Logs / diagnostics

```bash
journalctl -u nordlayer -f                # follow daemon log
journalctl -u nordlayer --since '10 min ago'
nordlayer-diagtool                        # bundles logs/state for support tickets
```

If `nordlayer login` can't open a browser, check that GNOME is the
session and `xdg-open` resolves (`xdg-mime query default x-scheme-handler/https`).

---

## Method 2 — Direct OpenVPN

### What this gives you

- A fully declarative OpenVPN connection straight to the NordLayer
  gateway, with no proprietary daemon involved.
- Two `services.openvpn.servers.*` units:
  - `openvpn-nordlayer-udp.service` — UDP/1194 (default, lower latency).
  - `openvpn-nordlayer-tcp.service` — TCP/8443 (fallback for networks
    that block UDP).
- Both **`autoStart = false`** so they don't fight the proprietary
  daemon for the tun device. You start whichever you want explicitly.

### How the nix works

`nordlayer-openvpn.nix` (single file):

- Embeds the **CyberHop Root CA** inline (public; safe to commit).
- References two out-of-band secret files:
  - `~/.ssh/nordlayer-tls-crypt-v2.key` — per-customer tls-crypt-v2
    client key, extracted from one of the `.ovpn` files NordLayer
    issues.
  - `~/.ssh/nordlayer-auth.txt` — two lines: username on line 1,
    password on line 2 (OpenVPN's `--auth-user-pass` format).
- Builds the OpenVPN config string in Nix via a `mkConfig { proto, port }`
  helper, then declares two `services.openvpn.servers.*` entries
  pointing at gateway `88.216.234.79`.
- Adds `openvpn` to `environment.systemPackages` plus two shell
  wrappers `vpn-nl-up [udp|tcp]` and `vpn-nl-down`.
- Adds `networkmanager-openvpn` plugin so the .ovpn files can also be
  imported via GNOME Settings → VPN → Import from file (GUI fallback).

The actual tls-crypt-v2 key never enters the Nix store or git: it lives
only at `~/.ssh/nordlayer-tls-crypt-v2.key` (mode 0600). The OpenVPN
process reads it as root at connect time.

### Setup (one-time per machine)

The `.ovpn` files come from the NordLayer admin console (Connections /
Servers / Manual setup → download). They contain the same tls-crypt-v2
key in both the UDP and TCP variants.

```bash
# 1. Extract the tls-crypt-v2 key from one .ovpn (both have the same key).
unzip -p ~/Downloads/config.zip "$(unzip -l ~/Downloads/config.zip | awk '/\.ovpn$/ {print $NF; exit}')" \
  | sed -n '/-----BEGIN OpenVPN tls-crypt-v2/,/-----END OpenVPN tls-crypt-v2/p' \
  > ~/.ssh/nordlayer-tls-crypt-v2.key
chmod 600 ~/.ssh/nordlayer-tls-crypt-v2.key

# 2. Service Credentials in the file. Generate them in the NordLayer admin
#    portal (Settings → Personal area / User profile → Service credentials).
#    These are NOT your portal email/password — those will fail on 2FA accounts.
$EDITOR ~/.ssh/nordlayer-auth.txt   # line 1: service-username, line 2: service-password
chmod 600 ~/.ssh/nordlayer-auth.txt
```

Then `make rebuild` so the wrappers and units are present.

### Use

```bash
vpn-nl-up                           # default: UDP/1194
vpn-nl-up tcp                       # fallback: TCP/8443
vpn-nl-down                         # stops whichever is running

# or directly:
sudo systemctl start  openvpn-nordlayer-udp
sudo systemctl stop   openvpn-nordlayer-udp
```

### Verify

```bash
systemctl status openvpn-nordlayer-udp        # active (running)
ip -br addr show tun0                         # tun0 has a 10.x.x.x address from NordLayer
ip route | head -5                            # default route via tun0 when up
curl -s https://ifconfig.me; echo             # egress IP shows the NordLayer gateway
```

A successful connect shows this in the journal:

```
... VERIFY OK: depth=0, CN=ntus<xxxxxx>.nordlayers.com
... Peer Connection Initiated with [AF_INET]88.216.234.79:1194
... Initialization Sequence Completed       <-- tunnel up
```

### Logs

```bash
journalctl -u openvpn-nordlayer-udp -f
journalctl -u openvpn-nordlayer-tcp -f
journalctl -u openvpn-nordlayer-udp --since '5 min ago'
```

### Known failure: `AUTH_FAILED`

```
AUTH: Received control message: AUTH_FAILED
SIGTERM received, sending exit notification to peer
```

The TLS handshake worked, the gateway accepted the tls-crypt-v2 key,
and rejected the username/password. Cause is almost always one of:

1. **2FA on the account, no Service Credentials.** Portal email +
   password won't authenticate via OpenVPN when 2FA is on, and the
   .ovpn has no `static-challenge` directive to prompt for a TOTP. Fix:
   generate Service Credentials in the NordLayer admin portal and put
   *those* in `~/.ssh/nordlayer-auth.txt`.
2. **CRLF in the auth file** (especially after editing on Windows).
   `cat -A ~/.ssh/nordlayer-auth.txt` — if you see `^M$`, run
   `sed -i 's/\r$//' ~/.ssh/nordlayer-auth.txt`.
3. **Two-line shape wrong.** `wc -l` should print 2. No trailing blank
   line, no key=value pairs, no quoting.

If `AUTH_FAILED` keeps the unit in a restart loop, stop it with
`vpn-nl-down` (or `sudo systemctl stop openvpn-nordlayer-udp`) before
debugging.

---

## Coexistence

Both methods are installed simultaneously. The proprietary daemon's
unit (`nordlayer.service`) is `wantedBy = multi-user.target` so it
starts at boot but only sits idle until you `nordlayer login`. The
OpenVPN units are `autoStart = false` so they never run unless
explicitly started.

Don't run both at once — they'll race for the tun device and routing
table. `vpn-nl-down` followed by `nordlayer connect` (or vice versa)
keeps things clean.

## Files at a glance

| File                    | Purpose                                                        |
| ----------------------- | -------------------------------------------------------------- |
| `nordlayer-package.nix` | Repackages the upstream .deb into a Nix derivation             |
| `nordlayer-vpn.nix`     | Wires the proprietary daemon into NixOS (users, units, caps)   |
| `nordlayer-openvpn.nix` | Direct OpenVPN method (UDP+TCP units, wrappers, NM plugin)     |
| `~/.ssh/nordlayer-tls-crypt-v2.key` | Per-customer OpenVPN tls-crypt-v2 client key (mode 0600) |
| `~/.ssh/nordlayer-auth.txt` | Service Credentials for OpenVPN (mode 0600, 2 lines)       |
