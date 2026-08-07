# nix/constants.nix
#
# Shared constants for K8s MicroVM cluster infrastructure.
# All network params, serial ports, k8s CIDRs, cert config, lifecycle timeouts.
#
# Topology: 3 control planes (cp0, cp1, cp2) + 1 worker (w3)
#
rec {
  # ─── Node Configuration ──────────────────────────────────────────────
  nodeNames = [ "cp0" "cp1" "cp2" "w3" ];

  # ─── Network Configuration ──────────────────────────────────────────
  network = {
    bridge = "k8sbr0";

    # Per-node TAP devices
    taps = {
      cp0 = "k8stap0";
      cp1 = "k8stap1";
      cp2 = "k8stap2";
      w3  = "k8stap3";
    };

    # Host bridge addresses (dual-stack)
    gateway4 = "10.33.33.1";
    gateway6 = "fd33:33:33::1";
    subnet4 = "10.33.33.0/24";
    subnet6 = "fd33:33:33::/64";

    # Per-node IP addresses
    ipv4 = {
      cp0 = "10.33.33.10";
      cp1 = "10.33.33.11";
      cp2 = "10.33.33.12";
      w3  = "10.33.33.13";
    };
    ipv6 = {
      cp0 = "fd33:33:33::10";
      cp1 = "fd33:33:33::11";
      cp2 = "fd33:33:33::12";
      w3  = "fd33:33:33::13";
    };

    # Per-node MAC addresses
    macs = {
      cp0 = "02:00:0a:21:21:10";
      cp1 = "02:00:0a:21:21:11";
      cp2 = "02:00:0a:21:21:12";
      w3  = "02:00:0a:21:21:13";
    };
  };

  # ─── Kubernetes Network CIDRs ──────────────────────────────────────
  k8s = {
    podCidr4 = "10.244.0.0/16";
    podCidr6 = "fd44:44:44::/48";
    serviceCidr4 = "10.96.0.0/12";
    serviceCidr6 = "fd96:96:96::/108";

    # First service IP (kubernetes.default)
    apiServiceIp = "10.96.0.1";

    # API endpoint via host-side load balancer (haproxy on bridge IP)
    apiEndpoint = "https://${network.gateway4}:6443";

    # DNS
    clusterDomain = "cluster.local";
    dnsServiceIp = "10.96.0.10";

    # PKI directory inside VMs
    pkiDir = "/var/lib/kubernetes/pki";

    # Cert output directory on host
    certDir = "./certs";
  };

  # ─── Serial Console Configuration ──────────────────────────────────
  # Each node gets 10 ports starting at base 25500.
  # +0 = serial (ttyS0), +1 = virtio (hvc0), +2-9 = reserved
  console = {
    portBase = 25500;
    serialOffset = 0;
    virtioOffset = 1;

    nodeBlocks = {
      cp0 = 0;    # 25500-25509
      cp1 = 10;   # 25510-25519
      cp2 = 20;   # 25520-25529
      w3  = 30;   # 25530-25539
    };
  };

  # ─── VM Resources ──────────────────────────────────────────────────
  vm = {
    controlPlane = {
      memoryMB = 4095;  # 4GB (avoid exact power-of-2 — QEMU hangs)
      vcpus = 4;
    };
    worker = {
      memoryMB = 3071;  # 3GB (avoid exact power-of-2 — QEMU hangs)
      vcpus = 2;
    };
  };

  # ─── SSH Configuration ─────────────────────────────────────────────
  ssh = {
    password = "k8s";
    user = "root";
  };

  # ─── Lifecycle Test Configuration ──────────────────────────────────
  lifecycle = {
    pollInterval = 1;

    timeouts = {
      build = 900;
      processStart = 5;
      serialReady = 30;
      virtioReady = 45;
      sshReady = 90;
      certInject = 30;
      serviceReady = 90;
      k8sHealth = 90;
      shutdown = 30;
      waitExit = 60;
    };

    # Cluster-level test timeouts
    clusterTimeouts = {
      nodesReady = 180;
      ciliumReady = 120;
      workloadsReady = 120;
    };
  };

  # ─── Helper Functions ──────────────────────────────────────────────

  # Get console ports for a node
  getConsolePorts = node: {
    serial = console.portBase + console.nodeBlocks.${node} + console.serialOffset;
    virtio = console.portBase + console.nodeBlocks.${node} + console.virtioOffset;
  };

  # Get hostname for a node
  getHostname = node: "k8s-${node}";

  # Get process name for pgrep matching
  getProcessName = node: getHostname node;

  # Get timeout for a phase (no per-node overrides for now)
  getTimeout = _node: phase: lifecycle.timeouts.${phase};

  # Get all node IPv4 addresses as a list
  allNodeIps4 = builtins.map (n: network.ipv4.${n}) nodeNames;

  # Get all node IPv6 addresses as a list
  allNodeIps6 = builtins.map (n: network.ipv6.${n}) nodeNames;

  # Get VM resources for a role
  getVmResources = role:
    if role == "control-plane" then vm.controlPlane
    else vm.worker;
}
