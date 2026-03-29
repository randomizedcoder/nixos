.PHONY: all build smoke_test test stress setup setup_http setup_dns setup_netem clear_netem clean unit_test

# Build the orchestrator binary
all: build

build:
	go build -buildvcs=false -o mq-cake-orchestrator ./cmd/orchestrator

# Unit tests for Go code (parsers, etc.)
unit_test:
	go test -v ./...

# Setup test environment (namespaces + servers)
setup:
	sudo mq-cake-full-setup

setup_http:
	sudo mq-cake-http-setup

setup_dns:
	sudo mq-cake-dns-setup

# Smoke test: quick verification with iperf2 + wrk
# Uses reduced matrix: 2 flow counts, 3 qdiscs, 2 tools = 12 test points
smoke_test: build
	sudo ./mq-cake-orchestrator --config config-test.yaml

# Full test: all tools with full matrix
# 6 tools x 4 flow counts x 3 qdiscs = 72 test points
test: build
	sudo ./mq-cake-orchestrator --config config.yaml

# Stress test: concurrent tools with flow ramping
# All tools run simultaneously, flows increment every step
stress: build setup_netem
	sudo ./mq-cake-orchestrator --stress --config stress-config.yaml

# Stress test with debug output
stress_debug: build setup_netem
	sudo ./mq-cake-orchestrator --stress --debug --config stress-config.yaml

# Stress test with full verbose output (debug + socket stats every 10s + commands)
stress_verbose: build setup_netem
	sudo ./mq-cake-orchestrator --stress --debug --socket-stats 10s --show-commands --config stress-config.yaml

# Stress test with frequent socket stats (every 1s)
stress_sockets: build setup_netem
	sudo ./mq-cake-orchestrator --stress --debug --socket-stats 1s --config stress-config.yaml

# Setup netem latency injection (30ms delay, 3ms jitter)
setup_netem:
	sudo mq-cake-netem 30 3

# Clear netem configuration
clear_netem:
	sudo mq-cake-netem-clear

# Show netem status
show_netem:
	sudo mq-cake-netem-show

# Debug mode: show commands and qdisc config
debug_test: build
	sudo ./mq-cake-orchestrator --config config-test.yaml --debug

# Clean up test environment
clean:
	sudo mq-cake-nginx stop 2>/dev/null || true
	sudo mq-cake-pdns stop 2>/dev/null || true
	sudo mq-cake-teardown 2>/dev/null || true
	rm -f mq-cake-orchestrator

# Verify wrk works (manual test)
verify_wrk:
	sudo ip netns exec ns-gen-a wrk -t8 -c100 -d5s --latency http://10.2.0.2/100k.bin

# Verify dnsperf works (manual test)
verify_dnsperf:
	sudo ip netns exec ns-gen-a dnsperf -s 10.2.0.2 -d /var/lib/mq-cake/dns/queries.txt -c 50 -l 5

# Quick verification of both wrk and dnsperf
verify: verify_wrk verify_dnsperf
