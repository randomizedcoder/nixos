# key9-macros.nix
#
# Macros for the SDCINNOVATION "Key-9" 9-key USB macro pad (USB 0816:060c).
#
# Design: the pad enumerates as an ordinary HID keyboard, so its keys would
# clash with the main keyboard if bound globally. Instead xremap grabs *only*
# this device (by name substring) and maps each key to a `launch` action that
# runs a small script. xremap runs as a systemd *user* service so the launched
# commands inherit the graphical session (needed to reach the per-user PipeWire
# socket and the ydotool daemon). Long text is typed via ydotool because wtype
# does not work on GNOME/Mutter Wayland.
#
# See key9-macros.md for the physical layout, the evtest capture procedure, and
# how to add a macro. Adding a macro = append ONE entry to `macros` below.
#
#   systemctl --user status key9-macros
#   journalctl --user -u key9-macros -f

{ config, lib, pkgs, ... }:

let
  # xremap built for GNOME (this box is GNOME/Wayland). We never use
  # `application:` matchers, so no GNOME shell extension is required.
  xremap = pkgs.xremap.override { withVariant = "gnome"; };

  # Socket exported by the programs.ydotool NixOS module (ydotoold runs as a
  # system service; its socket lives here).
  ydotoolSocket = "/run/ydotoold/socket";

  # Remote boxes that receive the clipboard screenshot so Claude Code there can
  # read it by path (Claude's Ctrl+V clipboard paste can't cross the SSH gap).
  # Key 4 ships to l2, Key 5 ships to hp5; Key 6 types the path (see l2-dev-box).
  l2Host = "das@l2";
  hp5Host = "das@hp5";
  l2ScreenshotPath = "/tmp/screenshot.png";

  # --- typed text constants ------------------------------------------------

  # Key 3 text. Pulled out of the script body so it is easy to read and edit
  # without touching the ydotool invocation below.
  tableTestText = "table driven unit test with positive, negative, boundary, and corner cases, and in the table include description and expected test outcome";

  # Fill-in text for the placeholder keys. Set each string to whatever you want
  # that key to type. Empty string = key types nothing (still safe to press).
  key1Text = "/compact";        # Key 1 also presses Enter after typing (submits)
  key2Text = "please continue"; # Key 2 also presses Enter after typing (submits)
  key8Text = "";
  key9Text = "";

  # --- helpers -------------------------------------------------------------

  # Build a script that types a fixed string into the focused window via
  # ydotool. (wtype does not work on GNOME/Mutter Wayland.) The 5ms key
  # delay/hold overrides ydotool's slow 20ms default (~4x faster).
  typeText = name: text: pkgs.writeShellScript name ''
    set -euo pipefail
    export YDOTOOL_SOCKET=${ydotoolSocket}
    ${pkgs.ydotool}/bin/ydotool type --key-delay 5 --key-hold 5 -- ${lib.escapeShellArg text}
  '';

  # Same as typeText but presses Enter afterwards (keycode 28 = KEY_ENTER, so
  # "28:1 28:0" is press-then-release). Use for keys that should submit.
  typeTextEnter = name: text: pkgs.writeShellScript name ''
    set -euo pipefail
    export YDOTOOL_SOCKET=${ydotoolSocket}
    ${pkgs.ydotool}/bin/ydotool type --key-delay 5 --key-hold 5 -- ${lib.escapeShellArg text}
    ${pkgs.ydotool}/bin/ydotool key 28:1 28:0
  '';

  # --- macro scripts (run inside the user graphical session) ---------------

  # Placeholder keys: each types its own fill-in constant (see above). Edit the
  # matching keyNText string to change what the key types.
  typeKey1 = typeTextEnter "k9-type-key1" key1Text;
  typeKey2 = typeTextEnter "k9-type-key2" key2Text;
  typeKey8 = typeText "k9-type-key8" key8Text;
  typeKey9 = typeText "k9-type-key9" key9Text;

  # Key 1: set the default audio output to the Amanero Combo384 DAC and move
  # any already-playing streams onto it. Change `match` to target a different
  # output; it is a case-insensitive substring of the PipeWire/Pulse sink name.
  audioCombo384 = pkgs.writeShellScript "k9-audio-combo384" ''
    set -euo pipefail
    match="combo384"
    sink=$(${pkgs.pulseaudio}/bin/pactl list short sinks \
      | ${pkgs.gnugrep}/bin/grep -i "$match" \
      | ${pkgs.coreutils}/bin/head -n1 \
      | ${pkgs.coreutils}/bin/cut -f2 || true)
    if [ -z "''${sink:-}" ]; then
      ${pkgs.libnotify}/bin/notify-send "Audio" "No sink matching '$match'" || true
      exit 1
    fi
    ${pkgs.pulseaudio}/bin/pactl set-default-sink "$sink"
    ${pkgs.pulseaudio}/bin/pactl list short sink-inputs \
      | ${pkgs.coreutils}/bin/cut -f1 \
      | while read -r i; do
          [ -n "$i" ] && ${pkgs.pulseaudio}/bin/pactl move-sink-input "$i" "$sink" || true
        done
    ${pkgs.libnotify}/bin/notify-send "Audio" "Output → $sink" || true
  '';

  # Key 2: type the table-driven unit-test boilerplate into the focused window.
  typeTableTest = typeText "k9-type-table-test" tableTestText;

  # Copy the image currently on the (Wayland) clipboard — e.g. a Gradia
  # screenshot — and scp it to <host>:<path> so Claude Code on that host can
  # read it by path (Claude's Ctrl+V clipboard paste can't cross the SSH gap).
  scpScreenshotTo = name: host: path: pkgs.writeShellScript name ''
    set -euo pipefail
    tmp=$(${pkgs.coreutils}/bin/mktemp --suffix=.png)
    trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
    if ! ${pkgs.wl-clipboard}/bin/wl-paste --type image/png > "$tmp" \
        || [ ! -s "$tmp" ]; then
      ${pkgs.libnotify}/bin/notify-send "Screenshot" "No image on clipboard" || true
      exit 1
    fi
    ${pkgs.openssh}/bin/scp -o BatchMode=yes "$tmp" ${host}:${path}
    ${pkgs.libnotify}/bin/notify-send "Screenshot" "Sent → ${host}:${path}" || true
  '';

  # Key 4: ship the clipboard screenshot to l2. Key 5: ship it to hp5.
  scpScreenshot    = scpScreenshotTo "k9-scp-screenshot"     l2Host  l2ScreenshotPath;
  scpScreenshotHp5 = scpScreenshotTo "k9-scp-screenshot-hp5" hp5Host l2ScreenshotPath;

  # Key 6: type the prompt pointing Claude Code at the uploaded image.
  typeScreenshotPrompt = typeText "k9-type-screenshot-prompt"
    "please see screenshot in ${l2ScreenshotPath}";

  # --- the extensible macro table ------------------------------------------
  # ONE ENTRY PER KEY. `key` is the xremap key name captured with evtest (see
  # key9-macros.md § Capture). This pad is a 3×3 numpad; the button number is
  # just the KP digit on the physical key:
  #   KP7 KP8 KP9   (top row)
  #   KP4 KP5 KP6   (middle row)
  #   KP1 KP2 KP3   (bottom row)
  macros = [
    { key = "KEY_KP1"; run = typeKey1;             desc = "Button 1: type \"/compact\" + Enter"; }
    { key = "KEY_KP2"; run = typeKey2;             desc = "Button 2: type \"please continue\" + Enter"; }
    { key = "KEY_KP3"; run = typeTableTest;        desc = "Button 3: type the table-driven-test string"; }
    { key = "KEY_KP4"; run = scpScreenshot;        desc = "Button 4: scp clipboard screenshot → l2:/tmp/screenshot.png"; }
    { key = "KEY_KP5"; run = scpScreenshotHp5;     desc = "Button 5: scp clipboard screenshot → hp5:/tmp/screenshot.png"; }
    { key = "KEY_KP6"; run = typeScreenshotPrompt; desc = "Button 6: type the \"see screenshot\" prompt"; }
    { key = "KEY_KP7"; run = audioCombo384;        desc = "Button 7: audio output → Combo384 DAC"; }
    { key = "KEY_KP8"; run = typeKey8;             desc = "Button 8: type key8Text"; }
    { key = "KEY_KP9"; run = typeKey9;             desc = "Button 9: type key9Text"; }
  ];

  # Build the xremap remap map from the table.
  remap = lib.listToAttrs (map (m: {
    name = m.key;
    value = { launch = [ "${m.run}" ]; };
  }) macros);

  xremapConfig = (pkgs.formats.yaml { }).generate "key9-xremap.yml" {
    keymap = [{
      name = "Key-9 macros";
      # Substring match on the device name grabs the pad. Alternatively use
      # "ids:0x0816:0x060c".
      device.only = [ "SDCINNOVATION Key-9" ];
      inherit remap;
    }];
  };
in
{
  # ydotoold system service + the `ydotool` CLI. Members of the `ydotool`
  # group may talk to the daemon.
  programs.ydotool.enable = true;

  # xremap runs rootless (as the user), so it needs write access to
  # /dev/uinput. hardware.uinput loads the module and grants the `uinput`
  # group access. (Read access to /dev/input/event* comes from the `input`
  # group — both groups are added to `das` in configuration.nix.)
  hardware.uinput.enable = true;

  environment.systemPackages = [ xremap ];

  systemd.user.services.key9-macros = {
    description = "xremap macros for the SDCINNOVATION Key-9 pad";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      # --watch=device re-grabs the pad after it resets/reconnects (it does
      # this on the USB bus per dmesg).
      ExecStart = "${xremap}/bin/xremap --watch=device ${xremapConfig}";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
