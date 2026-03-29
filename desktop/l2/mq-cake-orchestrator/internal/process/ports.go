// internal/process/ports.go
package process

import (
	"fmt"
	"sync"
)

// PortRange defines the port allocation range for a tool
type PortRange struct {
	Base int // Starting port number
	Max  int // Maximum instances (determines port range)
}

// DefaultPortRanges defines port allocation for each tool
var DefaultPortRanges = map[string]PortRange{
	"iperf2":   {Base: 5001, Max: 1},    // Single server, multiple clients connect to it
	"iperf3":   {Base: 5201, Max: 100},  // Multiple servers needed (1 client per server)
	"netperf":  {Base: 12865, Max: 1},   // Single server for flent
	"flent":    {Base: 12865, Max: 1},   // Uses netperf, single instance
	"crusader": {Base: 35481, Max: 1},   // Crusader default port
	"wrk":      {Base: 80, Max: 1},      // nginx (external), single instance
	"dnsperf":  {Base: 53, Max: 1},      // pdns (external), single instance
	"fping":    {Base: 0, Max: 1},       // ICMP, no port needed
}

// PortAllocator manages port allocation for multiple tool instances
type PortAllocator struct {
	mu       sync.Mutex
	ranges   map[string]PortRange
	inUse    map[string]map[int]bool // tool -> set of in-use ports
	nextPort map[string]int          // tool -> next port to try
}

// NewPortAllocator creates a new port allocator with default ranges
func NewPortAllocator() *PortAllocator {
	pa := &PortAllocator{
		ranges:   make(map[string]PortRange),
		inUse:    make(map[string]map[int]bool),
		nextPort: make(map[string]int),
	}
	// Copy default ranges
	for tool, pr := range DefaultPortRanges {
		pa.ranges[tool] = pr
		pa.inUse[tool] = make(map[int]bool)
		pa.nextPort[tool] = pr.Base
	}
	return pa
}

// Allocate returns an available port for the given tool
func (pa *PortAllocator) Allocate(tool string) (int, error) {
	pa.mu.Lock()
	defer pa.mu.Unlock()

	pr, ok := pa.ranges[tool]
	if !ok {
		return 0, fmt.Errorf("unknown tool: %s", tool)
	}

	// Find an available port
	for i := 0; i < pr.Max; i++ {
		port := pr.Base + i
		if !pa.inUse[tool][port] {
			pa.inUse[tool][port] = true
			return port, nil
		}
	}

	return 0, fmt.Errorf("no available ports for %s (all %d in use)", tool, pr.Max)
}

// Release returns a port back to the pool
func (pa *PortAllocator) Release(tool string, port int) {
	pa.mu.Lock()
	defer pa.mu.Unlock()

	if ports, ok := pa.inUse[tool]; ok {
		delete(ports, port)
	}
}

// ReleaseAll releases all ports for a tool
func (pa *PortAllocator) ReleaseAll(tool string) {
	pa.mu.Lock()
	defer pa.mu.Unlock()

	if _, ok := pa.inUse[tool]; ok {
		pa.inUse[tool] = make(map[int]bool)
	}
}

// InUseCount returns the number of ports currently in use for a tool
func (pa *PortAllocator) InUseCount(tool string) int {
	pa.mu.Lock()
	defer pa.mu.Unlock()

	if ports, ok := pa.inUse[tool]; ok {
		return len(ports)
	}
	return 0
}

// MaxInstances returns the maximum number of instances for a tool
func (pa *PortAllocator) MaxInstances(tool string) int {
	if pr, ok := pa.ranges[tool]; ok {
		return pr.Max
	}
	return 0
}
