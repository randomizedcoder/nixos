# Key-9 macro pad

Design + operating notes for the **SDCINNOVATION "Key-9"** 9-key USB macro pad on
host `l`. Implemented by [`key9-macros.nix`](./key9-macros.nix).

## The device

| | |
|---|---|
| Product | `SDCINNOVATION Key-9` |
| USB IDs | `0816:060c` (Vendor `0x0816`, Product `0x060c`) |
| Layout | 3×3 grid (9 keys) |
| Enumerates as | HID **keyboard** (+ mouse + consumer-control interfaces) |
| Stable path | `/dev/input/by-id/usb-SDCINNOVATION_Key-9_003123456789-event-kbd` (→ `event5`) |
| Extra kbd node | `…-if01-event-kbd` (→ `event18`), consumer on `…-event-if01` (→ `event20`) |

Because it presents as a normal keyboard, its keys emit standard keycodes that would
collide with the main keyboard if bound globally. We therefore grab **only this
device** and remap it in isolation.

## Toolchain (and why)

| Concern | Choice | Why |
|---|---|---|
| Catch the keypress | **xremap** (nixpkgs, `gnome` variant) as a **systemd user service** | Device-scoped `device.only` grab; `launch` runs commands; runs in the user session so macros reach PipeWire + ydotool. No new flake input. |
| Type a string | **ydotool** (`programs.ydotool`) | On GNOME/Mutter Wayland `wtype` does not work (no virtual-keyboard protocol); ydotool injects via kernel `uinput`. |
| Switch audio | **pactl** (PipeWire pulse-compat) | Simple `set-default-sink` + move active streams. |

Rejected: **keyd** (runs as root → can't cleanly reach the per-user PipeWire socket /
ydotool daemon); adding the **xremap flake input** (unnecessary — the nixpkgs package
is enough for pure device→launch macros).

Access wiring: `hardware.uinput.enable` (uinput write for xremap + ydotoold);
`programs.ydotool.enable` (ydotoold system service, socket `/run/ydotoold/socket`);
user `das` is in groups `input` (read `/dev/input/event*`), `uinput`, and `ydotool`.

## Key map

Physical 3×3 grid → macro. Captured with evtest: the pad emits **numpad** codes,
laid out to match the physical grid (NumLock stays on):

```
┌───────┬───────┬───────┐
│ 1 KP7 │ 2 KP8 │ 3 KP9 │
├───────┼───────┼───────┤
│ 4 KP4 │ 5 KP5 │ 6 KP6 │
├───────┼───────┼───────┤
│ 7 KP1 │ 8 KP2 │ 9 KP3 │
└───────┴───────┴───────┘
```

| Pos | Key (evtest) | Macro | Implementation |
|-----|--------------|-------|----------------|
| 1 | `KEY_KP7` | Audio output → Combo384 DAC | `k9-audio-combo384` |
| 2 | `KEY_KP8` | Type table-driven-test string | `k9-type-table-test` (ydotool) |
| 3 | `KEY_KP9` | *(unassigned)* | — |
| 4 | `KEY_KP4` | *(unassigned)* | — |
| 5 | `KEY_KP5` | *(unassigned)* | — |
| 6 | `KEY_KP6` | *(unassigned)* | — |
| 7 | `KEY_KP1` | *(unassigned)* | — |
| 8 | `KEY_KP2` | *(unassigned)* | — |
| 9 | `KEY_KP3` | *(unassigned)* | — |

Unassigned keys pass through as their numpad digit (7/8/9/4/5/6/1/2/3).

The typed string (Key 2) is:

> `table driven unit test with positive, negative, boundary, and corner cases, including description of the test in the table`

**Typing speed:** ydotool defaults to a 20 ms `--key-delay` *plus* a 20 ms
`--key-hold` per character (~40 ms/char), which crawls for long strings. The Key 2
script passes `--key-delay 5 --key-hold 5` (~10 ms/char, **~4× faster**). Adjust both
values together to trade speed for reliability — e.g. `10`/`10` for ~2×; going below
5 ms can drop or reorder characters if the focused app can't keep up with uinput.

### Suggested macros for the spare keys (ideas)

- Audio output → speakers / other DAC (second `pactl` script, different `match`).
- Mute toggle: `wpctl set-mute @DEFAULT_SINK@ toggle`.
- **Gradia** screenshot: `launch: [ "gradia-toggle" ]` — reuse the existing wrapper
  from `home.nix` (do **not** use Flameshot).
- Any other frequently-typed boilerplate via `ydotool type`.

## Capture

The pad advertises the full keyboard matrix, so which physical key sends which code
can only be learned by pressing them. In a terminal:

```bash
sudo nix shell nixpkgs#evtest -c \
  evtest /dev/input/by-id/usb-SDCINNOVATION_Key-9_003123456789-event-kbd
```

Press keys **1 → 9** (top-left to bottom-right), one each. Each press prints a line
like:

```
Event: time …, type 1 (EV_KEY), code 30 (KEY_A), value 1
```

Record the `KEY_*` name for each position, then Ctrl-C. If some keys produce nothing,
they emit on the other interface — repeat with
`…-if01-event-kbd` (event18) or `…-event-if01` (event20, consumer keys, which show as
`KEY_*` for media/consumer usages).

## Add / change a macro

1. Capture the key's `KEY_*` code (above).
2. Edit `key9-macros.nix` → append one entry to the `macros` list:
   ```nix
   { key = "KEY_F13"; run = someScript;      desc = "what it does"; }
   # run may also be a plain command name already on PATH, e.g. "gradia-toggle":
   { key = "KEY_F14"; run = "gradia-toggle"; desc = "Gradia screenshot"; }
   ```
   For a new script, add a `pkgs.writeShellScript` in the `let` block and reference it.
3. `cd /home/das/nixos/desktop/l && make`.
4. Update the key-map table above.

## Verify

```bash
make                                   # rebuild switch
systemctl --user status key9-macros    # active (running); grabbed the pad
journalctl --user -u key9-macros -f    # watch launches
```

- Press **Key 1** → GNOME Sound shows Output = "Analog Output – Combo384 Amanero";
  audio routes there; a toast appears.
- Focus an editor, press **Key 2** → the full sentence types out.
- Mapped keys no longer leak their literal character into apps (device is grabbed).
- Unplug/replug the pad → `--watch=device` re-grabs it, no restart needed.

## Troubleshooting

- **Nothing happens / keys still type literally**: the `KEY_*` in `macros` don't match
  what the key emits — re-run capture. If *no* pad key is grabbed, check the device
  name substring `SDCINNOVATION Key-9` in `key9-macros.nix` still matches
  `evtest`/`xremap --list-devices` output.
- **`ydotool` types nothing**: confirm `das` is in the `ydotool` group and
  `systemctl status ydotoold` is running; the script exports
  `YDOTOOL_SOCKET=/run/ydotoold/socket`.
- **xremap can't open uinput**: confirm `hardware.uinput.enable` took effect and `das`
  is in the `uinput` group (re-login after first rebuild so the new groups apply).
- **Audio switch fails**: run `pactl list short sinks` and check a sink name contains
  `Combo384`; adjust the `match` string in `k9-audio-combo384`.
