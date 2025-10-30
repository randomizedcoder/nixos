#
# fan2go.nix
#
# Not controlling the Radeon Pro W5700, because lact is doing this
# The config controls the corsair fan1 based on the temperature of the Radeon Pro VII/MI50
#
# sudo systemctl status fan2go
# sudo journalctl -u fan2go --follow
# sudo ls /var/lib/fan2go
#
# NATIVE KERNEL DRIVER IMPLEMENTATION:
# 1. setPwm: Directly writes PWM value (0-255) to /sys/class/hwmon/hwmon7/pwm1
# 2. getPwm: Reads current PWM value from /sys/class/hwmon/hwmon7/pwm1
# 3. getRpm: Reads current RPM from /sys/class/hwmon/hwmon7/fan1_input
# 4. Uses native corsair-cpro kernel driver (no liquidctl needed)
# 5. Direct sysfs interface - no external tools required
# 6. More reliable and faster than liquidctl
#
# Nix string literals:
# https://nix.dev/manual/nix/2.28/language/string-literals.html#string-literals
# https://nix.dev/manual/nix/2.28/language/string-interpolation.html
# https://github.com/NixOS/nix/blob/master/doc/manual/source/language/string-interpolation.md
#
# See also: https://github.com/arnarg/config/blob/8de65cf5f1649a4fe6893102120ede4363de9bfa/hosts/terra/fan2go.nix
#
# https://www.kernel.org/doc/html/latest/hwmon/corsair-cpro.html
#
# [  133.368198] corsair-cpro 0003:1B1C:0C10.0006: hidraw5: USB HID v1.11 Device [Corsair Commander PRO] on usb-0000:04:00.3-4/input0
#
# Native kernel driver detected at: /sys/class/hwmon/hwmon7/
# - fan1_input: Current RPM reading
# - pwm1: PWM control (0-255)
# - fan1_label: "fan1 4pin"
#
{
  lib,
  config,
  pkgs,
  ...
}:
let

  cfg = config.hardware.fan2go;

  # Path to the Corsair Commander PRO hwmon device
  corsairHwmonPath = "/sys/class/hwmon/hwmon7";

  # Debug level for the scripts (0=off, 7=max debug).
  debugLevel = 7;

  # fan2go monitoring script using Prometheus metrics
  fan2goMonitorScript = pkgs.writeShellApplication {
    name = "fan2go-monitor.bash";
    runtimeInputs = [ pkgs.curl pkgs.gawk pkgs.coreutils ];
    text = ''
      #!/bin/bash
      # fan2go monitoring script using Prometheus metrics
      # Provides real-time status of fan control system

      METRICS_URL="http://localhost:9900/metrics"

      # Colors for output
      RED='\033[0;31m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      BLUE='\033[0;34m'
      NC='\033[0m' # No Color

      # Function to get metric value
      get_metric() {
        local metric_name="$1"
        curl -s "$METRICS_URL" | grep "^$metric_name" | awk '{print $2}'
      }

      # Function to convert millidegrees to Celsius
      millidegrees_to_celsius() {
        echo "scale=1; $1 / 1000" | bc -l
      }

      # Function to calculate expected PWM for temperature using linear interpolation
      # This matches fan2go's interpolation logic
      expected_pwm() {
        local temp=$1

        # Curve points (temperature -> PWM)
        # Below first point: return value of first point
        if (( $(echo "$temp < 40" | bc -l) )); then
          echo "51"  # 20%
        # Above last point: return value of last point
        elif (( $(echo "$temp >= 80" | bc -l) )); then
          echo "255" # 100%
        # Linear interpolation between points
        elif (( $(echo "$temp >= 40 && $temp < 50" | bc -l) )); then
          # Interpolate between 40°C (51) and 50°C (102)
          ratio=$(echo "scale=4; ($temp - 40) / (50 - 40)" | bc -l)
          pwm=$(echo "scale=0; 51 + ($ratio * (102 - 51))" | bc -l)
          echo "$pwm"
        elif (( $(echo "$temp >= 50 && $temp < 60" | bc -l) )); then
          # Interpolate between 50°C (102) and 60°C (153)
          ratio=$(echo "scale=4; ($temp - 50) / (60 - 50)" | bc -l)
          pwm=$(echo "scale=0; 102 + ($ratio * (153 - 102))" | bc -l)
          echo "$pwm"
        elif (( $(echo "$temp >= 60 && $temp < 70" | bc -l) )); then
          # Interpolate between 60°C (153) and 70°C (204)
          ratio=$(echo "scale=4; ($temp - 60) / (70 - 60)" | bc -l)
          pwm=$(echo "scale=0; 153 + ($ratio * (204 - 153))" | bc -l)
          echo "$pwm"
        elif (( $(echo "$temp >= 70 && $temp < 80" | bc -l) )); then
          # Interpolate between 70°C (204) and 80°C (255)
          ratio=$(echo "scale=4; ($temp - 70) / (80 - 70)" | bc -l)
          pwm=$(echo "scale=0; 204 + ($ratio * (255 - 204))" | bc -l)
          echo "$pwm"
        else
          # Fallback (shouldn't reach here)
          echo "51"
        fi
      }

      echo -e "''${BLUE}=== fan2go Monitoring Dashboard ===''${NC}"
      echo "Timestamp: $(date)"
      echo

      # Get metrics
      temp_millidegrees=$(get_metric "fan2go_sensor_value{id=\"gpu_mi50_temp\"}")
      fan_pwm=$(get_metric "fan2go_fan_pwm{id=\"corsair_fan1\"}")
      fan_rpm=$(get_metric "fan2go_fan_rpm{id=\"corsair_fan1\"}")
      curve_pwm=$(get_metric "fan2go_curve_value{id=\"gpu_cooling_curve\"}")
      unexpected_count=$(get_metric "fan2go_controller_unexpected_pwm_value_count{id=\"corsair_fan1\"}")
      minpwm_offset=$(get_metric "fan2go_controller_minPwm_offset{id=\"corsair_fan1\"}")

      # Convert temperature
      if [[ -n "$temp_millidegrees" && "$temp_millidegrees" != "" ]]; then
        temp_celsius=$(millidegrees_to_celsius "$temp_millidegrees")
        expected_pwm=$(expected_pwm "$temp_celsius")
      else
        temp_celsius="N/A"
        expected_pwm="N/A"
      fi

      # Display temperature
      echo -e "''${BLUE}🌡️  Temperature:''${NC}"
      if [[ "$temp_celsius" != "N/A" ]]; then
        if (( $(echo "$temp_celsius > 70" | bc -l) )); then
          echo -e "   GPU Temperature: ''${RED}''${temp_celsius}°C''${NC} (HOT!)"
        elif (( $(echo "$temp_celsius > 60" | bc -l) )); then
          echo -e "   GPU Temperature: ''${YELLOW}''${temp_celsius}°C''${NC} (Warm)"
        else
          echo -e "   GPU Temperature: ''${GREEN}''${temp_celsius}°C''${NC} (Normal)"
        fi
        expected_pwm_percent=$(echo "scale=1; $expected_pwm * 100 / 255" | bc -l)
        echo -e "   Expected PWM at this temp: ''${expected_pwm} (''${expected_pwm_percent}%)"
      else
        echo -e "   GPU Temperature: ''${RED}N/A''${NC}"
      fi
      echo

      # Display fan status
      echo -e "''${BLUE}🌀 Fan Status:''${NC}"
      if [[ -n "$fan_pwm" && "$fan_pwm" != "" ]]; then
        pwm_percent=$(echo "scale=1; $fan_pwm * 100 / 255" | bc -l)
        echo -e "   Current PWM: ''${fan_pwm} (''${pwm_percent}%)"
        echo -e "   Current RPM: ''${fan_rpm}"

        # Check if PWM matches expected
        if [[ "$expected_pwm" != "N/A" ]]; then
          pwm_diff=$(echo "$fan_pwm - $expected_pwm" | bc -l)
          # Convert to absolute value
          if (( $(echo "$pwm_diff < 0" | bc -l) )); then
            pwm_diff=$(echo "0 - $pwm_diff" | bc -l)
          fi
          if (( $(echo "$pwm_diff < 5" | bc -l) )); then
            echo -e "   Status: ''${GREEN}✓ Normal''${NC}"
          else
            echo -e "   Status: ''${YELLOW}⚠ PWM mismatch (expected ~''${expected_pwm})''${NC}"
          fi
        fi
      else
        echo -e "   Fan Status: ''${RED}N/A''${NC}"
      fi
      echo

      # Display curve status
      echo -e "''${BLUE}📈 Curve Status:''${NC}"
      if [[ -n "$curve_pwm" && "$curve_pwm" != "" ]]; then
        curve_percent=$(echo "scale=1; $curve_pwm * 100 / 255" | bc -l)
        echo -e "   Curve Target: ''${curve_pwm} (''${curve_percent}%)"

        # Check if curve makes sense
        if [[ "$expected_pwm" != "N/A" ]]; then
          curve_diff=$(echo "$curve_pwm - $expected_pwm" | bc -l)
          # Convert to absolute value
          if (( $(echo "$curve_diff < 0" | bc -l) )); then
            curve_diff=$(echo "0 - $curve_diff" | bc -l)
          fi
          if (( $(echo "$curve_diff < 5" | bc -l) )); then
            echo -e "   Status: ''${GREEN}✓ Curve correct''${NC}"
          else
            echo -e "   Status: ''${RED}✗ Curve incorrect (expected ~''${expected_pwm})''${NC}"
          fi
        fi
      else
        echo -e "   Curve Status: ''${RED}N/A''${NC}"
      fi
      echo

      # Display errors
      echo -e "''${BLUE}⚠️  Error Status:''${NC}"
      if [[ -n "$unexpected_count" && "$unexpected_count" != "0" ]]; then
        echo -e "   PWM Mismatches: ''${RED}''${unexpected_count}''${NC}"
      else
        echo -e "   PWM Mismatches: ''${GREEN}0''${NC}"
      fi

      if [[ -n "$minpwm_offset" && "$minpwm_offset" != "0" ]]; then
        echo -e "   MinPWM Offset: ''${YELLOW}''${minpwm_offset}''${NC} (fan stalling detected)"
      else
        echo -e "   MinPWM Offset: ''${GREEN}0''${NC}"
      fi
      echo

      # Summary
      echo -e "''${BLUE}📊 Summary:''${NC}"
      if [[ "$temp_celsius" != "N/A" && "$expected_pwm" != "N/A" && -n "$fan_pwm" && -n "$curve_pwm" ]]; then
        # Check: 1) Curve is correct, 2) Fan follows curve, 3) No errors
        curve_ok=false
        fan_ok=false
        errors_ok=false

        # Check if curve matches expected (within 5 PWM tolerance)
        if [[ "$expected_pwm" != "N/A" && -n "$curve_pwm" ]]; then
          curve_diff=$(echo "$curve_pwm - $expected_pwm" | bc -l)
          if (( $(echo "$curve_diff < 0" | bc -l) )); then
            curve_diff=$(echo "0 - $curve_diff" | bc -l)
          fi
          if (( $(echo "$curve_diff < 5" | bc -l) )); then
            curve_ok=true
          fi
        fi

        # Check if fan matches curve (within 5 PWM tolerance)
        if [[ -n "$fan_pwm" && -n "$curve_pwm" ]]; then
          fan_curve_diff=$(echo "$fan_pwm - $curve_pwm" | bc -l)
          if (( $(echo "$fan_curve_diff < 0" | bc -l) )); then
            fan_curve_diff=$(echo "0 - $fan_curve_diff" | bc -l)
          fi
          if (( $(echo "$fan_curve_diff < 5" | bc -l) )); then
            fan_ok=true
          fi
        fi

        # Check for errors
        if [[ -z "$unexpected_count" || "$unexpected_count" == "0" ]]; then
          if [[ -z "$minpwm_offset" || "$minpwm_offset" == "0" ]]; then
            errors_ok=true
          fi
        fi

        # Determine overall status
        if [[ "$curve_ok" == "true" && "$fan_ok" == "true" && "$errors_ok" == "true" ]]; then
          echo -e "   ''${GREEN}✓ System working correctly''${NC}"
        else
          echo -e "   ''${YELLOW}⚠ System needs attention''${NC}"
          if [[ "$curve_ok" != "true" ]]; then
            echo -e "      - Curve calculation issue"
          fi
          if [[ "$fan_ok" != "true" ]]; then
            echo -e "      - Fan not following curve (may be adjusting)"
          fi
          if [[ "$errors_ok" != "true" ]]; then
            echo -e "      - Errors detected"
          fi
        fi
      else
        echo -e "   ''${RED}✗ Unable to determine system status''${NC}"
      fi
    '';
  };

  # Corsair Commander PRO initialization script
  # This ensures the device is in a known state before fan2go starts
  corsairInitScript = pkgs.writeShellApplication {
    name = "corsair-init.bash";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      #!/bin/bash
      # Initialize Corsair Commander PRO before fan2go starts
      # This ensures the device is in a known state for PWM mapping

    CORSIR_HWMON_PATH="${corsairHwmonPath}"
    ${corsairInitLogger}

      # Check if hwmon device exists
      if [[ ! -d "$CORSIR_HWMON_PATH" ]]; then
        log_error "Corsair hwmon device not found at $CORSIR_HWMON_PATH"
        exit 1
      fi

      # Set PWM to a known value (50% = 128)
      log_info "Initializing Corsair Commander PRO with PWM 128 (50%)"
      if echo "128" > "$CORSIR_HWMON_PATH/pwm1" 2>/dev/null; then
        log_info "Successfully set PWM to 128"
      else
        log_error "Failed to set PWM to 128"
        exit 1
      fi

      # Wait for device to settle
      log_info "Waiting for device to settle..."
      sleep 2

      # Verify the setting took effect
      if [[ -r "$CORSIR_HWMON_PATH/pwm1" ]]; then
        current_pwm=$(cat "$CORSIR_HWMON_PATH/pwm1" 2>/dev/null)
        log_info "Current PWM value: $current_pwm"

        if [[ "$current_pwm" == "128" ]]; then
          log_info "Corsair Commander PRO initialized successfully"
          exit 0
        else
          log_error "PWM verification failed: expected 128, got $current_pwm"
          exit 1
        fi
      else
        log_error "Cannot read PWM value for verification"
        exit 1
      fi
    '';
  };

  # Script-specific loggers to avoid shellcheck unused function warnings

  # Logger for setPwm script (uses debug, warning, and error)
  setPwmLogger = ''
    # Set default debug level if not provided
    DEBUG_LEVEL=''${DEBUG_LEVEL:-${toString debugLevel}}

    log_debug() {
      if [[ $DEBUG_LEVEL -ge 7 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1" >&2
      fi
    }

    log_warning() {
      if [[ $DEBUG_LEVEL -ge 3 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >&2
      fi
    }

    log_error() {
      if [[ $DEBUG_LEVEL -ge 1 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
      fi
    }
  '';

  # Logger for getPwm script (uses debug, warning, and info)
  getPwmLogger = ''
    # Set default debug level if not provided
    DEBUG_LEVEL=''${DEBUG_LEVEL:-${toString debugLevel}}

    log_debug() {
      if [[ $DEBUG_LEVEL -ge 7 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1" >&2
      fi
    }

    log_warning() {
      if [[ $DEBUG_LEVEL -ge 3 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >&2
      fi
    }

    log_info() {
      if [[ $DEBUG_LEVEL -ge 5 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >&2
      fi
    }
  '';

  # Logger for getRpm script (uses debug, warning, and info)
  getRpmLogger = ''
    # Set default debug level if not provided
    DEBUG_LEVEL=''${DEBUG_LEVEL:-${toString debugLevel}}

    log_debug() {
      if [[ $DEBUG_LEVEL -ge 7 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1" >&2
      fi
    }

    log_warning() {
      if [[ $DEBUG_LEVEL -ge 3 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >&2
      fi
    }

    log_info() {
      if [[ $DEBUG_LEVEL -ge 5 ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >&2
      fi
    }
  '';

  # Logger for corsair init script (uses info and error)
  corsairInitLogger = ''
    log_info() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1" >&2
    }

    log_error() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
    }
  '';

  # Create the bash scripts for fan control
  setPwmScript = pkgs.writeShellApplication {
    name = "setPwm.bash";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
    # Set PWM value directly via pwm1 interface
    # PWM value is passed as the first argument (0-255)
    ${setPwmLogger}
    log_debug "setPwm started with argument: $1"

    # Check if the pwm_value argument was provided.
    : "''${1:?PWM value not provided as an argument}"
    pwm_value=$1
    log_debug "Setting PWM to: $pwm_value"

    # Validate PWM range (0-255)
    if [[ $pwm_value -lt 0 || $pwm_value -gt 255 ]]; then
      log_error "PWM value $pwm_value is out of range (0-255)"
      exit 1
    fi

    # Write PWM value directly to pwm1 interface with retry logic
    for i in {1..3}; do
      if echo "$pwm_value" > ${corsairHwmonPath}/pwm1 2>/dev/null; then
        log_debug "Successfully set PWM to $pwm_value (attempt $i)"
        exit 0
      else
        log_warning "Failed to set PWM to $pwm_value (attempt $i)"
        if [[ $i -lt 3 ]]; then
          sleep 0.1
        fi
      fi
    done
    log_error "Failed to set PWM after 3 attempts"
    exit 1
    '';
  };

  getPwmScript = pkgs.writeShellApplication {
    name = "getPwm.bash";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
    # Get current PWM value from pwm1 interface
    # The driver can read PWM values if the fan is in PWM control mode
    ${getPwmLogger}
    log_debug "getPwm started."

    # Read current PWM value from pwm1 interface
    if [[ -r ${corsairHwmonPath}/pwm1 ]]; then
      pwm_value=$(cat ${corsairHwmonPath}/pwm1 2>/dev/null)
      if [[ -n "$pwm_value" && "$pwm_value" =~ ^[0-9]+$ ]]; then
        log_debug "Current PWM value: $pwm_value"
        echo "$pwm_value"
        exit 0
      else
        log_warning "Invalid PWM value read: $pwm_value"
      fi
    else
      log_warning "Cannot read PWM value from ${corsairHwmonPath}/pwm1"
    fi

    # Fallback to a reasonable PWM value if unable to read
    # Use a moderate fan speed (around 50% PWM) as fallback
    log_info "Falling back to PWM value 128 (50%)"
    echo 128
    '';
  };

  getRpmScript = pkgs.writeShellApplication {
    name = "getRpm.bash";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
    # Get current fan RPM value from sysfs interface
    ${getRpmLogger}
    log_debug "getRpm started."

    # Read current RPM value from sysfs
    if [[ -r ${corsairHwmonPath}/fan1_input ]]; then
      rpm_value=$(cat ${corsairHwmonPath}/fan1_input 2>/dev/null)
      if [[ -n "$rpm_value" && "$rpm_value" =~ ^[0-9]+$ ]]; then
        log_debug "Current RPM value: $rpm_value"
        echo "$rpm_value"
        exit 0
      else
        log_warning "Invalid RPM value read: $rpm_value"
      fi
    else
      log_warning "Cannot read RPM value from ${corsairHwmonPath}/fan1_input"
    fi

    # Fallback to 0 if unable to read
    log_info "Falling back to RPM value 0"
    echo 0
    '';
  };

  # Create a shellcheck validation script
  shellcheckScript = pkgs.writeShellApplication {
    name = "check-fan-scripts.sh";
    runtimeInputs = [ pkgs.shellcheck ];
    text = ''
    # Shellcheck validation for fan control scripts
    echo "Running shellcheck on fan control scripts..."

    echo "Checking setPwm script..."
    shellcheck ${setPwmScript}/bin/setPwm.bash || exit 1

    echo "Checking getPwm script..."
    shellcheck ${getPwmScript}/bin/getPwm.bash || exit 1

    echo "Checking getRpm script..."
    shellcheck ${getRpmScript}/bin/getRpm.bash || exit 1

    echo "All scripts passed shellcheck validation!"
    '';
  };

  fan2goConfig = pkgs.writeText "fan2go.yaml" ''
    #
    # fan2go.yaml
    #
    dbPath: ${cfg.dbPath}

    fans:
      # Define the fan to be controlled. This is Fan 1 on the Corsair Commander PRO.
      - id: corsair_fan1
        # Use native corsair-cpro kernel driver via sysfs interface.
        # The fan type for external commands is `cmd`.
        # Direct sysfs access to /sys/class/hwmon/hwmon7/
        # Uses pwm1 interface for direct PWM control
        cmd:
          # The `setPwm` command is required. It receives a value from 0-255.
          # Writes PWM value directly to pwm1 interface.
          setPwm:
            exec: "${setPwmScript}/bin/setPwm.bash"
            args: ["%pwm%"]
          # The `getPwm` command returns the current PWM value from pwm1 interface
          # The driver can read PWM values if the fan is in PWM control mode
          getPwm:
            exec: "${getPwmScript}/bin/getPwm.bash"
          # The `getRpm` command gets the current RPM value from sysfs.
          # This helps fan2go understand the fan's current state.
          getRpm:
            exec: "${getRpmScript}/bin/getRpm.bash"
        # Fan speed is PWM value (0-255) for native driver
        min: 0
        max: 255
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
      # Define the temperature sensor to monitor. This is the MI50 GPU (GPU0 in btop).
      # From `fan2go detect`, this is platform `amdgpu-pci-04400`.
      # The sensor type is `hwmon`.
      - id: gpu_mi50_temp
        hwmon:
          platform: amdgpu-pci-04400
          # Use the memory temperature (temp3_input) as it's the hottest part at 62°C
          index: 3

      # #
      # # Define the temperature sensor for the other GPU (not concerned about this one).
      # - id: gpu_other_temp
      #   hwmon:
      #     # From `fan2go detect`, this is platform `amdgpu-pci-06300`.
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
          # Define the temperature-to-fan-speed mapping using steps format.
          # Temps are in Celsius, fan speed is PWM value (0-255).
          # Format: temperature -> PWM value (YAML map format).
          steps:
            40: 51   # At 40°C, run fan at ~20% PWM (51/255)
            50: 102  # At 50°C, run fan at ~40% PWM (102/255)
            60: 153  # At 60°C, run fan at ~60% PWM (153/255)
            70: 204  # At 70°C, run fan at ~80% PWM (204/255)
            80: 255  # At 80°C and above, run fan at 100% PWM (255/255)

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
      description = "A simple daemon providing dynamic fan speed control based on temperature sensors. Monitor with: ${fan2goMonitorScript}/bin/fan2go-monitor.bash";
      wantedBy = [ "multi-user.target" ];
      after = [ "lm_sensors.service" ];

      serviceConfig = {
        ExecStartPre = [
          "${shellcheckScript}/bin/check-fan-scripts.sh"
          "${corsairInitScript}/bin/corsair-init.bash"
        ];
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.fan2go}/bin/fan2go"
          "-c"
          "${fan2goConfig}"
          "--no-style"
        ];

        Environment = [
          "GOMEMLIMIT=45MiB"
          "DEBUG_LEVEL=${toString debugLevel}"
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