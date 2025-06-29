# Systemd Slices Configuration for L2 WiFi Access Point
# Defines hierarchical slice structure with CPU affinity and resource limits

{ config, lib, pkgs, ... }:

let
  # Network core assignments (cache-aware, paired SMT siblings)
  networkCores = "0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19";  # Dedicated network processing cores
  userlandCores = "8,20,9,21,10,22,11,23"; # Remaining cores for userland

in {
  # Systemd slices for better resource organization
  systemd.slices = {
    # Network processing slice - Critical network services (paired SMT siblings)
    network-processing = {
      description = "Critical network processing (hostapd)";
      sliceConfig = {
        CPUAffinity = networkCores;
        Nice = -10;
        IOSchedulingClass = 1; # Real-time I/O
        IOSchedulingPriority = 4;
        MemoryHigh = "8G";
        MemoryMax = "16G";
      };
    };

    # Network services slice - DHCP, DNS, RA (userland cores)
    network-services = {
      description = "Network services (DHCP, DNS, RA)";
      sliceConfig = {
        CPUAffinity = userlandCores;
        Nice = -5;
        MemoryHigh = "4G";
        MemoryMax = "8G";
      };
    };

    # Use the existing system.slice for userland/system services
    system = {
      description = "System and userland services";
      sliceConfig = {
        CPUAffinity = userlandCores;
        Nice = 0;
        MemoryHigh = "32G";
        MemoryMax = "64G";
      };
    };

    # Per-daemon slices (inherit from main slices)
    kea = {
      description = "KEA DHCP server slice";
      sliceConfig = {
        Slice = "network-services.slice";
      };
    };
    pdns = {
      description = "PowerDNS Recursor slice";
      sliceConfig = {
        Slice = "network-services.slice";
      };
    };
    radvd = {
      description = "radvd IPv6 RA slice";
      sliceConfig = {
        Slice = "network-services.slice";
      };
    };
  };

  # CPU Affinity for Network Services
  systemd.services = {
    # Critical network processing services (network-processing slice)
    hostapd = {
      serviceConfig = {
        Slice = "network-processing.slice";
        Nice = -10;
        IOSchedulingClass = 1; # Real-time I/O
        IOSchedulingPriority = 4;
        LimitNOFILE = 65536;
        Restart = "always";
        RestartSec = "5s";
      };
    };

    # Network services (network-services slice, via per-daemon slices)
    kea-dhcp4-server = {
      serviceConfig = {
        Slice = "kea.slice";
        Nice = -5;
        LimitNOFILE = 65536;
        Restart = "always";
        RestartSec = "10s";
      };
    };
    pdns-recursor = {
      serviceConfig = {
        Slice = "pdns.slice";
        Nice = -5;
        LimitNOFILE = 65536;
        Restart = "always";
        RestartSec = "10s";
      };
    };
    radvd = {
      serviceConfig = {
        Slice = "radvd.slice";
        Nice = -5;
        Restart = "always";
        RestartSec = "10s";
      };
    };

    # Monitoring and userland services (system.slice)
    network-monitoring = {
      serviceConfig = {
        Slice = "system.slice";
        Nice = 0;
      };
    };
    performance-test = {
      serviceConfig = {
        Slice = "system.slice";
        Nice = 0;
      };
    };
    realtime-monitoring = {
      serviceConfig = {
        Slice = "system.slice";
        Nice = 0;
      };
    };

    # IRQ affinity service (system.slice - runs early)
    irq-affinity = {
      serviceConfig = {
        Slice = "system.slice";
        Nice = -10;
      };
    };
    # CPU performance service (system.slice - runs early)
    cpu-performance = {
      serviceConfig = {
        Slice = "system.slice";
        Nice = -10;
      };
    };
  };
}

# end

# [das@l2:~/nixos/desktop/l2]$ systemctl list-units --type=slice
#   UNIT                         LOAD   ACTIVE SUB    DESCRIPTION
#   -.slice                      loaded active active Root Slice
#   system-getty.slice           loaded active active Slice /system/getty
#   system-modprobe.slice        loaded active active Slice /system/modprobe
#   system-systemd\x2dfsck.slice loaded active active Slice /system/systemd-fsck
#   system.slice                 loaded active active System Slice
#   user-1000.slice              loaded active active Slice /user/1000
#   user.slice                   loaded active active User and Session Slice

# Legend: LOAD   → Reflects whether the unit definition was properly loaded.
#         ACTIVE → The high-level unit activation state, i.e. generalization of SUB.
#         SUB    → The low-level unit activation state, values depend on unit type.

# 7 loaded units listed. Pass --all to see loaded but inactive units, too.
# To show all installed unit files use 'systemctl list-unit-files'.

# [das@l2:~/nixos/desktop/l2]$