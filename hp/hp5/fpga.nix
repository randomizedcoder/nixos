#
# fpga.nix — host access for the Sipeed Tang Mega 138K Pro (Gowin GW5AST-138).
#
# hp5 is the machine physically cabled to the board, so it owns the USB/JTAG and
# serial permissions. This is the ONLY host-side change the FPGA work needs.
#
# NOT needed here: the Gowin EDA license MAC. The license (rtl-fun/./gowin,
# MODE=NODELOCK, HOST_ID=E04F43E628EF) is checked against the NIC of the *microVM*
# that runs Gowin, not this host — rtl-fun/nix/gowin-vm.nix presents that MAC on a
# QEMU user-mode interface. hp5's own MAC is irrelevant and must not be changed.
#
# The board presents ONE FTDI device with two interfaces:
#   0403:6010  SIPEED USB Debugger  (a BL616 emulating an FT2232D)
#     interface A -> ttyUSB0 -> JTAG  (openFPGALoader claims this via libftdi)
#     interface B -> ttyUSB1 -> UART  (serial console; minicom/screen)
# Stable paths: /dev/serial/by-id/usb-SIPEED_USB_Debugger_<serial>-if0{0,1}-port0
#
{ config, pkgs, ... }:

{
  # openFPGALoader's own rules use GROUP="plugdev", which does not exist on NixOS
  # by default. Create it rather than rewriting the vendor rule.
  users.groups.plugdev = { };

  # dialout -> /dev/ttyUSB* (the UART). plugdev -> the raw USB node (JTAG/libftdi).
  users.users.das.extraGroups = [ "dialout" "plugdev" ];

  # Derived from openFPGALoader's 99-openfpgaloader.rules. nixpkgs' openfpgaloader
  # package ships no udev rules (no postInstall installs them), so they go here.
  #
  # Both GROUP= and TAG+="uaccess" on purpose: uaccess only grants access to a user
  # with an active *local* seat, and this box is normally driven over SSH — the
  # group membership is what actually works there.
  # One rule per line: udev's backslash continuation works, but a stray trailing
  # space silently breaks it, so don't rely on it.
  services.udev.extraRules = ''
    # Raw USB node for libftdi/openFPGALoader (JTAG on FT2232 interface A).
    SUBSYSTEM=="usb", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0660", GROUP="plugdev", TAG+="uaccess"
    # The ttyUSB nodes the same device spawns (interface B is the UART).
    SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="0660", GROUP="dialout", TAG+="uaccess"
  '';

  # openFPGALoader is also exposed from the rtl-fun flake (nix run .#fpga-detect);
  # having it system-wide makes ad-hoc probing possible outside the repo.
  environment.systemPackages = [
    pkgs.openfpgaloader
  ];
}
