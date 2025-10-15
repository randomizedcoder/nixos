The system has x2 GPUs:
- [Radeon Pro W5700] which has temperature sensors and an attached PWM fan.  The fan2go can control this.  This config should be pretty simple, becasue fan2go can read the temperature and RPM all from the same card.
- [Radeon Pro VII/Radeon Instinct MI50 32GB] which has temperature sensors, but NO FAN.  Need to control the Corsair Commander Core Fan 1 to cool down this card.  The challenge is that liquidctl is required to set the fan speed, so pid-fan-controller service won't work.  Going to need to creata a fan2go configuration file for this.


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