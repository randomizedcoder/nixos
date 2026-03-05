# MQ-CAKE Test Network Topology

## Overview

This document describes the network topology used for MQ-CAKE qdisc performance testing. The setup uses Linux network namespaces to create isolated test environments on a single physical machine, with dedicated 10GbE NICs for each role.

## Physical Hardware

| Component | Description |
|-----------|-------------|
| CPU | AMD Ryzen Threadripper PRO 3945WX (12 cores / 24 threads) |
| RAM | 128 GB |
| Load Generator NICs | Intel X710 10GbE SFP+ (2 ports) |
| DUT NICs | Intel 82599ES 10GbE SFP+ (2 ports) |
| WAN NIC | Aquantia AQC107 10GbE (not used in test) |

## Network Diagram

```
                          ┌─────────────────────────────────────────────────────────────┐
                          │                      Physical Host (l2)                      │
                          │                  Ryzen Threadripper PRO 3945WX               │
                          └─────────────────────────────────────────────────────────────┘


  ┌─────────────────────────┐       ┌─────────────────────────┐       ┌─────────────────────────┐
  │      ns-gen-a           │       │        ns-dut           │       │      ns-gen-b           │
  │    (Load Generator)     │       │   (Device Under Test)   │       │       (Server)          │
  │                         │       │                         │       │                         │
  │  ┌───────────────────┐  │       │  ┌───────────────────┐  │       │  ┌───────────────────┐  │
  │  │   enp35s0f0np0    │  │       │  │      ixgbe0       │  │       │  │   enp35s0f1np1    │  │
  │  │   Intel X710 p0   │──╋───────╋──│  Intel 82599 p0   │  │       │  │   Intel X710 p1   │  │
  │  │   10.1.0.2/24     │  │  SFP+ │  │   10.1.0.1/24     │  │       │  │   10.2.0.2/24     │  │
  │  └───────────────────┘  │ Cable │  └─────────┬─────────┘  │       │  └─────────┬─────────┘  │
  │                         │       │            │            │       │            │            │
  │   netem: 30ms ±3ms      │       │     ┌──────┴──────┐     │       │   netem: 30ms ±3ms      │
  │                         │       │     │  Forwarding │     │       │            │            │
  │  Tools:                 │       │     │ (ip_forward)│     │       │  Services: │            │
  │  - iperf2 client        │       │     └──────┬──────┘     │       │  - iperf2  │            │
  │  - iperf3 client        │       │            │            │       │  - iperf3  │            │
  │  - wrk (HTTP)           │       │  ┌─────────┴─────────┐  │       │  - flent   │            │
  │  - dnsperf              │       │  │      ixgbe1       │  │       │  - crusader│            │
  │  - flent                │       │  │  Intel 82599 p1   │──╋───────╋──- nginx   │            │
  │  - crusader client      │       │  │   10.2.0.1/24     │  │  SFP+ │  - PowerDNS│            │
  │  - fping                │       │  └───────────────────┘  │ Cable │            │            │
  │                         │       │                         │       │            │            │
  └─────────────────────────┘       │  Qdisc under test:      │       └────────────┴────────────┘
                                    │  - fq_codel             │
                                    │  - cake                 │
                                    │  - mq-cake (mq+cake)    │
                                    │                         │
                                    └─────────────────────────┘


  Physical Cabling:
  ═════════════════

  ┌──────────────────┐                                        ┌──────────────────┐
  │  Intel X710      │                                        │  Intel 82599ES   │
  │  (PCI 23:00.x)   │                                        │  (PCI 42:00.x)   │
  ├──────────────────┤          10GbE SFP+ Cable              ├──────────────────┤
  │ Port 0           │◄══════════════════════════════════════►│ Port 0           │
  │ enp35s0f0np0     │          (Direct Attach Copper)        │ ixgbe0           │
  ├──────────────────┤                                        ├──────────────────┤
  │ Port 1           │◄══════════════════════════════════════►│ Port 1           │
  │ enp35s0f1np1     │          10GbE SFP+ Cable              │ ixgbe1           │
  └──────────────────┘          (Direct Attach Copper)        └──────────────────┘
```

## Traffic Flow

```
                    10.1.0.0/24 Subnet              10.2.0.0/24 Subnet
                    ==================              ==================

  Client (10.1.0.2)  ──────►  DUT Ingress (10.1.0.1)
                                    │
                                    │  IP Forwarding
                                    │  + Qdisc (cake/fq_codel/mq-cake)
                                    ▼
                              DUT Egress (10.2.0.1)  ──────►  Server (10.2.0.2)

  ◄─────────────────────────  Response Path  ──────────────────────────►
```

## IP Addressing

| Namespace | Interface | IP Address | Role |
|-----------|-----------|------------|------|
| ns-gen-a | enp35s0f0np0 | 10.1.0.2/24 | Client / Load Generator |
| ns-dut | ixgbe0 | 10.1.0.1/24 | DUT Ingress (gateway for ns-gen-a) |
| ns-dut | ixgbe1 | 10.2.0.1/24 | DUT Egress (gateway for ns-gen-b) |
| ns-gen-b | enp35s0f1np1 | 10.2.0.2/24 | Server |

## Interface Naming

Interface names are pinned by MAC address via udev rules (`udev-nic-names.nix`):

| MAC Address | Stable Name | PCI Address | Driver | Description |
|-------------|-------------|-------------|--------|-------------|
| 00:1b:21:66:a9:80 | ixgbe0 | 42:00.0 | ixgbe | 82599ES DUT port 0 |
| 00:1b:21:66:a9:81 | ixgbe1 | 42:00.1 | ixgbe | 82599ES DUT port 1 |
| (auto) | enp35s0f0np0 | 23:00.0 | i40e | X710 load gen port 0 |
| (auto) | enp35s0f1np1 | 23:00.1 | i40e | X710 load gen port 1 |

## NIC Configuration

From `ethtool-nics.nix`:

| Interface | Ring RX | Ring TX | Channels | Features |
|-----------|---------|---------|----------|----------|
| ixgbe0 | 8192 | 8192 | 8 | ntuple, rx-udp-gro-forwarding |
| ixgbe1 | 8192 | 8192 | 8 | ntuple, rx-udp-gro-forwarding |
| enp35s0f0np0 | 8160 | 8160 | 8 | rx-udp-gro-forwarding |
| enp35s0f1np1 | 8160 | 8160 | 8 | rx-udp-gro-forwarding |

## Netem Configuration

WAN simulation is applied on the load generator interfaces (not the DUT):

| Parameter | Value | Description |
|-----------|-------|-------------|
| Latency | 30ms | Base delay |
| Jitter | 3ms | Gaussian distribution |
| Limit | 100,000 packets | Queue depth |

This simulates ~60ms RTT (30ms each direction) with realistic jitter.

## Qdisc Configurations Tested

### fq_codel (baseline)
```
tc qdisc replace dev ixgbe0 root fq_codel
tc qdisc replace dev ixgbe1 root fq_codel
```

### cake (single queue)
```
tc qdisc replace dev ixgbe0 root cake bandwidth 10gbit diffserv4 nat wash split-gso
tc qdisc replace dev ixgbe1 root cake bandwidth 10gbit diffserv4 nat wash split-gso
```

### mq-cake (multi-queue)
```
tc qdisc replace dev ixgbe0 root handle 1: mq
tc qdisc replace dev ixgbe0 parent 1:1 cake bandwidth 10gbit diffserv4 nat wash split-gso
tc qdisc replace dev ixgbe0 parent 1:2 cake bandwidth 10gbit diffserv4 nat wash split-gso
... (one cake per TX queue, 8 total)
```

## Test Tools

| Tool | Protocol | Purpose | Port |
|------|----------|---------|------|
| iperf2 | TCP | High-flow throughput | 5001 |
| iperf3 | TCP | Throughput with JSON stats | 5201 |
| flent | TCP | RRUL latency under load | 12865 |
| crusader | TCP/UDP | Latency measurement | 35481 |
| wrk | HTTP | HTTP request throughput | 80 |
| dnsperf | UDP | DNS query throughput | 53 |
| fping | ICMP | Pure network latency | - |

## Setup Commands

```bash
# Create namespaces and configure networking
sudo mq-cake-setup

# Verify connectivity
sudo mq-cake-verify

# Configure qdisc
sudo mq-cake-qdisc mq-cake

# Start HTTP/DNS servers
sudo mq-cake-full-setup

# Run stress test
sudo mq-cake-stress

# Teardown
sudo mq-cake-teardown
```

## Prometheus Metrics

Metrics exposed on port 2112 during stress tests:

- `mqcake_test_throughput_gbps{tool, qdisc}` - Throughput per tool
- `mqcake_test_latency_p99_ms{tool, qdisc}` - P99 latency
- `mqcake_test_packet_loss_pct{tool, qdisc}` - Packet loss percentage
- `mqcake_test_flows{tool, qdisc}` - Active flow count
- `mqcake_qdisc_packets{interface}` - Qdisc packet count
- `mqcake_qdisc_drops{interface}` - Qdisc drop count
- `mqcake_socket_*` - TCP socket statistics

## Files

| File | Purpose |
|------|---------|
| `mq-cake-test.nix` | Namespace setup and test scripts |
| `mq-cake-orchestrator/` | Go orchestrator for stress testing |
| `udev-nic-names.nix` | Stable NIC naming via MAC address |
| `ethtool-nics.nix` | NIC ring buffer and channel configuration |
| `stress-config.yaml` | Stress test parameters |
