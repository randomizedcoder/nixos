# IRQ Affinity Configuration for L2 WiFi Access Point
# Optimizes interrupt distribution across dedicated network cores

{ config, lib, pkgs, ... }:

let
  # Network core assignments
  networkCores = "0-7";  # Dedicated network processing cores
  userlandCores = "8-23"; # Remaining cores for userland

  # IRQ affinity script
  irqAffinityScript = pkgs.writeShellScript "irq-affinity" ''
    #!/bin/bash
    set -euo pipefail

    echo "Setting IRQ affinity for network optimization..."

    # Function to set IRQ affinity
    set_irq_affinity() {
      local irq=$1
      local cpu=$2
      if [[ -e "/proc/irq/$irq/smp_affinity_list" ]]; then
        echo "$cpu" > "/proc/irq/$irq/smp_affinity_list"
        echo "IRQ $irq -> CPU $cpu"
      else
        echo "Warning: IRQ $irq not found"
      fi
    }

    # Ethernet interface (enp1s0) - Atlantic driver
    # Distribute across cores 0-7
    set_irq_affinity 168 0  # Core 0
    set_irq_affinity 169 1  # Core 1
    set_irq_affinity 170 2  # Core 2
    set_irq_affinity 171 3  # Core 3
    set_irq_affinity 172 4  # Core 4
    set_irq_affinity 173 5  # Core 5
    set_irq_affinity 174 6  # Core 6
    set_irq_affinity 175 7  # Core 7

    # WiFi interface wlp35s0 (IRQ 179-194)
    # Distribute across cores 0-3
    for irq in {179..194}; do
      cpu=$((irq - 179))
      set_irq_affinity $irq $cpu
    done

    # WiFi interface wlp65s0 (IRQ 198-213)
    # Distribute across cores 4-7
    for irq in {198..213}; do
      cpu=$((irq - 198 + 4))
      set_irq_affinity $irq $cpu
    done

    # WiFi interface wlp66s0 (IRQ 214-229)
    # Distribute across cores 0-3 (alternating pattern)
    for irq in {214..229}; do
      cpu=$(((irq - 214) % 4))
      set_irq_affinity $irq $cpu
    done

    # WiFi interface wlp97s0 (IRQ 231-246)
    # Distribute across cores 4-7 (alternating pattern)
    for irq in {231..246}; do
      cpu=$(((irq - 231) % 4 + 4))
      set_irq_affinity $irq $cpu
    done

    echo "IRQ affinity configuration complete"

    # Verify configuration
    echo "Current IRQ distribution:"
    cat /proc/interrupts | grep -E "(enp1s0|iwlwifi)" | head -20
  '';

in {
  # IRQ Affinity Service
  systemd.services.irq-affinity = {
    description = "Set IRQ affinity for network optimization";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "systemd-udev-settle.service" ];
    before = [ "hostapd.service" "kea-dhcp4-server.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${irqAffinityScript}";
      RemainAfterExit = true;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Systemd slices for better resource organization
  systemd.slices = {
    # Network processing slice - Critical network services (cores 0-7)
    network-processing = {
      description = "Critical network processing (hostapd, nftables)";
      sliceConfig = {
        CPUAffinity = networkCores;
        Nice = -10;
        IOSchedulingClass = 1; # Real-time I/O
        IOSchedulingPriority = 4;
        MemoryHigh = "2G";      # Limit memory usage
        MemoryMax = "4G";       # Hard memory limit
      };
    };

    # Network services slice - DHCP, DNS, RA (cores 8-15)
    network-services = {
      description = "Network services (DHCP, DNS, RA)";
      sliceConfig = {
        CPUAffinity = "8-15";   # Dedicated subset of userland cores
        Nice = -5;
        MemoryHigh = "1G";      # Limit memory usage
        MemoryMax = "2G";       # Hard memory limit
      };
    };

    # Userland processing slice - Everything else (cores 16-23)
    userland-processing = {
      description = "Userland processing (monitoring, system services)";
      sliceConfig = {
        CPUAffinity = "16-23";  # Remaining cores
        Nice = 0;
        MemoryHigh = "4G";      # Limit memory usage
        MemoryMax = "8G";       # Hard memory limit
      };
    };
  };

  # CPU Affinity for Network Services
  systemd.services = {
    # Critical network processing services (network-processing slice)
    hostapd = {
      serviceConfig = {
        Slice = "network-processing";
        CPUAffinity = networkCores;
        Nice = -10;
        IOSchedulingClass = 1; # Real-time I/O
        IOSchedulingPriority = 4;
        LimitNOFILE = 65536;
        Restart = "always";
        RestartSec = "5s";
      };
    };

    nftables = {
      serviceConfig = {
        Slice = "network-processing";
        CPUAffinity = networkCores;
        Nice = -5;
        LimitNOFILE = 65536;
        Restart = "always";
        RestartSec = "5s";
      };
    };

    # Network services (network-services slice)
    kea-dhcp4-server = {
      serviceConfig = {
        Slice = "network-services";
        CPUAffinity = "8-15";
        Nice = -5;
        LimitNOFILE = 65536;
        Restart = "always";
        RestartSec = "10s";
      };
    };

    pdns-recursor = {
      serviceConfig = {
        Slice = "network-services";
        CPUAffinity = "8-15";
        Nice = -5;
        LimitNOFILE = 65536;
        Restart = "always";
        RestartSec = "10s";
      };
    };

    radvd = {
      serviceConfig = {
        Slice = "network-services";
        CPUAffinity = "8-15";
        Nice = -5;
        Restart = "always";
        RestartSec = "10s";
      };
    };

    # Network optimization service (network-processing slice)
    network-optimization = {
      serviceConfig = {
        Slice = "network-processing";
        CPUAffinity = networkCores;
        Nice = -5;
      };
    };

    # IRQ affinity service (system slice - runs early)
    irq-affinity = {
      serviceConfig = {
        Slice = "system.slice"; # Keep in system slice for early execution
        CPUAffinity = networkCores;
        Nice = -10;
      };
    };

    # Monitoring services (userland-processing slice)
    network-monitoring = {
      serviceConfig = {
        Slice = "userland-processing";
        CPUAffinity = "16-23";
        Nice = 0;
      };
    };

    performance-test = {
      serviceConfig = {
        Slice = "userland-processing";
        CPUAffinity = "16-23";
        Nice = 0;
      };
    };

    realtime-monitoring = {
      serviceConfig = {
        Slice = "userland-processing";
        CPUAffinity = "16-23";
        Nice = 0;
      };
    };

    # CPU performance service (system slice - runs early)
    cpu-performance = {
      serviceConfig = {
        Slice = "system.slice"; # Keep in system slice for early execution
        CPUAffinity = networkCores;
        Nice = -10;
      };
    };
  };
}