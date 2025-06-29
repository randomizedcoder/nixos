# L2 WiFi Access Point Configuration

This directory contains the NixOS configuration for a high-performance WiFi access point with 4x WiFi NICs, designed to handle multiple concurrent clients with optimized network performance.

## Overview

The L2 system is configured as a dedicated WiFi access point with:
- **4x WiFi NICs** for high-capacity wireless networking
- **Custom hostapd 2.10** with LAR (License Assisted Radar) patch
- **Advanced network services** (DHCP, DNS, IPv6 RA)
- **nftables firewall** with connection tracking and NAT
- **Network interface optimizations** for maximum performance
- **CPU and IRQ optimizations** for dedicated network processing

## WiFi Configuration

### Hostapd 2.10 with LAR Patch

The system uses a custom hostapd 2.10 build with the LAR (License Assisted Radar) patch applied. This is configured in `flake.nix`:

```nix
overlays = {
  default = final: prev: {
    hostapd = prev.hostapd.overrideDerivation (old: {
      version = "2.10";
      src = final.fetchurl {
        url = "https://w1.fi/releases/hostapd-2.10.tar.gz";
        sha256 = "0pcik0a6yin9nib02frjhaglmg44hwik086iwg1751b7kdwpqvi0";
      };
      # Replace all patches with just the LAR patch
      patches = [
        (final.fetchpatch {
          url = "https://tildearrow.org/storage/hostapd-2.10-lar.patch";
          sha256 = "USiHBZH5QcUJfZSxGoFwUefq3ARc4S/KliwUm8SqvoI=";
        })
      ];
    });
  };
};
```

**Why hostapd 2.10?**
- Better support for modern WiFi features
- Improved performance and stability
- LAR patch enables License Assisted Radar functionality
- **Note**: Default nixpkgs hostapd version is 2.11, but the LAR patch can only be applied to 2.10

**LAR Patch Benefits:**
- Enables radar detection and avoidance
- Required for certain regulatory domains
- Improves coexistence with radar systems
- **Reference**: [Making hostapd LAR-friendly on Intel 5GHz wireless cards](https://tildearrow.org/?p=post&month=7&year=2022&item=lar)

The LAR patch addresses issues with Intel wireless cards that use Location-Aware Regulatory (LAR) to automatically detect the country/regulatory domain. The patch modifies hostapd to scan for nearby networks before setting up the access point, which helps the card properly detect the regulatory domain and enable 5GHz channels.

### WiFi Interface Configuration

The system manages 4 WiFi interfaces:
- `wlp35s0` - Channel 36 (non-DFS)
- `wlp65s0` - Channel 40 (non-DFS)
- `wlp66s0` - Channel 44 (non-DFS)
- `wlp97s0` - Channel 48 (non-DFS)

All interfaces operate in 5GHz band with WPA3-SAE authentication.

### WiFi WMM (QoS) Configuration

This system uses specific WMM (Wi-Fi Multimedia) settings for the best effort (AC_BE) access category, as suggested by Nokia WiFi engineer Koen De Schepper, to optimize WiFi performance for normal-priority traffic:

```
# Normal priority / AC_BE = best effort
wmm_ac_be_aifs=1
wmm_ac_be_cwmin=4
wmm_ac_be_cwmax=4
wmm_ac_be_txop_limit=32
wmm_ac_be_acm=0
```

These values are set in the `hostapd-multi.nix` configuration and ensure that best effort traffic is handled with optimal latency and fairness, as recommended by industry experts.

## CPU and IRQ Optimization

### System Architecture

The L2 system features an **AMD Ryzen Threadripper PRO 3945WX** with:
- **12 physical cores** (24 logical threads with SMT)
- **4 NUMA nodes** with **64 MiB L3 cache**
- **6 MiB L2 cache** (12 instances)
- **384 KiB L1 cache** per core

### Core Dedication Strategy

#### Network Processing Cores (0-7)
- **Dedicated cores** for network interrupts and processing
- **Isolated from scheduler** (`isolcpus=0-7`)
- **No tick processing** (`nohz_full=0-7`)
- **Disabled RCU callbacks** (`rcu_nocbs=0-7`)
- **Performance governor** with maximum frequency
- **Benefits**:
  - Dedicated L1/L2 cache for network processing
  - No competition with userland workloads
  - Better cache locality for network data structures
  - Reduced interrupt latency

#### Userland Processing Cores (8-23)
- **Remaining cores** for system services and userland
- **Normal scheduling** and power management
- **Benefits**:
  - Isolated from network interrupt processing
  - Dedicated resources for DHCP, DNS, firewall processing
  - Better performance for non-network workloads

### IRQ Affinity Configuration

#### Ethernet Interface (enp1s0)
- **8 MSI-X vectors** distributed across cores 0-7
- **Atlantic driver** with optimized interrupt handling

#### WiFi Interfaces
- **wlp35s0**: 16 MSI-X vectors → cores 0-3
- **wlp65s0**: 16 MSI-X vectors → cores 4-7
- **wlp66s0**: 16 MSI-X vectors → cores 0-3 (alternating)
- **wlp97s0**: 16 MSI-X vectors → cores 4-7 (alternating)

### Service CPU Affinity

#### Network Processing Services (Cores 0-7)
- **hostapd**: High priority (-10), real-time I/O, network-processing slice
- **nftables**: High priority (-5), network-processing slice
- **network-optimization**: High priority (-5), network-processing slice

#### Network Services (Cores 8-15)
- **kea-dhcp4-server**: High priority (-5), network-services slice
- **pdns-recursor**: High priority (-5), network-services slice
- **radvd**: High priority (-5), network-services slice

#### Userland Services (Cores 16-23)
- **Monitoring services**: Normal priority, userland-processing slice
- **System services**: Normal priority, userland-processing slice
- **User processes**: Normal priority, userland-processing slice

## Network Services (`hostapd-multi.nix`)

### DHCP Server (Kea)
- **Purpose**: Provides IPv4 addresses to WiFi clients
- **Subnet**: 192.168.1.0/24
- **Range**: 192.168.1.100 - 192.168.1.200
- **Gateway**: 192.168.1.1
- **DNS**: 192.168.1.1

### DNS Resolver (PowerDNS Recursor)
- **Purpose**: Local DNS resolution for WiFi clients
- **Listen addresses**: 127.0.0.1, ::1, 192.168.1.1, fd00::1
- **Features**: RFC1918 support, recursive resolution
- **Fallback**: Cloudflare DNS (1.1.1.1, 2606:4700:4700::1111)

### IPv6 Router Advertisement (radvd)
- **Purpose**: IPv6 SLAAC for WiFi clients
- **Prefix**: fd00::/64
- **Features**: Autonomous address configuration
- **DNS**: fd00::1

### Network Bridge (br0)
- **Purpose**: Bridges all WiFi interfaces
- **IPv4**: 192.168.1.1/24
- **IPv6**: fd00::1/64
- **QoS**: CAKE (Common Applications Kept Enhanced) for traffic shaping

## Firewall and NAT (`firewall.nix`)

### nftables Configuration
The system uses nftables with connection tracking for maximum security and performance:

#### Filter Table (inet)
- **Input Chain**: Handles incoming traffic to the router
  - SSH (port 22)
  - DNS (port 53)
  - DHCP (ports 67 for DHCPv4, 547 for DHCPv6)
  - ICMP (ping)
  - IPv6 RA
- **Forward Chain**: Handles traffic between networks
  - Allow internal to external (br0 → enp1s0)
  - Allow return traffic for established connections
- **Output Chain**: Allow all outgoing traffic

#### NAT Tables
- **IPv4 NAT**: Masquerades traffic from br0 to enp1s0
- **IPv6 NAT**: Masquerades IPv6 traffic from br0 to enp1s0

### Connection Tracking
- **Purpose**: Stateful packet filtering
- **Benefits**:
  - Only legitimate return traffic is allowed
  - Better security than stateless filtering
  - Improved performance for established connections

## Network Optimizations (`network-optimization.nix`)

### Hardware Optimizations
Applied via ethtool during boot:

#### Ring Buffers
- **RX/TX**: Increased to maximum (8184)
- **Benefit**: Higher throughput, better burst handling

#### Feature Enables
- **LRO (Large Receive Offload)**: Combines packets for CPU efficiency
- **IPv4 Checksum Offload**: Hardware handles checksum calculation
- **TCP ECN Segmentation**: Better ECN packet handling
- **GRO List**: Generic Receive Offload with list support

#### Interrupt Coalescing
- **RX**: 512μs, 32 frames (was 256μs, 0 frames)
- **TX**: 1024μs, 32 frames (was 1022μs, 0 frames)
- **Benefits**: Fewer interrupts, better batch processing

### Kernel Optimizations (`sysctl.nix`)
- **TCP buffers**: Optimized for high throughput
- **Connection tracking**: 262K entries for multiple clients
- **Network backlog**: Increased for burst traffic handling
- **Congestion control**: BBR for better performance

### Verification
Network optimization results are logged to `/tmp/network-optimization.log` and include:
- Ring buffer settings
- Feature status
- Interrupt coalescing configuration
- Driver information

## Performance Monitoring (`monitoring.nix`)

### Automated Monitoring
- **IRQ distribution**: Tracks interrupt distribution across cores
- **CPU utilization**: Monitors per-core usage patterns
- **Network statistics**: Tracks interface performance
- **Cache performance**: Monitors cache misses for network processes
- **System load**: Tracks overall system performance

### Performance Testing
- **Throughput testing**: Automated iperf3 testing
- **Latency testing**: Ping latency measurements
- **IRQ distribution testing**: Validates interrupt affinity
- **CPU utilization testing**: Monitors during network activity

### Logging and Analysis
- **Log directory**: `/var/log/network-performance/`
- **Real-time monitoring**: Continuous performance tracking
- **Historical data**: sysstat integration for trend analysis
- **Log rotation**: Automated log management

## System Architecture

```
Internet (enp1s0)
    ↓
[NAT/Firewall] ← nftables with connection tracking (cores 0-7, network-processing slice)
    ↓
[Bridge (br0)] ← 192.168.1.1/24, fd00::1/64
    ↓
[WiFi Clients] ← 4x WiFi interfaces with hostapd 2.10 (cores 0-7, network-processing slice)
    ↓
[Network Services] ← DHCP, DNS, RA (cores 8-15, network-services slice)
    ↓
[Userland Services] ← Monitoring, system services (cores 16-23, userland-processing slice)
```

## Services Overview

| Service | Purpose | CPU Cores | Priority | Slice |
|---------|---------|-----------|----------|-------|
| hostapd | WiFi access point | 0-7 | -10 (RT) | network-processing |
| nftables | Firewall/NAT | 0-7 | -5 | network-processing |
| Kea | DHCP server | 8-15 | -5 | network-services |
| PowerDNS | DNS resolver | 8-15 | -5 | network-services |
| radvd | IPv6 RA | 8-15 | -5 | network-services |
| CAKE | QoS | 0-7 | -5 | network-processing |
| Monitoring | Performance tracking | 16-23 | 0 | userland-processing |

## Performance Features

- **Multi-interface WiFi**: 4x concurrent access points
- **Hardware offloading**: Checksums, segmentation, GRO
- **Connection tracking**: Stateful firewall with 262K entries
- **Optimized buffers**: Maximum ring buffers and TCP windows
- **Interrupt coalescing**: Reduced CPU overhead
- **BBR congestion control**: Better throughput and latency
- **CPU isolation**: Dedicated network processing cores
- **IRQ affinity**: Optimized interrupt distribution
- **Cache optimization**: Dedicated L1/L2 cache for network processing

## Expected Performance Improvements

### 1. **Reduced Interrupt Latency**
- Dedicated cores eliminate competition for CPU resources
- Better cache locality reduces memory access latency
- SMT isolation prevents cache pollution

### 2. **Improved Throughput**
- Parallel processing across 8 dedicated network cores
- Better interrupt distribution reduces bottlenecks
- Optimized cache utilization for network data structures

### 3. **Lower CPU Overhead**
- Reduced context switching on network cores
- Better interrupt coalescing effectiveness
- Optimized memory allocation patterns

### 4. **Enhanced Scalability**
- Better support for multiple concurrent WiFi clients
- Improved handling of burst traffic
- More predictable performance under load

## Monitoring

- **Network optimization log**: `/tmp/network-optimization.log`
- **Performance monitoring**: `/var/log/network-performance/`
- **nftables rules**: `sudo nft list ruleset`
- **Service status**: `systemctl status hostapd kea-dhcp4-server pdns-recursor radvd nftables`
- **IRQ distribution**: `cat /proc/interrupts | grep -E "(enp1s0|iwlwifi)"`
- **CPU utilization**: `mpstat -P ALL 1`

## Files Overview

- `flake.nix` - Hostapd 2.10 overlay and flake configuration
- `hostapd-multi.nix` - WiFi, DHCP, DNS, and IPv6 services
- `firewall.nix` - nftables firewall and NAT configuration
- `network-optimization.nix` - Hardware and kernel optimizations
- `irq-affinity.nix` - IRQ affinity and CPU dedication configuration
- `kernel-params.nix` - Kernel boot parameters and runtime optimizations
- `monitoring.nix` - Performance monitoring and testing services
- `sysctl.nix` - Kernel network parameters
- `configuration.nix` - Main system configuration
- `CPU_and_IRQ_optimization.md` - Detailed optimization documentation