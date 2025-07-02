# Systemd Slices Configuration for L2 WiFi Access Point
# Defines hierarchical slice structure with resource limits (no CPUAffinity)

{ config, lib, pkgs, ... }:

let
  # Userland core assignments (remaining cores after network IRQ isolation)
  userlandCores = "8,20,9,21,10,22,11,23";

in {
  # Systemd slices for better resource organization
  systemd.slices = {
    # Network services slice - DHCP, DNS, RA, hostapd (userland cores)
    network-services = {
      description = "Network services (DHCP, DNS, RA, hostapd)";
      sliceConfig = {
        MemoryHigh = "4G";
        MemoryMax = "8G";
      };
    };

    # Use the existing system.slice for userland/system services
    system = {
      description = "System and userland services";
      sliceConfig = {
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
    hostapd = {
      description = "hostapd WiFi access point slice";
      sliceConfig = {
        Slice = "network-services.slice";
      };
    };
    crowdsec = {
      description = "CrowdSec threat detection engine slice";
      sliceConfig = {
        Slice = "network-services.slice";
      };
    };
    crowdsec-firewall-bouncer = {
      description = "CrowdSec firewall bouncer slice";
      sliceConfig = {
        Slice = "network-services.slice";
      };
    };
  };

  # CPU Affinity for Network Services
  systemd.services = {
    # Critical network processing services (network-services slice)
    hostapd = {
      serviceConfig = {
        Slice = "hostapd.slice";
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