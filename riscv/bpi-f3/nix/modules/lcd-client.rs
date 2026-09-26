// bpi-f3-lcd-client — feed a system-status summary to LCDd (lcdproc) for the
// USB character panel (LCD2USB, 0403:c630).
//
// Rust port of lcd-client.py. Same LCDd client protocol over TCP (default
// 127.0.0.1:13666): reads the panel geometry from the `hello` handshake and
// adapts (rotating pages on a 2-row 1602, one static screen on >=4 rows).
// Stats come from /proc + statvfs, so there are no dependencies beyond std;
// the two libc calls we need (statvfs, ioctl) go through a tiny extern block
// (libc is linked by the cc wrapper anyway), which keeps the nix build a bare
// `rustc` invocation with no cargo vendoring.
//
// It intentionally does not reconnect in-process: if LCDd restarts the socket
// breaks, this exits non-zero, and systemd restarts it.
//
// `--selftest` renders a fixed table of inputs deterministically and exits
// (no socket, no /proc); it is the oracle used to prove parity with the Python
// implementation.

use std::env;
use std::fs;
use std::io::{self, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::os::raw::{c_char, c_int, c_ulong, c_void};
use std::thread;
use std::time::{Duration, Instant};

const TICK: Duration = Duration::from_secs(1);

// glibc `struct statvfs` on a 64-bit (LP64) target: every count field is an
// unsigned long. We only read f_frsize/f_blocks/f_bfree.
#[repr(C)]
struct Statvfs {
    f_bsize: c_ulong,
    f_frsize: c_ulong,
    f_blocks: c_ulong,
    f_bfree: c_ulong,
    f_bavail: c_ulong,
    f_files: c_ulong,
    f_ffree: c_ulong,
    f_favail: c_ulong,
    f_fsid: c_ulong,
    f_flag: c_ulong,
    f_namemax: c_ulong,
    f_spare: [c_int; 6],
}

extern "C" {
    fn statvfs(path: *const c_char, buf: *mut Statvfs) -> c_int;
    fn ioctl(fd: c_int, request: c_ulong, arg: *mut c_void) -> c_int;
    fn socket(domain: c_int, ty: c_int, protocol: c_int) -> c_int;
    fn close(fd: c_int) -> c_int;
}

fn sanitize(s: &str) -> String {
    // LCDd wraps widget text in double quotes; keep the payload quote-free and
    // printable-ASCII so we never break the command line.
    s.chars()
        .map(|c| {
            let c = match c {
                '\\' => '/',
                '"' => '\'',
                other => other,
            };
            let o = c as u32;
            if (32..127).contains(&o) {
                c
            } else {
                '?'
            }
        })
        .collect()
}

fn trunc(s: &str, wid: usize) -> String {
    s.chars().take(wid).collect()
}

fn send(stream: &TcpStream, line: &str) -> io::Result<()> {
    let mut w = stream;
    w.write_all(line.as_bytes())?;
    w.write_all(b"\n")
}

fn readline(stream: &TcpStream) -> io::Result<String> {
    let mut r = stream;
    let mut buf = Vec::new();
    let mut b = [0u8; 1];
    loop {
        let n = r.read(&mut b)?;
        if n == 0 {
            return Err(io::Error::new(io::ErrorKind::UnexpectedEof, "LCDd closed the connection"));
        }
        if b[0] == b'\n' {
            break;
        }
        buf.push(b[0]);
    }
    Ok(String::from_utf8_lossy(&buf).trim().to_string())
}

fn drain(stream: &TcpStream) -> io::Result<()> {
    // Discard async server chatter (listen/ignore/key/success) so the socket
    // buffer never fills; detect a server-side close.
    stream.set_nonblocking(true)?;
    let mut r = stream;
    let mut buf = [0u8; 4096];
    let result = loop {
        match r.read(&mut buf) {
            Ok(0) => break Err(io::Error::new(io::ErrorKind::Other, "LCDd closed the connection")),
            Ok(_) => continue,
            Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => break Ok(()),
            Err(e) => break Err(e),
        }
    };
    stream.set_nonblocking(false)?;
    result
}

fn read_cpu() -> (u64, u64) {
    if let Ok(s) = fs::read_to_string("/proc/stat") {
        if let Some(line) = s.lines().next() {
            let vals: Vec<u64> = line.split_whitespace().skip(1).filter_map(|x| x.parse().ok()).collect();
            if vals.len() >= 4 {
                let idle = vals[3] + if vals.len() > 4 { vals[4] } else { 0 }; // idle + iowait
                let total: u64 = vals.iter().sum();
                return (idle, total);
            }
        }
    }
    (0, 0)
}

fn mem_pct() -> f64 {
    let mut total = 0.0f64;
    let mut avail = 0.0f64;
    let mut free = 0.0f64;
    let mut have_avail = false;
    if let Ok(s) = fs::read_to_string("/proc/meminfo") {
        for line in s.lines() {
            let mut it = line.split_whitespace();
            let key = it.next().unwrap_or("");
            let val: f64 = it.next().and_then(|v| v.parse().ok()).unwrap_or(0.0);
            match key {
                "MemTotal:" => total = val,
                "MemAvailable:" => {
                    avail = val;
                    have_avail = true;
                }
                "MemFree:" => free = val,
                _ => {}
            }
        }
    }
    let a = if have_avail { avail } else { free };
    if total > 0.0 {
        100.0 * (total - a) / total
    } else {
        0.0
    }
}

fn disk_stats(path: &str) -> (f64, f64, f64) {
    let c = match std::ffi::CString::new(path) {
        Ok(c) => c,
        Err(_) => return (0.0, 0.0, 0.0),
    };
    let mut st: Statvfs = unsafe { std::mem::zeroed() };
    if unsafe { statvfs(c.as_ptr(), &mut st) } != 0 {
        return (0.0, 0.0, 0.0);
    }
    let frsize = st.f_frsize as f64;
    let total = st.f_blocks as f64 * frsize;
    let used = total - st.f_bfree as f64 * frsize;
    let pct = if total > 0.0 { 100.0 * used / total } else { 0.0 };
    (pct, used, total)
}

fn loadavg() -> String {
    fs::read_to_string("/proc/loadavg")
        .ok()
        .and_then(|s| s.split_whitespace().next().map(str::to_string))
        .unwrap_or_else(|| "?".into())
}

fn uptime_fmt(up: f64) -> String {
    let d = (up / 86400.0) as u64;
    let h = ((up % 86400.0) / 3600.0) as u64;
    let m = ((up % 3600.0) / 60.0) as u64;
    if d > 0 {
        format!("{}d{}h", d, h)
    } else if h > 0 {
        format!("{}h{}m", h, m)
    } else {
        format!("{}m", m)
    }
}

fn uptime_s() -> String {
    let up = fs::read_to_string("/proc/uptime")
        .ok()
        .and_then(|s| s.split_whitespace().next().and_then(|x| x.parse::<f64>().ok()))
        .unwrap_or(0.0);
    uptime_fmt(up)
}

fn human(mut n: f64) -> String {
    for u in ["B", "K", "M", "G", "T"] {
        if n < 1024.0 {
            return format!("{:.0}{}", n, u);
        }
        n /= 1024.0;
    }
    format!("{:.0}P", n)
}

fn default_iface() -> Option<String> {
    // The interface carrying the default route, read from /proc/net/route
    // (destination 0.0.0.0 with the RTF_UP flag set).
    let s = fs::read_to_string("/proc/net/route").ok()?;
    for line in s.lines().skip(1) {
        let f: Vec<&str> = line.split_whitespace().collect();
        if f.len() >= 4 && f[1] == "00000000" {
            if let Ok(flags) = u32::from_str_radix(f[3], 16) {
                if flags & 0x2 != 0 {
                    return Some(f[0].to_string());
                }
            }
        }
    }
    None
}

fn primary_ip() -> String {
    // Resolve the default-route interface's IPv4 via ioctl only. We create an
    // unbound AF_INET datagram socket purely as an ioctl handle (never bind,
    // connect, or send) — no packets leave, and this keeps working under the
    // locked-down sandbox (IPAddressDeny=any, SocketBindDeny=any). A std
    // UdpSocket would call bind() and be denied, so we make the fd via libc.
    let iface = match default_iface() {
        Some(i) => i,
        None => return "no-ip".into(),
    };
    const AF_INET: c_int = 2;
    const SOCK_DGRAM: c_int = 2;
    const SIOCGIFADDR: c_ulong = 0x8915;
    let fd = unsafe { socket(AF_INET, SOCK_DGRAM, 0) };
    if fd < 0 {
        return "no-ip".into();
    }
    let mut buf = [0u8; 40]; // struct ifreq: char[16] name + 24-byte union
    let name = iface.as_bytes();
    let n = name.len().min(15);
    buf[..n].copy_from_slice(&name[..n]);
    let rc = unsafe { ioctl(fd, SIOCGIFADDR, buf.as_mut_ptr() as *mut c_void) };
    unsafe { close(fd) };
    if rc != 0 {
        return "no-ip".into();
    }
    // sockaddr_in sits at offset 16; sin_addr is 4 bytes at offset 20.
    format!("{}.{}.{}.{}", buf[20], buf[21], buf[22], buf[23])
}

fn lldp_neighbor(iface: &str) -> (String, String) {
    // LLDP neighbour (switch) for `iface`, from the keyvalue dump that the
    // bpi-f3-lcd-lldp timer writes (the client is too locked down to query the
    // _lldpd-only control socket itself). Returns (switch-name, port); empty
    // strings when there is no neighbour or no dump yet.
    let data = match fs::read_to_string("/run/lcd/lldp.kv") {
        Ok(s) => s,
        Err(_) => return (String::new(), String::new()),
    };
    let pfx = format!("lldp.{}.", iface);
    let (mut name, mut mac, mut ifname, mut descr, mut local) =
        (String::new(), String::new(), String::new(), String::new(), String::new());
    for line in data.lines() {
        if let Some(rest) = line.trim().strip_prefix(&pfx) {
            if let Some((k, v)) = rest.split_once('=') {
                match k {
                    "chassis.name" => name = v.to_string(),
                    "chassis.mac" => mac = v.to_string(),
                    "port.ifname" => ifname = v.to_string(),
                    "port.descr" => descr = v.to_string(),
                    "port.local" => local = v.to_string(),
                    _ => {}
                }
            }
        }
    }
    let sw = if !name.is_empty() {
        name
    } else if !mac.is_empty() {
        mac
    } else {
        return (String::new(), String::new());
    };
    // Prefer a real remote port name, then its description, then the numeric id.
    let port = if !ifname.is_empty() {
        ifname
    } else if !descr.is_empty() {
        descr
    } else if !local.is_empty() {
        format!("#{}", local)
    } else {
        String::new()
    };
    (sw, port)
}

fn hostname() -> String {
    fs::read_to_string("/proc/sys/kernel/hostname")
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|_| "?".into())
}

fn fit(left: &str, right: &str, wid: usize) -> String {
    // left-justify `left`, right-justify `right`, on a `wid`-wide line.
    let ll = left.chars().count();
    let rl = right.chars().count();
    if !right.is_empty() && ll + 1 + rl <= wid {
        format!("{}{}{}", left, " ".repeat(wid - ll - rl), right)
    } else {
        trunc(left, wid)
    }
}

// Pure page builder shared by the live path and --selftest.
#[allow(clippy::too_many_arguments)]
fn pages_from(
    wid: usize,
    hgt: usize,
    host: &str,
    ip: &str,
    cpu: f64,
    mem: f64,
    dpct: f64,
    dused: f64,
    dtot: f64,
    load: &str,
    up: &str,
    sw: &str,
    port: &str,
) -> Vec<Vec<String>> {
    if hgt >= 4 {
        // One static summary screen.
        return vec![vec![
            fit(host, &format!("up{}", up), wid),
            fit("IP", ip, wid),
            format!("CPU {:3.0}%  MEM {:3.0}%", cpu, mem),
            format!("/ {:3.0}%   ld {}", dpct, load),
        ]];
    }
    // <=3 rows: rotate compact pages (two lines each here). The identity page
    // packs CPU/MEM onto the hostname line so no row is half-empty; the last
    // page is the LLDP switch/port the board is cabled to (debugging aid).
    let sw_line = if sw.is_empty() { "no-lldp" } else { sw };
    vec![
        vec![fit(host, &format!("C{:.0} M{:.0}", cpu, mem), wid), trunc(ip, wid)],
        vec![
            format!("CPU {:3.0}% {:>4}", cpu, load),
            format!("MEM {:3.0}% up{}", mem, up),
        ],
        vec![
            "DISK /".to_string(),
            format!("{:3.0}% {}/{}", dpct, human(dused), human(dtot)),
        ],
        vec![trunc(sw_line, wid), trunc(port, wid)],
    ]
}

fn build_pages(wid: usize, hgt: usize, cpu: f64) -> Vec<Vec<String>> {
    let (dpct, dused, dtot) = disk_stats("/");
    let iface = default_iface().unwrap_or_default();
    let (sw, port) = lldp_neighbor(&iface);
    pages_from(
        wid,
        hgt,
        &hostname(),
        &primary_ip(),
        cpu,
        mem_pct(),
        dpct,
        dused,
        dtot,
        &loadavg(),
        &uptime_s(),
        &sw,
        &port,
    )
}

fn render(stream: &TcpStream, wid: usize, hgt: usize, lines: &[String]) -> io::Result<()> {
    for i in 1..=hgt {
        let text = if i - 1 < lines.len() {
            sanitize(&lines[i - 1])
        } else {
            String::new()
        };
        send(stream, &format!("widget_set status ln{} 1 {} \"{}\"", i, i, trunc(&text, wid)))?;
    }
    Ok(())
}

fn parse_geom(toks: &[&str]) -> (usize, usize) {
    let get = |k: &str| -> Option<usize> {
        toks.iter().position(|t| *t == k).and_then(|i| toks.get(i + 1)).and_then(|v| v.parse().ok())
    };
    match (get("wid"), get("hgt")) {
        (Some(w), Some(h)) if w > 0 && h > 0 => (w, h),
        _ => (16, 2), // sane fallback if the handshake is unexpected
    }
}

fn env_or<'a>(key: &str, default: &'a str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

fn run() -> io::Result<()> {
    let host = env_or("LCD_HOST", "127.0.0.1");
    let port: u16 = env::var("LCD_PORT").ok().and_then(|v| v.parse().ok()).unwrap_or(13666);
    let flip: f64 = env::var("LCD_FLIP_SECS").ok().and_then(|v| v.parse().ok()).unwrap_or(4.0);

    let target = format!("{}:{}", host, port);
    let mut stream = None;
    for _ in 0..30 {
        if let Ok(mut addrs) = target.to_socket_addrs() {
            if let Some(sa) = addrs.next() {
                if let Ok(s) = TcpStream::connect_timeout(&sa, Duration::from_secs(5)) {
                    stream = Some(s);
                    break;
                }
            }
        }
        thread::sleep(Duration::from_secs(2));
    }
    let stream = stream.ok_or_else(|| io::Error::new(io::ErrorKind::Other, "cannot reach LCDd"))?;

    send(&stream, "hello")?;
    let hello = readline(&stream)?;
    let toks: Vec<&str> = hello.split_whitespace().collect();
    let (wid, hgt) = parse_geom(&toks);

    send(&stream, "client_set -name bpi-f3")?;
    send(&stream, "screen_add status")?;
    send(&stream, "screen_set status -priority foreground -name Status -heartbeat off")?;
    for i in 1..=hgt {
        send(&stream, &format!("widget_add status ln{} string", i))?;
    }

    let (mut prev_idle, mut prev_total) = read_cpu();
    let mut page = 0usize;
    let mut last_flip = Instant::now();

    loop {
        drain(&stream)?;
        let (idle, total) = read_cpu();
        let d_idle = idle.saturating_sub(prev_idle) as f64;
        let d_total = total.saturating_sub(prev_total) as f64;
        let cpu = if d_total > 0.0 {
            100.0 * (1.0 - d_idle / d_total)
        } else {
            0.0
        };
        prev_idle = idle;
        prev_total = total;

        let pages = build_pages(wid, hgt, cpu);
        if last_flip.elapsed().as_secs_f64() >= flip {
            page = (page + 1) % pages.len();
            last_flip = Instant::now();
        }
        let idx = page % pages.len();
        render(&stream, wid, hgt, &pages[idx])?;
        thread::sleep(TICK);
    }
}

// Deterministic parity oracle: fixed inputs -> rendered lines, matched
// line-for-line by lcd-client.py --selftest. Positive / boundary / corner
// cases for the pure helpers plus both panel geometries.
fn selftest() {
    for n in [0.0f64, 1023.0, 1024.0, 1048576.0, 1073741824.0, 11811160064.0] {
        println!("human {} {}", n as u64, human(n));
    }
    for s in [30.0f64, 3599.0, 3600.0, 7200.0, 90000.0, 270000.0] {
        println!("uptime {} {}", s as u64, uptime_fmt(s));
    }
    println!("fit |{}|", fit("bpi-f3", "up3d5h", 16));
    println!("fit |{}|", fit("IP", "172.16.40.205", 20));
    println!("fit |{}|", fit("verylongname", "zz", 8));
    println!("fit |{}|", fit("short", "", 16));
    for s in ["ok", "a\"b", "a\\b", "x\ty", "café"] {
        println!("san |{}|", sanitize(s));
    }
    for (w, h) in [(16usize, 2usize), (20, 4)] {
        let pages = pages_from(
            w,
            h,
            "bpi-f3",
            "172.16.40.205",
            7.0,
            63.0,
            2.0,
            11811160064.0,
            983547510784.0,
            "0.42",
            "3d5h",
            "ex2200",
            "pi-sebastian:end0 | HOST",
        );
        for (pi, pg) in pages.iter().enumerate() {
            for i in 0..h {
                let line = if i < pg.len() { sanitize(&pg[i]) } else { String::new() };
                println!("pg {}x{} p{} l{} |{}|", w, h, pi, i, trunc(&line, w));
            }
        }
    }
}

fn main() {
    if env::args().skip(1).any(|a| a == "--selftest") {
        selftest();
        return;
    }
    std::process::exit(match run() {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("bpi-f3-lcd-client: {}", e);
            1
        }
    });
}
