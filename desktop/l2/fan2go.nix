#
# fan2go.nix (l2)
#
# Controls the Corsair Commander PRO fan based on MI50 GPU temperature
# MI50 + Corsair Commander PRO moved from machine l to l2
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
  # Note: hwmon device numbers can change after kernel updates
  # Check with: ls -la /sys/class/hwmon/ and find the one named "corsaircpro"
  # TODO: Discover after hardware install with:
  #   ls -la /sys/class/hwmon/ | grep corsaircpro
  #   or: cat /sys/class/hwmon/hwmon*/name | grep -n corsaircpro
  # Auto-detect at runtime via discoverCorsairHwmon snippet (embedded in each script)
  # No hardcoded hwmon number needed.
  discoverCorsairHwmon = ''
    CORSAIR_HWMON_PATH=""
    for hwmon in /sys/class/hwmon/hwmon*; do
      if [[ -r "$hwmon/name" ]] && [[ "$(cat "$hwmon/name" 2>/dev/null)" == "corsaircpro" ]]; then
        CORSAIR_HWMON_PATH="$hwmon"
        break
      fi
    done
    if [[ -z "$CORSAIR_HWMON_PATH" ]]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: Corsair Commander PRO hwmon device not found" >&2
      exit 1
    fi
  '';

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
        if (( $(echo "$temp < 30" | bc -l) )); then
          echo "77"  # 30%
        # Above last point: return value of last point
        elif (( $(echo "$temp >= 70" | bc -l) )); then
          echo "255" # 100%
        # Linear interpolation between points
        elif (( $(echo "$temp >= 30 && $temp < 40" | bc -l) )); then
          # Interpolate between 30°C (77) and 40°C (128)
          ratio=$(echo "scale=4; ($temp - 30) / (40 - 30)" | bc -l)
          pwm=$(echo "scale=0; 77 + ($ratio * (128 - 77))" | bc -l)
          echo "$pwm"
        elif (( $(echo "$temp >= 40 && $temp < 50" | bc -l) )); then
          # Interpolate between 40°C (128) and 50°C (179)
          ratio=$(echo "scale=4; ($temp - 40) / (50 - 40)" | bc -l)
          pwm=$(echo "scale=0; 128 + ($ratio * (179 - 128))" | bc -l)
          echo "$pwm"
        elif (( $(echo "$temp >= 50 && $temp < 60" | bc -l) )); then
          # Interpolate between 50°C (179) and 60°C (230)
          ratio=$(echo "scale=4; ($temp - 50) / (60 - 50)" | bc -l)
          pwm=$(echo "scale=0; 179 + ($ratio * (230 - 179))" | bc -l)
          echo "$pwm"
        elif (( $(echo "$temp >= 60 && $temp < 70" | bc -l) )); then
          # Interpolate between 60°C (230) and 70°C (255)
          ratio=$(echo "scale=4; ($temp - 60) / (70 - 60)" | bc -l)
          pwm=$(echo "scale=0; 230 + ($ratio * (255 - 230))" | bc -l)
          echo "$pwm"
        else
          # Fallback (shouldn't reach here)
          echo "77"
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

    ${corsairInitLogger}
    ${discoverCorsairHwmon}
    log_info "Found Corsair Commander PRO at $CORSAIR_HWMON_PATH"

      # Set PWM to a known value (50% = 128)
      log_info "Initializing Corsair Commander PRO with PWM 128 (50%)"
      if echo "128" > "$CORSAIR_HWMON_PATH/pwm1" 2>/dev/null; then
        log_info "Successfully set PWM to 128"
      else
        log_error "Failed to set PWM to 128"
        exit 1
      fi

      # Wait for device to settle
      log_info "Waiting for device to settle..."
      sleep 2

      # Verify the setting took effect
      if [[ -r "$CORSAIR_HWMON_PATH/pwm1" ]]; then
        current_pwm=$(cat "$CORSAIR_HWMON_PATH/pwm1" 2>/dev/null)
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
    ${discoverCorsairHwmon}
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
      if echo "$pwm_value" > "$CORSAIR_HWMON_PATH/pwm1" 2>/dev/null; then
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
    ${discoverCorsairHwmon}
    log_debug "getPwm started."

    # Read current PWM value from pwm1 interface
    if [[ -r "$CORSAIR_HWMON_PATH/pwm1" ]]; then
      pwm_value=$(cat "$CORSAIR_HWMON_PATH/pwm1" 2>/dev/null)
      if [[ -n "$pwm_value" && "$pwm_value" =~ ^[0-9]+$ ]]; then
        log_debug "Current PWM value: $pwm_value"
        echo "$pwm_value"
        exit 0
      else
        log_warning "Invalid PWM value read: $pwm_value"
      fi
    else
      log_warning "Cannot read PWM value from $CORSAIR_HWMON_PATH/pwm1"
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
    ${discoverCorsairHwmon}
    log_debug "getRpm started."

    # Read current RPM value from sysfs
    if [[ -r "$CORSAIR_HWMON_PATH/fan1_input" ]]; then
      rpm_value=$(cat "$CORSAIR_HWMON_PATH/fan1_input" 2>/dev/null)
      if [[ -n "$rpm_value" && "$rpm_value" =~ ^[0-9]+$ ]]; then
        log_debug "Current RPM value: $rpm_value"
        echo "$rpm_value"
        exit 0
      else
        log_warning "Invalid RPM value read: $rpm_value"
      fi
    else
      log_warning "Cannot read RPM value from $CORSAIR_HWMON_PATH/fan1_input"
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
        # Ensures the fan never fully stops - critical since MI50 has no built-in fan
        neverStop: true
        # The curve ID that should be used to determine the speed of this fan.
        curve: gpu_cooling_curve

      # Radeon Pro W5700 fan (amdgpu-pci-04400, PCI 44:00.0)
      # Adjacent to the MI50, so this fan also helps cool the MI50.
      # Uses native amdgpu hwmon PWM interface.
      - id: gpu_w5700_fan
        hwmon:
          platform: amdgpu-pci-04400
          rpmChannel: 1
          pwmChannel: 1
        neverStop: true
        curve: gpu_w5700_combined_curve

    sensors:
      # MI50 GPU memory temperature (temp3_input = mem, the hottest sensor)
      # PCI slot 63:00.0 -> platform amdgpu-pci-06300
      - id: gpu_mi50_temp
        hwmon:
          platform: amdgpu-pci-06300
          index: 3

      # W5700 GPU memory temperature (temp3_input = mem)
      # PCI slot 44:00.0 -> platform amdgpu-pci-04400
      - id: gpu_w5700_temp
        hwmon:
          platform: amdgpu-pci-04400
          index: 3

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
            30: 77   # At 30°C, run fan at ~30% PWM (77/255) - always some airflow
            40: 128  # At 40°C, run fan at ~50% PWM (128/255)
            50: 179  # At 50°C, run fan at ~70% PWM (179/255)
            60: 230  # At 60°C, run fan at ~90% PWM (230/255)
            70: 255  # At 70°C and above, run fan at 100% PWM (255/255)

      # W5700's own temperature curve
      - id: gpu_w5700_own_curve
        linear:
          sensor: gpu_w5700_temp
          steps:
            35: 51   # At 35°C, run fan at ~20% PWM
            45: 102  # At 45°C, run fan at ~40% PWM
            55: 153  # At 55°C, run fan at ~60% PWM
            65: 204  # At 65°C, run fan at ~80% PWM
            75: 255  # At 75°C and above, run fan at 100% PWM

      # MI50 neighbor curve - W5700 fan should also ramp up when MI50 is hot
      # (cards are adjacent, W5700 fan provides supplemental MI50 cooling)
      - id: gpu_mi50_neighbor_curve
        linear:
          sensor: gpu_mi50_temp
          steps:
            40: 51   # At MI50 40°C, W5700 fan at ~20%
            50: 128  # At MI50 50°C, W5700 fan at ~50%
            60: 179  # At MI50 60°C, W5700 fan at ~70%
            70: 255  # At MI50 70°C, W5700 fan at 100%

      # Combined curve: take the maximum of W5700's own needs and MI50 neighbor needs
      - id: gpu_w5700_combined_curve
        function:
          type: maximum
          curves:
            - gpu_w5700_own_curve
            - gpu_mi50_neighbor_curve

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
          "GOMAXPROCS=4"
          "GOMEMLIMIT=45MiB"
          "DEBUG_LEVEL=${toString debugLevel}"
        ];
        MemoryHigh = "48M";
        MemoryMax = "64M";
        CPUQuota = "50%";
        #RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        #Delegate = false;

        LimitNOFILE = 128;
        #LimitNOFILE = 8192;

        # Create and manage the state directory
        StateDirectory = "fan2go";

        # Allow access to hwmon devices for fan control
        # The service needs to read/write to /sys/class/hwmon/hwmon5/pwm1
        # Note: sysfs requires special handling - we need full access to /sys
        PrivateDevices = false;
        ProtectKernelTunables = false;
        # Don't restrict /sys - we need full read/write access for hwmon control
        # ReadWritePaths with /sys/class/hwmon should work, but we may need the parent /sys too
        ReadWritePaths = [
          "/sys"
        ];

      };
    };
  };
}