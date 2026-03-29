# Phase 3: Load Generation

**Goal**: Generate TCP/UDP load with many parallel flows to stress-test the qdisc.

**Prerequisites**: [Phase 2](./phase-02-qdisc.md) complete (can switch qdiscs).

**Outcome**: Scripts for each tool (`mq-cake-iperf2`, `mq-cake-iperf3`, `mq-cake-flent`, `mq-cake-crusader`) plus a wrapper (`mq-cake-load`).

---

## Tools Overview

| Tool | Purpose | Key Feature |
|------|---------|-------------|
| iperf2 | TCP/UDP throughput | `-P 100` for 100+ parallel flows |
| iperf3 | TCP/UDP with JSON | Better stats, max ~128 flows |
| flent | RRUL latency-under-load | Measures bufferbloat |
| crusader | Modern latency tester | Latency histograms, throughput+latency |

### Crusader Details

[Crusader](https://github.com/Zoxc/crusader) measures throughput, latency, and packet loss during traffic bursts.

**Ports**: TCP/UDP 35481 (data), TCP 35482 (remote web UI)

**CLI Commands**:
- `crusader serve` - Start server (listens for client connections)
- `crusader test <server-ip>` - Run test from client
- `crusader remote` - Start web UI for remote control (not used in scripts)

**Key Options for `crusader test`**:
- `--load-duration <SECONDS>` - Traffic generation time per phase (default: 10)
- `--streams <N>` - TCP connections per direction (default: 8)
- `--download` / `--upload` / `--bidirectional` - Test type (default: all three phases)

---

## Nix Scripts

```nix
# Add to mq-cake-test.nix
let
  x710_p0 = "enp35s0f0np0";
  x710_p1 = "enp35s0f1np1";

  # mq-cake-iperf2: High flow count TCP/UDP testing
  iperf2Script = pkgs.writeShellApplication {
    name = "mq-cake-iperf2";
    runtimeInputs = with pkgs; [ iproute2 iperf2 ];
    text = ''
      set -euo pipefail

      FLOWS=''${1:-100}
      DURATION=''${2:-30}
      PORT=5001
      TARGET="10.2.0.2"

      echo "=== iperf2: $FLOWS TCP flows for ''${DURATION}s ==="

      # Start server in ns-gen-b
      ip netns exec ns-gen-b iperf -s -p $PORT &>/dev/null &
      SERVER_PID=$!
      sleep 1

      # Run client from ns-gen-a
      ip netns exec ns-gen-a iperf -c $TARGET -p $PORT -P "$FLOWS" -t "$DURATION" -i 10

      # Cleanup
      kill $SERVER_PID 2>/dev/null || true
    '';
  };

  # mq-cake-iperf3: JSON output for parsing
  iperf3Script = pkgs.writeShellApplication {
    name = "mq-cake-iperf3";
    runtimeInputs = with pkgs; [ iproute2 iperf3 ];
    text = ''
      set -euo pipefail

      FLOWS=''${1:-10}
      DURATION=''${2:-30}
      PORT=5201
      TARGET="10.2.0.2"

      echo "=== iperf3: $FLOWS TCP flows for ''${DURATION}s ==="

      # Start server in ns-gen-b
      ip netns exec ns-gen-b iperf3 -s -p $PORT &>/dev/null &
      SERVER_PID=$!
      sleep 1

      # Run client from ns-gen-a (iperf3 max ~128 streams)
      ip netns exec ns-gen-a iperf3 -c $TARGET -p $PORT -P "$FLOWS" -t "$DURATION" --json

      # Cleanup
      kill $SERVER_PID 2>/dev/null || true
    '';
  };

  # mq-cake-flent: RRUL (Realtime Response Under Load) test
  flentScript = pkgs.writeShellApplication {
    name = "mq-cake-flent";
    runtimeInputs = with pkgs; [ iproute2 flent netperf ];
    text = ''
      set -euo pipefail

      DURATION=''${1:-60}
      TARGET="10.2.0.2"
      OUTPUT_DIR=''${MQ_CAKE_OUTPUT:-/tmp/mq-cake-results}

      mkdir -p "$OUTPUT_DIR"

      echo "=== flent RRUL test for ''${DURATION}s ==="

      # Start netserver in ns-gen-b (required by flent)
      ip netns exec ns-gen-b netserver -p 12865 &>/dev/null &
      SERVER_PID=$!
      sleep 1

      # Run flent from ns-gen-a
      ip netns exec ns-gen-a flent rrul \
        -l "$DURATION" \
        -H "$TARGET" \
        --local-bind=10.1.0.2 \
        -o "$OUTPUT_DIR/flent-rrul-$(date +%Y%m%d-%H%M%S).png"

      # Cleanup
      kill $SERVER_PID 2>/dev/null || true

      echo "Results saved to $OUTPUT_DIR"
    '';
  };

  # mq-cake-crusader: Modern latency measurement
  # Crusader CLI: https://github.com/Zoxc/crusader/blob/master/docs/CLI.md
  #   Server: crusader serve
  #   Client: crusader test <server-ip> [OPTIONS]
  #     --load-duration <SECONDS>  Traffic generation duration (default: 10)
  #     --streams <N>              TCP connections per direction (default: 8)
  #     --download/--upload/--bidirectional  Test type
  crusaderScript = pkgs.writeShellApplication {
    name = "mq-cake-crusader";
    runtimeInputs = with pkgs; [ iproute2 crusader ];
    text = ''
      set -euo pipefail

      DURATION=''${1:-10}
      TARGET="10.2.0.2"

      echo "=== crusader latency test for ''${DURATION}s ==="

      # Start crusader server in ns-gen-b
      ip netns exec ns-gen-b crusader serve &>/dev/null &
      SERVER_PID=$!
      sleep 3  # Crusader server needs time to initialize

      # Run crusader client from ns-gen-a
      # Uses 'test' subcommand (not 'remote' which is for web UI)
      ip netns exec ns-gen-a crusader test "$TARGET" --load-duration "$DURATION"

      # Cleanup
      kill $SERVER_PID 2>/dev/null || true
    '';
  };

  # mq-cake-load: Wrapper to run multiple tools
  loadScript = pkgs.writeShellApplication {
    name = "mq-cake-load";
    runtimeInputs = with pkgs; [ iproute2 iperf2 iperf3 flent netperf crusader ];
    text = ''
      set -euo pipefail

      TOOLS=''${1:-"iperf2"}  # Comma-separated: iperf2,iperf3,flent,crusader
      FLOWS=''${2:-100}
      DURATION=''${3:-30}

      echo "=== MQ-CAKE Load Generation ==="
      echo "Tools: $TOOLS"
      echo "Flows: $FLOWS"
      echo "Duration: ''${DURATION}s"
      echo ""

      # Parse tools
      IFS=',' read -ra TOOL_ARRAY <<< "$TOOLS"

      for tool in "''${TOOL_ARRAY[@]}"; do
        case "$tool" in
          iperf2)
            mq-cake-iperf2 "$FLOWS" "$DURATION"
            ;;
          iperf3)
            mq-cake-iperf3 "$FLOWS" "$DURATION"
            ;;
          flent)
            mq-cake-flent "$DURATION"
            ;;
          crusader)
            mq-cake-crusader "$DURATION"
            ;;
          all)
            mq-cake-iperf2 "$FLOWS" "$DURATION"
            mq-cake-iperf3 "$FLOWS" "$DURATION"
            mq-cake-flent "$DURATION"
            mq-cake-crusader "$DURATION"
            ;;
          *)
            echo "Unknown tool: $tool"
            echo "Supported: iperf2, iperf3, flent, crusader, all"
            exit 1
            ;;
        esac
        echo ""
      done

      echo "=== Load generation complete ==="
    '';
  };

in
{
  environment.systemPackages = [
    iperf2Script
    iperf3Script
    flentScript
    crusaderScript
    loadScript

    # Tools themselves
    pkgs.iperf2
    pkgs.iperf3
    pkgs.flent
    pkgs.netperf
    pkgs.crusader
  ];
}
```

---

## Usage

### Individual Tools

```bash
# iperf2: 100 TCP flows for 30 seconds
sudo mq-cake-iperf2 100 30

# iperf3: 10 flows for 60 seconds (JSON output)
sudo mq-cake-iperf3 10 60

# flent: RRUL test for 60 seconds
sudo mq-cake-flent 60

# crusader: Latency test for 30 seconds
sudo mq-cake-crusader 30
```

### Wrapper Script

```bash
# Run just iperf2
sudo mq-cake-load iperf2 100 30

# Run multiple tools sequentially
sudo mq-cake-load "iperf2,flent" 100 60

# Run all tools
sudo mq-cake-load all 100 30
```

---

## Test Scenarios

### Scenario 1: Baseline (fq_codel)

```bash
sudo mq-cake-qdisc fq_codel
sudo mq-cake-iperf2 100 30
```

### Scenario 2: Single-queue CAKE

```bash
sudo mq-cake-qdisc cake
sudo mq-cake-iperf2 100 30
```

### Scenario 3: Multi-queue CAKE (what we're proving)

```bash
sudo mq-cake-qdisc mq-cake
sudo mq-cake-iperf2 500 60
```

### Scenario 4: Latency under load

```bash
sudo mq-cake-qdisc mq-cake

# Terminal 1: Start background load
sudo mq-cake-iperf2 100 120 &

# Terminal 2: Measure latency
sudo mq-cake-flent 60
```

---

## Expected Results

### TCP Throughput (100 flows)

| Qdisc | Expected Aggregate |
|-------|-------------------|
| fq_codel | ~9 Gbps |
| cake | ~8-9 Gbps (may show CPU pressure) |
| mq-cake | ~9+ Gbps (scales better) |

### Latency Under Load (flent RRUL)

| Qdisc | Expected P99 Latency |
|-------|---------------------|
| fq_codel | <50ms |
| cake | <50ms |
| mq-cake | <50ms (with better throughput) |

---

## Checking Results

### Qdisc Statistics

```bash
# View drops, backlog, requeues
ip netns exec ns-dut tc -s qdisc show dev enp66s0f0
ip netns exec ns-dut tc -s qdisc show dev enp66s0f1
```

### CPU Usage During Test

```bash
# Watch per-core CPU usage
mpstat -P ALL 1
```

Key insight: With cake, you may see one core at 100%. With mq-cake, load should spread across cores.

---

## Troubleshooting

### iperf2 "connect failed: Connection refused"

Server not running. Check:
```bash
ip netns exec ns-gen-b ss -tlnp | grep 5001
```

### flent "netperf not found"

Ensure netperf is in runtimeInputs and netserver is started.

### Low throughput

1. Check qdisc drops: `tc -s qdisc show`
2. Check CPU usage: `mpstat -P ALL 1`
3. Check NIC ring buffers: `ethtool -g enp66s0f0`

### crusader fails to connect

Crusader server needs time to start. Increase sleep before client.

---

## Next Phase

Once you can generate load with all tools, proceed to [Phase 4: Orchestrator](./phase-04-orchestrator.md) for automated test matrix execution.
