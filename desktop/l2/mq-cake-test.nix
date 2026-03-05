# mq-cake-test.nix
#
# MQ-CAKE Performance Testing Framework
# Phase 1: Namespace setup scripts
# Phase 2: Qdisc configuration scripts
# Phase 3: Load generation scripts (iperf2, iperf3, flent, crusader)
# Phase 5: HTTP/DNS load generation (nginx, wrk, PowerDNS, dnsperf)
#
# Design References:
#   - docs/phase-01-namespaces.md
#   - docs/phase-02-qdisc.md
#   - docs/phase-03-loadgen.md
#   - docs/phase-05-http-dns-loadgen.md
# Implementation Plans:
#   - docs/phase-01-namespaces_plan.md
#   - docs/phase-02-qdisc_plan.md
#   - docs/phase-03-loadgen_plan.md
#   - docs/phase-05-http-dns_plan.md

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.mq-cake-test;

  # X710 interfaces (load generators)
  x710_p0 = "enp35s0f0np0";  # ns-gen-a (client)
  x710_p1 = "enp35s0f1np1";  # ns-gen-b (server)

  # 82599ES interfaces (DUT) - pinned by udev-nic-names.nix
  ixgbe_p0 = "ixgbe0";    # DUT ingress
  ixgbe_p1 = "ixgbe1";    # DUT egress

  # mq-cake-setup: Create namespaces and configure networking
  setupScript = pkgs.writeShellApplication {
    name = "mq-cake-setup";
    runtimeInputs = with pkgs; [ iproute2 procps ];
    text = ''
      set -euo pipefail

      echo "=== MQ-CAKE Test Environment Setup ==="

      # Create namespaces
      echo "Creating namespaces..."
      ip netns add ns-gen-a 2>/dev/null || true
      ip netns add ns-gen-b 2>/dev/null || true
      ip netns add ns-dut 2>/dev/null || true

      # Move interfaces to namespaces
      echo "Moving interfaces..."
      ip link set ${x710_p0} netns ns-gen-a 2>/dev/null || true
      ip link set ${x710_p1} netns ns-gen-b 2>/dev/null || true
      ip link set ${ixgbe_p0} netns ns-dut 2>/dev/null || true
      ip link set ${ixgbe_p1} netns ns-dut 2>/dev/null || true

      # Configure ns-gen-a (client)
      echo "Configuring ns-gen-a..."
      ip netns exec ns-gen-a bash -c "
        ip link set lo up
        ip link set ${x710_p0} up
        ip addr flush dev ${x710_p0}
        ip addr add 10.1.0.2/24 dev ${x710_p0}
        ip route add default via 10.1.0.1
      "

      # Configure ns-gen-b (server)
      echo "Configuring ns-gen-b..."
      ip netns exec ns-gen-b bash -c "
        ip link set lo up
        ip link set ${x710_p1} up
        ip addr flush dev ${x710_p1}
        ip addr add 10.2.0.2/24 dev ${x710_p1}
        ip route add default via 10.2.0.1
      "

      # Configure ns-dut (forwarding router)
      echo "Configuring ns-dut..."
      ip netns exec ns-dut bash -c "
        ip link set lo up
        ip link set ${ixgbe_p0} up
        ip link set ${ixgbe_p1} up
        ip addr flush dev ${ixgbe_p0}
        ip addr flush dev ${ixgbe_p1}
        ip addr add 10.1.0.1/24 dev ${ixgbe_p0}
        ip addr add 10.2.0.1/24 dev ${ixgbe_p1}
        sysctl -qw net.ipv4.ip_forward=1
      "

      echo ""
      echo "=== Setup Complete ==="
      echo "  ns-gen-a: 10.1.0.2/24 (client)"
      echo "  ns-gen-b: 10.2.0.2/24 (server)"
      echo "  ns-dut:   10.1.0.1/24, 10.2.0.1/24 (forwarding)"
      echo ""
      echo "Verify with: sudo mq-cake-verify"
    '';
  };

  # mq-cake-teardown: Remove namespaces and restore interfaces
  teardownScript = pkgs.writeShellApplication {
    name = "mq-cake-teardown";
    runtimeInputs = with pkgs; [ iproute2 ];
    text = ''
      set -euo pipefail

      echo "=== MQ-CAKE Test Environment Teardown ==="

      # Move interfaces back to default namespace (PID 1)
      echo "Restoring interfaces..."
      ip netns exec ns-gen-a ip link set ${x710_p0} netns 1 2>/dev/null || true
      ip netns exec ns-gen-b ip link set ${x710_p1} netns 1 2>/dev/null || true
      ip netns exec ns-dut ip link set ${ixgbe_p0} netns 1 2>/dev/null || true
      ip netns exec ns-dut ip link set ${ixgbe_p1} netns 1 2>/dev/null || true

      # Delete namespaces
      echo "Deleting namespaces..."
      ip netns delete ns-gen-a 2>/dev/null || true
      ip netns delete ns-gen-b 2>/dev/null || true
      ip netns delete ns-dut 2>/dev/null || true

      # Bring interfaces back up in default namespace
      ip link set ${x710_p0} up 2>/dev/null || true
      ip link set ${x710_p1} up 2>/dev/null || true
      ip link set ${ixgbe_p0} up 2>/dev/null || true
      ip link set ${ixgbe_p1} up 2>/dev/null || true

      echo "Teardown complete."
    '';
  };

  # mq-cake-verify: Test connectivity
  verifyScript = pkgs.writeShellApplication {
    name = "mq-cake-verify";
    runtimeInputs = with pkgs; [ iproute2 iputils ];
    text = ''
      FAILED=0

      pass() { printf '\033[0;32mPASS\033[0m\n'; }
      fail() { printf '\033[0;31mFAIL\033[0m\n'; FAILED=1; }

      check() {
        if "$@" &>/dev/null; then
          pass
        else
          fail
        fi
      }

      echo "=== MQ-CAKE Environment Verification ==="
      echo ""

      printf "1. Namespaces exist (3): "
      if [[ $(ip netns list | wc -l) -eq 3 ]]; then pass; else fail; fi

      printf "2. ns-gen-a has ${x710_p0}: "
      check ip netns exec ns-gen-a ip link show ${x710_p0}

      printf "3. ns-gen-b has ${x710_p1}: "
      check ip netns exec ns-gen-b ip link show ${x710_p1}

      printf "4. ns-dut has ${ixgbe_p0}: "
      check ip netns exec ns-dut ip link show ${ixgbe_p0}

      printf "5. ns-dut has ${ixgbe_p1}: "
      check ip netns exec ns-dut ip link show ${ixgbe_p1}

      printf "6. DUT forwarding enabled: "
      if [[ $(ip netns exec ns-dut sysctl -n net.ipv4.ip_forward) -eq 1 ]]; then pass; else fail; fi

      printf "7. ns-gen-a -> DUT (10.1.0.1): "
      check ip netns exec ns-gen-a ping -c 1 -W 2 10.1.0.1

      printf "8. ns-gen-b -> DUT (10.2.0.1): "
      check ip netns exec ns-gen-b ping -c 1 -W 2 10.2.0.1

      printf "9. End-to-end A->B (10.2.0.2): "
      check ip netns exec ns-gen-a ping -c 1 -W 2 10.2.0.2

      printf "10. End-to-end B->A (10.1.0.2): "
      check ip netns exec ns-gen-b ping -c 1 -W 2 10.1.0.2

      echo ""
      if [[ $FAILED -eq 0 ]]; then
        echo "=== All Checks Passed ==="
        exit 0
      else
        echo "=== Some Checks Failed ==="
        exit 1
      fi
    '';
  };

  # mq-cake-qdisc: Configure qdisc on DUT interfaces
  qdiscScript = pkgs.writeShellApplication {
    name = "mq-cake-qdisc";
    runtimeInputs = with pkgs; [ iproute2 coreutils ];
    text = ''
      set -euo pipefail

      QDISC=''${1:-fq_codel}
      # Bandwidth: CLI arg > env var > default
      BANDWIDTH=''${2:-''${MQ_CAKE_BANDWIDTH:-10gbit}}

      echo "=== MQ-CAKE Qdisc Configuration ==="
      echo "Qdisc: $QDISC"
      echo "Bandwidth: $BANDWIDTH"
      echo ""
      echo "Usage: mq-cake-qdisc <qdisc> [bandwidth]"
      echo "       Example: mq-cake-qdisc cake 1gbit"
      echo ""

      apply_fq_codel() {
        local iface=$1
        ip netns exec ns-dut tc qdisc replace dev "$iface" root fq_codel
        echo "  $iface: fq_codel applied"
      }

      apply_cake() {
        local iface=$1
        ip netns exec ns-dut tc qdisc replace dev "$iface" root cake \
          bandwidth "$BANDWIDTH" diffserv4 nat wash split-gso
        echo "  $iface: cake applied (bandwidth=$BANDWIDTH)"
      }

      apply_mq_cake() {
        local iface=$1
        # Try native cake_mq first (from mq-cake-module.nix)
        if ip netns exec ns-dut tc qdisc replace dev "$iface" root cake_mq \
            bandwidth "$BANDWIDTH" diffserv4 nat wash split-gso 2>/dev/null; then
          echo "  $iface: mq-cake (cake_mq) applied"
        else
          echo "  WARNING: cake_mq not available, falling back to mq + cake child"
          # Fallback: mq with cake per-queue
          # First, set up mq with a known handle
          ip netns exec ns-dut tc qdisc replace dev "$iface" root handle 1: mq
          # Get queue count
          local queues
          queues=$(ip netns exec ns-dut ls /sys/class/net/"$iface"/queues/ | grep -c tx-)
          # Add cake to each queue (parent 1:1, 1:2, etc.)
          for ((i=1; i<=queues; i++)); do
            ip netns exec ns-dut tc qdisc add dev "$iface" parent "1:$i" cake \
              bandwidth "$BANDWIDTH" diffserv4 nat wash split-gso
          done
          echo "  $iface: mq + cake child qdiscs applied ($queues queues)"
        fi
      }

      case "$QDISC" in
        fq_codel)
          apply_fq_codel ${ixgbe_p0}
          apply_fq_codel ${ixgbe_p1}
          ;;
        cake)
          apply_cake ${ixgbe_p0}
          apply_cake ${ixgbe_p1}
          ;;
        mq-cake|cake_mq)
          apply_mq_cake ${ixgbe_p0}
          apply_mq_cake ${ixgbe_p1}
          ;;
        *)
          echo "Unknown qdisc: $QDISC"
          echo "Supported: fq_codel, cake, mq-cake"
          exit 1
          ;;
      esac

      echo ""
      echo "Current qdisc on ${ixgbe_p0}:"
      ip netns exec ns-dut tc qdisc show dev ${ixgbe_p0} | head -1
      echo "Current qdisc on ${ixgbe_p1}:"
      ip netns exec ns-dut tc qdisc show dev ${ixgbe_p1} | head -1
    '';
  };

  # mq-cake-stats: Show qdisc statistics
  statsScript = pkgs.writeShellApplication {
    name = "mq-cake-stats";
    runtimeInputs = with pkgs; [ iproute2 ];
    text = ''
      set -euo pipefail

      IFACE=''${1:-${ixgbe_p0}}

      echo "=== Qdisc Statistics: $IFACE ==="
      echo ""

      echo "--- Qdisc Configuration ---"
      ip netns exec ns-dut tc qdisc show dev "$IFACE"
      echo ""

      echo "--- Qdisc Statistics ---"
      ip netns exec ns-dut tc -s qdisc show dev "$IFACE"
      echo ""

      echo "--- Class Statistics (if any) ---"
      ip netns exec ns-dut tc -s class show dev "$IFACE" 2>/dev/null || echo "No classes"
    '';
  };

  # mq-cake-reset: Reset qdiscs to default
  resetScript = pkgs.writeShellApplication {
    name = "mq-cake-reset";
    runtimeInputs = with pkgs; [ iproute2 ];
    text = ''
      set -euo pipefail

      echo "=== Resetting Qdiscs to Default ==="

      for iface in ${ixgbe_p0} ${ixgbe_p1}; do
        echo "Resetting $iface..."
        ip netns exec ns-dut tc qdisc del dev "$iface" root 2>/dev/null || true
        # Kernel will use pfifo_fast or fq_codel as default
      done

      echo ""
      echo "Current qdiscs:"
      ip netns exec ns-dut tc qdisc show dev ${ixgbe_p0} | head -1
      ip netns exec ns-dut tc qdisc show dev ${ixgbe_p1} | head -1
    '';
  };

  # ============================================================================
  # Phase 3: Load Generation Scripts
  # ============================================================================

  # mq-cake-iperf2: Run iperf2 TCP test through DUT
  iperf2Script = pkgs.writeShellApplication {
    name = "mq-cake-iperf2";
    runtimeInputs = with pkgs; [ iproute2 iperf2 coreutils inetutils ];
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
      ip netns exec ns-gen-a iperf -c "$TARGET" -p "$PORT" -P "$FLOWS" -t "$DURATION" -i 2

      echo ""
      echo "=== iperf2 complete ==="
    '';
  };

  # mq-cake-iperf3: Run iperf3 TCP test through DUT
  iperf3Script = pkgs.writeShellApplication {
    name = "mq-cake-iperf3";
    runtimeInputs = with pkgs; [ iproute2 iperf3 coreutils jq inetutils ];
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
        ip netns exec ns-gen-a iperf3 -c "$TARGET" -p "$PORT" -P "$FLOWS" -t "$DURATION" -i 2 --json
      else
        ip netns exec ns-gen-a iperf3 -c "$TARGET" -p "$PORT" -P "$FLOWS" -t "$DURATION" -i 2
      fi

      echo ""
      echo "=== iperf3 complete ==="
    '';
  };

  # mq-cake-flent: Run flent RRUL test through DUT
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
      OUTPUT_NAME="flent-$TEST-$TIMESTAMP"

      echo "=== flent $TEST test for ''${DURATION}s ==="
      echo "Target: $TARGET"
      echo "Output dir: $OUTPUT_DIR"
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
      # -D sets data directory, -o sets plot output file
      echo "Running flent $TEST..."
      echo ""

      ip netns exec ns-gen-a flent "$TEST" \
        -l "$DURATION" \
        -H "$TARGET" \
        --local-bind=10.1.0.2 \
        -D "$OUTPUT_DIR" \
        -o "$OUTPUT_DIR/$OUTPUT_NAME.png"

      echo ""
      echo "=== flent complete ==="
      echo "Results in: $OUTPUT_DIR"
      ls -la "$OUTPUT_DIR"/*.png "$OUTPUT_DIR"/*.flent.gz 2>/dev/null || true
    '';
  };

  # mq-cake-crusader: Run crusader latency test through DUT
  crusaderScript = pkgs.writeShellApplication {
    name = "mq-cake-crusader";
    runtimeInputs = with pkgs; [ iproute2 crusader coreutils ];
    text = ''
      set -euo pipefail

      DURATION=''${1:-10}
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
      # Uses 'test' subcommand with --load-duration for traffic duration
      echo "Running crusader client..."
      echo ""

      ip netns exec ns-gen-a crusader test "$TARGET" --load-duration "$DURATION"

      echo ""
      echo "=== crusader complete ==="
    '';
  };

  # mq-cake-collect-testdata: Collect sample outputs for Go parser tests
  collectTestdataScript = pkgs.writeShellApplication {
    name = "mq-cake-collect-testdata";
    runtimeInputs = with pkgs; [ iproute2 iperf2 iperf3 flent netperf crusader wrk dnsperf dnsutils curl coreutils ];
    text = ''
      set -euo pipefail

      OUTPUT_DIR=''${1:-/tmp/mq-cake-testdata}
      mkdir -p "$OUTPUT_DIR"

      echo "=== Collecting Tool Output Samples ==="
      echo "Output directory: $OUTPUT_DIR"
      echo ""

      # Helper to run server in background
      start_iperf_server() {
        ip netns exec ns-gen-b iperf -s -p 5001 &>/dev/null &
        echo $!
      }

      start_iperf3_server() {
        ip netns exec ns-gen-b iperf3 -s -p 5201 &>/dev/null &
        echo $!
      }

      start_netserver() {
        ip netns exec ns-gen-b netserver -p 12865 &>/dev/null &
        echo $!
      }

      start_crusader_server() {
        ip netns exec ns-gen-b crusader serve &>/dev/null &
        echo $!
      }

      # ============================================================
      # iperf2 samples
      # ============================================================
      echo "=== Collecting iperf2 samples ==="

      PID=$(start_iperf_server)
      sleep 1

      echo "  iperf2 - 1 flow..."
      ip netns exec ns-gen-a iperf -c 10.2.0.2 -p 5001 -P 1 -t 5 -i 2 \
        > "$OUTPUT_DIR/iperf2_1flow.txt" 2>&1 || true

      echo "  iperf2 - 10 flows..."
      ip netns exec ns-gen-a iperf -c 10.2.0.2 -p 5001 -P 10 -t 5 -i 2 \
        > "$OUTPUT_DIR/iperf2_10flows.txt" 2>&1 || true

      echo "  iperf2 - 100 flows..."
      ip netns exec ns-gen-a iperf -c 10.2.0.2 -p 5001 -P 100 -t 5 -i 2 \
        > "$OUTPUT_DIR/iperf2_100flows.txt" 2>&1 || true

      kill "$PID" 2>/dev/null || true
      wait "$PID" 2>/dev/null || true

      # ============================================================
      # iperf3 samples
      # ============================================================
      echo "=== Collecting iperf3 samples ==="

      PID=$(start_iperf3_server)
      sleep 1

      echo "  iperf3 - 1 flow (text)..."
      ip netns exec ns-gen-a iperf3 -c 10.2.0.2 -p 5201 -P 1 -t 5 -i 2 \
        > "$OUTPUT_DIR/iperf3_1flow.txt" 2>&1 || true

      # Need to restart server between iperf3 tests
      kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true
      PID=$(start_iperf3_server); sleep 1

      echo "  iperf3 - 10 flows (text)..."
      ip netns exec ns-gen-a iperf3 -c 10.2.0.2 -p 5201 -P 10 -t 5 -i 2 \
        > "$OUTPUT_DIR/iperf3_10flows.txt" 2>&1 || true

      kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true
      PID=$(start_iperf3_server); sleep 1

      echo "  iperf3 - 1 flow (json)..."
      ip netns exec ns-gen-a iperf3 -c 10.2.0.2 -p 5201 -P 1 -t 5 -i 2 --json \
        > "$OUTPUT_DIR/iperf3_1flow.json" 2>&1 || true

      kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true
      PID=$(start_iperf3_server); sleep 1

      echo "  iperf3 - 10 flows (json)..."
      ip netns exec ns-gen-a iperf3 -c 10.2.0.2 -p 5201 -P 10 -t 5 -i 2 --json \
        > "$OUTPUT_DIR/iperf3_10flows.json" 2>&1 || true

      kill "$PID" 2>/dev/null || true
      wait "$PID" 2>/dev/null || true

      # ============================================================
      # crusader sample
      # ============================================================
      echo "=== Collecting crusader sample ==="

      PID=$(start_crusader_server)
      sleep 3

      echo "  crusader - 5s test..."
      ip netns exec ns-gen-a crusader test 10.2.0.2 --load-duration 5 \
        > "$OUTPUT_DIR/crusader_5s.txt" 2>&1 || true

      kill "$PID" 2>/dev/null || true
      wait "$PID" 2>/dev/null || true

      # ============================================================
      # flent sample (shorter duration for speed)
      # ============================================================
      echo "=== Collecting flent sample ==="

      PID=$(start_netserver)
      sleep 2

      echo "  flent rrul - 10s test..."
      ip netns exec ns-gen-a flent rrul \
        -l 10 \
        -H 10.2.0.2 \
        --local-bind=10.1.0.2 \
        > "$OUTPUT_DIR/flent_rrul_10s.txt" 2>&1 || true

      kill "$PID" 2>/dev/null || true
      wait "$PID" 2>/dev/null || true

      # ============================================================
      # wrk HTTP samples (requires nginx running in ns-gen-b)
      # Test different file sizes and connection counts
      # ============================================================
      echo "=== Collecting wrk samples ==="

      # Check if nginx is running
      if ip netns exec ns-gen-b curl -s -o /dev/null -w "%{http_code}" http://10.2.0.2/health 2>/dev/null | grep -q "200"; then
        echo "  nginx is running, collecting wrk samples..."

        # Test different file sizes with 100 connections
        for size in 1k 10k 100k 1m; do
          echo "  wrk - 100 connections, $size file..."
          ip netns exec ns-gen-a wrk -t8 -c100 -d5s --latency "http://10.2.0.2/''${size}.bin" \
            > "$OUTPUT_DIR/wrk_100conn_''${size}.txt" 2>&1 || true
        done

        # Test different connection counts with 100k file (baseline)
        for conns in 10 100 500; do
          echo "  wrk - $conns connections, 100k file..."
          ip netns exec ns-gen-a wrk -t8 -c"$conns" -d5s --latency http://10.2.0.2/100k.bin \
            > "$OUTPUT_DIR/wrk_''${conns}conn_100k.txt" 2>&1 || true
        done
      else
        echo "  WARNING: nginx not running in ns-gen-b, skipping wrk samples"
        echo "  Run 'mq-cake-nginx start' first to collect wrk samples"
      fi

      # ============================================================
      # dnsperf DNS samples (requires PowerDNS running in ns-gen-b)
      # ============================================================
      echo "=== Collecting dnsperf samples ==="

      # Check if PowerDNS is running
      if ip netns exec ns-gen-b dig @10.2.0.2 host0001.test.local +short 2>/dev/null | grep -q "10.2.0"; then
        echo "  PowerDNS is running, collecting dnsperf samples..."

        # Test different concurrent query counts
        for conns in 10 50 100; do
          echo "  dnsperf - $conns concurrent queries..."
          ip netns exec ns-gen-a dnsperf \
            -s 10.2.0.2 \
            -d /var/lib/mq-cake/dns/queries.txt \
            -c "$conns" \
            -Q 50000 \
            -l 5 \
            > "$OUTPUT_DIR/dnsperf_''${conns}conc.txt" 2>&1 || true
        done
      else
        echo "  WARNING: PowerDNS not running in ns-gen-b, skipping dnsperf samples"
        echo "  Run 'mq-cake-pdns start' first to collect dnsperf samples"
      fi

      # ============================================================
      # Summary
      # ============================================================
      echo ""
      echo "=== Collection Complete ==="
      echo "Files created:"
      ls -la "$OUTPUT_DIR"
      echo ""
      echo "Copy to local machine with:"
      echo "  scp -r l2:$OUTPUT_DIR ./testdata"
    '';
  };

  # mq-cake-collect-testdata-streaming: Collect verbose/streaming outputs for real-time parser tests
  collectTestdataStreamingScript = pkgs.writeShellApplication {
    name = "mq-cake-collect-testdata-streaming";
    runtimeInputs = with pkgs; [ iproute2 iperf2 iperf3 flent netperf dnsperf dnsutils fping coreutils ];
    text = ''
      set -euo pipefail

      OUTPUT_DIR=''${1:-/tmp/mq-cake-testdata-streaming}
      mkdir -p "$OUTPUT_DIR"

      echo "=== Collecting Streaming/Verbose Tool Output Samples ==="
      echo "Output directory: $OUTPUT_DIR"
      echo ""

      # ============================================================
      # iperf2 streaming samples (CSV and enhanced text)
      # ============================================================
      echo "=== Collecting iperf2 streaming samples ==="

      ip netns exec ns-gen-b iperf -s -p 5001 &>/dev/null &
      PID=$!
      sleep 1

      echo "  iperf2 - 10 flows, CSV format (-i 1 -e -y C)..."
      ip netns exec ns-gen-a iperf -c 10.2.0.2 -p 5001 -P 10 -t 10 -i 1 -e -y C \
        > "$OUTPUT_DIR/iperf2_csv_10flows.txt" 2>&1 || true

      echo "  iperf2 - 10 flows, enhanced text (-i 1 -e)..."
      ip netns exec ns-gen-a iperf -c 10.2.0.2 -p 5001 -P 10 -t 10 -i 1 -e \
        > "$OUTPUT_DIR/iperf2_enhanced_10flows.txt" 2>&1 || true

      kill "$PID" 2>/dev/null || true
      wait "$PID" 2>/dev/null || true

      # ============================================================
      # iperf3 streaming samples (text mode, no --json)
      # ============================================================
      echo "=== Collecting iperf3 streaming samples ==="

      ip netns exec ns-gen-b iperf3 -s -p 5201 &>/dev/null &
      PID=$!
      sleep 1

      echo "  iperf3 - 10 flows, text mode (-i 1, no --json)..."
      ip netns exec ns-gen-a iperf3 -c 10.2.0.2 -p 5201 -P 10 -t 10 -i 1 \
        > "$OUTPUT_DIR/iperf3_text_10flows.txt" 2>&1 || true

      kill "$PID" 2>/dev/null || true
      wait "$PID" 2>/dev/null || true

      # ============================================================
      # fping streaming samples (no -q flag)
      # ============================================================
      echo "=== Collecting fping streaming samples ==="

      echo "  fping - per-packet output (no -q)..."
      ip netns exec ns-gen-a fping -c 20 -p 100 10.2.0.2 \
        > "$OUTPUT_DIR/fping_perpkt.txt" 2>&1 || true

      echo "  fping - per-packet with loss (short interval)..."
      ip netns exec ns-gen-a fping -c 20 -p 10 10.2.0.2 \
        > "$OUTPUT_DIR/fping_perpkt_loss.txt" 2>&1 || true

      # ============================================================
      # dnsperf streaming samples (-v -S 1 -W)
      # ============================================================
      echo "=== Collecting dnsperf streaming samples ==="

      if ip netns exec ns-gen-b dig @10.2.0.2 host0001.test.local +short 2>/dev/null | grep -q "10.2.0"; then
        echo "  dnsperf - verbose mode (-v -S 1 -W)..."
        ip netns exec ns-gen-a dnsperf \
          -s 10.2.0.2 \
          -d /var/lib/mq-cake/dns/queries.txt \
          -c 20 \
          -l 10 \
          -v -S 1 -W \
          > "$OUTPUT_DIR/dnsperf_verbose.txt" 2>&1 || true
      else
        echo "  WARNING: PowerDNS not running, skipping dnsperf"
      fi

      # ============================================================
      # flent streaming samples (-v --socket-stats)
      # ============================================================
      echo "=== Collecting flent streaming samples ==="

      ip netns exec ns-gen-b netserver -p 12865 &>/dev/null &
      PID=$!
      sleep 2

      echo "  flent - verbose with socket stats (-v --socket-stats -s 0.5)..."
      ip netns exec ns-gen-a flent rrul \
        -l 10 \
        -H 10.2.0.2 \
        --local-bind=10.1.0.2 \
        -v --socket-stats -s 0.5 \
        > "$OUTPUT_DIR/flent_verbose.txt" 2>&1 || true

      kill "$PID" 2>/dev/null || true
      wait "$PID" 2>/dev/null || true

      # ============================================================
      # Summary
      # ============================================================
      echo ""
      echo "=== Collection Complete ==="
      echo "Files created:"
      ls -la "$OUTPUT_DIR"
      echo ""
      echo "Copy to local testdata with:"
      echo "  mkdir -p internal/tools/testdata/streaming"
      echo "  scp -r l2:$OUTPUT_DIR/* internal/tools/testdata/streaming/"
    '';
  };

  # mq-cake-load: Wrapper to run multiple load tools
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

  # ============================================================================
  # Phase 5: HTTP/DNS Load Generation
  # ============================================================================

  # mq-cake-gen-testdata: Generate static files for HTTP benchmarking
  genTestdataScript = pkgs.writeShellApplication {
    name = "mq-cake-gen-testdata";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      WWW_DIR="/var/lib/mq-cake/www"

      echo "=== MQ-CAKE Test Data Generation ==="
      echo ""
      echo "Generating HTTP test files in $WWW_DIR..."
      echo ""

      # Generate binary test files with random data
      # Using /dev/urandom for random content (compressible test)
      echo "  1k.bin   (1 KB)..."
      dd if=/dev/urandom of="$WWW_DIR/1k.bin" bs=1K count=1 status=none

      echo "  10k.bin  (10 KB)..."
      dd if=/dev/urandom of="$WWW_DIR/10k.bin" bs=1K count=10 status=none

      echo "  100k.bin (100 KB)..."
      dd if=/dev/urandom of="$WWW_DIR/100k.bin" bs=1K count=100 status=none

      echo "  1m.bin   (1 MB)..."
      dd if=/dev/urandom of="$WWW_DIR/1m.bin" bs=1M count=1 status=none

      echo "  2m.bin   (2 MB)..."
      dd if=/dev/urandom of="$WWW_DIR/2m.bin" bs=1M count=2 status=none

      echo "  5m.bin   (5 MB)..."
      dd if=/dev/urandom of="$WWW_DIR/5m.bin" bs=1M count=5 status=none

      echo "  10m.bin  (10 MB)..."
      dd if=/dev/urandom of="$WWW_DIR/10m.bin" bs=1M count=10 status=none

      # Also create an index.html for basic testing
      echo "  index.html..."
      cat > "$WWW_DIR/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head><title>MQ-CAKE Test Server</title></head>
<body>
<h1>MQ-CAKE HTTP Test Server</h1>
<ul>
  <li><a href="/1k.bin">1k.bin</a> (1 KB)</li>
  <li><a href="/10k.bin">10k.bin</a> (10 KB)</li>
  <li><a href="/100k.bin">100k.bin</a> (100 KB)</li>
  <li><a href="/1m.bin">1m.bin</a> (1 MB)</li>
  <li><a href="/2m.bin">2m.bin</a> (2 MB)</li>
  <li><a href="/5m.bin">5m.bin</a> (5 MB)</li>
  <li><a href="/10m.bin">10m.bin</a> (10 MB)</li>
</ul>
</body>
</html>
HTMLEOF

      echo ""
      echo "HTTP test files:"
      ls -lh "$WWW_DIR"

      echo ""
      echo "=== Test Data Generation Complete ==="
    '';
  };

  # mq-cake-gen-queries: Generate DNS query file for dnsperf
  genQueriesScript = pkgs.writeShellApplication {
    name = "mq-cake-gen-queries";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      DNS_DIR="/var/lib/mq-cake/dns"
      QUERY_FILE="$DNS_DIR/queries.txt"
      NUM_HOSTS=''${1:-9999}

      echo "=== MQ-CAKE DNS Query File Generation ==="
      echo ""
      echo "Generating $NUM_HOSTS DNS queries..."

      # Generate A record queries for host0001.test.local through hostNNNN.test.local
      # Using printf for zero-padded numbers
      for i in $(seq 1 "$NUM_HOSTS"); do
        printf "host%04d.test.local A\n" "$i"
      done > "$QUERY_FILE"

      echo ""
      echo "Query file: $QUERY_FILE"
      echo "Total queries: $(wc -l < "$QUERY_FILE")"
      echo ""
      echo "Sample queries:"
      head -5 "$QUERY_FILE"
      echo "..."
      tail -5 "$QUERY_FILE"

      echo ""
      echo "=== DNS Query Generation Complete ==="
    '';
  };

  # mq-cake-gen-zone: Generate PowerDNS zone file
  genZoneScript = pkgs.writeShellApplication {
    name = "mq-cake-gen-zone";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      set -euo pipefail

      DNS_DIR="/var/lib/mq-cake/dns"
      ZONE_FILE="$DNS_DIR/test.local.zone"
      NUM_HOSTS=''${1:-9999}

      echo "=== MQ-CAKE DNS Zone File Generation ==="
      echo ""
      echo "Generating zone file with $NUM_HOSTS hosts..."

      # Generate zone file header
      cat > "$ZONE_FILE" << 'ZONEHEADER'
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

; Generated host records
ZONEHEADER

      # Generate A records - cycling through IPs 10.2.0.100-199
      for i in $(seq 1 "$NUM_HOSTS"); do
        # IP cycles: 10.2.0.100, 10.2.0.101, ..., 10.2.0.199, 10.2.0.100, ...
        IP_LAST=$((100 + (i - 1) % 100))
        printf "host%04d    IN  A   10.2.0.%d\n" "$i" "$IP_LAST"
      done >> "$ZONE_FILE"

      echo ""
      echo "Zone file: $ZONE_FILE"
      echo "Total records: $((NUM_HOSTS + 2))"  # +2 for SOA and NS
      echo ""
      echo "Sample records:"
      head -20 "$ZONE_FILE"
      echo "..."
      tail -5 "$ZONE_FILE"

      echo ""
      echo "=== DNS Zone Generation Complete ==="
    '';
  };

  # Runtime directory for nginx (pid, logs)
  runtimeDir = "/run/mq-cake";

  # nginx configuration file for namespace deployment
  # High-performance configuration optimized for benchmarking
  # Based on: go-ffmpeg-hls-swarm/nix/test-origin/nginx.nix
  nginxConf = pkgs.writeText "mq-cake-nginx.conf" ''
    # MQ-CAKE Test nginx configuration
    # Runs inside ns-gen-b namespace, binds to 10.2.0.2:80
    # Optimized for high-throughput file serving benchmarks

    worker_processes auto;
    worker_rlimit_nofile 65535;
    pid ${runtimeDir}/nginx.pid;
    error_log ${runtimeDir}/nginx-error.log warn;

    # Thread pool for async I/O - prevents worker blocking under load
    thread_pool default threads=32 max_queue=65536;

    events {
        worker_connections 16384;
        use epoll;
        multi_accept on;
    }

    http {
        include ${pkgs.nginx}/conf/mime.types;
        default_type application/octet-stream;

        # ═══════════════════════════════════════════════════════════════
        # Performance tuning (global)
        # ═══════════════════════════════════════════════════════════════
        sendfile           on;
        sendfile_max_chunk 512k;
        tcp_nopush         on;      # Fill packets before sending (throughput)
        tcp_nodelay        on;      # Disable Nagle for small responses
        keepalive_timeout  30;      # Reduced to free connections faster
        keepalive_requests 10000;

        # Free memory faster from dirty client exits
        reset_timedout_connection on;

        # Client body buffer (benchmarks don't POST)
        client_body_buffer_size 128k;

        # ═══════════════════════════════════════════════════════════════
        # File descriptor caching - aggressive for static files
        # ═══════════════════════════════════════════════════════════════
        open_file_cache          max=1000 inactive=30s;
        open_file_cache_valid    10s;
        open_file_cache_min_uses 1;
        open_file_cache_errors   on;

        # ═══════════════════════════════════════════════════════════════
        # Async I/O for high-load scenarios
        # Test files: 1k, 10k, 100k, 1m, 2m, 5m, 10m
        # directio 2m: Use direct I/O for 2m+ files (bypasses page cache)
        # Smaller files benefit from page cache
        # ═══════════════════════════════════════════════════════════════
        aio            threads=default;
        directio       2m;

        # Disable gzip - test files are random binary (incompressible)
        gzip off;

        # Disable access log for benchmarking (reduces overhead)
        access_log off;

        server {
            listen 10.2.0.2:80 reuseport;
            server_name _;

            root /var/lib/mq-cake/www;

            # ═══════════════════════════════════════════════════════════
            # Security: Method filtering
            # ═══════════════════════════════════════════════════════════
            if ($request_method !~ ^(GET|HEAD|OPTIONS)$ ) {
                return 405;
            }

            # ═══════════════════════════════════════════════════════════
            # Small files (1k, 10k, 100k) - optimize for low latency, high RPS
            # Page cache + sendfile, small output buffers
            # ═══════════════════════════════════════════════════════════
            location ~ ^/(1k|10k|100k)\.bin$ {
                sendfile       on;
                tcp_nodelay    on;      # Immediate delivery
                output_buffers 1 128k;
                add_header Cache-Control "public, max-age=3600";
            }

            # ═══════════════════════════════════════════════════════════
            # Medium files (1m, 2m) - balance latency and throughput
            # Page cache + sendfile with larger chunks
            # ═══════════════════════════════════════════════════════════
            location ~ ^/(1m|2m)\.bin$ {
                sendfile           on;
                sendfile_max_chunk 1m;
                tcp_nopush         on;  # Fill packets for throughput
                output_buffers     2 256k;
                add_header Cache-Control "public, max-age=3600";
            }

            # ═══════════════════════════════════════════════════════════
            # Large files (5m, 10m) - optimize for throughput
            # Direct I/O + async threads, large output buffers
            # ═══════════════════════════════════════════════════════════
            location ~ ^/(5m|10m)\.bin$ {
                sendfile           on;
                sendfile_max_chunk 2m;
                tcp_nopush         on;  # Fill packets for throughput
                aio                threads;
                output_buffers     4 512k;
                add_header Cache-Control "public, max-age=3600";
            }

            # ═══════════════════════════════════════════════════════════
            # Index and directory listing
            # ═══════════════════════════════════════════════════════════
            location / {
                try_files $uri $uri/ =404;
                autoindex on;
            }

            # ═══════════════════════════════════════════════════════════
            # Health check
            # ═══════════════════════════════════════════════════════════
            location /health {
                return 200 "OK\n";
                add_header Content-Type text/plain;
                add_header Cache-Control "no-store";
            }

            # ═══════════════════════════════════════════════════════════
            # Metrics (for monitoring)
            # ═══════════════════════════════════════════════════════════
            location /nginx_status {
                stub_status on;
                access_log off;
                add_header Cache-Control "no-store";
            }
        }
    }
  '';

  # mq-cake-nginx: Run nginx in ns-gen-b namespace
  nginxScript = pkgs.writeShellApplication {
    name = "mq-cake-nginx";
    runtimeInputs = with pkgs; [ iproute2 nginx coreutils procps ];
    text = ''
      set -euo pipefail

      ACTION=''${1:-start}

      CONF_FILE="${nginxConf}"
      RUNTIME_DIR="${runtimeDir}"
      PID_FILE="$RUNTIME_DIR/nginx.pid"

      case "$ACTION" in
        start)
          echo "=== Starting nginx in ns-gen-b ==="

          # Check namespace exists
          if ! ip netns list | grep -q "ns-gen-b"; then
            echo "ERROR: ns-gen-b namespace not found. Run mq-cake-setup first."
            exit 1
          fi

          # Check if already running
          if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "nginx already running (PID $(cat "$PID_FILE"))"
            exit 0
          fi

          # Check test files exist
          if [[ ! -f /var/lib/mq-cake/www/100k.bin ]]; then
            echo "WARNING: Test files not found. Run mq-cake-gen-testdata first."
          fi

          # Start nginx in namespace
          # -e overrides default error log before config is read
          echo "Starting nginx..."
          ip netns exec ns-gen-b ${pkgs.nginx}/bin/nginx -e "$RUNTIME_DIR/nginx-error.log" -c "$CONF_FILE"

          sleep 1

          if [[ -f "$PID_FILE" ]]; then
            echo "nginx started (PID $(cat "$PID_FILE"))"
            echo "Listening on 10.2.0.2:80"
          else
            echo "ERROR: nginx failed to start"
            exit 1
          fi
          ;;

        stop)
          echo "=== Stopping nginx ==="
          if [[ -f "$PID_FILE" ]]; then
            PID=$(cat "$PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
              kill "$PID"
              echo "nginx stopped (PID $PID)"
            else
              echo "nginx not running (stale PID file)"
            fi
            rm -f "$PID_FILE"
          else
            echo "nginx not running (no PID file)"
          fi
          ;;

        status)
          echo "=== nginx status ==="
          if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "nginx running (PID $(cat "$PID_FILE"))"
            # Test if responding
            if ip netns exec ns-gen-b curl -s -o /dev/null -w "%{http_code}" http://10.2.0.2/ | grep -q "200"; then
              echo "HTTP responding on 10.2.0.2:80"
            fi
          else
            echo "nginx not running"
          fi
          ;;

        restart)
          "$0" stop
          sleep 1
          "$0" start
          ;;

        *)
          echo "Usage: mq-cake-nginx {start|stop|status|restart}"
          exit 1
          ;;
      esac
    '';
  };

  # mq-cake-nginx-test: Test nginx from ns-gen-a
  nginxTestScript = pkgs.writeShellApplication {
    name = "mq-cake-nginx-test";
    runtimeInputs = with pkgs; [ iproute2 curl coreutils ];
    text = ''
      set -euo pipefail

      echo "=== Testing nginx from ns-gen-a ==="
      echo ""

      # Test each file size
      for file in index.html 1k.bin 10k.bin 100k.bin 1m.bin; do
        printf "  %-12s: " "$file"
        RESULT=$(ip netns exec ns-gen-a curl -s -o /dev/null -w "%{http_code} %{size_download}B %{time_total}s" "http://10.2.0.2/$file" 2>&1) || RESULT="FAILED"
        echo "$RESULT"
      done

      echo ""
      echo "=== Quick throughput test (100k.bin x 100) ==="
      START=$(date +%s.%N)
      for _ in $(seq 1 100); do
        ip netns exec ns-gen-a curl -s -o /dev/null "http://10.2.0.2/100k.bin"
      done
      END=$(date +%s.%N)
      ELAPSED=$(echo "$END - $START" | bc)
      RPS=$(echo "scale=2; 100 / $ELAPSED" | bc)
      echo "  100 requests in ''${ELAPSED}s = ''${RPS} req/s"

      echo ""
      echo "=== Test Complete ==="
    '';
  };

  # ============================================================================
  # Phase 5.4: PowerDNS DNS Server
  # ============================================================================

  # PowerDNS configuration directory
  pdnsConfigDir = "/var/lib/mq-cake/pdns";

  # PowerDNS configuration file
  # Uses bind backend to serve the test.local zone
  pdnsConf = pkgs.writeText "pdns.conf" ''
    # MQ-CAKE Test PowerDNS configuration
    # Runs inside ns-gen-b namespace, binds to 10.2.0.2:53

    # Bind backend for zone file
    launch=bind
    bind-config=${pdnsConfigDir}/named.conf

    # Network binding
    local-address=10.2.0.2
    local-port=53

    # Performance tuning
    receiver-threads=4
    distributor-threads=4
    cache-ttl=300
    negquery-cache-ttl=60
    query-cache-ttl=300

    # Logging
    loglevel=3
    log-dns-queries=no
    log-dns-details=no

    # Daemon control
    daemon=no
    guardian=no
    write-pid=no
  '';

  # BIND-style named.conf for PowerDNS bind backend
  pdnsNamedConf = pkgs.writeText "named.conf" ''
    zone "test.local" {
      type master;
      file "/var/lib/mq-cake/dns/test.local.zone";
    };
  '';

  # mq-cake-pdns: Run PowerDNS in ns-gen-b namespace
  pdnsScript = pkgs.writeShellApplication {
    name = "mq-cake-pdns";
    runtimeInputs = with pkgs; [ iproute2 pdns coreutils procps dnsutils ];
    text = ''
      set -euo pipefail

      ACTION=''${1:-start}

      CONFIG_DIR="${pdnsConfigDir}"
      PID_FILE="$CONFIG_DIR/pdns.pid"

      case "$ACTION" in
        start)
          echo "=== Starting PowerDNS in ns-gen-b ==="

          # Check namespace exists
          if ! ip netns list | grep -q "ns-gen-b"; then
            echo "ERROR: ns-gen-b namespace not found. Run mq-cake-setup first."
            exit 1
          fi

          # Check if already running
          if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "PowerDNS already running (PID $(cat "$PID_FILE"))"
            exit 0
          fi

          # Check zone file exists
          if [[ ! -f /var/lib/mq-cake/dns/test.local.zone ]]; then
            echo "ERROR: Zone file not found. Run mq-cake-gen-zone first."
            exit 1
          fi

          # Ensure config directory exists and copy configs
          mkdir -p "$CONFIG_DIR"
          cp -f ${pdnsConf} "$CONFIG_DIR/pdns.conf"
          cp -f ${pdnsNamedConf} "$CONFIG_DIR/named.conf"

          # Start PowerDNS in namespace
          echo "Starting PowerDNS..."
          ip netns exec ns-gen-b ${pkgs.pdns}/bin/pdns_server \
            --config-dir="$CONFIG_DIR" \
            --socket-dir="$CONFIG_DIR" &
          PDNS_PID=$!

          # Write PID file
          echo "$PDNS_PID" > "$PID_FILE"

          sleep 2

          # Verify it's running
          if kill -0 "$PDNS_PID" 2>/dev/null; then
            echo "PowerDNS started (PID $PDNS_PID)"
            echo "Listening on 10.2.0.2:53"

            # Quick test
            if ip netns exec ns-gen-b dig @10.2.0.2 host0001.test.local +short 2>/dev/null | grep -q "10.2.0"; then
              echo "DNS resolution working"
            fi
          else
            echo "ERROR: PowerDNS failed to start"
            rm -f "$PID_FILE"
            exit 1
          fi
          ;;

        stop)
          echo "=== Stopping PowerDNS ==="
          if [[ -f "$PID_FILE" ]]; then
            PID=$(cat "$PID_FILE")
            if kill -0 "$PID" 2>/dev/null; then
              kill "$PID"
              # Wait for clean shutdown
              for _ in $(seq 1 10); do
                if ! kill -0 "$PID" 2>/dev/null; then
                  break
                fi
                sleep 0.5
              done
              echo "PowerDNS stopped (PID $PID)"
            else
              echo "PowerDNS not running (stale PID file)"
            fi
            rm -f "$PID_FILE"
          else
            echo "PowerDNS not running (no PID file)"
          fi
          ;;

        status)
          echo "=== PowerDNS status ==="
          if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "PowerDNS running (PID $(cat "$PID_FILE"))"
            # Test resolution
            if ip netns exec ns-gen-b dig @10.2.0.2 host0001.test.local +short 2>/dev/null | grep -q "10.2.0"; then
              echo "DNS resolution working on 10.2.0.2:53"
            else
              echo "WARNING: DNS not responding"
            fi
          else
            echo "PowerDNS not running"
          fi
          ;;

        restart)
          "$0" stop
          sleep 1
          "$0" start
          ;;

        *)
          echo "Usage: mq-cake-pdns {start|stop|status|restart}"
          exit 1
          ;;
      esac
    '';
  };

  # mq-cake-pdns-test: Test PowerDNS from ns-gen-a
  pdnsTestScript = pkgs.writeShellApplication {
    name = "mq-cake-pdns-test";
    runtimeInputs = with pkgs; [ iproute2 dnsutils coreutils ];
    text = ''
      set -euo pipefail

      echo "=== Testing PowerDNS from ns-gen-a ==="
      echo ""

      # Test several hosts
      for host in host0001 host0100 host0500 host1000 host5000 host9999; do
        printf "  %-12s: " "$host"
        RESULT=$(ip netns exec ns-gen-a dig @10.2.0.2 "$host.test.local" +short 2>&1) || RESULT="FAILED"
        echo "$RESULT"
      done

      echo ""
      echo "=== Quick query test (100 queries) ==="
      START=$(date +%s.%N)
      for _ in $(seq 1 100); do
        HOST=$(printf "host%04d" $((RANDOM % 9999 + 1)))
        ip netns exec ns-gen-a dig @10.2.0.2 "$HOST.test.local" +short > /dev/null 2>&1
      done
      END=$(date +%s.%N)
      ELAPSED=$(echo "$END - $START" | bc)
      QPS=$(echo "scale=2; 100 / $ELAPSED" | bc)
      echo "  100 queries in ''${ELAPSED}s = ''${QPS} QPS"

      echo ""
      echo "=== Test Complete ==="
    '';
  };

  # mq-cake-http-setup: One-shot setup for HTTP testing (Phase 5)
  httpSetupScript = pkgs.writeShellApplication {
    name = "mq-cake-http-setup";
    runtimeInputs = with pkgs; [ iproute2 nginx curl coreutils bc ];
    text = ''
      set -euo pipefail

      echo "═══════════════════════════════════════════════════════════════"
      echo "  MQ-CAKE HTTP Test Environment Setup"
      echo "═══════════════════════════════════════════════════════════════"
      echo ""

      # Step 1: Namespaces
      echo "Step 1/4: Setting up namespaces..."
      if ! ip netns list | grep -q "ns-gen-b"; then
        mq-cake-setup
      else
        echo "  Namespaces already exist, skipping..."
      fi
      echo ""

      # Step 2: Generate test data
      echo "Step 2/4: Generating test data..."
      if [[ ! -f /var/lib/mq-cake/www/100k.bin ]]; then
        mq-cake-gen-testdata
      else
        echo "  Test files already exist, skipping..."
        find /var/lib/mq-cake/www -name "*.bin" -exec ls -lh {} \; | head -3
        echo "  ..."
      fi
      echo ""

      # Step 3: Start nginx
      echo "Step 3/4: Starting nginx in ns-gen-b..."
      mq-cake-nginx start
      echo ""

      # Step 4: Verify
      echo "Step 4/4: Verifying HTTP access from ns-gen-a..."
      echo ""
      for file in 1k.bin 100k.bin 1m.bin; do
        printf "  %-10s: " "$file"
        RESULT=$(ip netns exec ns-gen-a curl -s -o /dev/null -w "%{http_code} %{size_download}B" "http://10.2.0.2/$file" 2>&1) || RESULT="FAILED"
        echo "$RESULT"
      done

      echo ""
      echo "═══════════════════════════════════════════════════════════════"
      echo "  HTTP Test Environment Ready!"
      echo "═══════════════════════════════════════════════════════════════"
      echo ""
      echo "  nginx listening on: 10.2.0.2:80"
      echo "  Test files:         /var/lib/mq-cake/www/"
      echo ""
      echo "  Run benchmarks with wrk:"
      echo "    ip netns exec ns-gen-a wrk -t8 -c100 -d30s http://10.2.0.2/100k.bin"
      echo ""
      echo "  Stop nginx with:"
      echo "    sudo mq-cake-nginx stop"
      echo ""
    '';
  };

  # mq-cake-dns-setup: One-shot setup for DNS testing (Phase 5)
  dnsSetupScript = pkgs.writeShellApplication {
    name = "mq-cake-dns-setup";
    runtimeInputs = with pkgs; [ iproute2 pdns dnsutils coreutils bc ];
    text = ''
      set -euo pipefail

      echo "═══════════════════════════════════════════════════════════════"
      echo "  MQ-CAKE DNS Test Environment Setup"
      echo "═══════════════════════════════════════════════════════════════"
      echo ""

      # Step 1: Namespaces
      echo "Step 1/3: Setting up namespaces..."
      if ! ip netns list | grep -q "ns-gen-b"; then
        mq-cake-setup
      else
        echo "  Namespaces already exist, skipping..."
      fi
      echo ""

      # Step 2: Generate DNS data
      echo "Step 2/3: Generating DNS zone and queries..."
      if [[ ! -f /var/lib/mq-cake/dns/test.local.zone ]]; then
        mq-cake-gen-zone
        mq-cake-gen-queries
      else
        echo "  DNS files already exist, skipping..."
        echo "  Zone: $(wc -l < /var/lib/mq-cake/dns/test.local.zone) lines"
        echo "  Queries: $(wc -l < /var/lib/mq-cake/dns/queries.txt) entries"
      fi
      echo ""

      # Step 3: Start PowerDNS
      echo "Step 3/4: Starting PowerDNS in ns-gen-b..."
      mq-cake-pdns start
      echo ""

      # Step 4: Verify
      echo "Step 4/4: Verifying DNS resolution from ns-gen-a..."
      echo ""
      for host in host0001 host0500 host9999; do
        printf "  %-10s: " "$host"
        RESULT=$(ip netns exec ns-gen-a dig @10.2.0.2 "$host.test.local" +short 2>&1) || RESULT="FAILED"
        echo "$RESULT"
      done

      echo ""
      echo "═══════════════════════════════════════════════════════════════"
      echo "  DNS Test Environment Ready!"
      echo "═══════════════════════════════════════════════════════════════"
      echo ""
      echo "  PowerDNS listening on: 10.2.0.2:53"
      echo "  Zone file:  /var/lib/mq-cake/dns/test.local.zone"
      echo "  Query file: /var/lib/mq-cake/dns/queries.txt"
      echo ""
      echo "  Run benchmarks with dnsperf:"
      echo "    ip netns exec ns-gen-a dnsperf -s 10.2.0.2 -d /var/lib/mq-cake/dns/queries.txt -l 30"
      echo ""
      echo "  Stop PowerDNS with:"
      echo "    sudo mq-cake-pdns stop"
      echo ""
    '';
  };

  # ============================================================================
  # Phase 6: netem Latency Injection Scripts
  # ============================================================================

  # mq-cake-netem: Configure netem on X710 interfaces for WAN simulation
  netemScript = pkgs.writeShellApplication {
    name = "mq-cake-netem";
    runtimeInputs = with pkgs; [ iproute2 coreutils ];
    text = ''
      set -euo pipefail

      LATENCY=''${1:-30}
      JITTER=''${2:-3}
      LIMIT=''${3:-100000}

      echo "=== MQ-CAKE netem Configuration ==="
      echo "Latency: ''${LATENCY}ms"
      echo "Jitter:  ''${JITTER}ms"
      echo "Limit:   ''${LIMIT} packets"
      echo ""

      # Apply netem to X710 interfaces in ns-gen-a and ns-gen-b
      # This simulates WAN conditions for realistic testing

      echo "Applying netem to ns-gen-a (${x710_p0})..."
      ip netns exec ns-gen-a tc qdisc replace dev ${x710_p0} root netem \
        delay "''${LATENCY}ms" "''${JITTER}ms" distribution normal \
        limit "$LIMIT"

      echo "Applying netem to ns-gen-b (${x710_p1})..."
      ip netns exec ns-gen-b tc qdisc replace dev ${x710_p1} root netem \
        delay "''${LATENCY}ms" "''${JITTER}ms" distribution normal \
        limit "$LIMIT"

      echo ""
      echo "=== netem Applied ==="
      echo ""
      echo "Verify with: sudo mq-cake-netem-show"
    '';
  };

  # mq-cake-netem-clear: Remove netem from X710 interfaces
  netemClearScript = pkgs.writeShellApplication {
    name = "mq-cake-netem-clear";
    runtimeInputs = with pkgs; [ iproute2 ];
    text = ''
      set -euo pipefail

      echo "=== Clearing netem Configuration ==="

      echo "Removing netem from ns-gen-a (${x710_p0})..."
      ip netns exec ns-gen-a tc qdisc del dev ${x710_p0} root 2>/dev/null || true

      echo "Removing netem from ns-gen-b (${x710_p1})..."
      ip netns exec ns-gen-b tc qdisc del dev ${x710_p1} root 2>/dev/null || true

      echo ""
      echo "=== netem Cleared ==="
    '';
  };

  # mq-cake-netem-show: Display current netem configuration
  netemShowScript = pkgs.writeShellApplication {
    name = "mq-cake-netem-show";
    runtimeInputs = with pkgs; [ iproute2 ];
    text = ''
      set -euo pipefail

      echo "=== netem Configuration ==="
      echo ""

      echo "--- ns-gen-a (${x710_p0}) ---"
      ip netns exec ns-gen-a tc qdisc show dev ${x710_p0} 2>/dev/null || echo "No qdisc configured"
      ip netns exec ns-gen-a tc -s qdisc show dev ${x710_p0} 2>/dev/null || true
      echo ""

      echo "--- ns-gen-b (${x710_p1}) ---"
      ip netns exec ns-gen-b tc qdisc show dev ${x710_p1} 2>/dev/null || echo "No qdisc configured"
      ip netns exec ns-gen-b tc -s qdisc show dev ${x710_p1} 2>/dev/null || true
    '';
  };

  # mq-cake-full-setup: Complete setup for all Phase 5 testing
  fullSetupScript = pkgs.writeShellApplication {
    name = "mq-cake-full-setup";
    runtimeInputs = with pkgs; [ iproute2 nginx pdns dnsutils curl coreutils bc ];
    text = ''
      set -euo pipefail

      echo "═══════════════════════════════════════════════════════════════"
      echo "  MQ-CAKE Full Test Environment Setup (Phase 1-5)"
      echo "═══════════════════════════════════════════════════════════════"
      echo ""

      # Phase 1: Namespaces
      echo ">>> Phase 1: Namespaces"
      if ! ip netns list | grep -q "ns-gen-b"; then
        mq-cake-setup
      else
        echo "  Already configured"
      fi
      mq-cake-verify || true
      echo ""

      # Phase 2: Default qdisc
      echo ">>> Phase 2: Qdisc (fq_codel default)"
      mq-cake-qdisc fq_codel
      echo ""

      # Phase 5.1: Test data
      echo ">>> Phase 5.1: Test Data"
      mq-cake-gen-testdata
      mq-cake-gen-queries
      mq-cake-gen-zone
      echo ""

      # Phase 5.2: nginx
      echo ">>> Phase 5.2: nginx"
      mq-cake-nginx start
      echo ""

      # Phase 5.4: PowerDNS
      echo ">>> Phase 5.4: PowerDNS"
      mq-cake-pdns start
      echo ""

      # Verify HTTP and DNS
      echo ">>> Verification"
      echo ""
      echo "HTTP:"
      mq-cake-nginx-test || true
      echo ""
      echo "DNS:"
      mq-cake-pdns-test || true

      echo ""
      echo "═══════════════════════════════════════════════════════════════"
      echo "  Full Test Environment Ready!"
      echo "═══════════════════════════════════════════════════════════════"
      echo ""
      echo "  HTTP: nginx on 10.2.0.2:80"
      echo "  DNS:  PowerDNS on 10.2.0.2:53"
      echo ""
    '';
  };

  # =============================================================================
  # Phase 7: Orchestrator and Stress Test
  # =============================================================================

  # Build the orchestrator from local source
  orchestrator = pkgs.buildGoModule {
    pname = "mq-cake-orchestrator";
    version = "0.1.0";
    src = ./mq-cake-orchestrator;
    vendorHash = "sha256-xwMzxLsWzED66ghs3f0PiQKWtuyphPRs0DCw6IFpvkg=";
    ldflags = [ "-s" "-w" ];
    subPackages = [ "cmd/orchestrator" ];
    env.CGO_ENABLED = "0";
    postInstall = ''
      mv $out/bin/orchestrator $out/bin/mq-cake-orchestrator
    '';
    meta = with pkgs.lib; {
      description = "MQ-CAKE qdisc performance testing orchestrator";
      license = licenses.mit;
      mainProgram = "mq-cake-orchestrator";
    };
  };

  # mq-cake-stress: Run concurrent stress test with real-time streaming metrics
  stressScript = pkgs.writeShellApplication {
    name = "mq-cake-stress";
    runtimeInputs = with pkgs; [ orchestrator iproute2 ];
    text = ''
      set -euo pipefail

      # Default config file
      DEFAULT_CONFIG="${./mq-cake-orchestrator/stress-config.yaml}"

      # Check if -config flag is already provided
      HAS_CONFIG=false
      for arg in "$@"; do
        if [[ "$arg" == "-config" || "$arg" == "--config" ]]; then
          HAS_CONFIG=true
          break
        fi
      done

      echo "Starting MQ-CAKE stress test with streaming metrics..."

      if $HAS_CONFIG; then
        # User provided config, pass all args through
        exec mq-cake-orchestrator -stress "$@"
      else
        # Use default config, pass all args through
        echo "Config: $DEFAULT_CONFIG"
        echo ""
        exec mq-cake-orchestrator -stress -config "$DEFAULT_CONFIG" "$@"
      fi
    '';
  };

  # mq-cake-orchestrator-run: Run standard orchestrator (sequential tests)
  orchestratorRunScript = pkgs.writeShellApplication {
    name = "mq-cake-run";
    runtimeInputs = with pkgs; [ orchestrator iproute2 ];
    text = ''
      set -euo pipefail

      CONFIG_FILE=''${1:-/etc/mq-cake/config.yaml}

      # Check if config exists, fall back to bundled config
      if [ ! -f "$CONFIG_FILE" ]; then
        if [ -f "${./mq-cake-orchestrator/config.yaml}" ]; then
          CONFIG_FILE="${./mq-cake-orchestrator/config.yaml}"
        else
          echo "ERROR: No config file found at $CONFIG_FILE"
          echo "Usage: mq-cake-run [config-file]"
          exit 1
        fi
      fi

      echo "Starting MQ-CAKE orchestrator..."
      echo "Config: $CONFIG_FILE"
      echo ""

      exec mq-cake-orchestrator -config "$CONFIG_FILE"
    '';
  };

in
{
  options.services.mq-cake-test = {
    enable = mkEnableOption "MQ-CAKE test environment scripts";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      # Phase 1: Namespace scripts
      setupScript
      teardownScript
      verifyScript
      # Phase 2: Qdisc scripts
      qdiscScript
      statsScript
      resetScript
      # Phase 3: Load generation scripts
      iperf2Script
      iperf3Script
      flentScript
      crusaderScript
      loadScript
      collectTestdataScript
      collectTestdataStreamingScript
      # Phase 3: Load generation tools
      iperf2
      iperf3
      flent
      netperf
      crusader
      # Phase 5: HTTP/DNS test data generation
      genTestdataScript
      genQueriesScript
      genZoneScript
      # Phase 5: nginx HTTP server
      nginxScript
      nginxTestScript
      nginx
      curl
      bc
      # Phase 5: wrk HTTP benchmarking
      wrk
      # Phase 5: PowerDNS server
      pdnsScript
      pdnsTestScript
      pdns
      dnsutils
      # Phase 5: dnsperf DNS benchmarking
      dnsperf
      # Phase 5: One-shot setup scripts
      httpSetupScript
      dnsSetupScript
      fullSetupScript
      # Phase 6: netem latency injection
      netemScript
      netemClearScript
      netemShowScript
      # Phase 6: ICMP latency probe
      fping
      # Phase 7: Orchestrator and stress test
      orchestrator
      stressScript
      orchestratorRunScript
    ];

    boot.kernelModules = [ "sch_cake" "sch_fq_codel" ];

    # Runtime directories (tmpfs, created on boot)
    systemd.tmpfiles.rules = [
      "d /run/mq-cake 0755 root root -"
      "d /var/lib/mq-cake 0755 root root -"
      "d /var/lib/mq-cake/www 0755 root root -"
      "d /var/lib/mq-cake/dns 0755 root root -"
      "d /var/lib/mq-cake/pdns 0755 root root -"
    ];
  };
}
