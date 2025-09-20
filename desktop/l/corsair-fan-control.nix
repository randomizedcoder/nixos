#
# Corsair Commander Fan Control Service
#
# This service sets the fan speed for Corsair Commander controlled fans at boot time.
# Uses liquidctl to control the fan speed.
#

# sudo liquidctl status --match corsair

{ config, lib, pkgs, ... }:

let
  # Configuration - modify these values for your setup
  fanNumber = "fan1";      # Change this to control different fans (fan1, fan2, fan3, etc.)
  fanSpeed = 80;           # Change this to desired fan speed (0-100)

  # Script to set fan speed using liquidctl
  corsairFanControlScript = pkgs.writeShellScript "corsair-fan-control" ''
    #!/bin/sh
    set -eu

    FAN_NUMBER="${fanNumber}"
    FAN_SPEED="${toString fanSpeed}"

    echo "Setting Corsair Commander ${fanNumber} speed to ${toString fanSpeed}%"

    # Set the fan speed using the full path to liquidctl
    if ${pkgs.liquidctl}/bin/liquidctl --match corsair set "$FAN_NUMBER" speed "$FAN_SPEED"; then
      echo "Fan speed set successfully to ${toString fanSpeed}%"
      exit 0
    else
      echo "Failed to set fan speed"
      exit 1
    fi
  '';

in {

  systemd.services.corsair-fan-control = {
    description = "Set Corsair Commander fan speed at boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" "udev.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${corsairFanControlScript}";
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
      # Run as root since liquidctl needs elevated privileges
      User = "root";
      Group = "root";
    };
  };

  # Optional: Add a manual service for runtime fan control
  systemd.user.services.corsair-fan-control-manual = {
    description = "Manual Corsair fan control (user service)";
    wantedBy = [ "default.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${corsairFanControlScript}";
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
      # Note: This will need sudo privileges to work
    };
  };

}
