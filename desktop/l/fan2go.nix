#
# fan2go.nix
#
# Not controlling the Radeon Pro W5700, because lact is doing this
# The config controls the corsair fan1 based on the temperatur of the Radeon Pro VII/MI50
#
# sudo systemctl status fan2go
# sudo journalctl -u fan2go --follow
# sudo ls /var/lib/fan2go
#
# CLEAN IMPLEMENTATION:
# 1. setPwm: Converts 0-255 PWM to 0-100% for liquidctl
# 2. getPwm: Uses pure bash string manipulation to extract fan speed and convert to PWM (0-255)
# 3. getRpm: Uses pure bash string manipulation to extract RPM value for fan2go monitoring
# 4. No external tools (grep, awk, jq, sed) - pure bash string operations
# 5. Bash variables escaped with \$ to prevent Nix interpolation
# 6. Uses bash parameter expansion: ${var#pattern} and ${var%%pattern}
# 7. No temporary files or delays needed since fan2go is the only liquidctl user
#
# See also: https://github.com/arnarg/config/blob/8de65cf5f1649a4fe6893102120ede4363de9bfa/hosts/terra/fan2go.nix
#
#
# [das@l:~/nixos/desktop/l]$ sudo liquidctl status
# [sudo] password for das:
# Corsair Commander Core XT (broken)
# ├── Fan speed 1    1360  rpm
# ├── Fan speed 2       0  rpm
# ├── Fan speed 3       0  rpm
# ├── Fan speed 4       0  rpm
# ├── Fan speed 5       0  rpm
# └── Fan speed 6       0  rpm
#
{
  lib,
  config,
  pkgs,
  ...
}:
let

  cfg = config.hardware.fan2go;

  # Create the bash scripts for fan control
  setPwmScript = pkgs.writeText "setPwm.bash" ''
    #!${pkgs.bash}/bin/bash
    # Convert fan2go PWM (0-255) to liquidctl percentage (0-100)
    percent=$((%pwm% * 100 / 255))
    ${pkgs.liquidctl}/bin/liquidctl set fan1 speed $percent
  '';

  getPwmScript = pkgs.writeText "getPwm.bash" ''
    #!${pkgs.bash}/bin/bash
    # Get current fan RPM and convert to PWM value
    output=$(${pkgs.liquidctl}/bin/liquidctl status 2>/dev/null)
    if [[ $output =~ Fan\ speed\ 1[^0-9]+([0-9]+) ]]; then
      rpm=${BASH_REMATCH[1]}
      echo $((rpm * 255 / 2000))
    else
      echo 0
    fi
  '';

  getRpmScript = pkgs.writeText "getRpm.bash" ''
    #!${pkgs.bash}/bin/bash
    # Get current fan RPM value
    output=$(${pkgs.liquidctl}/bin/liquidctl status 2>/dev/null)
    if [[ $output =~ Fan\ speed\ 1[^0-9]+([0-9]+) ]]; then
      rpm=${BASH_REMATCH[1]}
      echo $rpm
    else
      echo 0
    fi
  '';

  # Create a shellcheck validation script
  shellcheckScript = pkgs.writeText "check-fan-scripts.sh" ''
    #!${pkgs.bash}/bin/bash
    # Shellcheck validation for fan control scripts
    echo "Running shellcheck on fan control scripts..."

    echo "Checking setPwm script..."
    ${pkgs.shellcheck}/bin/shellcheck ${setPwmScript} || exit 1

    echo "Checking getPwm script..."
    ${pkgs.shellcheck}/bin/shellcheck ${getPwmScript} || exit 1

    echo "Checking getRpm script..."
    ${pkgs.shellcheck}/bin/shellcheck ${getRpmScript} || exit 1

    echo "All scripts passed shellcheck validation!"
  '';

  fan2goConfig = pkgs.writeText "fan2go.yaml" ''
    #
    # fan2go.yaml
    #
    dbPath: ${cfg.dbPath}

    fans:
      # Define the fan to be controlled. This is Fan 1 on the Corsair Commander Core XT.
      - id: corsair_fan1
        # Use liquidctl to set the fan speed.
        # The fan type for external commands is `cmd`.
        # Assumes the Corsair Commander Core XT is the first device liquidctl finds.
        cmd:
          # The `setPwm` command is required. It receives a value from 0-255.
          # We use a shell command to convert the 0-255 PWM value from fan2go
          # into a 0-100 percentage for liquidctl.
          setPwm:
            exec: "${setPwmScript}"
          # The `getPwm` command should return the current PWM value.
          # Since liquidctl doesn't provide PWM directly, we convert from the RPM value.
          getPwm:
            exec: "${getPwmScript}"
          # The `getRpm` command gets the current RPM value from liquidctl.
          # This helps fan2go understand the fan's current state.
          getRpm:
            exec: "${getRpmScript}"
        # Fan speed is a percentage for liquidctl
        min: 10
        max: 100
        ## Ensures the fan never fully stops, maintaining minimum airflow.
        #neverStop: true
        # The curve ID that should be used to determine the speed of this fan.
        curve: gpu_cooling_curve

      # #
      # # Define the fan for the Radeon Pro W5700 (amdgpu-pci-06300).
      # # This GPU has its own controllable fan via hwmon.
      # - id: gpu_w5700_fan
      #   hwmon:
      #     # From `fan2go detect`, this is the platform for the W5700.
      #     platform: amdgpu-pci-06300
      #     # The channel for the fan's RPM sensor.
      #     rpmChannel: 1
      #     # The PWM channel that controls this fan's speed.
      #     pwmChannel: 1
      #   neverStop: true
      #   curve: gpu_w5700_curve

    sensors:
      # Define the temperature sensor to monitor. This is the Radeon Pro VII/MI50.
      # From `fan2go detect`, this is platform `amdgpu-pci-04400`.
      # The sensor type is `hwmon`.
      - id: gpu_mi50_temp
        hwmon:
          platform: amdgpu-pci-04400
          # Use the junction temperature (temp2_input) as it's a good indicator of core heat.
          index: 2

      # #
      # # Define the temperature sensor for the Radeon Pro W5700.
      # - id: gpu_w5700_temp
      #   hwmon:
      #     # From `fan2go detect`, this is the platform for the W5700.
      #     platform: amdgpu-pci-06300
      #     # Use the junction temperature (temp2_input).
      #     index: 2

    curves:
      # Link the GPU temperature to the case fan speed.
      - id: gpu_cooling_curve
        # Use a linear interpolation curve based on the defined points.
        linear:
          # The sensor ID to use as a temperature input for this curve.
          sensor: gpu_mi50_temp
          # Define the temperature-to-fan-speed mapping.
          # Temps are in Celsius, fan speed is in percent.
          points:
            - [40, 20]  # At 40°C, run fan at 20%
            - [50, 40]  # At 50°C, run fan at 40%
            - [60, 60]  # At 60°C, run fan at 60%
            - [70, 80]  # At 70°C, run fan at 80%
            - [80, 100] # At 80°C and above, run fan at 100%

      # #
      # # Define the curve for the Radeon Pro W5700's own fan.
      # - id: gpu_w5700_curve
      #   linear:
      #     # The sensor ID to use as a temperature input for this curve.
      #     sensor: gpu_w5700_temp
      #     # Define the temperature-to-PWM-value mapping.
      #     # Temps are in Celsius, output is a PWM value (0-255).
      #     points:
      #       - [45, 51]   # At 45°C, run fan at ~20% (51/255)
      #       - [55, 102]  # At 55°C, run fan at 40%
      #       - [65, 153]  # At 65°C, run fan at 60%
      #       - [75, 204]  # At 75°C, run fan at 80%
      #       - [85, 255]  # At 85°C and above, run fan at 100%

    statistics:
      enabled: true
      port: 9900
  '';
in
{
  options.hardware.fan2go = with lib; {
    enable = mkEnableOption "fan2go";

    dbPath = mkOption {
      type = types.str;
      default = "/var/lib/fan2go/fan2go.db";
      description = "The path of the database file";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.fan2go = {
      description = "A simple daemon providing dynamic fan speed control based on temperature sensors";
      wantedBy = [ "multi-user.target" ];
      after = [ "lm_sensors.service" ];

      serviceConfig = {
        ExecStartPre = "${shellcheckScript}";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.fan2go}/bin/fan2go"
          "-c"
          "${fan2goConfig}"
          "--no-style"
        ];

        MemoryHigh = "48M";
        MemoryMax = "64M";
        CPUQuota = "50%";
        #RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        #Delegate = false;

        LimitNOFILE = 8192;

      };
    };
  };
}