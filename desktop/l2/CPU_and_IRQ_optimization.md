# CPU and IRQ Optimization for L2 WiFi Access Point

## System Overview

The L2 system is equipped with an **AMD Ryzen Threadripper PRO 3945WX** featuring:
- **12 physical cores** with **24 logical threads** (SMT enabled)
- **4 NUMA nodes** with **64 MiB L3 cache** total
- **6 MiB L2 cache** (12 instances)
- **384 KiB L1 cache** per core (data + instruction)

## Current Interrupt Distribution Analysis

### Network Interface Interrupts

#### Ethernet Interface (enp1s0) - Atlantic Driver
- **IRQ 168-175**: 8 MSI-X vectors distributed across cores 16-23
- **Current distribution**:
  - IRQ 168: CPU 16 (5,051 interrupts)
  - IRQ 169: CPU 17 (706 interrupts)
  - IRQ 170: CPU 18 (4,608 interrupts)
  - IRQ 171: CPU 20 (85 interrupts)
  - IRQ 172: CPU 22 (115 interrupts)
  - IRQ 173: CPU 23 (521 interrupts)
  - IRQ 174: CPU 14 (108 interrupts)
  - IRQ 175: CPU 15 (3,924 interrupts)

#### WiFi Interfaces (4x Intel iwlwifi)
- **wlp35s0** (IRQ 179-194): 16 MSI-X vectors, mostly on CPU 21
- **wlp65s0** (IRQ 198-213): 16 MSI-X vectors, mostly on CPU 23
- **wlp66s0** (IRQ 214-229): 16 MSI-X vectors, mostly on CPU 14
- **wlp97s0** (IRQ 231-246): 16 MSI-X vectors, mostly on CPU 15

### Storage and Other Interrupts
- **NVMe drives**: Heavy interrupt load on cores 8-13, 20-23
- **USB controllers**: Scattered across cores 5-6, 18
- **GPU**: Core 3 (19,866 interrupts)

## Current Issues

### 1. **Interrupt Contention**
- Network interrupts are competing with storage I/O on the same cores
- WiFi interfaces are clustered on a few cores (14, 15, 21, 23)
- No isolation between network processing and userland workloads

### 2. **Cache Inefficiency**
- Network interrupts and userland processes share the same CPU caches
- SMT threads on the same physical core compete for cache resources
- No NUMA awareness for network processing

### 3. **Suboptimal Core Utilization**
- Cores 0-7, 9, 11, 13, 16-19, 22 have minimal network interrupt load
- Heavy network processing concentrated on cores 14, 15, 21, 23
- No dedicated cores for network processing

## Proposed Optimization Strategy

### Phase 1: Core Isolation and Dedication

#### Network Processing Cores (0-7)
**Dedicated cores for critical network interrupts and processing:**
- **Cores 0-3**: Primary network processing (4 physical cores, 8 logical threads)
- **Cores 4-7**: Secondary network processing (4 physical cores, 8 logical threads)
- **Services**: hostapd, nftables, network-optimization
- **Slice**: network-processing
- **Benefits**:
  - Dedicated L1/L2 cache for network processing
  - No competition with userland workloads
  - Better cache locality for network data structures

#### Network Services Cores (8-15)
**Dedicated cores for network infrastructure services:**
- **Cores 8-15**: Network services (8 logical threads)
- **Services**: DHCP (Kea), DNS (PowerDNS), IPv6 RA (radvd)
- **Slice**: network-services
- **Benefits**:
  - Dedicated resources for network infrastructure
  - Isolated from critical network processing
  - Better performance for network services

#### Userland Processing Cores (16-23)
**Remaining cores for system services and userland:**
- **Cores 16-23**: Userland processes, monitoring, system services
- **Slice**: userland-processing
- **Benefits**:
  - Isolated from network interrupt processing
  - Dedicated resources for monitoring and system services
  - Better performance for non-network workloads

### Phase 2: IRQ Affinity Optimization

#### Ethernet Interface (enp1s0)
```bash
# Distribute across dedicated network cores
echo 0 > /proc/irq/168/smp_affinity_list  # Core 0
echo 1 > /proc/irq/169/smp_affinity_list  # Core 1
echo 2 > /proc/irq/170/smp_affinity_list  # Core 2
echo 3 > /proc/irq/171/smp_affinity_list  # Core 3
echo 4 > /proc/irq/172/smp_affinity_list  # Core 4
echo 5 > /proc/irq/173/smp_affinity_list  # Core 5
echo 6 > /proc/irq/174/smp_affinity_list  # Core 6
echo 7 > /proc/irq/175/smp_affinity_list  # Core 7
```

#### WiFi Interfaces
**wlp35s0 (IRQ 179-194):**
```bash
# Distribute across cores 0-3
for irq in {179..194}; do
  echo $((irq - 179)) > /proc/irq/$irq/smp_affinity_list
done
```

**wlp65s0 (IRQ 198-213):**
```bash
# Distribute across cores 4-7
for irq in {198..213}; do
  echo $((irq - 198 + 4)) > /proc/irq/$irq/smp_affinity_list
done
```

**wlp66s0 (IRQ 214-229):**
```bash
# Distribute across cores 0-3 (alternating pattern)
for irq in {214..229}; do
  echo $(((irq - 214) % 4)) > /proc/irq/$irq/smp_affinity_list
done
```

**wlp97s0 (IRQ 231-246):**
```bash
# Distribute across cores 4-7 (alternating pattern)
for irq in {231..246}; do
  echo $(((irq - 231) % 4 + 4)) > /proc/irq/$irq/smp_affinity_list
done
```

### Phase 3: Systemd Slice Configuration

#### Network Processing Slice
Create a dedicated slice for critical network processing:

```nix
systemd.slices = {
  network-processing = {
    description = "Critical network processing (hostapd, nftables)";
    sliceConfig = {
      CPUAffinity = "0-7";  # Dedicated network cores
      Nice = -10;           # Higher priority
      IOSchedulingClass = 1; # Real-time I/O
      IOSchedulingPriority = 4;
      MemoryHigh = "2G";    # Limit memory usage
      MemoryMax = "4G";     # Hard memory limit
    };
  };
};
```

#### Network Services Slice
```nix
systemd.slices = {
  network-services = {
    description = "Network services (DHCP, DNS, RA)";
    sliceConfig = {
      CPUAffinity = "8-15"; # Dedicated network services cores
      Nice = -5;            # High priority
      MemoryHigh = "1G";    # Limit memory usage
      MemoryMax = "2G";     # Hard memory limit
    };
  };
};
```

#### Userland Processing Slice
```nix
systemd.slices = {
  userland-processing = {
    description = "Userland processing (monitoring, system services)";
    sliceConfig = {
      CPUAffinity = "16-23"; # Remaining cores
      Nice = 0;              # Normal priority
      MemoryHigh = "4G";     # Limit memory usage
      MemoryMax = "8G";      # Hard memory limit
    };
  };
};
```

### Phase 4: Kernel Parameter Optimization

#### CPU Isolation
```bash
# Boot parameters
isolcpus=0-7  # Isolate network cores from scheduler
nohz_full=0-7 # Disable tick for network cores
rcu_nocbs=0-7 # Disable RCU callbacks on network cores
```

#### Network Stack Optimization
```bash
# Kernel parameters for network performance
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 8000
net.core.netdev_tstamp_prequeue = 0
net.core.rps_sock_flow_entries = 32768
```

### Phase 5: NUMA Optimization

#### Memory Allocation
```bash
# Bind network processes to NUMA node 0
numactl --cpunodebind=0 --membind=0 <network_process>
```

#### Network Buffer Allocation
```bash
# Allocate network buffers from local NUMA node
echo 0 > /proc/sys/vm/numa_balancing
```

## Implementation Plan

### Step 1: Create IRQ Affinity Script
Create a systemd service to set IRQ affinities at boot:

```nix
systemd.services.irq-affinity = {
  description = "Set IRQ affinity for network optimization";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" "systemd-udev-settle.service" ];
  before = [ "hostapd.service" "kea-dhcp4-server.service" ];

  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${pkgs.writeShellScript "irq-affinity" ''
      #!/bin/bash
      # Ethernet interface IRQs
      echo 0 > /proc/irq/168/smp_affinity_list
      echo 1 > /proc/irq/169/smp_affinity_list
      # ... (complete script)
    ''}";
    RemainAfterExit = true;
  };
};
```

### Step 2: CPU Affinity for Network Services
```nix
systemd.services = {
  # Critical network processing (network-processing slice)
  hostapd = {
    serviceConfig = {
      Slice = "network-processing";
      CPUAffinity = "0-7";
      Nice = -10;
    };
  };

  nftables = {
    serviceConfig = {
      Slice = "network-processing";
      CPUAffinity = "0-7";
      Nice = -5;
    };
  };

  # Network services (network-services slice)
  kea-dhcp4-server = {
    serviceConfig = {
      Slice = "network-services";
      CPUAffinity = "8-15";
      Nice = -5;
    };
  };

  pdns-recursor = {
    serviceConfig = {
      Slice = "network-services";
      CPUAffinity = "8-15";
      Nice = -5;
    };
  };

  radvd = {
    serviceConfig = {
      Slice = "network-services";
      CPUAffinity = "8-15";
      Nice = -5;
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
};
```

### Step 3: Kernel Boot Parameters
```nix
boot.kernelParams = [
  "isolcpus=0-7"
  "nohz_full=0-7"
  "rcu_nocbs=0-7"
  "net.core.netdev_budget=600"
  "net.core.netdev_budget_usecs=8000"
];
```

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

### 5. **Better Resource Management**
- Memory limits prevent resource contention
- Slice-based isolation improves system stability
- Automatic restart policies for critical services

## Monitoring and Verification

### IRQ Distribution Check
```bash
# Monitor IRQ distribution
watch -n 1 'cat /proc/interrupts | grep -E "(enp1s0|iwlwifi)"'
```

### CPU Utilization Monitoring
```bash
# Monitor CPU usage per core
mpstat -P ALL 1
```

### Slice Status Monitoring
```bash
# Check slice status and resource usage
systemctl status network-processing.slice network-services.slice userland-processing.slice
```

### Network Performance Testing
```bash
# Test network throughput
iperf3 -s  # On network cores
iperf3 -c <server>  # From client
```

### Cache Performance
```bash
# Monitor cache misses
perf stat -e cache-misses,cache-references -p <network_process_pid>
```

## Configuration Files

### 1. `irq-affinity.nix`
Network IRQ affinity configuration and slice definitions

### 2. `kernel-params.nix`
Kernel boot parameters for optimization

### 3. `monitoring.nix`
Performance monitoring and logging configuration

### 4. `sysctl.nix`
Runtime kernel network parameters

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

## Conclusion

This optimization strategy provides:
- **Dedicated network processing cores** (0-7) for maximum performance
- **Dedicated network services cores** (8-15) for infrastructure services
- **Isolated userland processing** (16-23) for system stability
- **Optimized IRQ distribution** across dedicated cores
- **Slice-based resource management** with memory limits
- **NUMA-aware memory allocation** for better locality
- **Kernel parameter tuning** for network performance

The result is a high-performance WiFi access point optimized for maximum network throughput with minimal latency and CPU overhead, featuring a clean and maintainable systemd hierarchy with proper resource isolation.