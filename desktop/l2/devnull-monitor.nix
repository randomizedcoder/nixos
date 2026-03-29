# devnull-monitor.nix
#
# Monitors /dev/null for permission changes or other modifications.
# Logs events to journald for debugging the mysterious /dev/null permission issue.
#
# View logs: journalctl -u devnull-monitor -f
# Check current state: ls -la /dev/null

{ config, pkgs, ... }:

{
  systemd.services.devnull-monitor = {
    description = "Monitor /dev/null for permission changes";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
      ExecStart = pkgs.writeShellScript "devnull-monitor" ''
        #!/bin/bash
        set -euo pipefail

        echo "Starting /dev/null monitor"
        echo "Initial state: $(ls -la /dev/null)"

        # Monitor /dev/null for any attribute changes, modifications, deletions
        ${pkgs.inotify-tools}/bin/inotifywait -m -e attrib,modify,delete,delete_self,move_self,create /dev/null 2>&1 | while read -r line; do
          TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
          echo "[$TIMESTAMP] EVENT: $line"
          echo "[$TIMESTAMP] Current state: $(ls -la /dev/null 2>&1 || echo 'MISSING')"

          # Log what processes have /dev/null open
          echo "[$TIMESTAMP] Processes with /dev/null open:"
          ${pkgs.lsof}/bin/lsof /dev/null 2>/dev/null | head -20 || echo "  (none or lsof failed)"

          # Check if permissions are wrong
          PERMS=$(stat -c '%a' /dev/null 2>/dev/null || echo "000")
          if [ "$PERMS" != "666" ]; then
            echo "[$TIMESTAMP] WARNING: /dev/null permissions are $PERMS (should be 666)"
          fi
        done
      '';
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
}
