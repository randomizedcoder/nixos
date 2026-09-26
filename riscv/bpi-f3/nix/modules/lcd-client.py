#!/usr/bin/env python3
#
# bpi-f3-lcd-client — feed a system-status summary to LCDd (lcdproc) for the
# USB character panel (LCD2USB, 0403:c630).
#
# Talks the LCDd client protocol over TCP (default 127.0.0.1:13666): it reads
# the panel geometry from the `hello` handshake, so it adapts to whatever the
# server reports. On a 2-row panel (the 1602 here) it rotates through pages;
# on a >=4-row panel it renders one static summary. Stats come straight from
# /proc + statvfs, so there are no dependencies beyond the stdlib.
#
# It intentionally does not reconnect in-process: if LCDd restarts the socket
# breaks, this exits non-zero, and systemd restarts it.

import fcntl
import os
import select
import socket
import struct
import sys
import time

HOST = os.environ.get("LCD_HOST", "127.0.0.1")
PORT = int(os.environ.get("LCD_PORT", "13666"))
FLIP_SECS = float(os.environ.get("LCD_FLIP_SECS", "4"))
TICK_SECS = 1.0

DQ = chr(34)   # "
BSL = chr(92)  # backslash


def sanitize(s):
    # LCDd wraps widget text in double quotes; keep the payload quote-free and
    # printable-ASCII so we never break the command line.
    s = s.replace(BSL, "/").replace(DQ, "'")
    return "".join(c if 32 <= ord(c) < 127 else "?" for c in s)


def send(sock, line):
    sock.sendall((line + "\n").encode("ascii", "replace"))


def readline(sock):
    buf = b""
    while not buf.endswith(b"\n"):
        ch = sock.recv(1)
        if not ch:
            raise ConnectionError("LCDd closed the connection")
        buf += ch
    return buf.decode("ascii", "replace").strip()


def drain(sock):
    # Discard async server chatter (listen/ignore/key/success) so the socket
    # buffer never fills; detect a server-side close.
    while select.select([sock], [], [], 0)[0]:
        if not sock.recv(4096):
            raise ConnectionError("LCDd closed the connection")


def read_cpu():
    with open("/proc/stat") as f:
        vals = [int(x) for x in f.readline().split()[1:]]
    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)  # idle + iowait
    return idle, sum(vals)


def mem_pct():
    d = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, _, rest = line.partition(":")
            d[k] = int(rest.split()[0])
    total = d["MemTotal"]
    avail = d.get("MemAvailable", d.get("MemFree", 0))
    return 100.0 * (total - avail) / total if total else 0.0


def disk_stats(path="/"):
    st = os.statvfs(path)
    total = st.f_blocks * st.f_frsize
    used = total - st.f_bfree * st.f_frsize
    pct = 100.0 * used / total if total else 0.0
    return pct, used, total


def loadavg():
    with open("/proc/loadavg") as f:
        return f.read().split()[0]


def uptime_fmt(up):
    d = int(up // 86400)
    h = int(up % 86400 // 3600)
    m = int(up % 3600 // 60)
    if d:
        return f"{d}d{h}h"
    if h:
        return f"{h}h{m}m"
    return f"{m}m"


def uptime_s():
    with open("/proc/uptime") as f:
        up = float(f.read().split()[0])
    return uptime_fmt(up)


def human(n):
    n = float(n)
    for u in ("B", "K", "M", "G", "T"):
        if n < 1024:
            return f"{n:.0f}{u}"
        n /= 1024
    return f"{n:.0f}P"


def default_iface():
    # The interface carrying the default route, read from /proc/net/route
    # (destination 0.0.0.0 with the RTF_UP flag set).
    with open("/proc/net/route") as f:
        next(f)  # skip header
        for line in f:
            fields = line.split()
            if len(fields) >= 4 and fields[1] == "00000000" and int(fields[3], 16) & 0x2:
                return fields[0]
    return None


def primary_ip():
    # Resolve the default-route interface's IPv4 via ioctl only. No packets are
    # sent, so this keeps working under a fully network-locked-down sandbox
    # (IPAddressDeny=any); we only ever touch the loopback socket to LCDd.
    try:
        iface = default_iface()
        if not iface:
            return "no-ip"
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            SIOCGIFADDR = 0x8915
            res = fcntl.ioctl(
                s.fileno(),
                SIOCGIFADDR,
                struct.pack("256s", iface[:15].encode("ascii")),
            )
            return socket.inet_ntoa(res[20:24])
        finally:
            s.close()
    except OSError:
        return "no-ip"


def lldp_neighbor(iface):
    # LLDP neighbour (switch) for `iface`, from the keyvalue dump the
    # bpi-f3-lcd-lldp timer writes (the client is too locked down to query the
    # _lldpd-only control socket itself). Returns (switch-name, port); empty
    # strings when there is no neighbour or no dump yet.
    try:
        with open("/run/lcd/lldp.kv") as f:
            data = f.read()
    except OSError:
        return "", ""
    pfx = f"lldp.{iface}."
    name = mac = ifname = descr = local = ""
    for line in data.splitlines():
        line = line.strip()
        if not line.startswith(pfx):
            continue
        k, _, v = line[len(pfx):].partition("=")
        if k == "chassis.name":
            name = v
        elif k == "chassis.mac":
            mac = v
        elif k == "port.ifname":
            ifname = v
        elif k == "port.descr":
            descr = v
        elif k == "port.local":
            local = v
    sw = name or mac
    if not sw:
        return "", ""
    # Prefer a real remote port name, then its description, then the numeric id.
    port = ifname or descr or (f"#{local}" if local else "")
    return sw, port


def fit(left, right, wid):
    # left-justify `left`, right-justify `right`, on a `wid`-wide line.
    if right and len(left) + 1 + len(right) <= wid:
        return left + " " * (wid - len(left) - len(right)) + right
    return left[:wid]


# Pure page builder shared by the live path and --selftest.
def _pages(wid, hgt, host, ip, cpu, mem, dpct, dused, dtot, load, up, sw, port):
    if hgt >= 4:
        # One static summary screen.
        return [[
            fit(host, "up" + up, wid),
            fit("IP", ip, wid),
            f"CPU {cpu:3.0f}%  MEM {mem:3.0f}%",
            f"/ {dpct:3.0f}%   ld {load}",
        ]]

    # <=3 rows: rotate compact pages (two lines each here). The identity page
    # packs CPU/MEM onto the hostname line so no row is half-empty; the last
    # page is the LLDP switch/port the board is cabled to (debugging aid).
    return [
        [fit(host, f"C{cpu:.0f} M{mem:.0f}", wid), ip[:wid]],
        [f"CPU {cpu:3.0f}% {load:>4}", f"MEM {mem:3.0f}% up{up}"],
        ["DISK /", f"{dpct:3.0f}% {human(dused)}/{human(dtot)}"],
        [(sw or "no-lldp")[:wid], port[:wid]],
    ]


def build_pages(wid, hgt, cpu):
    dpct, dused, dtot = disk_stats("/")
    iface = default_iface()
    sw, port = lldp_neighbor(iface) if iface else ("", "")
    return _pages(wid, hgt, socket.gethostname(), primary_ip(), cpu, mem_pct(),
                  dpct, dused, dtot, loadavg(), uptime_s(), sw, port)


def render(sock, wid, hgt, lines):
    for i in range(1, hgt + 1):
        text = sanitize(lines[i - 1]) if i - 1 < len(lines) else ""
        send(sock, f'widget_set status ln{i} 1 {i} "{text[:wid]}"')


# Deterministic parity oracle: fixed inputs -> rendered lines, matched
# line-for-line by lcd-client.rs --selftest. Positive / boundary / corner cases
# for the pure helpers plus both panel geometries.
def selftest():
    for n in [0, 1023, 1024, 1048576, 1073741824, 11811160064]:
        print(f"human {n} {human(n)}")
    for s in [30, 3599, 3600, 7200, 90000, 270000]:
        print(f"uptime {s} {uptime_fmt(s)}")
    print(f"fit |{fit('bpi-f3', 'up3d5h', 16)}|")
    print(f"fit |{fit('IP', '172.16.40.205', 20)}|")
    print(f"fit |{fit('verylongname', 'zz', 8)}|")
    print(f"fit |{fit('short', '', 16)}|")
    for s in ["ok", 'a"b', "a\\b", "x\ty", "café"]:
        print(f"san |{sanitize(s)}|")
    for (w, h) in [(16, 2), (20, 4)]:
        pages = _pages(w, h, "bpi-f3", "172.16.40.205", 7.0, 63.0, 2.0,
                       11811160064.0, 983547510784.0, "0.42", "3d5h",
                       "ex2200", "pi-sebastian:end0 | HOST")
        for pi, pg in enumerate(pages):
            for i in range(h):
                line = sanitize(pg[i]) if i < len(pg) else ""
                print(f"pg {w}x{h} p{pi} l{i} |{line[:w]}|")


def main():
    sock = None
    for _ in range(30):
        try:
            sock = socket.create_connection((HOST, PORT), timeout=5)
            break
        except OSError:
            time.sleep(2)
    if sock is None:
        print("bpi-f3-lcd-client: cannot reach LCDd", file=sys.stderr)
        return 1

    send(sock, "hello")
    hello = readline(sock)
    toks = hello.split()
    try:
        wid = int(toks[toks.index("wid") + 1])
        hgt = int(toks[toks.index("hgt") + 1])
    except (ValueError, IndexError):
        wid, hgt = 16, 2  # sane fallback if the handshake is unexpected

    send(sock, "client_set -name bpi-f3")
    send(sock, "screen_add status")
    send(sock, "screen_set status -priority foreground -name Status -heartbeat off")
    for i in range(1, hgt + 1):
        send(sock, f"widget_add status ln{i} string")

    prev_idle, prev_total = read_cpu()
    page = 0
    last_flip = time.monotonic()
    pages = build_pages(wid, hgt, 0.0)

    while True:
        drain(sock)
        idle, total = read_cpu()
        d_idle, d_total = idle - prev_idle, total - prev_total
        cpu = 100.0 * (1 - d_idle / d_total) if d_total > 0 else 0.0
        prev_idle, prev_total = idle, total

        pages = build_pages(wid, hgt, cpu)
        now = time.monotonic()
        if now - last_flip >= FLIP_SECS:
            page = (page + 1) % len(pages)
            last_flip = now

        render(sock, wid, hgt, pages[page % len(pages)])
        time.sleep(TICK_SECS)


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        selftest()
        sys.exit(0)
    sys.exit(main())
