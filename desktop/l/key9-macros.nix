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
  typeTableTest = pkgs.writeShellScript "k9-type-table-test" ''
    set -euo pipefail
    export YDOTOOL_SOCKET=${ydotoolSocket}
    # ydotool defaults to 20ms key-delay + 20ms key-hold (~40ms/char, very slow
    # for long strings). Drop both to 5ms for ~4x faster typing.
    ${pkgs.ydotool}/bin/ydotool type --key-delay 5 --key-hold 5 -- "table driven unit test with positive, negative, boundary, and corner cases, including description of the test in the table"
  '';

  # --- the extensible macro table ------------------------------------------
  # ONE ENTRY PER KEY. `key` is the xremap key name captured with evtest (see
  # key9-macros.md § Capture). This pad is a 3×3 numpad:
  #   KP7 KP8 KP9   (top row,    positions 1 2 3)
  #   KP4 KP5 KP6   (middle row, positions 4 5 6)
  #   KP1 KP2 KP3   (bottom row, positions 7 8 9)
  macros = [
    { key = "KEY_KP7"; run = audioCombo384; desc = "Pos 1: audio output → Combo384 DAC"; }
    { key = "KEY_KP8"; run = typeTableTest; desc = "Pos 2: type the table-driven-test string"; }
    # Add more keys here (KP9, KP4, KP5, KP6, KP1, KP2, KP3), e.g.:
    # { key = "KEY_KP9"; run = audioDefault;   desc = "Pos 3: audio output → speakers"; }
    # { key = "KEY_KP6"; run = "gradia-toggle"; desc = "Pos 6: Gradia screenshot"; }  # reuse existing wrapper
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
