// claude-statusline-rs
//
// Drop-in replacement for the shell-based claude-statusline. Produces the
// exact same output given the same Claude Code statusline JSON on stdin.
//
// Written with std only (no serde_json) so the nix build needs no cargo
// vendoring — it's a tiny JSON parser sufficient for Claude Code's shape.
//
// Output format:
//   <profile> <dir> [<branch>] | c:USED%/REMAIN% [| s:USED%/REMAIN%] [| <model> [<effort>]]
//
// Palettes (see claude.nix for the rationale):
//   context (c): green / orange / red   at <50 / <80 / >=80
//   session (s): bright blue / bright magenta / bright red
//   branch: yellow
//   model + effort: dim

use std::io::{self, BufWriter, Read, Write};
use std::fs;

// ---------- tiny JSON ----------

#[allow(dead_code)]
enum Val {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Val>),
    Obj(Vec<(String, Val)>),
}

impl Val {
    fn get(&self, k: &str) -> Option<&Val> {
        match self {
            Val::Obj(o) => o.iter().find(|(n, _)| n == k).map(|(_, v)| v),
            _ => None,
        }
    }
    fn as_f64(&self) -> Option<f64> {
        match self {
            Val::Num(n) => Some(*n),
            _ => None,
        }
    }
    fn as_str(&self) -> Option<&str> {
        match self {
            Val::Str(s) => Some(s.as_str()),
            _ => None,
        }
    }
}

struct P<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> P<'a> {
    fn ws(&mut self) {
        while self.i < self.b.len() && matches!(self.b[self.i], b' ' | b'\t' | b'\n' | b'\r') {
            self.i += 1;
        }
    }
    fn peek(&self) -> Option<u8> {
        self.b.get(self.i).copied()
    }
    fn eat(&mut self) -> Option<u8> {
        let c = self.peek()?;
        self.i += 1;
        Some(c)
    }
    fn expect(&mut self, c: u8) -> Option<()> {
        if self.eat()? == c {
            Some(())
        } else {
            None
        }
    }
    fn lit<const N: usize>(&mut self, s: &[u8; N]) -> Option<()> {
        if self.b.get(self.i..self.i + N)? == &s[..] {
            self.i += N;
            Some(())
        } else {
            None
        }
    }

    fn value(&mut self) -> Option<Val> {
        self.ws();
        match self.peek()? {
            b'"' => Some(Val::Str(self.string()?)),
            b'{' => self.object(),
            b'[' => self.array(),
            b't' => {
                self.lit(b"true")?;
                Some(Val::Bool(true))
            }
            b'f' => {
                self.lit(b"false")?;
                Some(Val::Bool(false))
            }
            b'n' => {
                self.lit(b"null")?;
                Some(Val::Null)
            }
            _ => self.number(),
        }
    }

    fn string(&mut self) -> Option<String> {
        self.expect(b'"')?;
        let mut raw = Vec::<u8>::new();
        loop {
            let c = self.eat()?;
            match c {
                b'"' => return String::from_utf8(raw).ok(),
                b'\\' => {
                    let e = self.eat()?;
                    match e {
                        b'"' => raw.push(b'"'),
                        b'\\' => raw.push(b'\\'),
                        b'/' => raw.push(b'/'),
                        b'n' => raw.push(b'\n'),
                        b't' => raw.push(b'\t'),
                        b'r' => raw.push(b'\r'),
                        b'b' => raw.push(0x08),
                        b'f' => raw.push(0x0C),
                        b'u' => {
                            let hex =
                                std::str::from_utf8(self.b.get(self.i..self.i + 4)?).ok()?;
                            self.i += 4;
                            let cp = u32::from_str_radix(hex, 16).ok()?;
                            if let Some(ch) = char::from_u32(cp) {
                                let mut buf = [0u8; 4];
                                raw.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                            }
                        }
                        _ => return None,
                    }
                }
                _ => raw.push(c),
            }
        }
    }

    fn number(&mut self) -> Option<Val> {
        let start = self.i;
        if self.peek() == Some(b'-') {
            self.i += 1;
        }
        while let Some(c) = self.peek() {
            if c.is_ascii_digit() || matches!(c, b'.' | b'e' | b'E' | b'+' | b'-') {
                self.i += 1;
            } else {
                break;
            }
        }
        let s = std::str::from_utf8(&self.b[start..self.i]).ok()?;
        s.parse::<f64>().ok().map(Val::Num)
    }

    fn object(&mut self) -> Option<Val> {
        self.expect(b'{')?;
        let mut o = Vec::new();
        self.ws();
        if self.peek() == Some(b'}') {
            self.i += 1;
            return Some(Val::Obj(o));
        }
        loop {
            self.ws();
            let k = self.string()?;
            self.ws();
            self.expect(b':')?;
            let v = self.value()?;
            o.push((k, v));
            self.ws();
            match self.eat()? {
                b',' => continue,
                b'}' => return Some(Val::Obj(o)),
                _ => return None,
            }
        }
    }

    fn array(&mut self) -> Option<Val> {
        self.expect(b'[')?;
        let mut a = Vec::new();
        self.ws();
        if self.peek() == Some(b']') {
            self.i += 1;
            return Some(Val::Arr(a));
        }
        loop {
            let v = self.value()?;
            a.push(v);
            self.ws();
            match self.eat()? {
                b',' => continue,
                b']' => return Some(Val::Arr(a)),
                _ => return None,
            }
        }
    }
}

fn parse(s: &str) -> Option<Val> {
    let mut p = P { b: s.as_bytes(), i: 0 };
    p.value()
}

// ---------- output ----------

fn pick<'a>(pct: i64, low: &'a str, mid: &'a str, high: &'a str) -> &'a str {
    if pct >= 80 {
        high
    } else if pct >= 50 {
        mid
    } else {
        low
    }
}

fn tier_abbrev(s: &str) -> String {
    match s {
        "max" => "max".into(),
        "pro" => "pro".into(),
        "enterprise" => "ent".into(),
        "team" => "team".into(),
        "free" => "free".into(),
        other => other.chars().take(4).collect::<String>().to_lowercase(),
    }
}

// Falls back to the active profile's subscription tier when Anthropic
// doesn't include `rate_limits.five_hour` (enterprise / usage-based seats).
fn read_subscription_tier() -> Option<String> {
    let dir = std::env::var("CLAUDE_CONFIG_DIR").ok()
        .filter(|s| !s.is_empty())
        .or_else(|| std::env::var("HOME").ok().map(|h| format!("{h}/.claude")))?;
    let raw = fs::read_to_string(format!("{dir}/.credentials.json")).ok()?;
    let v = parse(&raw)?;
    let tier = v.get("claudeAiOauth")?.get("subscriptionType")?.as_str()?;
    Some(tier_abbrev(tier))
}

fn main() {
    let mut input = String::new();
    let _ = io::stdin().read_to_string(&mut input);
    let root = parse(&input).unwrap_or(Val::Null);

    let project_dir = root
        .get("workspace")
        .and_then(|w| w.get("project_dir"))
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");
    let dir_name = project_dir.rsplit('/').next().unwrap_or(project_dir);

    let ctx_used = root
        .get("context_window")
        .and_then(|w| w.get("used_percentage"))
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0) as i64;
    let ctx_remain = root
        .get("context_window")
        .and_then(|w| w.get("remaining_percentage"))
        .and_then(|v| v.as_f64())
        .unwrap_or(100.0) as i64;

    let sess_used_opt: Option<i64> = root
        .get("rate_limits")
        .and_then(|r| r.get("five_hour"))
        .and_then(|f| f.get("used_percentage"))
        .and_then(|v| v.as_f64())
        .map(|n| n as i64);

    // Git branch from .git/HEAD
    let branch: Option<String> = fs::read_to_string(format!("{project_dir}/.git/HEAD"))
        .ok()
        .map(|s| {
            let s = s.trim();
            if let Some(r) = s.strip_prefix("ref: refs/heads/") {
                r.to_string()
            } else if s.len() >= 7 {
                s[..7].to_string()
            } else {
                s.to_string()
            }
        });

    // Model name: prefer display_name, fall back to id
    let model_name: Option<&str> = root
        .get("model")
        .and_then(|m| m.get("display_name").and_then(|v| v.as_str())
            .or_else(|| m.get("id").and_then(|v| v.as_str())));

    // Effort level (only present when model supports it)
    let effort: Option<&str> = root
        .get("effort")
        .and_then(|e| e.get("level"))
        .and_then(|v| v.as_str());

    let effort_abbrev = effort.map(|e| match e {
        "low" => "lo",
        "medium" => "med",
        "high" => "hi",
        "xhigh" => "xhi",
        "max" => "max",
        other => other,
    });

    let profile = std::env::var("CLAUDE_CONFIG_DIR")
        .ok()
        .and_then(|p| p.rsplit('/').next().map(|s| s.to_string()))
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "default".to_string());

    const CYAN: &str = "\x1b[36m";
    const MAGENTA: &str = "\x1b[35m";
    const RESET: &str = "\x1b[0m";
    const CTX_LOW: &str = "\x1b[32m";
    const CTX_MID: &str = "\x1b[33m";
    const CTX_HIGH: &str = "\x1b[31m";
    const SESS_LOW: &str = "\x1b[94m";
    const SESS_MID: &str = "\x1b[95m";
    const SESS_HIGH: &str = "\x1b[91m";
    const YELLOW: &str = "\x1b[33m";
    const DIM: &str = "\x1b[2m";

    let ctx_color = pick(ctx_used, CTX_LOW, CTX_MID, CTX_HIGH);

    let stdout = io::stdout();
    let mut out = BufWriter::new(stdout.lock());
    let _ = write!(
        out,
        "{MAGENTA}{profile}{RESET} {CYAN}{dir_name}{RESET}"
    );
    if let Some(ref br) = branch {
        let _ = write!(out, " {YELLOW}{br}{RESET}");
    }
    let _ = write!(
        out,
        " | {ctx_color}c:{ctx_used}%/{ctx_remain}%{RESET}"
    );
    if let Some(sess_used) = sess_used_opt {
        let sess_remain = 100 - sess_used;
        let sc = pick(sess_used, SESS_LOW, SESS_MID, SESS_HIGH);
        let _ = write!(out, " | {sc}s:{sess_used}%/{sess_remain}%{RESET}");
    } else if let Some(tier) = read_subscription_tier() {
        let _ = write!(out, " | {DIM}{tier}{RESET}");
    }
    if let Some(model) = model_name {
        let _ = write!(out, " | {DIM}{model}{RESET}");
    }
    if let Some(eff) = effort_abbrev {
        let _ = write!(out, " {DIM}{eff}{RESET}");
    }
}
