# Firewall Design for L2 WiFi Access Point

## 1. Overview

This document outlines the design and principles of the `nftables` firewall configuration for the L2 WiFi access point. The primary goals are to provide robust security for the router and its clients, ensure correct network functionality, and maintain a clear, auditable ruleset with maximum performance.

The firewall leverages `nftables` for its modern syntax, performance, and ability to handle both IPv4 and IPv6 within a unified `inet` table family where possible. The configuration is optimized for performance through extensive use of nftables sets and strategic rule ordering.

### 1.1. Configuration Variables

The firewall configuration is designed to be reusable across different machines by using configurable variables:

*   **Interface Names**: `wanInterface` and `lanInterface` can be customized for different NIC naming schemes
*   **Network Prefixes**: `upstreamLanPrefix`, `internalIPv4Prefix`, and `internalIPv6Prefix` can be adjusted for different network topologies
*   **Service Ports**: Defined as sets for easy modification and reuse

This modular approach allows the same firewall rules to be deployed on machines with different interface names (e.g., `enp1s0`, `eth0`, `wlan0`) and network configurations.

## 2. Core Design Principles

The entire firewall is built upon the following security principles:

*   **Default-Deny Policy**: For traffic destined for the router (`input` chain) and traffic being routed through it (`forward` chain), the default policy is `drop`. Any traffic not explicitly permitted by a rule is silently discarded.
*   **Stateful Packet Inspection**: The firewall uses the `nftables` connection tracking (`conntrack`) system. This allows it to understand the state of connections, automatically permitting return traffic for established sessions while blocking unsolicited incoming packets.
*   **Defense in Depth & Rule Ordering**: Rules are ordered to drop malicious or invalid traffic as early as possible, improving both security and efficiency. The general order is:
    1.  Drop invalid/malformed packets.
    2.  Drop spoofed or explicitly denied traffic.
    3.  Accept traffic for established connections (the "fast path").
    4.  Accept specific, legitimate new connections.
*   **Principle of Least Privilege**: Services and clients are only granted the minimum access required for them to function correctly.
*   **Rate Limiting**: Critical services are protected with rate limiting to prevent abuse and DoS attacks.
*   **Comprehensive Logging**: All dropped packets are logged with rate limiting to prevent log flooding while maintaining audit trails.
*   **Performance Optimization**: Extensive use of nftables sets and strategic rule ordering for maximum packet processing efficiency.

## 3. Firewall Structure: Tables and Chains

The ruleset is organized into three tables:

*   `table inet filter`: Contains all filtering rules for both IPv4 and IPv6. The `inet` family allows for a single set of rules to manage both protocols.
*   `table ip nat`: Handles IPv4 Network Address Translation (NAT).
*   `table ip6 nat`: Handles IPv6 Network Address Translation (NAT).

### 3.1. Set-Based Architecture

The firewall extensively uses nftables sets for optimal performance and maintainability:

#### 3.1.1. Address Sets
*   **`special_purpose_ipv4`**: Contains all RFC 6890 special-purpose IPv4 ranges (excluding 192.168.0.0/16 in which 192.168.1.0/24 is allocated to the br0 interface)
*   **`special_purpose_ipv6`**: Contains all RFC 6890 special-purpose IPv6 ranges
*   **`loopback_ipv4`**: IPv4 loopback addresses (127.0.0.0/8)
*   **`loopback_ipv6`**: IPv6 loopback addresses (::1/128)
*   **`blacklist`**: Dynamic blacklist for CrowdSec integration (timeout-based, auto-merge)

#### 3.1.2. Service Port Sets
*   **`ssh_ports`**: SSH service ports (22)
*   **`dns_ports`**: DNS service ports (53)
*   **`dhcp_ports`**: DHCP service ports (67, 547)

#### 3.1.3. ICMP Type Sets
*   **`icmp_allowed`**: Allowed ICMP types (echo-request, echo-reply, destination-unreachable, time-exceeded, parameter-problem)
*   **`icmpv6_allowed`**: Allowed ICMPv6 types including Neighbor Discovery protocol types

### 3.2. `input` Chain (Traffic to the Router)

This chain protects the access point itself with optimized rule ordering:

*   **Early Invalid Packet Drops**:
    *   **Drops** invalid connection states immediately
    *   **Drops** fragmented packets (potential evasion technique)
    *   **Drops** packets with invalid TCP flag combinations
*   **Fast Path for Established Connections**:
    *   **Accepts** established and related connections early for maximum performance
*   **Loopback Protection**:
    *   **Accepts** all legitimate traffic on the loopback interface (`lo`)
    *   **Drops** any packet seen on a physical interface with loopback addresses using optimized set lookups
*   **Global Anti-Spoofing**:
    *   **Drops** any incoming packet with a source address from special-purpose ranges using set-based filtering
*   **Service Access Control**:
    *   **Allows** access to essential network services using set-based port matching
    *   **Rate limiting** is applied to SSH access to prevent brute force attacks
*   **ICMP/ICMPv6 Handling**:
    *   **Allows** ICMP/ICMPv6 messages using consolidated set-based type matching
    *   **Rate limiting** is applied to echo requests to prevent ping floods
*   **Logging and Default Drop**:
    *   Any packet that does not match an `accept` rule is logged with rate limiting and dropped

### 3.3. `forward` Chain (Traffic Through the Router)

This chain governs the traffic from WiFi clients to the internet and vice-versa with optimized performance:

*   **Early Invalid Packet Drops**:
    *   **Drops** invalid connection states and malformed packets immediately
*   **Anti-Spoofing with Set-Based Filtering**:
    *   **Drops** any packet being forwarded that contains loopback addresses using set lookups
    *   **Drops** any packet from internal clients with spoofed upstream LAN addresses
    *   **Drops** any packet from internal clients destined for special-purpose ranges using set-based filtering
*   **Fast Path for Return Traffic**:
    *   **Allows** return traffic from external to internal for established connections (most common case)
*   **Connection Rate Limiting**:
    *   **Rate limits** new connections to prevent resource exhaustion
*   **Client Forwarding**:
    *   **Allows** new connections from internal clients to external network with source address validation
*   **ICMP Forwarding**:
    *   **Allows** essential ICMP/ICMPv6 messages using consolidated set-based type matching
*   **Logging and Default Drop**:
    *   Any forwarded packet not matching an `accept` rule is logged and dropped

### 3.4. `output` Chain (Traffic from the Router)

This chain governs traffic generated by the access point itself with comprehensive egress filtering:

*   **Default-Accept Policy**: The policy is `accept`, but hardened with explicit `drop` rules
*   **Early Invalid Packet Drops**:
    *   **Drops** invalid connection states, fragmented packets, and invalid TCP flags
*   **Loopback Protection**:
    *   **Drops** any packet with loopback addresses on physical interfaces using set-based filtering
*   **Global Egress Filtering**:
    *   **Drops** any packet destined for special-purpose ranges using set-based filtering
*   **Interface-Specific Egress Filtering**:
    *   **Drops** internal subnet traffic from WAN interface to prevent network leakage
    *   **Allows** internal subnet traffic on internal interface for legitimate communication

### 3.5. `nat` Tables (`ip` and `ip6`)

These tables handle Network Address Translation for both IPv4 and IPv6:

*   **`postrouting` Chain**: Implements masquerading for traffic exiting the WAN interface
*   **`masquerade` Rule**: Rewrites source addresses to the WAN interface address for both IPv4 and IPv6

### 3.6. Performance Optimization Techniques

The firewall employs several advanced optimization techniques:

#### 3.6.1. Set-Based Performance
*   **Address Range Sets**: Special-purpose and loopback address ranges are defined as sets with `flags interval` for optimal prefix matching
*   **Service Port Sets**: Common service ports are grouped into sets for efficient port matching
*   **ICMP Type Sets**: ICMP and ICMPv6 types are consolidated into comprehensive sets for type matching
*   **Dynamic Blacklist**: CrowdSec-managed blacklist set with timeout-based automatic cleanup

#### 3.6.2. Rule Ordering Optimization
*   **Early Drops**: Invalid packets and spoofed traffic are dropped as early as possible
*   **Fast Path**: Established connections are accepted early to avoid expensive rule evaluation
*   **Global Filters**: Non-interface-specific drops (like special-purpose IP blocking) are applied before interface-specific rules
*   **Most Common Traffic First**: Return traffic and established connections are prioritized

#### 3.6.3. Logical Consolidation
*   **ICMP Type Consolidation**: Multiple ICMP types are grouped into comprehensive sets rather than individual rules
*   **Service Port Consolidation**: Related service ports are grouped into sets for efficient matching
*   **Address Range Consolidation**: Related address ranges are grouped into interval sets for optimal performance

#### 3.6.4. Memory and CPU Optimization
*   **Set Lookups**: Address and port matching uses optimized set lookups instead of individual rules
*   **Reduced Rule Count**: Consolidation reduces the total number of rules, improving packet processing speed
*   **Efficient Data Structures**: Interval sets use optimized data structures for prefix matching

### 3.7. CrowdSec Integration

The firewall integrates with CrowdSec for advanced threat detection and dynamic blocking:

#### 3.7.1. CrowdSec Architecture
*   **Threat Detection**: CrowdSec monitors system logs for suspicious behavior patterns
*   **Community Intelligence**: Leverages global threat intelligence from the CrowdSec community
*   **Real-time Blocking**: Automatically blocks malicious IPs using the nftables blacklist set
*   **Performance**: Written in Go, providing 60x better performance than traditional solutions

#### 3.7.2. Integration Components
*   **CrowdSec Engine**: Monitors logs and detects threats using YAML-based scenarios
*   **Firewall Bouncer**: Modern Go-based bouncer that manages the blacklist set in real-time
*   **Dynamic Blacklist**: Timeout-based set that automatically removes expired blocks
*   **Community Collections**: Pre-built detection rules for common services (SSH, web servers, etc.)

#### 3.7.3. Benefits
*   **Zero-Day Protection**: Community-driven threat detection catches new attack patterns
*   **Reduced False Positives**: Machine learning and community curation improve accuracy
*   **Automatic Updates**: Threat intelligence is continuously updated from the community
*   **Scalable Architecture**: Decoupled detection and remediation for better performance
*   **Resource Management**: Services run in the `network-services` slice with proper resource limits

#### 3.7.4. Configuration Decisions

The CrowdSec integration makes several deliberate architectural choices:

**Flake Input Integration**
*   **External Flake**: Uses `kampka/nix-flake-crowdsec` for official NixOS modules
*   **Minimal Overrides**: Leverages flake defaults for most configuration
*   **Selective Customization**: Only overrides necessary settings (API URLs, memory limits)
*   **Maintainability**: Reduces configuration complexity and maintenance burden
*   **Upstream Compatibility**: Benefits from upstream improvements and security updates

**Default Configuration Strategy**
*   **Flake Defaults**: Uses flake-provided default configurations for scenarios, parsers, and collections
*   **Minimal Customization**: Only customizes API communication and resource management
*   **Community Collections**: Leverages pre-built detection rules from the CrowdSec community
*   **Automatic Updates**: Threat intelligence and detection rules updated via flake updates
*   **Reduced Maintenance**: Less custom configuration means fewer potential issues

**Log Monitoring Configuration**
*   **SSH Monitoring**: Monitors `sshd.service` logs for brute force attacks and suspicious patterns
*   **Login Monitoring**: Monitors `systemd-logind.service` for authentication failures and session anomalies
*   **Journal Integration**: Uses systemd journal as data source for efficient log processing
*   **Real-time Detection**: Processes logs in real-time for immediate threat response
*   **Community Intelligence**: Combines local detection with global threat intelligence

**API Communication Architecture**
*   **Decoupled Design**: CrowdSec engine and firewall bouncer are separate services
*   **Loopback Communication**: Services communicate via IPv6 loopback (`[::1]:8080`)
*   **No API Keys**: Trusted IPs (`127.0.0.1`, `::1`) provide sufficient authentication for localhost
*   **No Forwarded Headers**: Direct loopback communication eliminates need for proxy headers

**Service Placement**
*   **Network Services Slice**: Both services run in `network-services.slice` with other network components
*   **High Priority**: Assigned `Nice = -5` for higher CPU priority than normal services
*   **Resource Limits**: 4GB memory high, 8GB memory max (inherited from network-services slice)
*   **File Descriptors**: Increased limit to 65,536 for high-traffic scenarios

**IPv6-First Approach**
*   **API Server**: Listens on IPv6 localhost (`[::1]:8080`) for better performance
*   **Bouncer Connection**: Connects to IPv6 localhost for consistency
*   **Future-Proof**: Ready for IPv6-only network environments
*   **Performance**: IPv6 loopback has slightly lower overhead than IPv4

**Security Model**
*   **Localhost-Only**: API server only accessible via loopback interface
*   **No External Exposure**: Eliminates risk of external API access
*   **Simplified Authentication**: Trusted IPs provide sufficient security for local communication
*   **Reduced Attack Surface**: No API key management or complex authentication

**Integration with nftables**
*   **Dynamic Blacklist**: Uses timeout-based set with automatic cleanup
*   **Early Drop**: Blacklisted IPs are dropped early in the input chain
*   **Set-Based Performance**: Leverages nftables set lookups for optimal performance
*   **Real-Time Updates**: Bouncer updates the blacklist set every 10 seconds

**Memory Management Strategy**
*   **Go Memory Limits**: GOMEMLIMIT set to 90% of systemd memory limits for proper garbage collection
*   **CrowdSec Engine**: 512MB high water mark, 1GB hard limit (GOMEMLIMIT: 460MB)
*   **Firewall Bouncer**: 256MB high water mark, 512MB hard limit (GOMEMLIMIT: 230MB)
*   **Memory Estimation**: Engine needs more memory for log processing and threat detection
*   **Bouncer Efficiency**: Bouncer is lightweight, only managing API polling and nftables updates
*   **Preventive Limits**: Prevents memory leaks and ensures predictable resource usage

## 4. Security Considerations

### 4.1. Rate Limiting
- SSH access is rate-limited to 6 connections per minute to prevent brute force attacks
- ICMP echo requests are rate-limited to prevent ping floods (10/second internal, 5/second external)
- Logging is rate-limited to 5 entries per minute to prevent log flooding during attacks
- New connections are rate-limited to 500/second to prevent resource exhaustion

### 4.2. Anti-Spoofing Measures
- Loopback address spoofing is blocked on all interfaces using set-based filtering
- Special-purpose IP ranges are blocked as source addresses using comprehensive set coverage
- Internal clients cannot spoof upstream LAN addresses
- Fragment and TCP flag filtering prevents evasion techniques

### 4.3. Network Segmentation
- Clear separation between internal (br0) and external (enp1s0) interfaces
- Service access is restricted to internal interfaces only
- Upstream LAN access is explicitly controlled
- Egress filtering prevents internal network leakage

### 4.4. IPv6 Security
- Comprehensive ICMPv6 filtering for proper IPv6 operation
- Neighbor Discovery Protocol protection
- Router Advertisement control
- Path MTU Discovery support

## 5. Monitoring and Logging

### 5.1. Log Analysis
Monitor firewall logs for:
- Repeated connection attempts (potential scanning)
- Spoofed packet attempts
- Rate limit violations
- Unusual traffic patterns

### 5.2. Performance Monitoring
- Connection tracking table utilization
- Packet processing statistics
- Interface traffic patterns
- Set lookup performance

### 5.3. Security Monitoring
- Failed authentication attempts
- Unusual source/destination patterns
- Protocol violations
- Anti-spoofing violations

## 6. Summary of Protections

| Protection Type                 | `input` Chain (Router) | `forward` Chain (Clients) | `output` Chain (Router) |
| ------------------------------- | :--------------------: | :-----------------------: | :---------------------: |
| **Default-Deny Policy**         |           ✓            |             ✓             |            ✗            |
| **Stateful Inspection**         |           ✓            |             ✓             |            ✓            |
| **Loopback Anti-Spoofing**      |           ✓            |             ✓             |            ✓            |
| **Special-Purpose IP Blocking** |           ✓            |             ✓             |            ✓            |
| **Service Access Control**      |           ✓            |            N/A            |           N/A           |
| **Client Subnet Enforcement**   |          N/A           |             ✓             |           N/A           |
| **Rate-Limited Drop Logging**   |           ✓            |             ✓             |           N/A           |
| **Rate Limiting Protection**    |           ✓            |            N/A            |           N/A           |
| **Set-Based Performance**       |           ✓            |             ✓             |            ✓            |
| **Optimized Rule Ordering**     |           ✓            |             ✓             |            ✓            |

## 7. Verification

The live, active ruleset can be inspected at any time using the following commands:

```bash
# List all rules (most common)
sudo nft list ruleset

# List specific table
sudo nft list table inet filter

# List specific chain
sudo nft list chain inet filter input

# Show rules with handles (useful for deleting specific rules)
sudo nft list ruleset -a

# Monitor nftables events in real-time
sudo nft monitor

# Show packet counters
sudo nft list ruleset -n

# Show rules with statistics
sudo nft list ruleset -s
```

### 7.1. Testing Commands
```bash
# Test SSH rate limiting
for i in {1..10}; do ssh -o ConnectTimeout=1 user@192.168.1.1; done

# Test ICMP filtering
ping -c 1 192.168.1.1  # Should work from br0
ping -c 1 8.8.8.8      # Should be blocked from external

# Test connection tracking
curl -I https://example.com  # Should work
# Return traffic should be automatically allowed

# Monitor firewall logs
journalctl -f -u nftables
```

### 7.2. Security Testing
```bash
# Test anti-spoofing
ping -I 127.0.0.1 8.8.8.8  # Should be blocked

# Test special-purpose IP blocking
ping -I 192.168.1.100 10.0.0.1  # Should be blocked

# Test IPv6 functionality
ping6 -c 1 fd00::1  # Should work from internal

# Test set-based filtering performance
time ping -c 1000 192.168.1.1  # Measure performance impact
```

### 7.3. Performance Testing
```bash
# Test set lookup performance
sudo nft list set inet filter special_purpose_ipv4
sudo nft list set inet filter icmp_allowed

# Monitor packet processing statistics
sudo nft list ruleset -s

# Test connection tracking performance
ss -s  # Show connection statistics
```