#
# qotom/nfb/serial-tty.nix
#
# Serial console configuration for /dev/ttyS0
# Enables login via serial interface

# https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/ttys/getty.nix
# https://github.com/NixOS/nixpkgs/issues/84105

{ config, lib, pkgs, ... }:

{
  # Enable serial console on ttyS0
  boot.kernelParams = [
    "console=ttyS0,115200"
  ];

  # Disable the upstream getty module's automatic configuration for serial-getty@
  # This prevents conflicts with our custom configuration
  systemd.services."serial-getty@" = {
    enable = false;
  };

  # Configure our own serial-getty@ttyS0 service
  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    wantedBy = [ "getty.target" ];
    after = [ "systemd-user-sessions.service" ];
    wants = [ "systemd-user-sessions.service" ];
    serviceConfig = {
      Type = "idle";
      Restart = "always";
      Environment = "TERM=vt220";
      ExecStart = "${pkgs.util-linux}/bin/agetty --login-program ${pkgs.shadow}/bin/login --noclear --keep-baud ttyS0 115200,57600,38400,9600 vt220";
      UtmpIdentifier = "ttyS0";
      StandardInput = "tty";
      StandardOutput = "tty";
      TTYPath = "/dev/ttyS0";
      TTYReset = "yes";
      TTYVHangup = "yes";
      IgnoreSIGPIPE = "no";
      SendSIGHUP = "yes";
    };
  };

  # Enable early console output during boot
  #boot.consoleLogLevel = 7;  # Show all kernel messages
  boot.initrd.verbose = true;  # Show initrd messages
}
