The system has x2 GPUs:
- [Radeon Pro W5700] which has temperature sensors and an attached PWM fan.  The pid-fan-controller service is suitable for controlling this fan.
- [Radeon Pro VII/Radeon Instinct MI50 32GB] which has temperature sensors, but NO FAN.  Need to control the Corsair Commander Core Fan 1 to cool down this card.  The challenge is that liquidctl is required to set the fan speed, so pid-fan-controller service won't work.  Going to need to creata a fan2go configuration file for this.

I want to use the NixOS services pid-fan-controller to control the fan for Radeon Pro W5700.

https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/hardware/pid-fan-controller.nix
```
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.pid-fan-controller;
  heatSource = {
    options = {
      name = lib.mkOption {
        type = lib.types.uniq lib.types.nonEmptyStr;
        description = "Name of the heat source.";
      };
      wildcardPath = lib.mkOption {
        type = lib.types.nonEmptyStr;
        description = ''
          Path of the heat source's `hwmon` `temp_input` file.
          This path can contain multiple wildcards, but has to resolve to
          exactly one result.
        '';
      };
      pidParams = {
        setPoint = lib.mkOption {
          type = lib.types.ints.unsigned;
          description = "Set point of the controller in °C.";
        };
        P = lib.mkOption {
          description = "K_p of PID controller.";
          type = lib.types.float;
        };
        I = lib.mkOption {
          description = "K_i of PID controller.";
          type = lib.types.float;
        };
        D = lib.mkOption {
          description = "K_d of PID controller.";
          type = lib.types.float;
        };
      };
    };
  };

  fan = {
    options = {
      wildcardPath = lib.mkOption {
        type = lib.types.str;
        description = ''
          Wildcard path of the `hwmon` `pwm` file.
          If the fans are not to be found in `/sys/class/hwmon/hwmon*` the corresponding
          kernel module (like `nct6775`) needs to be added to `boot.kernelModules`.
          See the [`hwmon` Documentation](https://www.kernel.org/doc/html/latest/hwmon/index.html).
        '';
      };
      minPwm = lib.mkOption {
        default = 0;
        type = lib.types.ints.u8;
        description = "Minimum PWM value.";
      };
      maxPwm = lib.mkOption {
        default = 255;
        type = lib.types.ints.u8;
        description = "Maximum PWM value.";
      };
      cutoff = lib.mkOption {
        default = false;
        type = lib.types.bool;
        description = "Whether to stop the fan when `minPwm` is reached.";
      };
      heatPressureSrcs = lib.mkOption {
        type = lib.types.nonEmptyListOf lib.types.str;
        description = "Heat pressure sources affected by the fan.";
      };
    };
  };
in
{
  options.services.pid-fan-controller = {
    enable = lib.mkEnableOption "the PID fan controller, which controls the configured fans by running a closed-loop PID control loop";
    package = lib.mkPackageOption pkgs "pid-fan-controller" { };
    settings = {
      interval = lib.mkOption {
        default = 500;
        type = lib.types.int;
        description = "Interval between controller cycles in milliseconds.";
      };
      heatSources = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule heatSource);
        description = "List of heat sources to be monitored.";
        example = ''
          [
            {
              name = "cpu";
              wildcardPath = "/sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon*/temp1_input";
              pidParams = {
                setPoint = 60;
                P = -5.0e-3;
                I = -2.0e-3;
                D = -6.0e-3;
              };
            }
          ];
        '';
      };
      fans = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule fan);
        description = "List of fans to be controlled.";
        example = ''
          [
            {
              wildcardPath = "/sys/devices/platform/nct6775.2592/hwmon/hwmon*/pwm1";
              minPwm = 60;
              maxPwm = 255;
              heatPressureSrcs = [
                "cpu"
                "gpu"
              ];
            }
          ];
        '';
      };
    };
  };
  config = lib.mkIf cfg.enable {
    #map camel cased attrs into snake case for config
    environment.etc."pid-fan-settings.json".text = builtins.toJSON {
      interval = cfg.settings.interval;
      heat_srcs = map (heatSrc: {
        name = heatSrc.name;
        wildcard_path = heatSrc.wildcardPath;
        PID_params = {
          set_point = heatSrc.pidParams.setPoint;
          P = heatSrc.pidParams.P;
          I = heatSrc.pidParams.I;
          D = heatSrc.pidParams.D;
        };
      }) cfg.settings.heatSources;
      fans = map (fan: {
        wildcard_path = fan.wildcardPath;
        min_pwm = fan.minPwm;
        max_pwm = fan.maxPwm;
        cutoff = fan.cutoff;
        heat_pressure_srcs = fan.heatPressureSrcs;
      }) cfg.settings.fans;
    };

    systemd.services.pid-fan-controller = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = [ (lib.getExe cfg.package) ];
        ExecStopPost = [ "${lib.getExe cfg.package} disable" ];
        Restart = "always";
        #This service needs to run as root to write to /sys.
        #therefore it should operate with the least amount of privileges needed
        ProtectHome = "yes";
        #strict is not possible as it needs /sys
        ProtectSystem = "full";
        ProtectProc = "invisible";
        PrivateNetwork = "yes";
        NoNewPrivileges = "yes";
        MemoryDenyWriteExecute = "yes";
        RestrictNamespaces = "~user pid net uts mnt";
        ProtectKernelModules = "yes";
        RestrictRealtime = "yes";
        SystemCallFilter = "@system-service";
        CapabilityBoundingSet = "~CAP_KILL CAP_WAKE_ALARM CAP_IPC_LOC CAP_BPF CAP_LINUX_IMMUTABLE CAP_BLOCK_SUSPEND CAP_MKNOD";
      };
      # restart unit if config changed
      restartTriggers = [ config.environment.etc."pid-fan-settings.json".source ];
    };
    #sleep hook to restart the service as it breaks otherwise
    systemd.services.pid-fan-controller-sleep = {
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      unitConfig = {
        StopWhenUnneeded = "yes";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = [ "systemctl stop pid-fan-controller.service" ];
        ExecStop = [ "systemctl restart pid-fan-controller.service" ];
      };
    };
  };
  meta.maintainers = with lib.maintainers; [ zimward ];
}
```


```
[das@l:~/nixos]$ lspci | grep -i radeon
44:00.0 Display controller: Advanced Micro Devices, Inc. [AMD/ATI] Vega 20 [Radeon Pro VII/Radeon Instinct MI50 32GB]
63:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 10 [Radeon Pro W5700]

[das@l:~/nixos]$
```

```
[das@l:~/nixos]$ rocm-smi


=========================================== ROCm System Management Interface ===========================================
===================================================== Concise Info =====================================================
Device  Node  IDs              Temp    Power     Partitions          SCLK    MCLK    Fan     Perf  PwrCap  VRAM%  GPU%
              (DID,     GUID)  (Edge)  (Socket)  (Mem, Compute, ID)
========================================================================================================================
0       2     0x66a1,   33678  39.0°C  19.0W     N/A, N/A, 0         938Mhz  350Mhz  14.51%  auto  225.0W  0%     0%
1       1     0x7312,   11012  48.0°C  36.0W     N/A, N/A, 0         800Mhz  900Mhz  40.0%   auto  140.0W  36%    4%
========================================================================================================================
================================================= End of ROCm SMI Log ==================================================

[das@l:~/nixos]$
```

rocm-smi --alldevices --showallinfo


```
[das@l:~/nixos]$ rocm-smi --alldevices --showallinfo 2>&1 | grep -E '(Device|ID)'
=========================================== ID ===========================================
GPU[0]          : Device Name:          TBD VEGA20 CARD
GPU[0]          : Device ID:            0x66a1
GPU[0]          : Device Rev:           0x00
GPU[0]          : Subsystem ID:         0x1002
GPU[0]          : GUID:                 33678
GPU[1]          : Device Name:          0x1002
GPU[1]          : Device ID:            0x7312
GPU[1]          : Device Rev:           0x00
GPU[1]          : Subsystem ID:         0x1002
GPU[1]          : GUID:                 11012
======================================= Unique ID ========================================
GPU[0]          : Unique ID: 0xe54792172da5eeb
GPU[1]          : Unique ID: N/A
GPU[0]          : 2. Available power profile (#2 of 7): VIDEO
GPU[1]          : 2. Available power profile (#2 of 7): VIDEO
PID     PROCESS NAME    GPU(s)  VRAM USED       SDMA USED       CU OCCUPANCY
================================== GPUs Indexed by PID ===================================
PID 2210 is using 0 DRM device(s)
======================================= PCI Bus ID =======================================
GPU[0]          : Subsystem ID:         0x1002
GPU[0]          : Device Rev:           0x00
GPU[0]          : Node ID:              2
GPU[0]          : GUID:                 33678
GPU[1]          : Subsystem ID:         0x1002
GPU[1]          : Device Rev:           0x00
GPU[1]          : Node ID:              1
GPU[1]          : GUID:                 11012

[das@l:~/nixos]$
```

```
[das@l:~/nixos]$ rocm-smi --showtemp --showfan


============================ ROCm System Management Interface ============================
====================================== Temperature =======================================
GPU[0]          : Temperature (Sensor edge) (C): 39.0
GPU[0]          : Temperature (Sensor junction) (C): 40.0
GPU[0]          : Temperature (Sensor memory) (C): 38.0
GPU[1]          : Temperature (Sensor edge) (C): 47.0
GPU[1]          : Temperature (Sensor junction) (C): 50.0
GPU[1]          : Temperature (Sensor memory) (C): 62.0
==========================================================================================
=================================== Current Fan Metric ===================================
GPU[0]          : Fan Level: 37 (15%)
GPU[0]          : Fan RPM: 0
GPU[1]          : Fan Level: 102 (40%)
GPU[1]          : Fan RPM: 2380
==========================================================================================
================================== End of ROCm SMI Log ===================================

[das@l:~/nixos]$
```

```
[das@l:~/nixos]$ for x in /sys/class/hwmon/hwmon*; do
  echo "$x: $(cat $x/name 2>/dev/null)"
done
/sys/class/hwmon/hwmon0: amdgpu
/sys/class/hwmon/hwmon1: amdgpu
/sys/class/hwmon/hwmon10: hidpp_battery_3
/sys/class/hwmon/hwmon2: nvme
/sys/class/hwmon/hwmon3: nvme
/sys/class/hwmon/hwmon4: bnxt_en
/sys/class/hwmon/hwmon5: bnxt_en
/sys/class/hwmon/hwmon6: k10temp
/sys/class/hwmon/hwmon7: ucsi_source_psy_18_00081
/sys/class/hwmon/hwmon8: ucsi_source_psy_18_00082
/sys/class/hwmon/hwmon9: enp1s0

[das@l:~/nixos]$
```


MI50 card
```
[das@l:~/nixos]$ cat /sys/class/hwmon/hwmon1/device/device
0x66a1
```


```
[das@l:~/nixos]$ cat /sys/class/hwmon/hwmon0/device/device
0x7312

[das@l:~/nixos]$
```

```
[das@l:~/nixos]$ sudo liquidctl status
[sudo] password for das:
Corsair Commander Core XT (broken)
├── Fan speed 1    4427  rpm
├── Fan speed 2       0  rpm
├── Fan speed 3       0  rpm
├── Fan speed 4       0  rpm
├── Fan speed 5       0  rpm
└── Fan speed 6       0  rpm


[das@l:~/nixos]$
```

Fan2go can be used to read the temperature from the MI50 card, and then use liquidctl to set the fan1 speed based on the temperature for the GPU.

```
[das@l:~/nixos]$ sudo liquidctl list
[sudo] password for das:
Device #0: Corsair Commander Core XT (broken)
```

```
[das@l:~/nixos]$ lsusb | grep -i corsair
Bus 007 Device 004: ID 1b1c:0c2a Corsair CORSAIR iCUE COMMANDER CORE XT

[das@l:~/nixos]$
```

```
[das@l:~/nixos]$ sudo liquidctl status | grep "Fan speed 1"
sudo liquidctl set fan1 speed 30
├── Fan speed 1    4314  rpm

[das@l:~/nixos]$ sudo liquidctl set fan1 speed 30

[das@l:~/nixos]$ sudo liquidctl status | grep "Fan speed 1"
├── Fan speed 1    3938  rpm

[das@l:~/nixos]$ sudo liquidctl set fan1 speed 10

[das@l:~/nixos]$
```


```
[nix-shell:~/nixos]$ fan2go detect
=========== hwmon: ============

> Platform: k10temp-pci-00c3
  Sensors  Index  Label                Value
           1      Tctl (temp1_input)   82000
           2      Tccd3 (temp5_input)  70000
           3      Tccd5 (temp7_input)  80500

> Platform: bnxt_en-pci-04100
  Sensors  Index  Label                       Value
           1      hwmon4/temp1 (temp1_input)  85000

> Platform: nvme-pci-02100
  Sensors  Index  Label                    Value
           1      Composite (temp1_input)  32850
           2      Sensor 1 (temp2_input)   35850
           3      Sensor 2 (temp3_input)   32850

> Platform: amdgpu-pci-06300
  Fans     Index  PWM Channel  RPM Channel  Label        RPM   PWM  Mode
           1      1            1            hwmon0/fan1  2376  102  Manual
           2      1            N/A          hwmon0/pwm1  N/A   102  Manual
  Sensors  Index  Label                   Value
           1      edge (temp1_input)      48000
           2      junction (temp2_input)  50000
           3      mem (temp3_input)       62000

> Platform: enp1s0-pci-0100
  Sensors  Index  Label                          Value
           1      PHY Temperature (temp1_input)  69285
           2      MAC Temperature (temp2_input)  70995

> Platform: bnxt_en-pci-04101
  Sensors  Index  Label                       Value
           1      hwmon5/temp1 (temp1_input)  85000

> Platform: nvme-pci-02200
  Sensors  Index  Label                    Value
           1      Composite (temp1_input)  33850
           2      Sensor 1 (temp2_input)   34850
           3      Sensor 2 (temp3_input)   33850

> Platform: amdgpu-pci-04400
  Fans     Index  PWM Channel  RPM Channel  Label        RPM  PWM  Mode
           1      1            1            hwmon1/fan1  0    37   Manual
           2      1            N/A          hwmon1/pwm1  N/A  37   Manual
  Sensors  Index  Label                   Value
           1      edge (temp1_input)      45000
           2      junction (temp2_input)  46000
           3      mem (temp3_input)       44000


[nix-shell:~/nixos]$
```

Summary

```
Radeon Instinct MI50 32GB
PCIe = 44:00.0
DID = 0x66a1
GUID = 33678
GPU = 0
hwmon device = /sys/class/hwmon/hwmon1
fan2go detect
> Platform: amdgpu-pci-04400
  Fans     Index  PWM Channel  RPM Channel  Label        RPM  PWM  Mode
           1      1            1            hwmon1/fan1  0    37   Manual
           2      1            N/A          hwmon1/pwm1  N/A  37   Manual
  Sensors  Index  Label                   Value
           1      edge (temp1_input)      45000
           2      junction (temp2_input)  46000
           3      mem (temp3_input)       44000

Radeon Pro W5700
PCIe = 63:00.0
DID = 0x7312
GUID = 11012
GPU = 1
hwmon device = /sys/class/hwmon/hwmon0
fan2go detect
> Platform: amdgpu-pci-06300
  Fans     Index  PWM Channel  RPM Channel  Label        RPM   PWM  Mode
           1      1            1            hwmon0/fan1  2376  102  Manual
           2      1            N/A          hwmon0/pwm1  N/A   102  Manual
  Sensors  Index  Label                   Value
           1      edge (temp1_input)      48000
           2      junction (temp2_input)  50000
           3      mem (temp3_input)       62000
```