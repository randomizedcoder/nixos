#
# GPU Fan Control Service
#
# This service sets the fan speed for AMD GPUs at boot time.
# Configure the GPU bus address and desired fan speed below.
#

# [nix-shell:~/nixos/desktop/l]$ rocm-smi


# =========================================== ROCm System Management Interface ===========================================
# ===================================================== Concise Info =====================================================
# Device  Node  IDs              Temp    Power     Partitions          SCLK    MCLK    Fan     Perf  PwrCap  VRAM%  GPU%
#               (DID,     GUID)  (Edge)  (Socket)  (Mem, Compute, ID)
# ========================================================================================================================
# 0       2     0x66a1,   33678  35.0°C  19.0W     N/A, N/A, 0         938Mhz  350Mhz  100.0%  auto  225.0W  0%     0%
# 1       1     0x7312,   11012  45.0°C  33.0W     N/A, N/A, 0         800Mhz  900Mhz  49.41%  auto  140.0W  22%    2%
# ========================================================================================================================
# ================================================= End of ROCm SMI Log ==================================================

{ config, lib, pkgs, ... }:

let
  # Configuration - modify these values for your setup
  gpuBus = "0000:63:00.0";  # Change this to your GPU's bus address

  #[nix-shell:~]$ lspci | grep -i radeon
  #44:00.0 Display controller: Advanced Micro Devices, Inc. [AMD/ATI] Vega 20 [Radeon Pro VII/Radeon Instinct MI50 32GB]
  #63:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 [Radeon Pro W5700]

  fanSpeedPercent = 40;      # Change this to desired fan speed (0-100)

  # Calculate the actual PWM value based on percentage
  fanSpeedPWM = builtins.toString (fanSpeedPercent * 255 / 100);

  # Script to set fan speed
  fanControlScript = pkgs.writeShellScript "gpu-fan-control" ''
    #!/bin/sh
    set -eu

    BUS="${gpuBus}"
    FAN_SPEED="${fanSpeedPWM}"

    echo "Setting GPU fan speed to ${toString fanSpeedPercent}% (PWM: $FAN_SPEED) for bus $BUS"

    # Find the GPU device and set fan speed
    for dev in /sys/class/drm/card*/device; do
      if grep -q "PCI_SLOT_NAME=$BUS" "$dev/uevent" 2>/dev/null; then
        echo "Found GPU device at $dev"

        # Find the hwmon directory
        for hwmon in "$dev"/hwmon/hwmon*; do
          if [ -d "$hwmon" ]; then
            echo "Found hwmon at $hwmon"

            # Check if fan control files exist
            if [ -f "$hwmon/pwm1_enable" ] && [ -f "$hwmon/pwm1" ]; then
              echo "Setting fan control mode to manual"
              echo 1 > "$hwmon/pwm1_enable"

              # Get max PWM value
              max_pwm=$(cat "$hwmon/pwm1_max" 2>/dev/null || echo 255)
              echo "Max PWM: $max_pwm"

              # Calculate actual PWM value based on percentage
              # Note: fanSpeedPercent is interpolated by Nix, so we use toString to convert the integer to string
              actual_pwm=$(( max_pwm * ${toString fanSpeedPercent} / 100 ))
              echo "Setting PWM to $actual_pwm"
              echo "$actual_pwm" > "$hwmon/pwm1"

              echo "Fan speed set successfully"
              exit 0
            else
              echo "Fan control files not found in $hwmon"
            fi
          fi
        done

        echo "No hwmon directory found for device $dev"
        exit 1
      fi
    done

    echo "GPU with bus $BUS not found"
    exit 1
  '';

in {

  systemd.services.gpu-fan-control = {
    description = "Set AMD GPU fan speed at boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" "udev.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${fanControlScript}";
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Optional: Add a manual service for runtime fan control
  systemd.user.services.gpu-fan-control-manual = {
    description = "Manual GPU fan control (user service)";
    wantedBy = [ "default.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${fanControlScript}";
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

}
