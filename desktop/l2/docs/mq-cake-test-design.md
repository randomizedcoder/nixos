# MQ-CAKE Performance Testing Framework

## Design Document v2.0

### Overview

This framework validates MQ-CAKE (Multi-Queue CAKE) qdisc performance compared to traditional CAKE and other qdiscs. The goal is to prove MQ-CAKE's scalability for high-flow-count scenarios, simulating 300-400 conference attendees with phones and laptops.

### Why MQ-CAKE?

Traditional CAKE is single-threaded and becomes a bottleneck on high-speed multi-queue NICs. MQ-CAKE creates a CAKE instance per hardware TX queue, allowing:

- Linear scaling across CPU cores
- Better cache locality per queue
- Sustained throughput under high flow counts
- Same fairness and latency benefits as CAKE

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              HOST: l2 (NixOS)                               │
│                    AMD Ryzen Threadripper PRO 3945WX                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────────┐                              ┌──────────────────────┐    │
│   │  ns-gen-a    │        Physical Cable        │      ns-dut          │    │
│   │              │                              │                      │    │
│   │  X710 p0     │─────────────────────────────▶│  82599ES p0          │    │
│   │  10.1.0.2/24 │                              │  10.1.0.1/24         │    │
│   │              │                              │                      │    │
│   │  (client)    │                              │  ┌────────────────┐  │    │
│   └──────────────┘                              │  │ QDISC UNDER    │  │    │
│                                                 │  │ TEST           │  │    │
│   ┌──────────────┐                              │  │                │  │    │
│   │  ns-gen-b    │        Physical Cable        │  │ - fq_codel     │  │    │
│   │              │                              │  │ - cake         │  │    │
│   │  X710 p1     │◀─────────────────────────────│  │ - mq-cake      │  │    │
│   │  10.2.0.2/24 │                              │  └────────────────┘  │    │
│   │              │                              │                      │    │
│   │  (server)    │                              │  82599ES p1          │    │
│   └──────────────┘                              │  10.2.0.1/24         │    │
│                                                 └──────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

Traffic flows: `ns-gen-a (10.1.0.2) → ns-dut (forwarding) → ns-gen-b (10.2.0.2)`

---

## Deliverables

| Phase | Description | Scripts |
|-------|-------------|---------|
| 1 | [Namespaces](./phase-01-namespaces.md) | `mq-cake-setup`, `mq-cake-teardown`, `mq-cake-verify` |
| 2 | [Qdisc](./phase-02-qdisc.md) | `mq-cake-qdisc <fq_codel|cake|mq-cake>` |
| 3 | [Load Generation](./phase-03-loadgen.md) | `mq-cake-iperf2`, `mq-cake-iperf3`, `mq-cake-flent`, `mq-cake-crusader`, `mq-cake-load` |
| 4 | [Orchestrator](./phase-04-orchestrator.md) | `mq-cake-orchestrator` (Go program) |
| 5 | [HTTP/DNS Load](./phase-05-http-dns-loadgen.md) | `mq-cake-nginx`, `mq-cake-pdns`, `mq-cake-gen-testdata` |

---

## Hardware

```
Machine: l2 (NixOS)
CPU: AMD Ryzen Threadripper PRO 3945WX (12 cores / 24 threads)

Network Interfaces:
┌─────────────────────────────────────────────────────────────────────────────┐
│ PCI Slot   │ NIC                              │ Interface Names             │
├─────────────────────────────────────────────────────────────────────────────┤
│ 01:00.0    │ Aquantia AQC107 10G              │ (not used)                  │
│ 23:00.0/1  │ Intel X710 10GbE SFP+ (i40e)     │ enp35s0f0np0, enp35s0f1np1  │
│ 42:00.0/1  │ Intel 82599ES 10GbE (ixgbe)      │ enp66s0f0, enp66s0f1        │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## IP Addressing (10/8)

| Namespace | Interface | IP Address | Role |
|-----------|-----------|------------|------|
| ns-gen-a | enp35s0f0np0 | 10.1.0.2/24 | Load generator (client) |
| ns-gen-b | enp35s0f1np1 | 10.2.0.2/24 | Load generator (server) |
| ns-dut | enp66s0f0 | 10.1.0.1/24 | DUT ingress |
| ns-dut | enp66s0f1 | 10.2.0.1/24 | DUT egress |

---

## Load Generation Tools

| Tool | Purpose | Nix Package |
|------|---------|-------------|
| iperf2 | TCP/UDP throughput, 100+ parallel flows | `pkgs.iperf2` |
| iperf3 | TCP/UDP with JSON output | `pkgs.iperf3` |
| flent | RRUL latency-under-load | `pkgs.flent` |
| crusader | Modern latency tester | `pkgs.crusader` |
| wrk | HTTP benchmarking (requests/sec) | `pkgs.wrk` |
| dnsperf | DNS benchmarking (queries/sec) | `pkgs.dnsperf` |

### Application Servers (Phase 5)

| Server | Purpose | Nix Package |
|--------|---------|-------------|
| nginx | Static file serving | `pkgs.nginx` |
| PowerDNS | Authoritative DNS | `pkgs.pdns` |

---

## Test Matrix

The orchestrator iterates through combinations:

| Variable | Values | Count |
|----------|--------|-------|
| Qdisc | fq_codel, cake, mq-cake | 3 |
| Parallel Flows | 1, 10, 100, 500 | 4 |
| **Total combinations** | | **12** |

For each combination:
1. Configure qdisc on DUT
2. Start load generators (iperf2, iperf3, flent, crusader)
3. Ramp up flow count
4. Hold steady state, collect metrics
5. Ramp down
6. Export results

---

## Success Criteria

1. **Scalability**: mq-cake handles 500+ flows without CPU bottleneck
2. **Fairness**: Per-flow throughput variance < 10% at steady state
3. **Latency**: P99 latency < 100ms at 80% link utilization
4. **Stability**: No crashes during 10-minute sustained test

---

## Quick Start

```bash
# Phase 1: Set up namespaces
sudo mq-cake-setup
sudo mq-cake-verify

# Phase 2: Configure qdisc
sudo mq-cake-qdisc mq-cake

# Phase 3: Run load generators manually
sudo mq-cake-iperf2 --flows 100 --duration 60

# Phase 4: Run full test suite
mq-cake-orchestrator --config /etc/mq-cake/config.yaml
```

---

## References

- [MQ-CAKE Net-Next Patches](https://patch.msgid.link/20260109-mq-cake-sub-qdisc-v8-1-8d613fece5d8@redhat.com)
- [Netdev 0x19 Presentation](https://netdevconf.info/0x19/sessions/talk/mq-cake-scaling-software-rate-limiting-across-cpu-cores.html)
- [CAKE Documentation](https://www.bufferbloat.net/projects/codel/wiki/CAKE/)
- [Flent Documentation](https://flent.org/)
