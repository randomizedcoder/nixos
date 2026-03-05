# Phase 5: HTTP and DNS Load Generation

## Overview

Add application-layer load testing to complement TCP-layer tools (iperf2/iperf3). This validates MQ-CAKE performance with realistic workloads:

- **HTTP**: nginx serving static files + wrk load generator
- **DNS**: PowerDNS authoritative + dnsperf query generator

These tests simulate real conference traffic patterns where users make web requests and DNS lookups simultaneously with varying payload sizes.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              HOST: l2 (NixOS)                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌──────────────────┐                           ┌──────────────────────┐   │
│   │  ns-gen-a        │      Physical Cable       │      ns-dut          │   │
│   │  (client)        │                           │                      │   │
│   │                  │                           │                      │   │
│   │  X710 p0         │──────────────────────────▶│  82599ES p0          │   │
│   │  10.1.0.2/24     │                           │  10.1.0.1/24         │   │
│   │                  │                           │                      │   │
│   │  ┌────────────┐  │                           │  ┌────────────────┐  │   │
│   │  │ wrk        │  │                           │  │ QDISC UNDER    │  │   │
│   │  │ dnsperf    │  │                           │  │ TEST           │  │   │
│   │  └────────────┘  │                           │  └────────────────┘  │   │
│   └──────────────────┘                           │                      │   │
│                                                  │                      │   │
│   ┌──────────────────┐                           │                      │   │
│   │  ns-gen-b        │      Physical Cable       │                      │   │
│   │  (server)        │                           │                      │   │
│   │                  │                           │                      │   │
│   │  X710 p1         │◀──────────────────────────│  82599ES p1          │   │
│   │  10.2.0.2/24     │                           │  10.2.0.1/24         │   │
│   │                  │                           │                      │   │
│   │  ┌────────────┐  │                           └──────────────────────┘   │
│   │  │ nginx:80   │  │                                                      │
│   │  │ pdns:53    │  │                                                      │
│   │  └────────────┘  │                                                      │
│   └──────────────────┘                                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Sub-Phase 5.1: Static File Generation

Generate test files of various sizes for HTTP benchmarking:

| File | Size | Use Case |
|------|------|----------|
| `1k.bin` | 1 KB | Small API responses, icons |
| `10k.bin` | 10 KB | JSON payloads, small images |
| `100k.bin` | 100 KB | Medium images, JS bundles |
| `1m.bin` | 1 MB | Large images, PDF documents |
| `2m.bin` | 2 MB | High-res images |
| `5m.bin` | 5 MB | Short videos, large assets |
| `10m.bin` | 10 MB | Video clips, downloads |

**Implementation**: `mq-cake-gen-testdata` script to create files with random data.

---

## Sub-Phase 5.2: Nginx Configuration

Deploy nginx in `ns-gen-b` serving static files:

```nginx
# /etc/nginx/nginx.conf (namespace-aware)
worker_processes auto;
worker_cpu_affinity auto;

events {
    worker_connections 65535;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    server {
        listen 80;
        server_name _;
        root /var/lib/mq-cake/www;

        location / {
            try_files $uri =404;
        }
    }
}
```

**NixOS Integration**:
- Create systemd service that runs nginx inside `ns-gen-b`
- Use `ip netns exec ns-gen-b nginx`
- Bind to `10.2.0.2:80`

---

## Sub-Phase 5.3: wrk HTTP Load Generator

[wrk](https://github.com/wg/wrk) is a modern HTTP benchmarking tool capable of generating significant load.

**Nix Package**: `pkgs.wrk`

**Client Command**:
```bash
ip netns exec ns-gen-a wrk \
    -t 8 \                    # 8 threads
    -c 100 \                  # 100 connections
    -d 30s \                  # 30 second duration
    --latency \               # Print latency stats
    http://10.2.0.2/100k.bin
```

**Output Format**:
```
Running 30s test @ http://10.2.0.2/100k.bin
  8 threads and 100 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.23ms  234.56us   5.67ms   89.12%
    Req/Sec    10.12k   456.78    12.34k    78.90%
  Latency Distribution
     50%    1.12ms
     75%    1.34ms
     90%    1.56ms
     99%    2.34ms
  2424242 requests in 30.00s, 2.34GB read
Requests/sec:  80808.08
Transfer/sec:     80.00MB
```

**Parsed Metrics**:
- Requests/sec
- Transfer/sec (throughput)
- Latency P50, P75, P90, P99
- Total requests completed

---

## Sub-Phase 5.4: PowerDNS Configuration

Deploy PowerDNS authoritative server in `ns-gen-b`:

**Zone Configuration** (`test.local`):
```
$ORIGIN test.local.
$TTL 300

@       IN      SOA     ns1.test.local. admin.test.local. (
                        2024021701      ; serial
                        3600            ; refresh
                        600             ; retry
                        604800          ; expire
                        300             ; minimum
                        )

@       IN      NS      ns1.test.local.
ns1     IN      A       10.2.0.2

; Generate 10000 A records for load testing
host0001    IN  A   10.2.0.100
host0002    IN  A   10.2.0.101
...
host9999    IN  A   10.2.0.199
```

**PowerDNS Config** (`pdns.conf`):
```ini
launch=bind
bind-config=/etc/pdns/named.conf
local-address=10.2.0.2
local-port=53
```

**NixOS Integration**:
- Run `pdns_server` inside `ns-gen-b`
- Bind to `10.2.0.2:53`

---

## Sub-Phase 5.5: dnsperf DNS Load Generator

[dnsperf](https://github.com/DNS-OARC/dnsperf) is the standard DNS benchmarking tool.

**Nix Package**: `pkgs.dnsperf`

**Query File** (`queries.txt`):
```
host0001.test.local A
host0002.test.local A
host0003.test.local A
...
```

**Client Command**:
```bash
ip netns exec ns-gen-a dnsperf \
    -s 10.2.0.2 \             # Server address
    -p 53 \                   # Port
    -d queries.txt \          # Query file
    -c 100 \                  # Concurrent queries
    -Q 50000 \                # Target QPS
    -l 30                     # Duration (seconds)
```

**Output Format**:
```
DNS Performance Testing Tool
[Status] Queries completed:  1500000 (100.00%)
[Status] Queries lost:       0 (0.00%)

Statistics:
  Queries sent:         1500000
  Queries completed:    1500000 (100.00%)
  Queries lost:         0 (0.00%)

  Response codes:       NOERROR 1500000 (100.00%)

  Average packet size:  request 45, response 61
  Run time (s):         30.000000
  Queries per second:   50000.000000

  Average Latency (s):  0.001234 (min 0.000100, max 0.050000)
  Latency StdDev (s):   0.000567
```

**Parsed Metrics**:
- Queries per second (QPS)
- Queries lost (packet loss)
- Average/min/max latency
- Response code distribution

---

## Sub-Phase 5.6: Go Tool Implementations

### HTTP Tool (`internal/tools/wrk.go`)

```go
type Wrk struct{}

func (t *Wrk) Name() string { return "wrk" }

func (t *Wrk) ServerCmd(port int) []string {
    // nginx started separately via systemd
    return []string{"nginx", "-g", "daemon off;"}
}

func (t *Wrk) ClientCmd(target string, port int, flows int, duration time.Duration) []string {
    // flows = connections for wrk
    return []string{
        "wrk",
        "-t", "8",                              // threads
        "-c", strconv.Itoa(flows),              // connections
        "-d", strconv.Itoa(int(duration.Seconds())) + "s",
        "--latency",
        fmt.Sprintf("http://%s:%d/100k.bin", target, port),
    }
}

func (t *Wrk) Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error) {
    // Parse: "Requests/sec:  80808.08"
    // Parse: "Transfer/sec:     80.00MB"
    // Parse latency distribution
}
```

### DNS Tool (`internal/tools/dnsperf.go`)

```go
type DNSPerf struct {
    QueryFile string
}

func (t *DNSPerf) Name() string { return "dnsperf" }

func (t *DNSPerf) ServerCmd(port int) []string {
    // PowerDNS started separately via systemd
    return []string{"pdns_server", "--daemon=no"}
}

func (t *DNSPerf) ClientCmd(target string, port int, flows int, duration time.Duration) []string {
    return []string{
        "dnsperf",
        "-s", target,
        "-p", strconv.Itoa(port),
        "-d", t.QueryFile,
        "-c", strconv.Itoa(flows),      // concurrent queries
        "-Q", "50000",                   // target QPS
        "-l", strconv.Itoa(int(duration.Seconds())),
    }
}

func (t *DNSPerf) Parse(output string, flows int, duration time.Duration) (*NormalizedResult, error) {
    // Parse: "Queries per second:   50000.000000"
    // Parse: "Average Latency (s):  0.001234"
}
```

---

## Sub-Phase 5.7: NixOS Module Updates

### mq-cake-test.nix Additions

```nix
{
  # Test data generation
  mq-cake-gen-testdata = pkgs.writeShellApplication {
    name = "mq-cake-gen-testdata";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      mkdir -p /var/lib/mq-cake/www
      cd /var/lib/mq-cake/www

      # Generate test files
      dd if=/dev/urandom of=1k.bin bs=1K count=1
      dd if=/dev/urandom of=10k.bin bs=10K count=1
      dd if=/dev/urandom of=100k.bin bs=100K count=1
      dd if=/dev/urandom of=1m.bin bs=1M count=1
      dd if=/dev/urandom of=2m.bin bs=1M count=2
      dd if=/dev/urandom of=5m.bin bs=1M count=5
      dd if=/dev/urandom of=10m.bin bs=1M count=10

      echo "Generated test files:"
      ls -lh /var/lib/mq-cake/www/
    '';
  };

  # DNS query file generation
  mq-cake-gen-queries = pkgs.writeShellApplication {
    name = "mq-cake-gen-queries";
    text = ''
      mkdir -p /var/lib/mq-cake/dns

      # Generate 10000 query entries
      for i in $(seq -f "%04g" 1 9999); do
        echo "host''${i}.test.local A"
      done > /var/lib/mq-cake/dns/queries.txt

      echo "Generated $(wc -l < /var/lib/mq-cake/dns/queries.txt) queries"
    '';
  };

  # Start nginx in namespace
  mq-cake-nginx = pkgs.writeShellApplication {
    name = "mq-cake-nginx";
    runtimeInputs = [ pkgs.nginx pkgs.iproute2 ];
    text = ''
      ip netns exec ns-gen-b nginx -c /etc/mq-cake/nginx.conf -g "daemon off;"
    '';
  };

  # Start PowerDNS in namespace
  mq-cake-pdns = pkgs.writeShellApplication {
    name = "mq-cake-pdns";
    runtimeInputs = [ pkgs.pdns pkgs.iproute2 ];
    text = ''
      ip netns exec ns-gen-b pdns_server --config-dir=/etc/mq-cake/pdns --daemon=no
    '';
  };
}
```

---

## Sub-Phase 5.8: Test Matrix Extension

Add HTTP and DNS to the test matrix:

| Tool | Protocol | Metric | Connections/Flows |
|------|----------|--------|-------------------|
| wrk | HTTP | Requests/sec, Throughput | 1, 10, 100, 500 |
| dnsperf | DNS | QPS, Latency | 1, 10, 100, 500 |

**Extended Matrix**:
- 3 qdiscs × 4 flow counts × 6 tools = **72 test points**

---

## Sub-Phase 5.9: File Size Variations (HTTP)

Test different file sizes to measure throughput vs latency trade-offs:

| File | Expected Behavior |
|------|-------------------|
| 1k | High RPS, low throughput, latency-sensitive |
| 100k | Balanced RPS/throughput |
| 1m | Low RPS, high throughput |
| 10m | Very low RPS, sustained throughput |

**Config Option**:
```yaml
http:
  file_sizes: ["1k", "100k", "1m"]
  connections: [1, 10, 100, 500]
```

---

## Implementation Checklist

### Phase 5.1: Test Data
- [ ] Create `mq-cake-gen-testdata` script
- [ ] Generate files: 1k, 10k, 100k, 1m, 2m, 5m, 10m
- [ ] Verify file integrity

### Phase 5.2: Nginx
- [ ] Create nginx.conf for namespace
- [ ] Create `mq-cake-nginx` wrapper script
- [ ] Test nginx serves files from ns-gen-a

### Phase 5.3: wrk
- [ ] Add wrk tool to Go orchestrator
- [ ] Parse wrk output (RPS, throughput, latency)
- [ ] Add testdata for parser tests

### Phase 5.4: PowerDNS
- [ ] Create zone file for test.local
- [ ] Create pdns.conf for namespace
- [ ] Create `mq-cake-pdns` wrapper script
- [ ] Test DNS resolution from ns-gen-a

### Phase 5.5: dnsperf
- [ ] Create `mq-cake-gen-queries` script
- [ ] Add dnsperf tool to Go orchestrator
- [ ] Parse dnsperf output (QPS, latency)
- [ ] Add testdata for parser tests

### Phase 5.6: Integration
- [ ] Update config.yaml schema for http/dns options
- [ ] Add nginx/pdns to preflight checks
- [ ] Run full matrix with all 6 tools
- [ ] Update results export for new metrics

---

## Expected Results

| Qdisc | wrk RPS (100k) | dnsperf QPS | Notes |
|-------|----------------|-------------|-------|
| fq_codel | ~80k | ~50k | Baseline |
| cake | ~40k (degrades) | ~30k | CPU bottleneck |
| mq-cake | ~75k | ~48k | Near-baseline |

---

## Dependencies

| Package | Nix Attribute | Version |
|---------|---------------|---------|
| nginx | `pkgs.nginx` | 1.24+ |
| wrk | `pkgs.wrk` | 4.2+ |
| PowerDNS | `pkgs.pdns` | 4.8+ |
| dnsperf | `pkgs.dnsperf` | 2.11+ |

---

## References

- [wrk GitHub](https://github.com/wg/wrk)
- [dnsperf GitHub](https://github.com/DNS-OARC/dnsperf)
- [PowerDNS Documentation](https://doc.powerdns.com/)
- [nginx Performance Tuning](https://nginx.org/en/docs/http/ngx_http_core_module.html)
