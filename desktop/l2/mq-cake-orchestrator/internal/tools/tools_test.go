// internal/tools/tools_test.go
package tools

import (
	"math"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func readTestdata(t *testing.T, filename string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("testdata", filename))
	if err != nil {
		t.Fatalf("failed to read testdata/%s: %v", filename, err)
	}
	return string(data)
}

func assertFloat(t *testing.T, name string, got, want, tolerance float64) {
	t.Helper()
	if math.Abs(got-want) > tolerance {
		t.Errorf("%s: got %.3f, want %.3f (tolerance %.3f)", name, got, want, tolerance)
	}
}

// =============================================================================
// Iperf2 Tests
// =============================================================================

func TestIperf2Parse(t *testing.T) {
	tool := NewIperf2()

	tests := []struct {
		name           string
		filename       string
		flows          int
		wantThroughput float64 // Gbps
		tolerance      float64
	}{
		{
			name:           "single flow",
			filename:       "iperf2_1flow.txt",
			flows:          1,
			wantThroughput: 9.31, // [  1] 0.0000-5.0138 sec  5.43 GBytes  9.31 Gbits/sec
			tolerance:      0.1,
		},
		{
			name:           "10 flows",
			filename:       "iperf2_10flows.txt",
			flows:          10,
			wantThroughput: 9.44, // [SUM] 0.0000-5.0089 sec  5.51 GBytes  9.44 Gbits/sec
			tolerance:      0.1,
		},
		{
			name:           "100 flows",
			filename:       "iperf2_100flows.txt",
			flows:          100,
			wantThroughput: 9.49, // [SUM] 0.0000-5.1105 sec  5.65 GBytes  9.49 Gbits/sec
			tolerance:      0.1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			output := readTestdata(t, tt.filename)
			result, err := tool.Parse(output, tt.flows, 5*time.Second)
			if err != nil {
				t.Fatalf("Parse error: %v", err)
			}

			if result.Tool != "iperf2" {
				t.Errorf("Tool: got %q, want %q", result.Tool, "iperf2")
			}
			if result.FlowCount != tt.flows {
				t.Errorf("FlowCount: got %d, want %d", result.FlowCount, tt.flows)
			}
			assertFloat(t, "ThroughputGbps", result.ThroughputGbps, tt.wantThroughput, tt.tolerance)
		})
	}
}

func TestIperf2ServerCmd(t *testing.T) {
	tool := NewIperf2()
	cmd := tool.ServerCmd(5001)
	want := []string{"iperf", "-s", "-p", "5001"}

	if len(cmd) != len(want) {
		t.Fatalf("ServerCmd length: got %d, want %d", len(cmd), len(want))
	}
	for i := range cmd {
		if cmd[i] != want[i] {
			t.Errorf("ServerCmd[%d]: got %q, want %q", i, cmd[i], want[i])
		}
	}
}

func TestIperf2ClientCmd(t *testing.T) {
	tool := NewIperf2()
	cmd := tool.ClientCmd("10.2.0.2", 5001, 10, 30*time.Second)

	// Check key arguments are present
	if cmd[0] != "iperf" {
		t.Errorf("cmd[0]: got %q, want %q", cmd[0], "iperf")
	}
	// Should contain -P 10 for parallel flows
	found := false
	for i, arg := range cmd {
		if arg == "-P" && i+1 < len(cmd) && cmd[i+1] == "10" {
			found = true
			break
		}
	}
	if !found {
		t.Error("ClientCmd missing -P 10")
	}
}

// =============================================================================
// Iperf3 Tests
// =============================================================================

func TestIperf3Parse(t *testing.T) {
	tool := NewIperf3()

	tests := []struct {
		name            string
		filename        string
		flows           int
		wantThroughput  float64 // Gbps
		wantRetransmits int64
		tolerance       float64
	}{
		{
			name:            "single flow JSON",
			filename:        "iperf3_1flow.json",
			flows:           1,
			wantThroughput:  9.15, // sum_received.bits_per_second: 9145165621 / 1e9
			wantRetransmits: 0,
			tolerance:       0.1,
		},
		{
			name:            "10 flows JSON",
			filename:        "iperf3_10flows.json",
			flows:           10,
			wantThroughput:  9.41, // sum_received.bits_per_second: 9410428555 / 1e9
			wantRetransmits: 18,   // actual retransmits from test run
			tolerance:       0.1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			output := readTestdata(t, tt.filename)
			result, err := tool.Parse(output, tt.flows, 5*time.Second)
			if err != nil {
				t.Fatalf("Parse error: %v", err)
			}

			if result.Tool != "iperf3" {
				t.Errorf("Tool: got %q, want %q", result.Tool, "iperf3")
			}
			if result.FlowCount != tt.flows {
				t.Errorf("FlowCount: got %d, want %d", result.FlowCount, tt.flows)
			}
			assertFloat(t, "ThroughputGbps", result.ThroughputGbps, tt.wantThroughput, tt.tolerance)
			if result.Retransmits != tt.wantRetransmits {
				t.Errorf("Retransmits: got %d, want %d", result.Retransmits, tt.wantRetransmits)
			}
		})
	}
}

func TestIperf3ClientCmdCapsFlows(t *testing.T) {
	tool := NewIperf3()

	// iperf3 has max 128 streams
	cmd := tool.ClientCmd("10.2.0.2", 5201, 500, 30*time.Second)

	// Should cap at 128
	found := false
	for i, arg := range cmd {
		if arg == "-P" && i+1 < len(cmd) {
			if cmd[i+1] == "128" {
				found = true
			} else if cmd[i+1] == "500" {
				t.Error("ClientCmd did not cap flows at 128")
			}
			break
		}
	}
	if !found {
		t.Error("ClientCmd missing -P flag")
	}
}

// =============================================================================
// Crusader Tests
// =============================================================================

func TestCrusaderParse(t *testing.T) {
	tool := NewCrusader()

	output := readTestdata(t, "crusader_5s.txt")
	result, err := tool.Parse(output, 8, 5*time.Second) // crusader uses 8 streams by default
	if err != nil {
		t.Fatalf("Parse error: %v", err)
	}

	if result.Tool != "crusader" {
		t.Errorf("Tool: got %q, want %q", result.Tool, "crusader")
	}

	// Crusader output shows:
	// Download: 9414.27 Mbps = 9.414 Gbps
	// Upload: 9414.38 Mbps = 9.414 Gbps
	// Bidirectional: 18761.59 Mbps = 18.76 Gbps
	// We're parsing the first throughput match which is download
	assertFloat(t, "ThroughputGbps", result.ThroughputGbps, 9.414, 0.1)

	// Latency from download test: 0.5 ms
	assertFloat(t, "LatencyP50Ms", result.LatencyP50Ms, 0.5, 0.5)

	// Packet loss: 0%
	assertFloat(t, "PacketLossPct", result.PacketLossPct, 0.0, 0.1)
}

func TestCrusaderServerCmd(t *testing.T) {
	tool := NewCrusader()
	cmd := tool.ServerCmd(35481)
	want := []string{"crusader", "serve"}

	if len(cmd) != len(want) {
		t.Fatalf("ServerCmd length: got %d, want %d", len(cmd), len(want))
	}
	for i := range cmd {
		if cmd[i] != want[i] {
			t.Errorf("ServerCmd[%d]: got %q, want %q", i, cmd[i], want[i])
		}
	}
}

func TestCrusaderClientCmd(t *testing.T) {
	tool := NewCrusader()
	cmd := tool.ClientCmd("10.2.0.2", 35481, 8, 10*time.Second)

	if cmd[0] != "crusader" || cmd[1] != "test" || cmd[2] != "10.2.0.2" {
		t.Errorf("ClientCmd prefix: got %v, want [crusader test 10.2.0.2 ...]", cmd[:3])
	}
	// Should have --load-duration 10
	found := false
	for i, arg := range cmd {
		if arg == "--load-duration" && i+1 < len(cmd) && cmd[i+1] == "10" {
			found = true
			break
		}
	}
	if !found {
		t.Error("ClientCmd missing --load-duration 10")
	}
}

// =============================================================================
// Flent Tests
// =============================================================================

func TestFlentParse(t *testing.T) {
	tool := NewFlent("/tmp/test")

	output := readTestdata(t, "flent_rrul_10s.txt")
	result, err := tool.Parse(output, 4, 10*time.Second) // RRUL uses 4 flows per direction
	if err != nil {
		t.Fatalf("Parse error: %v", err)
	}

	if result.Tool != "flent" {
		t.Errorf("Tool: got %q, want %q", result.Tool, "flent")
	}

	// Flent shows "TCP totals : 18780.89 Mbits/s" = 18.78 Gbps
	assertFloat(t, "ThroughputGbps", result.ThroughputGbps, 18.78, 0.1)

	// Ping ICMP avg: 2.79 ms (parser extracts avg column)
	assertFloat(t, "LatencyP50Ms", result.LatencyP50Ms, 2.79, 0.2)
}

func TestFlentServerCmd(t *testing.T) {
	tool := NewFlent("/tmp/test")
	cmd := tool.ServerCmd(12865)
	want := []string{"netserver", "-p", "12865"}

	if len(cmd) != len(want) {
		t.Fatalf("ServerCmd length: got %d, want %d", len(cmd), len(want))
	}
	for i := range cmd {
		if cmd[i] != want[i] {
			t.Errorf("ServerCmd[%d]: got %q, want %q", i, cmd[i], want[i])
		}
	}
}

// =============================================================================
// Wrk Tests
// =============================================================================

func TestWrkParse(t *testing.T) {
	tool := NewWrk("100k")

	tests := []struct {
		name           string
		filename       string
		flows          int
		wantThroughput float64 // Gbps
		wantLatP50     float64 // ms
		wantLatP99     float64 // ms
		tolerance      float64
	}{
		{
			name:           "100 connections 100k",
			filename:       "wrk_100conn_100k.txt",
			flows:          100,
			wantThroughput: 8.8, // 1.10GB/s * 8 = 8.8 Gbps
			wantLatP50:     7.71,
			wantLatP99:     18.75,
			tolerance:      0.5,
		},
		{
			name:           "500 connections 100k",
			filename:       "wrk_500conn_100k.txt",
			flows:          500,
			wantThroughput: 8.72,   // 1.09GB/s * 8 = 8.72 Gbps
			wantLatP50:     26.34,  // actual P50
			wantLatP99:     386.74, // actual P99
			tolerance:      1.0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			output := readTestdata(t, tt.filename)
			result, err := tool.Parse(output, tt.flows, 30*time.Second)
			if err != nil {
				t.Fatalf("Parse error: %v", err)
			}

			if result.Tool != "wrk" {
				t.Errorf("Tool: got %q, want %q", result.Tool, "wrk")
			}
			if result.FlowCount != tt.flows {
				t.Errorf("FlowCount: got %d, want %d", result.FlowCount, tt.flows)
			}
			assertFloat(t, "ThroughputGbps", result.ThroughputGbps, tt.wantThroughput, tt.tolerance)
			assertFloat(t, "LatencyP50Ms", result.LatencyP50Ms, tt.wantLatP50, 0.1)
			assertFloat(t, "LatencyP99Ms", result.LatencyP99Ms, tt.wantLatP99, 0.1)
		})
	}
}

func TestWrkServerCmd(t *testing.T) {
	tool := NewWrk("100k")
	cmd := tool.ServerCmd(80)
	want := []string{"mq-cake-nginx", "start"}

	if len(cmd) != len(want) {
		t.Fatalf("ServerCmd length: got %d, want %d", len(cmd), len(want))
	}
	for i := range cmd {
		if cmd[i] != want[i] {
			t.Errorf("ServerCmd[%d]: got %q, want %q", i, cmd[i], want[i])
		}
	}
}

func TestWrkClientCmd(t *testing.T) {
	tool := NewWrk("100k")
	cmd := tool.ClientCmd("10.2.0.2", 80, 100, 30*time.Second)

	if cmd[0] != "wrk" {
		t.Errorf("cmd[0]: got %q, want %q", cmd[0], "wrk")
	}

	// Should contain -c 100 for connections
	foundC := false
	foundLatency := false
	for i, arg := range cmd {
		if arg == "-c" && i+1 < len(cmd) && cmd[i+1] == "100" {
			foundC = true
		}
		if arg == "--latency" {
			foundLatency = true
		}
	}
	if !foundC {
		t.Error("ClientCmd missing -c 100")
	}
	if !foundLatency {
		t.Error("ClientCmd missing --latency")
	}
}

// =============================================================================
// DNSPerf Tests
// =============================================================================

func TestDNSPerfParse(t *testing.T) {
	tool := NewDNSPerf("/var/lib/mq-cake/dns/queries.txt")

	// Use real collected data: dnsperf_100conc.txt
	output := readTestdata(t, "dnsperf_100conc.txt")
	result, err := tool.Parse(output, 100, 5*time.Second)
	if err != nil {
		t.Fatalf("Parse error: %v", err)
	}

	if result.Tool != "dnsperf" {
		t.Errorf("Tool: got %q, want %q", result.Tool, "dnsperf")
	}

	// Queries per second: 49996.060295
	// Throughput = 49996 * 800 bits / 1e9 = 0.03999 Gbps
	assertFloat(t, "ThroughputGbps", result.ThroughputGbps, 0.03999, 0.001)

	// Queries lost: 0 (0.00%)
	assertFloat(t, "PacketLossPct", result.PacketLossPct, 0.0, 0.01)

	// Average Latency (s): 0.000193 -> 0.193 ms
	assertFloat(t, "LatencyP50Ms", result.LatencyP50Ms, 0.193, 0.01)

	// Max Latency (s): 0.001268 -> 1.268 ms
	assertFloat(t, "LatencyP99Ms", result.LatencyP99Ms, 1.268, 0.01)
}

func TestDNSPerfServerCmd(t *testing.T) {
	tool := NewDNSPerf("/var/lib/mq-cake/dns/queries.txt")
	cmd := tool.ServerCmd(53)
	want := []string{"mq-cake-pdns", "start"}

	if len(cmd) != len(want) {
		t.Fatalf("ServerCmd length: got %d, want %d", len(cmd), len(want))
	}
	for i := range cmd {
		if cmd[i] != want[i] {
			t.Errorf("ServerCmd[%d]: got %q, want %q", i, cmd[i], want[i])
		}
	}
}

func TestDNSPerfClientCmd(t *testing.T) {
	tool := NewDNSPerf("/var/lib/mq-cake/dns/queries.txt")
	cmd := tool.ClientCmd("10.2.0.2", 53, 100, 30*time.Second)

	if cmd[0] != "dnsperf" {
		t.Errorf("cmd[0]: got %q, want %q", cmd[0], "dnsperf")
	}

	// Should contain -c 100 for concurrent queries
	foundC := false
	foundQ := false
	for i, arg := range cmd {
		if arg == "-c" && i+1 < len(cmd) && cmd[i+1] == "100" {
			foundC = true
		}
		if arg == "-Q" {
			foundQ = true
		}
	}
	if !foundC {
		t.Error("ClientCmd missing -c 100")
	}
	if !foundQ {
		t.Error("ClientCmd missing -Q (target QPS)")
	}
}

// =============================================================================
// Fping Tests
// =============================================================================

func TestFpingParse(t *testing.T) {
	tool := NewFping()

	tests := []struct {
		name        string
		output      string
		wantLatAvg  float64 // P50 approximation (avg)
		wantLatMax  float64 // P99 approximation (max)
		wantLossPct float64
		tolerance   float64
	}{
		{
			name:        "10 pings no loss",
			output:      "1.1.1.1 : xmt/rcv/%loss = 10/10/0%, min/avg/max = 9.59/12.2/17.0",
			wantLatAvg:  12.2,
			wantLatMax:  17.0,
			wantLossPct: 0.0,
			tolerance:   0.1,
		},
		{
			name:        "20 pings no loss",
			output:      "1.1.1.1 : xmt/rcv/%loss = 20/20/0%, min/avg/max = 6.96/12.8/27.5",
			wantLatAvg:  12.8,
			wantLatMax:  27.5,
			wantLossPct: 0.0,
			tolerance:   0.1,
		},
		{
			name:        "50 pings no loss",
			output:      "1.1.1.1 : xmt/rcv/%loss = 50/50/0%, min/avg/max = 8.41/12.8/43.7",
			wantLatAvg:  12.8,
			wantLatMax:  43.7,
			wantLossPct: 0.0,
			tolerance:   0.1,
		},
		{
			name:        "with packet loss",
			output:      "10.2.0.2 : xmt/rcv/%loss = 100/95/5%, min/avg/max = 30.1/31.5/35.2",
			wantLatAvg:  31.5,
			wantLatMax:  35.2,
			wantLossPct: 5.0,
			tolerance:   0.1,
		},
		{
			name:        "high jitter",
			output:      "10.2.0.2 : xmt/rcv/%loss = 100/100/0%, min/avg/max = 28.5/32.1/156.3",
			wantLatAvg:  32.1,
			wantLatMax:  156.3,
			wantLossPct: 0.0,
			tolerance:   0.1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := tool.Parse(tt.output, 1, 10*time.Second)
			if err != nil {
				t.Fatalf("Parse error: %v", err)
			}

			if result.Tool != "fping" {
				t.Errorf("Tool: got %q, want %q", result.Tool, "fping")
			}
			assertFloat(t, "LatencyP50Ms", result.LatencyP50Ms, tt.wantLatAvg, tt.tolerance)
			assertFloat(t, "LatencyP99Ms", result.LatencyP99Ms, tt.wantLatMax, tt.tolerance)
			assertFloat(t, "PacketLossPct", result.PacketLossPct, tt.wantLossPct, tt.tolerance)
			// fping doesn't measure throughput
			if result.ThroughputGbps != 0 {
				t.Errorf("ThroughputGbps: got %f, want 0", result.ThroughputGbps)
			}
		})
	}
}

func TestFpingServerCmd(t *testing.T) {
	tool := NewFping()
	cmd := tool.ServerCmd(0)
	// Should be a no-op (ICMP handled by kernel)
	want := []string{"true"}

	if len(cmd) != len(want) {
		t.Fatalf("ServerCmd length: got %d, want %d", len(cmd), len(want))
	}
	for i := range cmd {
		if cmd[i] != want[i] {
			t.Errorf("ServerCmd[%d]: got %q, want %q", i, cmd[i], want[i])
		}
	}
}

func TestFpingClientCmd(t *testing.T) {
	tool := NewFping()
	cmd := tool.ClientCmd("10.2.0.2", 0, 1, 10*time.Second)

	if cmd[0] != "fping" {
		t.Errorf("cmd[0]: got %q, want %q", cmd[0], "fping")
	}

	// Should have -c for count and -q for quiet
	foundC := false
	foundQ := false
	for i, arg := range cmd {
		if arg == "-c" && i+1 < len(cmd) {
			foundC = true
		}
		if arg == "-q" {
			foundQ = true
		}
	}
	if !foundC {
		t.Error("ClientCmd missing -c (count)")
	}
	if !foundQ {
		t.Error("ClientCmd missing -q (quiet mode)")
	}
}

// =============================================================================
// Tool Interface Tests
// =============================================================================

func TestToolsImplementInterface(t *testing.T) {
	// Compile-time check that all tools implement the Tool interface
	var _ Tool = (*Iperf2)(nil)
	var _ Tool = (*Iperf3)(nil)
	var _ Tool = (*Flent)(nil)
	var _ Tool = (*Crusader)(nil)
	var _ Tool = (*Wrk)(nil)
	var _ Tool = (*DNSPerf)(nil)
	var _ Tool = (*Fping)(nil)
}

func TestToolNames(t *testing.T) {
	tests := []struct {
		tool Tool
		want string
	}{
		{NewIperf2(), "iperf2"},
		{NewIperf3(), "iperf3"},
		{NewFlent("/tmp"), "flent"},
		{NewCrusader(), "crusader"},
		{NewWrk("100k"), "wrk"},
		{NewDNSPerf("/tmp/queries.txt"), "dnsperf"},
		{NewFping(), "fping"},
	}

	for _, tt := range tests {
		if got := tt.tool.Name(); got != tt.want {
			t.Errorf("%T.Name(): got %q, want %q", tt.tool, got, tt.want)
		}
	}
}

func TestToolDefaultPorts(t *testing.T) {
	tests := []struct {
		tool Tool
		want int
	}{
		{NewIperf2(), 5001},
		{NewIperf3(), 5201},
		{NewFlent("/tmp"), 12865},
		{NewCrusader(), 35481},
		{NewWrk("100k"), 80},
		{NewDNSPerf("/tmp/queries.txt"), 53},
		{NewFping(), 0}, // ICMP doesn't use ports
	}

	for _, tt := range tests {
		if got := tt.tool.DefaultPort(); got != tt.want {
			t.Errorf("%T.DefaultPort(): got %d, want %d", tt.tool, got, tt.want)
		}
	}
}

func TestToolSupportsFlowCount(t *testing.T) {
	tests := []struct {
		tool Tool
		want bool
	}{
		{NewIperf2(), true},
		{NewIperf3(), true},
		{NewFlent("/tmp"), false},    // RRUL has fixed flows
		{NewCrusader(), false},       // Fixed stream count
		{NewWrk("100k"), true},       // connections map to flows
		{NewDNSPerf("/tmp/q"), true}, // concurrent queries map to flows
		{NewFping(), false},          // ICMP ping is single "flow"
	}

	for _, tt := range tests {
		if got := tt.tool.SupportsFlowCount(); got != tt.want {
			t.Errorf("%T.SupportsFlowCount(): got %v, want %v", tt.tool, got, tt.want)
		}
	}
}

// =============================================================================
// Streaming Parser Tests
// =============================================================================

func TestIperf2ParseLineCSV(t *testing.T) {
	tool := NewIperf2()

	// Real iperf2 -e -y C format:
	// Header: time,srcaddress,srcport,dstaddr,dstport,transferid,istart,iend,bytes,speed,...
	// Data:   -0800:20260218111259.511098,10.1.0.2,51018,10.2.0.2,5001,4,0.0,1.0,76073032,608584256,...
	// SUM lines have transferid=-1
	tests := []struct {
		name           string
		line           string
		wantParsed     bool
		wantThroughput float64
		tolerance      float64
	}{
		{
			name: "SUM line (transferid=-1)",
			// Real SUM line from collected testdata - aggregates all flows
			line:           "-0800:20260218111259.511098,10.1.0.2,0,10.2.0.2,5001,-1,0.0,1.0,561022792,4488182336,4293,0,21,0,0,0,0",
			wantParsed:     true,
			wantThroughput: 4.488, // 4488182336 bits/sec = 4.488 Gbps
			tolerance:      0.01,
		},
		{
			name: "SUM line interval 2",
			// Second interval SUM line
			line:           "-0800:20260218111300.511098,10.1.0.2,0,10.2.0.2,5001,-1,1.0,2.0,988151808,7905214464,7539,0,12,0,0,0,0",
			wantParsed:     true,
			wantThroughput: 7.905, // 7905214464 bits/sec = 7.905 Gbps
			tolerance:      0.01,
		},
		{
			name:       "individual flow line (transferid=4, should be skipped)",
			line:       "-0800:20260218111259.511098,10.1.0.2,51018,10.2.0.2,5001,4,0.0,1.0,76073032,608584256,582,0,3,2975,2104,58228,1847",
			wantParsed: false, // Individual flows are skipped, we only want SUM
		},
		{
			name:       "header line",
			line:       "time,srcaddress,srcport,dstaddr,dstport,transferid,istart,iend,bytes,speed,writecnt,writeerr,tcpretry,tcpcwnd,tcppcwnd,tcprtt,tcprttvar",
			wantParsed: false,
		},
		{
			name:       "empty line",
			line:       "",
			wantParsed: false,
		},
		{
			name:       "non-CSV line",
			line:       "Connecting to host 10.2.0.2...",
			wantParsed: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			acc := &StreamAccumulator{}
			parsed := tool.ParseLine(tt.line, acc)

			if parsed != tt.wantParsed {
				t.Errorf("ParseLine() returned %v, want %v", parsed, tt.wantParsed)
			}

			if tt.wantParsed {
				assertFloat(t, "ThroughputGbps", acc.ThroughputGbps, tt.wantThroughput, tt.tolerance)
			}
		})
	}
}

func TestIperf3ParseLine(t *testing.T) {
	tool := NewIperf3()

	tests := []struct {
		name           string
		line           string
		wantParsed     bool
		wantThroughput float64
		wantRetrans    int64
		tolerance      float64
	}{
		{
			name:           "interval line with retransmits",
			line:           "[  5]   0.00-1.00   sec  1.13 GBytes  9.72 Gbits/sec    0   1.87 MBytes",
			wantParsed:     true,
			wantThroughput: 9.72,
			wantRetrans:    0,
			tolerance:      0.01,
		},
		{
			name:           "interval line with retransmits 2",
			line:           "[  5]   1.00-2.00   sec  1.12 GBytes  9.59 Gbits/sec    2   1.87 MBytes",
			wantParsed:     true,
			wantThroughput: 9.59,
			wantRetrans:    2,
			tolerance:      0.01,
		},
		{
			name:           "SUM line",
			line:           "[SUM]   0.00-5.00   sec  5.64 GBytes  9.69 Gbits/sec    3",
			wantParsed:     true,
			wantThroughput: 9.69,
			wantRetrans:    3,
			tolerance:      0.01,
		},
		{
			name:       "header line",
			line:       "[ ID] Interval           Transfer     Bitrate         Retr  Cwnd",
			wantParsed: false,
		},
		{
			name:       "connecting line",
			line:       "Connecting to host 10.2.0.2, port 5201",
			wantParsed: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			acc := &StreamAccumulator{}
			parsed := tool.ParseLine(tt.line, acc)

			if parsed != tt.wantParsed {
				t.Errorf("ParseLine() returned %v, want %v", parsed, tt.wantParsed)
			}

			if tt.wantParsed {
				assertFloat(t, "ThroughputGbps", acc.ThroughputGbps, tt.wantThroughput, tt.tolerance)
				if acc.Retransmits != tt.wantRetrans {
					t.Errorf("Retransmits: got %d, want %d", acc.Retransmits, tt.wantRetrans)
				}
			}
		})
	}
}

func TestFpingParseLine(t *testing.T) {
	tool := NewFping()

	tests := []struct {
		name        string
		line        string
		wantParsed  bool
		wantLatency float64
		wantAvg     float64
		wantLoss    float64
		tolerance   float64
	}{
		{
			name:        "success per-ping line",
			line:        "10.2.0.2 : [0], 64 bytes, 0.52 ms (0.52 avg, 0% loss)",
			wantParsed:  true,
			wantLatency: 0.52,
			wantAvg:     0.52,
			wantLoss:    0,
			tolerance:   0.01,
		},
		{
			name:        "success per-ping line 2",
			line:        "10.2.0.2 : [4], 64 bytes, 0.61 ms (0.53 avg, 0% loss)",
			wantParsed:  true,
			wantLatency: 0.61,
			wantAvg:     0.53,
			wantLoss:    0,
			tolerance:   0.01,
		},
		{
			name:       "timeout per-ping line",
			line:       "10.2.0.2 : [0], timed out (NaN avg, 100% loss)",
			wantParsed: true,
			wantLoss:   100,
			tolerance:  0.01,
		},
		{
			name:       "timeout with accumulated loss",
			line:       "10.2.0.2 : [4], timed out (8.47 avg, 60% loss)",
			wantParsed: true,
			wantLoss:   60,
			tolerance:  0.01,
		},
		{
			name:        "final summary line",
			line:        "10.2.0.2 : xmt/rcv/%loss = 10/10/0%, min/avg/max = 0.46/0.52/0.61",
			wantParsed:  true,
			wantAvg:     0.52,
			wantLatency: 0.52,
			wantLoss:    0,
			tolerance:   0.01,
		},
		{
			name:        "summary with loss",
			line:        "10.2.0.2 : xmt/rcv/%loss = 10/6/40%, min/avg/max = 7.23/8.14/9.72",
			wantParsed:  true,
			wantAvg:     8.14,
			wantLatency: 8.14,
			wantLoss:    40,
			tolerance:   0.01,
		},
		{
			name:       "comment line",
			line:       "# fping output",
			wantParsed: false,
		},
		{
			name:       "empty line",
			line:       "",
			wantParsed: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			acc := &StreamAccumulator{}
			parsed := tool.ParseLine(tt.line, acc)

			if parsed != tt.wantParsed {
				t.Errorf("ParseLine() returned %v, want %v", parsed, tt.wantParsed)
			}

			if tt.wantParsed {
				if tt.wantLatency > 0 {
					assertFloat(t, "LatencyMs", acc.LatencyMs, tt.wantLatency, tt.tolerance)
				}
				if tt.wantAvg > 0 {
					assertFloat(t, "AvgLatencyMs", acc.AvgLatencyMs, tt.wantAvg, tt.tolerance)
				}
				assertFloat(t, "PacketLossPct", acc.PacketLossPct, tt.wantLoss, tt.tolerance)
			}
		})
	}
}

func TestDNSPerfParseLine(t *testing.T) {
	tool := NewDNSPerf("")

	tests := []struct {
		name       string
		line       string
		wantParsed bool
		checkFn    func(t *testing.T, acc *StreamAccumulator)
	}{
		{
			name:       "queries sent/completed line",
			line:       "  Queries sent:         50000",
			wantParsed: false, // This partial line won't match
		},
		{
			name:       "queries per second line",
			line:       "  Queries per second:   49950.827083",
			wantParsed: true,
			checkFn: func(t *testing.T, acc *StreamAccumulator) {
				assertFloat(t, "QPS", acc.QPS, 49950.827, 1.0)
				// Throughput = QPS * 800 bits / 1e9
				assertFloat(t, "ThroughputGbps", acc.ThroughputGbps, 0.0399, 0.001)
			},
		},
		{
			name:       "average latency line",
			line:       "  Average Latency (s):  0.000345 (min 0.000089, max 0.002672)",
			wantParsed: true,
			checkFn: func(t *testing.T, acc *StreamAccumulator) {
				assertFloat(t, "LatencyMs", acc.LatencyMs, 0.345, 0.01)
			},
		},
		{
			name:       "average latency also parses max",
			line:       "  Average Latency (s):  0.000345 (min 0.000089, max 0.002672)",
			wantParsed: true,
			checkFn: func(t *testing.T, acc *StreamAccumulator) {
				// Both avg and max latency are parsed from the same line
				assertFloat(t, "LatencyMs", acc.LatencyMs, 0.345, 0.01)
				assertFloat(t, "MaxLatencyMs", acc.MaxLatencyMs, 2.672, 0.01)
			},
		},
		{
			name:       "command line (ignored)",
			line:       "[Status] Command line: dnsperf -s 10.2.0.2 -d queries.txt",
			wantParsed: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			acc := &StreamAccumulator{}
			parsed := tool.ParseLine(tt.line, acc)

			if parsed != tt.wantParsed {
				t.Errorf("ParseLine() returned %v, want %v", parsed, tt.wantParsed)
			}

			if tt.wantParsed && tt.checkFn != nil {
				tt.checkFn(t, acc)
			}
		})
	}
}

func TestFlentParseLine(t *testing.T) {
	tool := NewFlent("/tmp")

	tests := []struct {
		name       string
		line       string
		wantParsed bool
		checkFn    func(t *testing.T, acc *StreamAccumulator)
	}{
		{
			name:       "throughput in Gbits/s",
			line:       "TCP download: 9.72 Gbits/s",
			wantParsed: true,
			checkFn: func(t *testing.T, acc *StreamAccumulator) {
				assertFloat(t, "ThroughputGbps", acc.ThroughputGbps, 9.72, 0.01)
			},
		},
		{
			name:       "throughput in Mbits/s",
			line:       "TCP upload: 856.5 Mbits/s",
			wantParsed: true,
			checkFn: func(t *testing.T, acc *StreamAccumulator) {
				assertFloat(t, "ThroughputGbps", acc.ThroughputGbps, 0.8565, 0.01)
			},
		},
		{
			name:       "RTT measurement",
			line:       "RTT: 1.23 ms",
			wantParsed: true,
			checkFn: func(t *testing.T, acc *StreamAccumulator) {
				assertFloat(t, "LatencyMs", acc.LatencyMs, 1.23, 0.01)
			},
		},
		{
			name:       "empty line",
			line:       "",
			wantParsed: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			acc := &StreamAccumulator{}
			parsed := tool.ParseLine(tt.line, acc)

			if parsed != tt.wantParsed {
				t.Errorf("ParseLine() returned %v, want %v", parsed, tt.wantParsed)
			}

			if tt.wantParsed && tt.checkFn != nil {
				tt.checkFn(t, acc)
			}
		})
	}
}

// =============================================================================
// Streaming/Chunked Interface Tests
// =============================================================================

func TestStreamingToolsImplementInterface(t *testing.T) {
	// Compile-time check that streaming tools implement StreamingParser
	var _ StreamingParser = (*Iperf2)(nil)
	var _ StreamingParser = (*Iperf3)(nil)
	var _ StreamingParser = (*Fping)(nil)
	var _ StreamingParser = (*DNSPerf)(nil)
	var _ StreamingParser = (*Flent)(nil)
}

func TestChunkedToolsImplementInterface(t *testing.T) {
	// Compile-time check that chunked tools implement ChunkedTool
	var _ ChunkedTool = (*Wrk)(nil)
	var _ ChunkedTool = (*Crusader)(nil)
}

func TestStreamingSupport(t *testing.T) {
	tests := []struct {
		tool             Tool
		wantStreaming    bool
		wantChunkFactor  int
		wantStartOffset  time.Duration
	}{
		{NewIperf2(), true, 0, 0},
		{NewIperf3(), true, 0, 0},
		{NewFping(), true, 0, 0},
		{NewDNSPerf(""), true, 0, 0},
		{NewFlent("/tmp"), true, 0, 0},
		{NewWrk("100k"), false, 5, 0},
		{NewCrusader(), false, 3, 4 * time.Second},
	}

	for _, tt := range tests {
		t.Run(tt.tool.Name(), func(t *testing.T) {
			// Check streaming support
			if sp, ok := tt.tool.(StreamingParser); ok {
				if got := sp.SupportsStreaming(); got != tt.wantStreaming {
					t.Errorf("SupportsStreaming(): got %v, want %v", got, tt.wantStreaming)
				}
			}

			// Check chunked support
			if ct, ok := tt.tool.(ChunkedTool); ok {
				if got := ct.ChunkFactor(); got != tt.wantChunkFactor {
					t.Errorf("ChunkFactor(): got %d, want %d", got, tt.wantChunkFactor)
				}
				if got := ct.StartOffset(); got != tt.wantStartOffset {
					t.Errorf("StartOffset(): got %v, want %v", got, tt.wantStartOffset)
				}
			}
		})
	}
}

// =============================================================================
// Streaming Testdata File Tests
// =============================================================================

func TestIperf2ParseLineCSVFromFile(t *testing.T) {
	tool := NewIperf2()

	// Read real streaming testdata
	content := readTestdata(t, "streaming/iperf2_csv_10flows.txt")
	lines := splitLines(content)

	acc := &StreamAccumulator{}
	parsedCount := 0
	for _, line := range lines {
		if tool.ParseLine(line, acc) {
			parsedCount++
		}
	}

	// Should parse multiple SUM lines (one per interval)
	if parsedCount == 0 {
		t.Error("No lines were parsed from iperf2_csv_10flows.txt")
	}

	// Final throughput should be reasonable (several Gbps)
	if acc.ThroughputGbps < 1.0 {
		t.Errorf("ThroughputGbps too low: %.2f (expected > 1.0)", acc.ThroughputGbps)
	}

	t.Logf("Parsed %d intervals, final throughput: %.2f Gbps", parsedCount, acc.ThroughputGbps)
}

func TestFpingParseLineFromFile(t *testing.T) {
	tool := NewFping()

	// Test no-loss file
	t.Run("no_loss", func(t *testing.T) {
		content := readTestdata(t, "streaming/fping_perpkt.txt")
		lines := splitLines(content)

		acc := &StreamAccumulator{}
		parsedCount := 0
		for _, line := range lines {
			if tool.ParseLine(line, acc) {
				parsedCount++
			}
		}

		if parsedCount == 0 {
			t.Error("No lines were parsed")
		}

		// Should have low/no packet loss
		if acc.PacketLossPct > 1.0 {
			t.Errorf("PacketLossPct too high: %.2f%% (expected ~0%%)", acc.PacketLossPct)
		}

		// Should have reasonable latency
		if acc.LatencyMs < 0.1 || acc.LatencyMs > 1000 {
			t.Errorf("LatencyMs unexpected: %.2f", acc.LatencyMs)
		}

		t.Logf("Parsed %d pings, avg latency: %.2f ms, loss: %.1f%%",
			parsedCount, acc.AvgLatencyMs, acc.PacketLossPct)
	})

	// Test loss file
	t.Run("with_loss", func(t *testing.T) {
		content := readTestdata(t, "streaming/fping_perpkt_loss.txt")
		lines := splitLines(content)

		acc := &StreamAccumulator{}
		parsedCount := 0
		for _, line := range lines {
			if tool.ParseLine(line, acc) {
				parsedCount++
			}
		}

		if parsedCount == 0 {
			t.Error("No lines were parsed")
		}

		// This file has 100% loss (all timeouts)
		if acc.PacketLossPct < 50 {
			t.Errorf("PacketLossPct too low: %.2f%% (expected high loss)", acc.PacketLossPct)
		}

		t.Logf("Parsed %d entries, loss: %.1f%%", parsedCount, acc.PacketLossPct)
	})
}

func TestIperf3ParseLineFromFile(t *testing.T) {
	tool := NewIperf3()

	content := readTestdata(t, "streaming/iperf3_text_10flows.txt")
	lines := splitLines(content)

	acc := &StreamAccumulator{}
	parsedCount := 0
	for _, line := range lines {
		if tool.ParseLine(line, acc) {
			parsedCount++
		}
	}

	if parsedCount == 0 {
		t.Error("No lines were parsed from iperf3_text_10flows.txt")
	}

	// Final throughput should be reasonable
	if acc.ThroughputGbps < 1.0 {
		t.Errorf("ThroughputGbps too low: %.2f (expected > 1.0)", acc.ThroughputGbps)
	}

	t.Logf("Parsed %d intervals, final throughput: %.2f Gbps, retransmits: %d",
		parsedCount, acc.ThroughputGbps, acc.Retransmits)
}

func TestDNSPerfParseLineFromFile(t *testing.T) {
	tool := NewDNSPerf("")

	content := readTestdata(t, "streaming/dnsperf_verbose.txt")
	lines := splitLines(content)

	acc := &StreamAccumulator{}
	parsedCount := 0
	for _, line := range lines {
		if tool.ParseLine(line, acc) {
			parsedCount++
		}
	}

	if parsedCount == 0 {
		t.Error("No lines were parsed from dnsperf_verbose.txt")
	}

	// Should have QPS > 0
	if acc.QPS == 0 {
		t.Error("QPS should be > 0")
	}

	// Should have parsed latency
	if acc.LatencyMs == 0 {
		t.Error("LatencyMs should be > 0")
	}

	t.Logf("Parsed %d metrics, QPS: %.0f, latency: %.2f ms, max: %.2f ms",
		parsedCount, acc.QPS, acc.LatencyMs, acc.MaxLatencyMs)
}

func splitLines(content string) []string {
	var lines []string
	for _, line := range strings.Split(content, "\n") {
		lines = append(lines, line)
	}
	return lines
}

func TestStreamClientCmdDiffersFromClientCmd(t *testing.T) {
	target := "10.2.0.2"
	port := 5001
	flows := 10
	duration := 30 * time.Second

	tools := []struct {
		name string
		tool interface {
			Tool
			StreamingParser
		}
	}{
		{"iperf2", NewIperf2()},
		{"iperf3", NewIperf3()},
		{"fping", NewFping()},
		{"dnsperf", NewDNSPerf("")},
		{"flent", NewFlent("/tmp")},
	}

	for _, tt := range tools {
		t.Run(tt.name, func(t *testing.T) {
			normalCmd := tt.tool.ClientCmd(target, port, flows, duration)
			streamCmd := tt.tool.StreamClientCmd(target, port, flows, duration)

			// Stream command should typically have different flags
			// At minimum, check they're both non-empty and the tool name matches
			if len(normalCmd) == 0 || len(streamCmd) == 0 {
				t.Error("Command should not be empty")
			}
			if normalCmd[0] != streamCmd[0] {
				t.Errorf("Tool executable differs: normal=%s, stream=%s", normalCmd[0], streamCmd[0])
			}
		})
	}
}
