# Phase 3: Load Generation - Implementation Log

**Plan Reference**: [phase-03-loadgen_plan.md](./phase-03-loadgen_plan.md)
**Design Reference**: [phase-03-loadgen.md](./phase-03-loadgen.md)

---

## Log Format

Each sub-phase entry should include:
- Start timestamp
- Completion timestamp
- Test results (pass/fail with details)
- Issues encountered and resolutions
- Sign-off

---

## Sub-Phase 3.1: Add Required Packages

| Field | Value |
|-------|-------|
| Started | 2026-02-16 11:00 |
| Completed | 2026-02-16 11:10 |
| Status | COMPLETE |

### Test Results

| Test ID | Result | Notes |
|---------|--------|-------|
| 3.1.1 | PASS | `which iperf` returns path |
| 3.1.2 | PASS | `which iperf3` returns path |
| 3.1.3 | PASS | `which flent` returns path |
| 3.1.4 | PASS | `which netperf` returns path |
| 3.1.5 | PASS | `which crusader` returns path |
| 3.1.6 | PASS | iperf2 version 2.2.1 |
| 3.1.7 | PASS | iperf3 version 3.20 |

### Package Versions

| Package | Version |
|---------|---------|
| iperf2 | 2.2.1 (4 Nov 2024) |
| iperf3 | 3.20 (cJSON 1.7.15) |
| flent | 2.2.0 |
| netperf | (bundled with flent) |
| crusader | 0.3.2 |

### Issues Encountered

_None_

### Sign-off

- [x] All tests pass
- [x] Definition of done complete

---

## Sub-Phase 3.2: Implement `mq-cake-iperf2` Script

| Field | Value |
|-------|-------|
| Started | 2026-02-16 11:10 |
| Completed | 2026-02-16 13:15 |
| Status | COMPLETE |

### Test Results

| Test ID | Result | Notes |
|---------|--------|-------|
| 3.2.1 | PASS | `which mq-cake-iperf2` returns path |
| 3.2.2 | PASS | Single flow completes |
| 3.2.3 | PASS | 10 flows: 9.44 Gbps aggregate |
| 3.2.4 | PASS | 100 flows complete |
| 3.2.5 | PASS | Throughput shows Gbits/sec |
| 3.2.6 | PASS | Server cleaned up after test |

### Sample Output

```
=== iperf2: 10 TCP flows for 10s ===
Target: 10.2.0.2:5001

Starting iperf2 server in ns-gen-b...
Running iperf2 client from ns-gen-a...

[SUM] 0.0000-2.0000 sec  2.22 GBytes  9.52 Gbits/sec
[SUM] 2.0000-4.0000 sec  2.19 GBytes  9.42 Gbits/sec
...
[SUM] 0.0000-10.0009 sec  11.0 GBytes  9.44 Gbits/sec

=== iperf2 complete ===
Stopping server (PID 37181)...
```

### Issues Encountered

_None_

### Sign-off

- [x] All tests pass
- [x] Definition of done complete

---

## Sub-Phase 3.3: Implement `mq-cake-iperf3` Script

| Field | Value |
|-------|-------|
| Started | 2026-02-16 13:15 |
| Completed | 2026-02-16 13:20 |
| Status | COMPLETE |

### Test Results

| Test ID | Result | Notes |
|---------|--------|-------|
| 3.3.1 | PASS | `which mq-cake-iperf3` returns path |
| 3.3.2 | PASS | Single flow completes |
| 3.3.3 | PASS | 10 flows: 9.44 Gbps sender, 9.41 Gbps receiver |
| 3.3.4 | PASS | 128+ flows capped with warning |
| 3.3.5 | PASS | JSON output mode works |
| 3.3.6 | PASS | bits_per_second in JSON |

### Sample Output

```
=== iperf3: 10 TCP flows for 10s ===
Target: 10.2.0.2:5201

[SUM]   0.00-2.00   sec  2.22 GBytes  9.53 Gbits/sec   30
[SUM]   2.00-4.00   sec  2.19 GBytes  9.41 Gbits/sec    8
...
[SUM]   0.00-10.01  sec  11.0 GBytes  9.44 Gbits/sec   48             sender
[SUM]   0.00-10.01  sec  11.0 GBytes  9.41 Gbits/sec                  receiver
```

### Issues Encountered

_None_

### Sign-off

- [x] All tests pass
- [x] Definition of done complete

---

## Sub-Phase 3.4: Implement `mq-cake-flent` Script

| Field | Value |
|-------|-------|
| Started | 2026-02-16 13:20 |
| Completed | 2026-02-16 14:40 |
| Status | COMPLETE |

### Test Results

| Test ID | Result | Notes |
|---------|--------|-------|
| 3.4.1 | PASS | `which mq-cake-flent` returns path |
| 3.4.2 | PASS | RRUL test completes in ~30s |
| 3.4.3 | PASS | PNG file created |
| 3.4.4 | PASS | .flent.gz data file created |
| 3.4.5 | PASS | Other tests (tcp_download) work |

### Output Files Generated

| File | Size | Contents |
|------|------|----------|
| flent-rrul-20260216-143556.png | 1553 | Plot image |
| rrul-2026-02-16T143559.004586.flent.gz | 38723 | Raw data |

### Issues Encountered

- **Initial -D flag issue**: `-D` expects directory, not filename
  - **Fix**: Changed to `-D "$OUTPUT_DIR"` for data dir

### Sign-off

- [x] All tests pass
- [x] Definition of done complete

---

## Sub-Phase 3.5: Implement `mq-cake-crusader` Script

| Field | Value |
|-------|-------|
| Started | 2026-02-16 14:40 |
| Completed | 2026-02-16 14:57 |
| Status | COMPLETE |

### Test Results

| Test ID | Result | Notes |
|---------|--------|-------|
| 3.5.1 | PASS | `which mq-cake-crusader` returns path |
| 3.5.2 | PASS | 10s test completes |
| 3.5.3 | PASS | Latency reported (0.5-2.0ms) |
| 3.5.4 | PASS | Server cleaned up |

### Sample Latency Output

```
[2026-02-16 14:56:31] Client version 0.3.2 running
[2026-02-16 14:56:31] Connected to server 10.2.0.2:35481
[2026-02-16 14:56:32] Idle latency to server 0.62 ms

-- Download test --
          Throughput: 9415.04 Mbps
             Latency: 2.0 ms (1.9 ms down, 0.1 ms up)
         Packet loss: 0%

-- Upload test --
          Throughput: 9414.58 Mbps
             Latency: 0.5 ms (0.2 ms down, 0.3 ms up)
         Packet loss: 0%

-- Bidirectional test --
          Throughput: 18756.86 Mbps (9378.44 Mbps down, 9378.41 Mbps up)
             Latency: 0.9 ms (0.5 ms down, 0.4 ms up)
         Packet loss: 0%

[2026-02-16 14:57:13] Saved raw data as crusader-results/test 2026-02-16 14.57.13.crr
[2026-02-16 14:57:13] Saved plot as crusader-results/test 2026-02-16 14.57.13.png
```

### Issues Encountered

- **Initial syntax error**: Used `crusader remote` instead of `crusader test`
  - **Fix**: Changed to `crusader test "$TARGET" --load-duration "$DURATION"`
- **Nix sandbox /dev/null error**: Transient sandbox permission issue
  - **Fix**: Machine reboot resolved it

### Sign-off

- [x] All tests pass
- [x] Definition of done complete

---

## Sub-Phase 3.6: Implement `mq-cake-load` Wrapper

| Field | Value |
|-------|-------|
| Started | 2026-02-16 14:57 |
| Completed | 2026-02-16 15:00 |
| Status | COMPLETE |

### Test Results

| Test ID | Result | Notes |
|---------|--------|-------|
| 3.6.1 | PASS | `which mq-cake-load` returns path |
| 3.6.2 | PASS | `mq-cake-load iperf2 5 5` works |
| 3.6.3 | PASS | Comma-separated tools work |
| 3.6.4 | PASS | `all` runs all four tools |
| 3.6.5 | PASS | Invalid tool rejected |

### Sample Output

```
=== MQ-CAKE Load Generation ===
Tools: iperf2
Flows: 5
Duration: 5s

----------------------------------------
=== iperf2: 5 TCP flows for 5s ===
...
[SUM] 0.0000-5.0031 sec  5.49 GBytes  9.43 Gbits/sec

=== iperf2 complete ===
Stopping server (PID 19090)...

=== Load generation complete ===
```

### Issues Encountered

_None_

### Sign-off

- [x] All tests pass
- [x] Definition of done complete

---

## Sub-Phase 3.7: Integration Test - Per-Qdisc Load Testing

| Field | Value |
|-------|-------|
| Started | 2026-02-16 15:00 |
| Completed | 2026-02-16 15:10 |
| Status | COMPLETE (basic validation) |

### Test Results

| Test ID | Result | Notes |
|---------|--------|-------|
| 3.7.1 | PASS | iperf2 100 flows works with all qdiscs |
| 3.7.2 | PASS | iperf3 10 flows works with all qdiscs |
| 3.7.3 | PASS | flent RRUL creates output files |
| 3.7.4 | PASS | crusader reports latency |
| 3.7.5 | DEFER | 500-flow stress test deferred to Phase 4 |
| 3.7.6 | DEFER | CPU saturation comparison deferred to Phase 4 |

### Baseline Results (default qdisc, mq)

**Crusader (10s test):**

| Test | Throughput | Latency | Packet Loss |
|------|------------|---------|-------------|
| Download | 9415 Mbps | 2.0 ms | 0% |
| Upload | 9414 Mbps | 0.5 ms | 0% |
| Bidirectional | 18756 Mbps | 0.9 ms | 0% |

**Idle Latency**: 0.62 ms

**iperf2 (10 flows, 10s):** 9.44 Gbps aggregate

**iperf3 (10 flows, 10s):** 9.41 Gbps receiver

### Notes

- Full per-qdisc comparison (fq_codel vs cake vs mq-cake) will be performed in Phase 4 Orchestrator
- CPU distribution analysis requires mpstat monitoring during high-flow tests
- All tools verified working before proceeding to orchestration

### Issues Encountered

_None_

### Sign-off

- [x] Basic tool validation complete
- [x] Ready for Phase 4 orchestration

---

## Phase 3 Summary

| Field | Value |
|-------|-------|
| Phase Started | 2026-02-16 11:00 |
| Phase Completed | 2026-02-16 15:10 |
| Total Duration | ~4 hours |
| Final Status | COMPLETE |

### Deliverables

| Deliverable | Location | Status |
|-------------|----------|--------|
| `mq-cake-iperf2` | `/run/current-system/sw/bin/mq-cake-iperf2` | COMPLETE |
| `mq-cake-iperf3` | `/run/current-system/sw/bin/mq-cake-iperf3` | COMPLETE |
| `mq-cake-flent` | `/run/current-system/sw/bin/mq-cake-flent` | COMPLETE |
| `mq-cake-crusader` | `/run/current-system/sw/bin/mq-cake-crusader` | COMPLETE |
| `mq-cake-load` | `/run/current-system/sw/bin/mq-cake-load` | COMPLETE |

### Key Findings

**Baseline Performance (default mq qdisc):**
- **Throughput**: 9.4+ Gbps unidirectional, 18.7 Gbps bidirectional
- **Latency**: 0.62 ms idle, 0.5-2.0 ms under load
- **Packet Loss**: 0%

**Tool Capabilities:**
- iperf2: Best for high flow counts (100+), 2-second interval reporting
- iperf3: JSON output, max 128 parallel streams, retransmit tracking
- flent: RRUL bufferbloat testing, generates PNG plots
- crusader: Modern latency tester, measures throughput + latency simultaneously

### Notes for Phase 4

1. **Crusader CLI syntax**: Use `crusader test <server-ip>` not `crusader remote`
2. **Flent output**: Use `-D <directory>` for data files, `-o <file.png>` for plot
3. **2-second intervals**: Both iperf2 and iperf3 configured for 2s reporting
4. **Server cleanup**: All scripts properly clean up background servers via trap
5. **Nix sandbox**: Transient `/dev/null` permission errors resolved by reboot

---

## Approval

- [x] Phase 3 complete and verified
- [x] Ready for Phase 4: Orchestrator
- [x] Signed: das Date: 2026-02-16
