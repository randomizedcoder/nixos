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

  # Remote dev box (see l2-dev-box notes). Key 4 ships the clipboard screenshot
  # here so Claude Code running on l2 can read it by path; Key 5 types that path.
  l2Host = "das@l2";
  l2ScreenshotPath = "/tmp/screenshot.png";

  # --- typed text constants ------------------------------------------------

  # Key 2 text. Pulled out of the script body so it is easy to read and edit
  # without touching the ydotool invocation below.
  tableTestText = "table driven unit test with positive, negative, boundary, and corner cases, and in the table include description and expected test outcome";

  # --- helpers -------------------------------------------------------------

  # Build a script that types a fixed string into the focused window via
  # ydotool. (wtype does not work on GNOME/Mutter Wayland.) The 5ms key
  # delay/hold overrides ydotool's slow 20ms default (~4x faster).
  typeText = name: text: pkgs.writeShellScript name ''
    set -euo pipefail
    export YDOTOOL_SOCKET=${ydotoolSocket}
    ${pkgs.ydotool}/bin/ydotool type --key-delay 5 --key-hold 5 -- ${lib.escapeShellArg text}
  '';

  # Placeholder macro: types "button N" for pad position N. Handy for
  # confirming a key is wired up before assigning it a real action.
  buttonN = n: typeText "k9-button-${toString n}" "button ${toString n}";

  # --- macro scripts (run inside the user graphical session) ---------------

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

  # Key 4: copy the image currently on the (Wayland) clipboard — e.g. a Gradia
  # screenshot — and scp it to l2:/tmp/screenshot.png so Claude Code on l2 can
  # read it by path (Claude's Ctrl+V clipboard paste can't cross the SSH gap).
  scpScreenshot = pkgs.writeShellScript "k9-scp-screenshot" ''
    set -euo pipefail
    tmp=$(${pkgs.coreutils}/bin/mktemp --suffix=.png)
    trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
    if ! ${pkgs.wl-clipboard}/bin/wl-paste --type image/png > "$tmp" \
        || [ ! -s "$tmp" ]; then
      ${pkgs.libnotify}/bin/notify-send "Screenshot" "No image on clipboard" || true
      exit 1
    fi
    ${pkgs.openssh}/bin/scp -o BatchMode=yes "$tmp" ${l2Host}:${l2ScreenshotPath}
    ${pkgs.libnotify}/bin/notify-send "Screenshot" "Sent → ${l2Host}:${l2ScreenshotPath}" || true
  '';

  # Key 5: type the prompt pointing Claude Code (on l2) at the uploaded image.
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
    { key = "KEY_KP1"; run = buttonN 1;       desc = "Button 1: type \"button 1\""; }
    { key = "KEY_KP2"; run = buttonN 2;       desc = "Button 2: type \"button 2\""; }
    { key = "KEY_KP3"; run = buttonN 3;       desc = "Button 3: type \"button 3\""; }
    { key = "KEY_KP4"; run = scpScreenshot;        desc = "Button 4: scp clipboard screenshot → l2:/tmp/screenshot.png"; }
    { key = "KEY_KP5"; run = typeScreenshotPrompt; desc = "Button 5: type the \"see screenshot\" prompt"; }
    { key = "KEY_KP6"; run = buttonN 6;       desc = "Button 6: type \"button 6\""; }
    { key = "KEY_KP7"; run = audioCombo384;   desc = "Button 7: audio output → Combo384 DAC"; }
    { key = "KEY_KP8"; run = typeTableTest;   desc = "Button 8: type the table-driven-test string"; }
    { key = "KEY_KP9"; run = buttonN 9;       desc = "Button 9: type \"button 9\""; }
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
