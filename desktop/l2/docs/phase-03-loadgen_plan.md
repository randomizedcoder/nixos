# Phase 3: Load Generation - Implementation Plan

**Design Reference**: [phase-03-loadgen.md](./phase-03-loadgen.md)

**Prerequisites**: Phase 2 complete (can switch qdiscs without breaking connectivity)

**Overview**: Implement wrapper scripts for iperf2, iperf3, flent, and crusader to generate load through the DUT.

**Log File**: [phase-03-loadgen_log.md](./phase-03-loadgen_log.md) (update on completion of each sub-phase)

---

## Sub-Phase 3.1: Add Required Packages

### Steps

1. **Update `mq-cake-test.nix`** config section to include tools:
   ```nix
   config = mkIf cfg.enable {
     environment.systemPackages = [
       # Scripts (existing)
       setupScript teardownScript verifyScript qdiscScript statsScript resetScript

       # Load generation tools
       pkgs.iperf2
       pkgs.iperf3
       pkgs.flent
       pkgs.netperf
       pkgs.crusader
     ];

     boot.kernelModules = [ "sch_cake" "sch_fq_codel" ];
   };
   ```

2. **Rebuild and verify packages**:
   ```bash
   sudo nixos-rebuild switch
   which iperf
   which iperf3
   which flent
   which netperf
   which crusader
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 3.1.1 | `which iperf` | Path to iperf2 |
| 3.1.2 | `which iperf3` | Path to iperf3 |
| 3.1.3 | `which flent` | Path to flent |
| 3.1.4 | `which netperf` | Path to netperf |
| 3.1.5 | `which crusader` | Path to crusader |
| 3.1.6 | `iperf --version` | Version string |
| 3.1.7 | `iperf3 --version` | Version string |

### Definition of Done

- [ ] All five packages available in PATH
- [ ] Version commands work for each tool
- [ ] No missing dependencies
- [ ] Log file updated

---

## Sub-Phase 3.2: Implement `mq-cake-iperf2` Script

### Steps

1. **Add `iperf2Script`** to `mq-cake-test.nix`:
   ```nix
   iperf2Script = pkgs.writeShellApplication {
     name = "mq-cake-iperf2";
     runtimeInputs = with pkgs; [ iproute2 iperf2 coreutils ];
     text = ''
       set -euo pipefail

       FLOWS=''${1:-100}
       DURATION=''${2:-30}
       PORT=5001
       TARGET="10.2.0.2"

       echo "=== iperf2: $FLOWS TCP flows for ''${DURATION}s ==="
       echo "Target: $TARGET:$PORT"
       echo ""

       # Start server in ns-gen-b
       echo "Starting iperf2 server in ns-gen-b..."
       ip netns exec ns-gen-b iperf -s -p "$PORT" &>/dev/null &
       SERVER_PID=$!

       # Cleanup function
       cleanup() {
         echo "Stopping server (PID $SERVER_PID)..."
         kill "$SERVER_PID" 2>/dev/null || true
         wait "$SERVER_PID" 2>/dev/null || true
       }
       trap cleanup EXIT

       sleep 1

       # Verify server is listening
       if ! ip netns exec ns-gen-b ss -tlnp | grep -q ":$PORT"; then
         echo "ERROR: Server not listening on port $PORT"
         exit 1
       fi

       # Run client from ns-gen-a
       echo "Running iperf2 client from ns-gen-a..."
       echo ""
       ip netns exec ns-gen-a iperf -c "$TARGET" -p "$PORT" -P "$FLOWS" -t "$DURATION" -i 10

       echo ""
       echo "=== iperf2 complete ==="
     '';
   };
   ```

2. **Add to systemPackages**

3. **Test iperf2 wrapper**:
   ```bash
   sudo mq-cake-setup
   sudo mq-cake-qdisc fq_codel
   sudo mq-cake-iperf2 10 10  # 10 flows, 10 seconds
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 3.2.1 | `which mq-cake-iperf2` | Path returned |
| 3.2.2 | `sudo mq-cake-iperf2 1 5` | Single flow completes |
| 3.2.3 | `sudo mq-cake-iperf2 10 10` | 10 flows complete |
| 3.2.4 | `sudo mq-cake-iperf2 100 10` | 100 flows complete |
| 3.2.5 | Output shows throughput | Mbits/sec or Gbits/sec in output |
| 3.2.6 | Server cleaned up after test | No orphan iperf processes |

### Definition of Done

- [ ] `mq-cake-iperf2` command available
- [ ] Default: 100 flows, 30 seconds
- [ ] Arguments work: flows, duration
- [ ] Server started and stopped cleanly
- [ ] Throughput displayed in output
- [ ] No zombie processes after completion
- [ ] Log file updated

---

## Sub-Phase 3.3: Implement `mq-cake-iperf3` Script

### Steps

1. **Add `iperf3Script`** to `mq-cake-test.nix`:
   ```nix
   iperf3Script = pkgs.writeShellApplication {
     name = "mq-cake-iperf3";
     runtimeInputs = with pkgs; [ iproute2 iperf3 coreutils jq ];
     text = ''
       set -euo pipefail

       FLOWS=''${1:-10}
       DURATION=''${2:-30}
       JSON=''${3:-no}
       PORT=5201
       TARGET="10.2.0.2"

       # iperf3 max parallel streams is ~128
       if [[ $FLOWS -gt 128 ]]; then
         echo "WARNING: iperf3 limited to 128 parallel streams, capping"
         FLOWS=128
       fi

       echo "=== iperf3: $FLOWS TCP flows for ''${DURATION}s ==="
       echo "Target: $TARGET:$PORT"
       echo ""

       # Start server in ns-gen-b
       echo "Starting iperf3 server in ns-gen-b..."
       ip netns exec ns-gen-b iperf3 -s -p "$PORT" &>/dev/null &
       SERVER_PID=$!

       cleanup() {
         kill "$SERVER_PID" 2>/dev/null || true
         wait "$SERVER_PID" 2>/dev/null || true
       }
       trap cleanup EXIT

       sleep 1

       # Run client from ns-gen-a
       echo "Running iperf3 client from ns-gen-a..."
       echo ""

       if [[ "$JSON" == "json" ]]; then
         ip netns exec ns-gen-a iperf3 -c "$TARGET" -p "$PORT" -P "$FLOWS" -t "$DURATION" --json
       else
         ip netns exec ns-gen-a iperf3 -c "$TARGET" -p "$PORT" -P "$FLOWS" -t "$DURATION"
       fi

       echo ""
       echo "=== iperf3 complete ==="
     '';
   };
   ```

2. **Add to systemPackages**

3. **Test iperf3 wrapper**:
   ```bash
   sudo mq-cake-iperf3 10 10
   sudo mq-cake-iperf3 10 10 json | jq '.end.sum_received.bits_per_second'
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 3.3.1 | `which mq-cake-iperf3` | Path returned |
| 3.3.2 | `sudo mq-cake-iperf3 1 5` | Single flow completes |
| 3.3.3 | `sudo mq-cake-iperf3 10 10` | 10 flows complete |
| 3.3.4 | `sudo mq-cake-iperf3 200 5` | Capped to 128, completes |
| 3.3.5 | `sudo mq-cake-iperf3 10 5 json \| jq .` | Valid JSON output |
| 3.3.6 | JSON includes bits_per_second | Throughput in JSON |

### Definition of Done

- [ ] `mq-cake-iperf3` command available
- [ ] Default: 10 flows, 30 seconds
- [ ] JSON output mode works
- [ ] Flow count capped at 128 with warning
- [ ] Server cleanup works
- [ ] Log file updated

---

## Sub-Phase 3.4: Implement `mq-cake-flent` Script

### Steps

1. **Add `flentScript`** to `mq-cake-test.nix`:
   ```nix
   flentScript = pkgs.writeShellApplication {
     name = "mq-cake-flent";
     runtimeInputs = with pkgs; [ iproute2 flent netperf coreutils ];
     text = ''
       set -euo pipefail

       DURATION=''${1:-60}
       TEST=''${2:-rrul}
       TARGET="10.2.0.2"
       OUTPUT_DIR=''${MQ_CAKE_OUTPUT:-/tmp/mq-cake-results}

       mkdir -p "$OUTPUT_DIR"

       TIMESTAMP=$(date +%Y%m%d-%H%M%S)
       OUTPUT_FILE="$OUTPUT_DIR/flent-$TEST-$TIMESTAMP"

       echo "=== flent $TEST test for ''${DURATION}s ==="
       echo "Target: $TARGET"
       echo "Output: $OUTPUT_FILE"
       echo ""

       # Start netserver in ns-gen-b (required by flent)
       echo "Starting netserver in ns-gen-b..."
       ip netns exec ns-gen-b netserver -p 12865 &>/dev/null &
       SERVER_PID=$!

       cleanup() {
         kill "$SERVER_PID" 2>/dev/null || true
         wait "$SERVER_PID" 2>/dev/null || true
       }
       trap cleanup EXIT

       sleep 2

       # Run flent from ns-gen-a
       echo "Running flent $TEST..."
       echo ""

       ip netns exec ns-gen-a flent "$TEST" \
         -l "$DURATION" \
         -H "$TARGET" \
         --local-bind=10.1.0.2 \
         -o "$OUTPUT_FILE.png" \
         -D "$OUTPUT_FILE.dat"

       echo ""
       echo "=== flent complete ==="
       echo "Results:"
       echo "  Plot: $OUTPUT_FILE.png"
       echo "  Data: $OUTPUT_FILE.dat"
     '';
   };
   ```

2. **Add to systemPackages**

3. **Test flent wrapper**:
   ```bash
   sudo mq-cake-flent 30
   ls /tmp/mq-cake-results/
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 3.4.1 | `which mq-cake-flent` | Path returned |
| 3.4.2 | `sudo mq-cake-flent 20` | RRUL test completes |
| 3.4.3 | `ls /tmp/mq-cake-results/flent-*.png` | PNG file created |
| 3.4.4 | `ls /tmp/mq-cake-results/flent-*.dat` | Data file created |
| 3.4.5 | `sudo mq-cake-flent 20 tcp_download` | Alternative test works |

### Definition of Done

- [ ] `mq-cake-flent` command available
- [ ] Default: RRUL test, 60 seconds
- [ ] Creates PNG and DAT output files
- [ ] Output directory configurable via MQ_CAKE_OUTPUT
- [ ] Netserver started and cleaned up
- [ ] Log file updated

---

## Sub-Phase 3.5: Implement `mq-cake-crusader` Script

### Steps

1. **Add `crusaderScript`** to `mq-cake-test.nix`:
   ```nix
   crusaderScript = pkgs.writeShellApplication {
     name = "mq-cake-crusader";
     runtimeInputs = with pkgs; [ iproute2 crusader coreutils ];
     text = ''
       set -euo pipefail

       DURATION=''${1:-30}
       TARGET="10.2.0.2"

       echo "=== crusader latency test for ''${DURATION}s ==="
       echo "Target: $TARGET"
       echo ""

       # Start crusader server in ns-gen-b
       echo "Starting crusader server in ns-gen-b..."
       ip netns exec ns-gen-b crusader serve &>/dev/null &
       SERVER_PID=$!

       cleanup() {
         kill "$SERVER_PID" 2>/dev/null || true
         wait "$SERVER_PID" 2>/dev/null || true
       }
       trap cleanup EXIT

       # Crusader server takes longer to initialize
       sleep 3

       # Run crusader client from ns-gen-a
       echo "Running crusader client..."
       echo ""

       ip netns exec ns-gen-a crusader remote "$TARGET" --duration "$DURATION"

       echo ""
       echo "=== crusader complete ==="
     '';
   };
   ```

2. **Add to systemPackages**

3. **Test crusader wrapper**:
   ```bash
   sudo mq-cake-crusader 20
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 3.5.1 | `which mq-cake-crusader` | Path returned |
| 3.5.2 | `sudo mq-cake-crusader 10` | Test completes |
| 3.5.3 | Output shows latency | "latency" in output |
| 3.5.4 | Server cleaned up | No orphan crusader processes |

### Definition of Done

- [ ] `mq-cake-crusader` command available
- [ ] Default: 30 seconds
- [ ] Latency measurements displayed
- [ ] Server startup wait adequate (3s)
- [ ] Log file updated

---

## Sub-Phase 3.6: Implement `mq-cake-load` Wrapper

### Steps

1. **Add `loadScript`** to `mq-cake-test.nix`:
   ```nix
   loadScript = pkgs.writeShellApplication {
     name = "mq-cake-load";
     runtimeInputs = with pkgs; [ iproute2 iperf2 iperf3 flent netperf crusader coreutils ];
     text = ''
       set -euo pipefail

       TOOLS=''${1:-"iperf2"}
       FLOWS=''${2:-100}
       DURATION=''${3:-30}

       echo "=== MQ-CAKE Load Generation ==="
       echo "Tools: $TOOLS"
       echo "Flows: $FLOWS"
       echo "Duration: ''${DURATION}s"
       echo ""

       # Parse comma-separated tools
       IFS=',' read -ra TOOL_ARRAY <<< "$TOOLS"

       for tool in "''${TOOL_ARRAY[@]}"; do
         echo "----------------------------------------"
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
             echo "----------------------------------------"
             mq-cake-iperf3 "$FLOWS" "$DURATION"
             echo "----------------------------------------"
             mq-cake-flent "$DURATION"
             echo "----------------------------------------"
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
   ```

2. **Add to systemPackages**

3. **Test wrapper**:
   ```bash
   sudo mq-cake-load iperf2 50 10
   sudo mq-cake-load "iperf2,iperf3" 10 10
   ```

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 3.6.1 | `which mq-cake-load` | Path returned |
| 3.6.2 | `sudo mq-cake-load iperf2 10 5` | iperf2 runs |
| 3.6.3 | `sudo mq-cake-load "iperf2,iperf3" 10 5` | Both run sequentially |
| 3.6.4 | `sudo mq-cake-load all 10 10` | All four tools run |
| 3.6.5 | `sudo mq-cake-load invalid 10 5` | Error message |

### Definition of Done

- [ ] `mq-cake-load` command available
- [ ] Single tool invocation works
- [ ] Comma-separated tool list works
- [ ] `all` runs all four tools
- [ ] Invalid tool rejected with error
- [ ] Log file updated

---

## Sub-Phase 3.7: Integration Test - Per-Qdisc Load Testing

### Steps

1. **Fresh environment**:
   ```bash
   sudo mq-cake-teardown
   sudo mq-cake-setup
   sudo mq-cake-verify
   ```

2. **Test each tool with each qdisc**:
   ```bash
   for qdisc in fq_codel cake mq-cake; do
     echo "========================================"
     echo "Testing with $qdisc"
     echo "========================================"
     sudo mq-cake-qdisc $qdisc
     sudo mq-cake-stats

     # Quick test of each tool
     sudo mq-cake-iperf2 10 10
     sudo mq-cake-iperf3 10 10
     sudo mq-cake-flent 20
     sudo mq-cake-crusader 10

     sudo mq-cake-stats
     echo ""
   done
   ```

3. **High flow count test (key validation)**:
   ```bash
   for qdisc in fq_codel cake mq-cake; do
     echo "High flow test: $qdisc"
     sudo mq-cake-qdisc $qdisc
     sudo mq-cake-iperf2 500 30
     # Monitor CPU during test (in another terminal):
     # mpstat -P ALL 1
   done
   ```

4. **Record performance baselines**:
   - Throughput per qdisc at 100 flows
   - Throughput per qdisc at 500 flows
   - Latency (crusader) per qdisc

### Tests

| Test ID | Command | Expected Result |
|---------|---------|-----------------|
| 3.7.1 | iperf2 100 flows with each qdisc | All complete, throughput >8 Gbps |
| 3.7.2 | iperf3 10 flows with each qdisc | All complete |
| 3.7.3 | flent RRUL with each qdisc | Creates output files |
| 3.7.4 | crusader with each qdisc | Latency reported |
| 3.7.5 | 500-flow test with mq-cake | No single core at 100% |
| 3.7.6 | 500-flow test with cake | May show single core saturation |

### Definition of Done

- [ ] All tools work with all qdiscs
- [ ] No crashes or hangs during tests
- [ ] Server processes cleaned up after each test
- [ ] Performance baselines recorded in log
- [ ] CPU distribution difference observed between cake and mq-cake
- [ ] Log file updated with performance data

---

## Phase 3 Complete Checklist

Before proceeding to Phase 4, verify:

- [ ] `mq-cake-iperf2` works with configurable flows and duration
- [ ] `mq-cake-iperf3` works with JSON output option
- [ ] `mq-cake-flent` creates PNG and DAT output files
- [ ] `mq-cake-crusader` reports latency
- [ ] `mq-cake-load` wrapper runs tools individually and combined
- [ ] All tools work with all three qdiscs
- [ ] No orphan processes after tests complete
- [ ] Performance baselines documented
- [ ] Log file complete with all sub-phase timestamps

---

## Design Reference Summary

From [phase-03-loadgen.md](./phase-03-loadgen.md):

- **iperf2**: TCP/UDP, 100+ parallel flows via `-P`
- **iperf3**: JSON output, max ~128 streams
- **flent**: RRUL (Realtime Response Under Load), needs netserver
- **crusader**: Modern latency tester, needs longer startup

**IP Addresses**:
- Client (ns-gen-a): 10.1.0.2
- Server (ns-gen-b): 10.2.0.2
- DUT: 10.1.0.1, 10.2.0.1

---

## Next Phase

Proceed to [Phase 4: Orchestrator](./phase-04-orchestrator_plan.md) once all checks pass.
