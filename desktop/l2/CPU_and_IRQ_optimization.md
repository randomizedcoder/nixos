# CPU and IRQ Optimization for L2 WiFi Access Point

## System Overview

The L2 system is equipped with an **AMD Ryzen Threadripper PRO 3945WX** featuring:
- **12 physical cores** with **24 logical threads** (SMT enabled)
- **4 NUMA nodes**
- **L3 cache**: 16MB per core complex (4x 16MB, each shared among 6 cores)
- **L2 cache**: 512KB per core
- **L1 cache**: 32KB instruction + 32KB data per core
- **128 GB RAM** for optimal network buffer allocation

## Cache-Aware Core Pairing for Network Optimization

On this architecture, each physical core is split into two logical processors (SMT siblings), e.g., P0/P12, P1/P13, ..., P11/P23. Both siblings share the same L1, L2, and L3 cache. To maximize cache locality and avoid cache pollution from userland processes, **network processing and IRQs should be grouped by physical core, using paired SMT siblings**.

**Recommended pattern:**
- Use one or both SMT siblings per physical core for network processing (e.g., 0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19 for 8 physical cores)
- Assign userland to the remaining SMT siblings (e.g., 8,20,9,21,10,22,11,23)

## Current Interrupt Distribution Analysis

### Network Interface Interrupts

#### Ethernet Interface (enp1s0) - Atlantic Driver
- **8 MSI-X vectors** distributed across cores 16-23
- **Current distribution**: Interrupts are clustered on cores 14, 15, 16, 17, 18, 20, 22, 23
- **Issue**: Competing with storage I/O and userland processes

#### WiFi Interfaces (4x Intel iwlwifi)
- **wlp35s0**: 16 MSI-X vectors, mostly on CPU 21
- **wlp65s0**: 16 MSI-X vectors, mostly on CPU 23
- **wlp66s0**: 16 MSI-X vectors, mostly on CPU 14
- **wlp97s0**: 16 MSI-X vectors, mostly on CPU 15
- **Issue**: All WiFi interfaces clustered on a few cores

### Storage and Other Interrupts
- **NVMe drives**: Heavy interrupt load on cores 8-13, 20-23
- **USB controllers**: Scattered across cores 5-6, 18
- **GPU**: Core 3 (heavy interrupt load)

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

#### Network Processing Cores (Paired SMT Siblings)
**Dedicated SMT sibling pairs for critical network interrupts and processing:**
- **Network cores**: 0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19 (one or both SMT siblings per physical core)
- **Userland cores**: 8,20,9,21,10,22,11,23
- **Services**: hostapd, nftables, network-optimization
- **Slice**: network-processing
- **Benefits**:
  - Dedicated L1/L2/L3 cache for network processing
  - No competition with userland workloads on the same physical core
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

#### Ethernet and WiFi Interfaces
```bash
# Distribute IRQs across paired SMT siblings for network processing
# Example: 0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19
network_cores=(0 12 1 13 2 14 3 15 4 16 5 17 6 18 7 19)
irq_index=0
for irq in $(grep -E '(enp|wlp)' /proc/interrupts | awk '{print $1}' | sed 's/://'); do
  cpu=${network_cores[$((irq_index % ${#network_cores[@]}))]}
  echo $cpu > /proc/irq/$irq/smp_affinity_list
  irq_index=$((irq_index + 1))
done
```

### Phase 3: Systemd Slice Configuration

#### Network Processing Slice
```nix
systemd.slices = {
  network-processing = {
    description = "Critical network processing (hostapd, nftables)";
    sliceConfig = {
      CPUAffinity = "0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19";  # Paired SMT siblings
      Nice = -10;
      IOSchedulingClass = 1;
      IOSchedulingPriority = 4;
      MemoryHigh = "8G";
      MemoryMax = "16G";
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
      MemoryHigh = "4G";    # Limit memory usage (3% of 128GB)
      MemoryMax = "8G";     # Hard memory limit (6% of 128GB)
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
      CPUAffinity = "8,20,9,21,10,22,11,23";  # Remaining SMT siblings
      Nice = 0;
      MemoryHigh = "32G";
      MemoryMax = "64G";
    };
  };
};
```

### Phase 4: Kernel Parameter and Sysctl Optimization

#### CPU Isolation (Kernel Boot Parameters)
```bash
# Boot parameters (set in boot.kernelParams)
# Isolate both SMT siblings of each physical core used for network processing
isolcpus=0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19
nohz_full=0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19
rcu_nocbs=0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19
```

#### Network Stack Optimization (Sysctl)
> **Note:** Network stack tunables such as `net.core.netdev_budget`, `net.core.netdev_budget_usecs`, and similar should be set via sysctl (NixOS: `boot.kernel.sysctl` or sysctl.nix), **not** as kernel boot parameters. These are runtime tunables and are not recognized as boot parameters.

```nix
# In sysctl.nix or boot.kernel.sysctl
boot.kernel.sysctl = {
  "net.core.netdev_budget" = 600;
  "net.core.netdev_budget_usecs" = 8000;
  # ... other network tunables ...
};
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
      # Dynamic IRQ affinity distribution script
      # Automatically detects network interfaces and distributes IRQs
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
      CPUAffinity = "0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19";
      Nice = -10;
    };
  };

  nftables = {
    serviceConfig = {
      Slice = "network-processing";
      CPUAffinity = "0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19";
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
      CPUAffinity = "8,20,9,21,10,22,11,23";
      Nice = 0;
    };
  };
};
```

### Step 3: Kernel Boot Parameters
```nix
boot.kernelParams = [
  "isolcpus=0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19"
  "nohz_full=0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19"
  "rcu_nocbs=0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19"
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
# Test network throughput with iperf2
iperf -s  # On network cores
iperf -c <server>  # From client

# Test with flent (FLExible Network Tester)
flent rrul -H <client_ip> -l 60

# Test with netperf
netserver  # On server
netperf -H <server_ip> -t TCP_STREAM
```

### Cache Performance
```bash
# Monitor cache misses
perf stat -e cache-misses,cache-references -p <network_process_pid>
```

### Real-time Network Monitoring
```bash
# Monitor network interfaces
iftop -i br0
nethogs
nload br0
```

## Configuration Files

### 1. `irq-affinity.nix`
Network IRQ affinity configuration and service for distributing interrupts across dedicated network cores

### 2. `systemd-slices.nix`
Systemd slice definitions with CPU affinity, resource limits, and service assignments for hierarchical resource management

### 3. `kernel-params.nix`
Kernel boot parameters for optimization (complements existing boot config in configuration.nix)

### 4. `monitoring.nix`
Performance monitoring and logging configuration

### 5. `sysctl.nix`
Runtime kernel network parameters

### 6. `systemPackages.nix`
Network testing tools: iperf2, flent, netperf, ethtool, sysstat, htop, iftop, nethogs, nload, speedtest-cli, mtr, traceroute, nmap, wireshark, tshark, perf-tools, perf

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

| Service      | Purpose                | Slice                   | Slice CPU Affinity                  | Priority |
|--------------|------------------------|-------------------------|-------------------------------------|----------|
| hostapd      | WiFi access point      | network-processing.slice| 0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19 | -10 (RT) |
| Kea          | DHCP server            | kea.slice (child of network-services.slice) | 8,20,9,21,10,22,11,23 | -5       |
| PowerDNS     | DNS resolver           | pdns.slice (child of network-services.slice)| 8,20,9,21,10,22,11,23 | -5       |
| radvd        | IPv6 RA                | radvd.slice (child of network-services.slice)| 8,20,9,21,10,22,11,23 | -5       |
| Monitoring   | Performance tracking   | system.slice            | 8,20,9,21,10,22,11,23               | 0        |

**Note:** All services inherit CPU affinity and resource limits from their assigned slice. Only the three main parent slices need explicit CPU affinity settings. Kernel-level components like nftables and CAKE (QoS) are not managed by systemd slices; their performance is influenced by CPU isolation, IRQ affinity, and kernel boot parameters, not by systemd.

## Integration with Existing Configuration

### Boot Configuration
The system already has boot configuration in `configuration.nix`:
- **systemd-boot** with EFI support
- **linuxPackages_latest** kernel
- **Regulatory database** loading in initrd
- **cfg80211** and **iwlwifi** module options
- **Blacklisted modules** (nouveau)

The `kernel-params.nix` module complements this existing configuration by adding:
- CPU isolation parameters
- Network performance optimizations
- Bluetooth disabling
- Security mitigation adjustments

### System Packages
Network testing tools are installed via `systemPackages.nix`:
- **iperf2**: Traditional network performance testing
- **flent**: FLExible Network Tester for advanced network analysis
- **netperf**: Comprehensive network performance testing
- **Additional tools**: ethtool, sysstat, htop, iftop, nethogs, nload, speedtest-cli, mtr, traceroute, nmap, wireshark, tshark, perf-tools, perf

## System Assessment and Adaptation Guide

This section describes how to assess a different system and adapt the CPU/IRQ optimization configuration for different hardware configurations.

### Step 1: System Hardware Assessment

#### CPU Information
```bash
# Get CPU details
lscpu

# Expected output example:
# CPU(s):                          24
# Thread(s) per core:              2
# Core(s) per socket:              12
# Socket(s):                       1
# NUMA node(s):                    4
# NUMA node0 CPU(s):               0-5
# NUMA node1 CPU(s):               6-11
# NUMA node2 CPU(s):               12-17
# NUMA node3 CPU(s):               18-23
```

**Key information to extract:**
- Total CPU cores and threads
- Physical cores vs logical threads (SMT/Hyperthreading)
- NUMA node configuration
- Cache sizes (L1, L2, L3)

#### Memory Information
```bash
# Get memory details
cat /proc/meminfo | grep -E "(MemTotal|MemFree|HugePages)"

# Expected output example:
# MemTotal:       131750188 kB
# MemFree:        128223008 kB
# HugePages_Total:       0
# Hugepagesize:       2048 kB
```

**Key information to extract:**
- Total system memory
- Available memory
- Huge page configuration

#### Network Interface Assessment
```bash
# List network interfaces
ip link show

# Get detailed interface information
lspci | grep -i ethernet
lspci | grep -i network

# Check WiFi interfaces
iw dev

# Expected output example:
# Interface wlp35s0
# Interface wlp65s0
# Interface wlp66s0
# Interface wlp97s0
```

**Key information to extract:**
- Ethernet interface names and drivers
- WiFi interface names and drivers
- Number of network interfaces

### Step 2: Current Interrupt Distribution Analysis

#### IRQ Distribution
```bash
# View current interrupt distribution
cat /proc/interrupts

# Filter for network interfaces
cat /proc/interrupts | grep -E "(enp|wlp|eth|wlan)"

# Expected output example:
#  168:      5051      706     4608       85      115      521      108     3924  IR-PCI-MSI 65536-edge      enp1s0
#  179:      1234      567      890      234      456      789      123      456  IR-PCI-MSI 65536-edge      wlp35s0
```

**Key information to extract:**
- IRQ numbers for each network interface
- Current CPU distribution of interrupts
- Number of MSI-X vectors per interface

#### CPU Utilization Patterns
```bash
# Monitor CPU usage during network activity
mpstat -P ALL 1 10

# Check CPU topology
cat /proc/cpuinfo | grep -E "(processor|physical id|core id)"

# Expected output example:
# processor       : 0
# physical id     : 0
# core id         : 0
# processor       : 1
# physical id     : 0
# core id         : 0
```

**Key information to extract:**
- CPU topology (physical cores vs logical threads)
- Current CPU utilization patterns
- Identify cores with high interrupt load

### Step 3: Storage and Other Interrupt Analysis

#### Storage Interrupts
```bash
# Check storage device interrupts
cat /proc/interrupts | grep -E "(nvme|ahci|scsi)"

# Check storage devices
lsblk
lspci | grep -i storage
```

#### Other System Interrupts
```bash
# Check USB, GPU, and other interrupts
cat /proc/interrupts | grep -E "(usb|gpu|pcie)"

# Check PCIe devices
lspci -t
```

### Step 4: Core Allocation Strategy (Assessment Guide)

Based on the assessment, determine the optimal core allocation:

#### For Different CPU Configurations (Paired SMT Siblings)

**Example: 8 physical cores, 16 logical threads**
```bash
# Assessment shows: 8 physical cores, 16 logical threads
# Strategy: Use paired SMT siblings for network processing
network_cores="0,8,1,9,2,10,3,11,4,12,5,13,6,14,7,15"
userland_cores="remaining SMT siblings"
```

**For your system (12 physical cores, 24 threads):**
```bash
network_cores="0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19"
userland_cores="8,20,9,21,10,22,11,23"
```

> **Rationale:** This pattern ensures that network processing and IRQs are always on separate physical cores (and their SMT siblings) from userland, maximizing cache locality and minimizing cross-core interference.

### Step 5: Memory Limit Calculations

**Formula for memory limits:**
```bash
# Calculate memory limits based on total system memory
total_memory_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))

# Network processing slice: 6-12% of total memory
network_processing_memory_high=$((total_memory_gb * 6 / 100))
network_processing_memory_max=$((total_memory_gb * 12 / 100))

# Network services slice: 3-6% of total memory
network_services_memory_high=$((total_memory_gb * 3 / 100))
network_services_memory_max=$((total_memory_gb * 6 / 100))

# Userland processing slice: 25-50% of total memory
userland_memory_high=$((total_memory_gb * 25 / 100))
userland_memory_max=$((total_memory_gb * 50 / 100))
```

### Step 6: IRQ Affinity Script Generation

#### Dynamic IRQ Detection Script
```bash
#!/bin/bash
# Generate IRQ affinity script for the target system

# Detect network interfaces
ethernet_interfaces=$(ip link show | grep -E "enp|eth" | awk -F: '{print $2}' | tr -d ' ')
wifi_interfaces=$(iw dev | grep Interface | awk '{print $2}')

echo "#!/bin/bash"
echo "set -euo pipefail"
echo ""
echo "echo \"Setting IRQ affinity for network optimization...\""
echo ""

# Ethernet interfaces - distribute across network cores
for interface in $ethernet_interfaces; do
    echo "# Ethernet interface $interface"
    echo "for irq in \$(grep $interface /proc/interrupts | awk '{print \$1}' | sed 's/://'); do"
    echo "  cpu=\$((irq % 8))  # Distribute across cores 0-7"
    echo "  echo \$cpu > /proc/irq/\$irq/smp_affinity_list"
    echo "done"
    echo ""
done

# WiFi interfaces - distribute across network cores
echo "# WiFi interfaces - distribute across network cores"
wifi_count=0
for interface in $wifi_interfaces; do
    if [ $((wifi_count % 2)) -eq 0 ]; then
        echo "# $interface -> cores 0-3"
        echo "for irq in \$(grep $interface /proc/interrupts | awk '{print \$1}' | sed 's/://'); do"
        echo "  cpu=\$((irq % 4))  # Distribute across cores 0-3"
        echo "  echo \$cpu > /proc/irq/\$irq/smp_affinity_list"
        echo "done"
    else
        echo "# $interface -> cores 4-7"
        echo "for irq in \$(grep $interface /proc/interrupts | awk '{print \$1}' | sed 's/://'); do"
        echo "  cpu=\$((irq % 4 + 4))  # Distribute across cores 4-7"
        echo "  echo \$cpu > /proc/irq/\$irq/smp_affinity_list"
        echo "done"
    fi
    echo ""
    wifi_count=$((wifi_count + 1))
done

echo "echo \"IRQ affinity configuration complete\""
```

### Step 7: Configuration File Adaptation

#### Kernel Parameters Adaptation
```bash
# Generate kernel parameters based on CPU configuration
cpu_count=$(nproc)
physical_cores=$(lscpu | grep "Core(s) per socket" | awk '{print $4}')
network_cores_count=$((physical_cores / 2))  # Use half of physical cores for network

# Generate isolcpus parameter
isolcpus_range="0-$((network_cores_count * 2 - 1))"  # Account for SMT

echo "# Generated kernel parameters for $(hostname)"
echo "boot.kernelParams = ["
echo "  # CPU isolation for network cores"
echo "  \"isolcpus=$isolcpus_range\""
echo "  \"nohz_full=$isolcpus_range\""
echo "  \"rcu_nocbs=$isolcpus_range\""
echo "  # ... additional parameters"
echo "];"
```

#### Slice Configuration Adaptation
```bash
# Generate slice configuration based on system resources
total_memory_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
network_cores_count=$((physical_cores / 2))

echo "systemd.slices = {"
echo "  network-processing = {"
echo "    description = \"Critical network processing\";"
echo "    sliceConfig = {"
echo "      CPUAffinity = \"0-$((network_cores_count * 2 - 1))\";"
echo "      MemoryHigh = \"${network_processing_memory_high}G\";"
echo "      MemoryMax = \"${network_processing_memory_max}G\";"
echo "    };"
echo "  };"
echo "  # ... additional slices"
echo "};"
```

### Step 8: Validation and Testing

#### Pre-optimization Baseline
```bash
# Capture baseline performance
iperf -s &
sleep 5
iperf -c localhost -t 30 > baseline_results.txt
killall iperf

# Capture baseline IRQ distribution
cat /proc/interrupts > baseline_interrupts.txt
```

#### Post-optimization Validation
```bash
# Verify IRQ distribution
echo "Verifying IRQ distribution..."
cat /proc/interrupts | grep -E "(enp|wlp|eth|wlan)"

# Verify CPU isolation
echo "Verifying CPU isolation..."
cat /proc/cmdline | grep isolcpus

# Verify slice configuration
echo "Verifying slice configuration..."
systemctl status network-processing.slice network-services.slice userland-processing.slice

# Performance testing
iperf -s &
sleep 5
iperf -c localhost -t 30 > optimized_results.txt
killall iperf

# Compare results
echo "Performance comparison:"
echo "Baseline: $(grep -E "SUM.*Gbits/sec" baseline_results.txt)"
echo "Optimized: $(grep -E "SUM.*Gbits/sec" optimized_results.txt)"
```

### Step 9: Documentation Template

Create a system-specific documentation file:

```bash
cat > system_assessment_$(hostname).md << EOF
# System Assessment for $(hostname)

## Hardware Configuration
- **CPU**: $(lscpu | grep "Model name" | cut -d: -f2 | xargs)
- **Cores**: $(nproc) logical, $(lscpu | grep "Core(s) per socket" | awk '{print $4}') physical
- **Memory**: $(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024)) GB
- **NUMA Nodes**: $(lscpu | grep "NUMA node(s)" | awk '{print $3}')

## Network Interfaces
$(ip link show | grep -E "enp|eth|wlp" | awk '{print "  - " $2}')

## Optimization Strategy
- **Network Cores**: 0-$((network_cores_count * 2 - 1))
- **Userland Cores**: $((network_cores_count * 2))-$((nproc - 1))
- **Memory Limits**: Network=${network_processing_memory_high}G/${network_processing_memory_max}G, Services=${network_services_memory_high}G/${network_services_memory_max}G

## Configuration Files
- Modified: kernel-params.nix, irq-affinity.nix, sysctl.nix
- Generated: system-specific IRQ affinity script

## Performance Results
- Baseline: [To be measured]
- Optimized: [To be measured]
EOF
```

This assessment guide provides a systematic approach to adapting the CPU/IRQ optimization configuration for different hardware configurations, ensuring optimal performance regardless of the specific system architecture.

## Conclusion

This optimization strategy provides:
- **Dedicated network processing cores** (0-7) for maximum performance
- **Dedicated network services cores** (8-15) for infrastructure services
- **Isolated userland processing** (16-23) for system stability
- **Optimized IRQ distribution** across dedicated cores
- **Slice-based resource management** with memory limits optimized for 128GB RAM
- **NUMA-aware memory allocation** for better locality
- **Kernel parameter tuning** for network performance
- **Comprehensive network testing tools** for performance validation
- **Systematic assessment methodology** for adapting to different hardware configurations

The result is a high-performance WiFi access point optimized for maximum network throughput with minimal latency and CPU overhead, featuring a clean and maintainable systemd hierarchy with proper resource isolation and extensive monitoring capabilities.

## Per-Daemon Systemd Slices for Maximum Visibility and Control

To achieve the highest level of resource isolation, monitoring, and control, this design uses a dedicated systemd slice for each major network service (daemon). This approach leverages systemd's hierarchical cgroup model, allowing you to:
- Set CPU, memory, and IO limits per service
- Monitor each service's resource usage independently
- Apply fine-grained policies and priorities
- Optionally group related slices under a parent slice for aggregate monitoring

### Three Main Parent Slices with CPU Affinity

The configuration defines three main parent slices, each with its own CPU affinity and resource limits:
- **network-processing.slice**: For critical network processing (hostapd, nftables, etc.)
- **network-services.slice**: For network infrastructure services (Kea, PowerDNS, radvd, etc.)
- **system.slice**: For userland/system services

**CPU affinity and resource limits are set only on these three main slices.**

### Per-Daemon Subordinate Slices Inherit from Main Slices

Each major daemon gets its own subordinate slice (e.g., `kea.slice`, `pdns.slice`, `radvd.slice`), which is attached as a child to the appropriate main slice. The per-daemon slices inherit CPU affinity and other limits from their parent, so you only need to set these on the main slices.

#### Example NixOS Configuration

```nix
# Main parent slices with CPU affinity
systemd.slices.network-processing = {
  description = "Critical network processing";
  sliceConfig = {
    CPUAffinity = "0,12,1,13,2,14,3,15,4,16,5,17,6,18,7,19";
    MemoryHigh = "8G";
    MemoryMax = "16G";
  };
};
systemd.slices.network-services = {
  description = "Network infrastructure services";
  sliceConfig = {
    CPUAffinity = "8,20,9,21,10,22,11,23";
    MemoryHigh = "4G";
    MemoryMax = "8G";
  };
};
# Use the existing system.slice for userland/system services
systemd.slices.system = {
  description = "System and userland services";
  sliceConfig = {
    CPUAffinity = "8,20,9,21,10,22,11,23";
    MemoryHigh = "32G";
    MemoryMax = "64G";
  };
};

# Per-daemon slices inherit from main slices
systemd.slices.kea = {
  description = "KEA DHCP server slice";
  sliceConfig = {
    Slice = "network-services.slice";
  };
};
systemd.slices.pdns = {
  description = "PowerDNS Recursor slice";
  sliceConfig = {
    Slice = "network-services.slice";
  };
};
systemd.slices.radvd = {
  description = "radvd IPv6 RA slice";
  sliceConfig = {
    Slice = "network-services.slice";
  };
};

# Assign each service to its per-daemon slice
systemd.services.kea-dhcp4-server.serviceConfig.Slice = "kea.slice";
systemd.services.pdns-recursor.serviceConfig.Slice = "pdns.slice";
systemd.services.radvd.serviceConfig.Slice = "radvd.slice";
```

### Benefits
- **Simplicity**: Only set CPU affinity and main limits on three main slices
- **Visibility**: Each daemon is tracked and controlled independently
- **Hierarchy**: Per-daemon slices inherit from main slices, keeping configuration clear and maintainable
- **Flexibility**: You can still override or add limits on a per-daemon basis if needed

This hierarchical slice design is recommended for maximum clarity, control, and monitoring in high-performance NixOS network systems.