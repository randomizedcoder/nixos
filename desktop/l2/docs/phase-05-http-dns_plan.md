# Phase 5: HTTP and DNS Load Generation - Implementation Plan

**Design Reference**: [phase-05-http-dns-loadgen.md](./phase-05-http-dns-loadgen.md)

---

## Sub-Phase 5.1: Test Data Generation

**Goal**: Create static files for HTTP benchmarking and DNS query file.

### Tasks

1. Create `mq-cake-gen-testdata` writeShellApplication
   - Generate random binary files: 1k, 10k, 100k, 1m, 2m, 5m, 10m
   - Store in `/var/lib/mq-cake/www/`

2. Create `mq-cake-gen-queries` writeShellApplication
   - Generate 10,000 DNS query entries
   - Store in `/var/lib/mq-cake/dns/queries.txt`

### Definition of Done

| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| 5.1.1 | Test files exist | All 7 files present with correct sizes |
| 5.1.2 | Query file valid | Contains 9999 A record queries |

---

## Sub-Phase 5.2: Nginx Deployment

**Goal**: Deploy nginx in ns-gen-b serving static files.

### Tasks

1. Create `/etc/mq-cake/nginx.conf`
   - Bind to `10.2.0.2:80`
   - Serve `/var/lib/mq-cake/www/`
   - Optimize for high concurrency

2. Create `mq-cake-nginx` wrapper script
   - Run nginx inside `ns-gen-b` namespace
   - Foreground mode for process management

3. Update orchestrator preflight checks

### Definition of Done

| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| 5.2.1 | nginx starts | No errors, listening on :80 |
| 5.2.2 | File accessible | `curl http://10.2.0.2/100k.bin` from ns-gen-a succeeds |
| 5.2.3 | All sizes work | Each file size returns correct Content-Length |

---

## Sub-Phase 5.3: wrk Tool Implementation

**Goal**: Add wrk HTTP benchmarking to Go orchestrator.

### Tasks

1. Create `internal/tools/wrk.go`
   - Implement Tool interface
   - ServerCmd: nginx wrapper
   - ClientCmd: wrk with connections, duration, latency flags
   - Parse: Extract RPS, throughput, latency percentiles

2. Create testdata
   - Capture real wrk output
   - Add to `internal/tools/testdata/wrk_100conn.txt`

3. Add unit tests in `tools_test.go`

### Definition of Done

| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| 5.3.1 | Compiles | `go build ./...` succeeds |
| 5.3.2 | Parser works | Extracts RPS, throughput, P50/P99 latency |
| 5.3.3 | Integration | wrk runs from orchestrator, results recorded |

---

## Sub-Phase 5.4: PowerDNS Deployment

**Goal**: Deploy PowerDNS authoritative server in ns-gen-b.

### Tasks

1. Create zone file `/etc/mq-cake/pdns/test.local.zone`
   - SOA, NS records
   - 10,000 A records (host0001-host9999)

2. Create `/etc/mq-cake/pdns/pdns.conf`
   - Bind backend
   - Listen on `10.2.0.2:53`

3. Create `mq-cake-pdns` wrapper script
   - Run pdns_server inside `ns-gen-b` namespace
   - Foreground mode

### Definition of Done

| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| 5.4.1 | pdns starts | No errors, listening on :53 |
| 5.4.2 | DNS resolves | `dig @10.2.0.2 host0001.test.local` returns A record |
| 5.4.3 | All hosts work | Random hosts resolve correctly |

---

## Sub-Phase 5.5: dnsperf Tool Implementation

**Goal**: Add dnsperf DNS benchmarking to Go orchestrator.

### Tasks

1. Create `internal/tools/dnsperf.go`
   - Implement Tool interface
   - ServerCmd: pdns wrapper
   - ClientCmd: dnsperf with QPS target, concurrent queries
   - Parse: Extract QPS, latency, packet loss

2. Create testdata
   - Capture real dnsperf output
   - Add to `internal/tools/testdata/dnsperf_50kqps.txt`

3. Add unit tests

### Definition of Done

| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| 5.5.1 | Compiles | `go build ./...` succeeds |
| 5.5.2 | Parser works | Extracts QPS, avg latency, loss % |
| 5.5.3 | Integration | dnsperf runs from orchestrator, results recorded |

---

## Sub-Phase 5.6: NixOS Module Updates

**Goal**: Add all new scripts to mq-cake-test.nix.

### Tasks

1. Add packages:
   - `pkgs.wrk`
   - `pkgs.dnsperf`
   - nginx config file
   - pdns config files

2. Add writeShellApplications:
   - `mq-cake-gen-testdata`
   - `mq-cake-gen-queries`
   - `mq-cake-nginx`
   - `mq-cake-pdns`

3. Update environment.systemPackages

### Definition of Done

| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| 5.6.1 | NixOS builds | `nixos-rebuild switch` succeeds |
| 5.6.2 | Scripts available | All 4 new scripts in PATH |
| 5.6.3 | Packages available | wrk, dnsperf, nginx, pdns installed |

---

## Sub-Phase 5.7: Config Schema Extension

**Goal**: Add HTTP/DNS options to orchestrator config.

### Tasks

1. Update `internal/config/config.go`
   ```go
   type HTTPConfig struct {
       FileSizes   []string `yaml:"file_sizes"`   // ["1k", "100k", "1m"]
       Connections []int    `yaml:"connections"`  // [1, 10, 100, 500]
   }

   type DNSConfig struct {
       QueryFile string `yaml:"query_file"`
       TargetQPS int    `yaml:"target_qps"`
   }
   ```

2. Update config.yaml with new sections

3. Update matrix builder to include HTTP/DNS variations

### Definition of Done

| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| 5.7.1 | Config loads | HTTP/DNS sections parsed correctly |
| 5.7.2 | Matrix extended | Includes wrk/dnsperf test points |

---

## Sub-Phase 5.8: Preflight Updates

**Goal**: Add HTTP/DNS service checks to preflight.

### Tasks

1. Add nginx check
   - Verify nginx running in ns-gen-b
   - Test file accessibility

2. Add pdns check
   - Verify pdns running in ns-gen-b
   - Test DNS resolution

### Definition of Done

| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| 5.8.1 | HTTP preflight | Reports nginx status |
| 5.8.2 | DNS preflight | Reports pdns status |
| 5.8.3 | Failures detected | Missing services cause preflight fail |

---

## Sub-Phase 5.9: Full Integration Test

**Goal**: Run complete test matrix with all 6 tools.

### Tasks

1. Generate test data and start services
2. Run full matrix (72 test points)
3. Verify results for all tools
4. Compare qdisc performance

### Definition of Done

| Test ID | Description | Pass Criteria |
|---------|-------------|---------------|
| 5.9.1 | Setup complete | nginx, pdns, test files ready |
| 5.9.2 | Matrix completes | 72/72 test points succeed |
| 5.9.3 | Results valid | All tools report non-zero metrics |
| 5.9.4 | mq-cake advantage | HTTP/DNS show same scaling pattern |

---

## Execution Order

```
5.1 Test Data Generation
 ↓
5.2 Nginx Deployment ←──────────────┐
 ↓                                  │
5.3 wrk Implementation              │ (parallel)
 ↓                                  │
5.4 PowerDNS Deployment ←───────────┘
 ↓
5.5 dnsperf Implementation
 ↓
5.6 NixOS Module Updates
 ↓
5.7 Config Schema Extension
 ↓
5.8 Preflight Updates
 ↓
5.9 Full Integration Test
```

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| nginx/pdns namespace binding | Use explicit IP binding, test early |
| wrk connection limits | Test with OS tuning (ulimit -n) |
| dnsperf packet drops | Start with lower QPS, increase gradually |
| Config compatibility | Keep HTTP/DNS optional, default disabled |

---

## Estimated Effort

| Sub-Phase | Complexity | Dependencies |
|-----------|------------|--------------|
| 5.1 | Low | None |
| 5.2 | Medium | 5.1 |
| 5.3 | Medium | 5.2 |
| 5.4 | Medium | 5.1 |
| 5.5 | Medium | 5.4 |
| 5.6 | Low | 5.1-5.5 |
| 5.7 | Low | 5.3, 5.5 |
| 5.8 | Low | 5.2, 5.4 |
| 5.9 | Medium | All |
