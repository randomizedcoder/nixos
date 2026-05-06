# K8s MicroVM Cluster

HA Kubernetes cluster (3 control planes + 1 worker) running as NixOS MicroVMs with QEMU. All PKI is generated at Nix build time and baked into VM images. Host-side haproxy provides apiserver HA. Uses Cilium CNI, dual-stack networking, and GitOps deployment via ArgoCD.

## Architecture

```
Host Machine (NixOS)
├── k8sbr0 (bridge): 10.33.33.1/24, fd33:33:33::1/64
│   ├── k8stap0 → cp0  10.33.33.10  fd33:33:33::10  serial:25500 virtio:25501
│   ├── k8stap1 → cp1  10.33.33.11  fd33:33:33::11  serial:25510 virtio:25511
│   ├── k8stap2 → cp2  10.33.33.12  fd33:33:33::12  serial:25520 virtio:25521
│   └── k8stap3 → w3   10.33.33.13  fd33:33:33::13  serial:25530 virtio:25531
├── haproxy on 10.33.33.1:6443 → load-balances to cp0, cp1, cp2
├── nftables NAT: masquerade outbound only (VM-to-VM traffic stays un-NATed)
└── IP forwarding enabled (v4 + v6)

K8s Internal Networks (Cilium-managed):
  Pod CIDR:     10.244.0.0/16, fd44:44:44::/48
  Service CIDR: 10.96.0.0/12,  fd96:96:96::/108

HA: 3-node etcd quorum (tolerates 1 CP failure), haproxy LB for apiserver
```

**cp0, cp1, cp2** (control planes): etcd, kube-apiserver, kube-controller-manager, kube-scheduler, containerd, kubelet
**w3** (worker): containerd, kubelet

## Quick Start

```bash
# Enter the dev shell (kubectl, helm, cilium-cli, step-cli, argocd, socat, expect, ...)
nix develop

# Verify the host has /dev/net/tun, vhost_net, bridge module, sudo
nix run .#k8s-check-host

# Create bridge, 4 TAP devices, nftables NAT, haproxy apiserver LB
sudo nix run .#k8s-network-setup

# Build and start all 4 VMs (3 CPs first, then worker)
# PKI is generated at build time and baked into VM images — no separate cert step needed
nix run .#k8s-start-all

# Verify the cluster (3 control planes + 1 worker)
nix run .#k8s-vm-ssh -- --node=cp0 kubectl get nodes
```

## Certificate Architecture (PKI)

All certificates are generated at `nix build` time by `certs.nix` and baked directly into VM images. There is no runtime certificate injection — VMs boot with all PKI material already in place at `/var/lib/kubernetes/pki/`.

### Certificate Authorities (3 independent CAs)

The cluster uses three separate CA hierarchies to isolate trust domains:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Certificate Authorities                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐  │
│  │  k8s-cluster-ca  │  │     etcd-ca      │  │    front-proxy-ca       │  │
│  │  (ca.crt/ca.key) │  │  (etcd-ca.crt/   │  │  (front-proxy-ca.crt/  │  │
│  │                  │  │   etcd-ca.key)   │  │   front-proxy-ca.key)  │  │
│  └────────┬─────────┘  └────────┬─────────┘  └────────────┬───────────┘  │
│           │                     │                          │              │
│  Signs:   │            Signs:   │                 Signs:   │              │
│  ┌────────┴──────────┐ ┌───────┴──────────┐    ┌─────────┴──────────┐   │
│  │ apiserver.crt     │ │ etcd-server.crt  │    │ front-proxy-client │   │
│  │ apiserver-kubelet │ │ etcd-peer.crt    │    │   .crt             │   │
│  │  -client.crt      │ │ apiserver-etcd   │    └────────────────────┘   │
│  │ kubelet-{node}.crt│ │  -client.crt     │                             │
│  │ controller-       │ └──────────────────┘                             │
│  │  manager.crt      │                                                   │
│  │ scheduler.crt     │                                                   │
│  │ admin.crt         │                                                   │
│  └───────────────────┘                                                   │
│                                                                             │
│  + Service Account keypair (sa.key / sa.pub) — RSA 2048, signs JWTs       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Chain of Trust

```
k8s-cluster-ca (ca.crt)
├── apiserver.crt              API server TLS (serves on :6443)
│   SANs: kubernetes, kubernetes.default, kubernetes.default.svc,
│         kubernetes.default.svc.cluster.local, 10.96.0.1,
│         10.33.33.1 (haproxy VIP), 127.0.0.1, ::1,
│         10.33.33.{10,11,12,13}, fd33:33:33::{10,11,12,13}
├── apiserver-kubelet-client.crt   apiserver → kubelet mTLS client
├── kubelet-cp0.crt            kubelet identity (CN=system:node:k8s-cp0, O=system:nodes)
├── kubelet-cp1.crt            kubelet identity (CN=system:node:k8s-cp1, O=system:nodes)
├── kubelet-cp2.crt            kubelet identity (CN=system:node:k8s-cp2, O=system:nodes)
├── kubelet-w3.crt             kubelet identity (CN=system:node:k8s-w3, O=system:nodes)
├── controller-manager.crt     CN=system:kube-controller-manager
├── scheduler.crt              CN=system:kube-scheduler
└── admin.crt                  CN=kubernetes-admin, O=system:masters (cluster-admin)

etcd-ca (etcd-ca.crt)
├── etcd-server-{cp0,cp1,cp2}.crt   etcd TLS server (per-node)
│   SANs: localhost, 127.0.0.1, ::1, all node IPs
├── etcd-peer-{cp0,cp1,cp2}.crt     etcd peer-to-peer mTLS (per-node)
│   SANs: localhost, 127.0.0.1, ::1, all node IPs
└── apiserver-etcd-client.crt        apiserver → etcd mTLS client

front-proxy-ca (front-proxy-ca.crt)
└── front-proxy-client.crt     aggregation layer (API extension servers)

sa.key / sa.pub (RSA 2048)
└── Used by apiserver to sign and verify ServiceAccount JWTs
```

### Per-Node Certificate Bundles

Each VM receives only the certs it needs, assembled by `mkNodePki` in `certs.nix`:

| File | Control Plane | Worker | Purpose |
|------|:---:|:---:|---------|
| ca.crt, ca.key | Y | Y | Cluster CA (verify + sign) |
| etcd-ca.crt | Y | Y | Verify etcd connections |
| front-proxy-ca.crt | Y | Y | Verify aggregation layer |
| sa.pub, sa.key | Y | Y | ServiceAccount token verify/sign |
| kubelet.crt, kubelet.key | Y | Y | Node identity (per-node CN) |
| kubelet-kubeconfig | Y | Y | kubelet → apiserver auth |
| kubelet-config.yaml | Y | Y | kubelet runtime config |
| apiserver.crt, apiserver.key | Y | - | API server TLS |
| apiserver-kubelet-client.crt/key | Y | - | apiserver → kubelet mTLS |
| apiserver-etcd-client.crt/key | Y | - | apiserver → etcd mTLS |
| front-proxy-ca.key | Y | - | Sign aggregation certs |
| front-proxy-client.crt/key | Y | - | Aggregation layer client |
| etcd-ca.key | Y | - | Sign etcd certs |
| etcd-server.crt/key | Y | - | etcd TLS server (per-node) |
| etcd-peer.crt/key | Y | - | etcd peer mTLS (per-node) |
| controller-manager.crt/key | Y | - | Controller manager identity |
| scheduler.crt/key | Y | - | Scheduler identity |
| admin.crt/key | Y | - | Cluster admin (kubectl) |
| controller-manager-kubeconfig | Y | - | CM → apiserver auth |
| scheduler-kubeconfig | Y | - | Scheduler → apiserver auth |
| admin-kubeconfig | Y | - | Admin → apiserver auth |

**Total: 33 files per control plane, 10 files per worker.**

### How Certs Flow from Build to VM

```
nix build .#k8s-microvm-cp0
        │
        ▼
  ┌─────────────┐     ┌──────────────────┐     ┌─────────────────────┐
  │  certs.nix  │────▶│    pkiStore      │────▶│  mkNodePki          │
  │  (step-cli  │     │  /nix/store/...  │     │  Selects per-node   │
  │   openssl)  │     │  All 50+ certs   │     │  subset (33 or 10)  │
  └─────────────┘     └──────────────────┘     └──────────┬──────────┘
                                                          │
                                                          ▼
                                               ┌─────────────────────┐
                                               │   microvm.nix       │
                                               │   NixOS activation  │
                                               │   script copies     │
                                               │   from /nix/store   │
                                               │   → /var/lib/       │
                                               │   kubernetes/pki/   │
                                               └─────────────────────┘
```

All kubeconfigs point to `https://10.33.33.1:6443` (the haproxy VIP), not to any individual control plane node. This means kubelets and kubectl work through the load balancer for HA.

## API Server High Availability (haproxy)

The cluster uses a host-side haproxy to load-balance the Kubernetes API endpoint across all 3 control plane nodes. This solves the chicken-and-egg problem: kubelets and Cilium need a stable apiserver endpoint before in-cluster service routing exists.

### Why haproxy on the Host?

```
                    ┌─────────────────────────────────────────┐
                    │              Host Machine                │
                    │                                         │
  kubectl ──────┐   │   haproxy (10.33.33.1:6443)            │
                │   │     │  TCP mode, round-robin            │
  kubelet ──────┤   │     │  health: TCP check every 5s      │
   (all nodes)  │   │     │  tolerates: 1 CP down            │
                ├───┼────▶│                                   │
  Cilium ───────┤   │     ├──▶ cp0 (10.33.33.10:6443)       │
   agent        │   │     ├──▶ cp1 (10.33.33.11:6443)       │
                │   │     └──▶ cp2 (10.33.33.12:6443)       │
  controller ───┘   │                                         │
   -manager         │    Backend health: check inter 5s       │
                    │    fall 3 (mark down after 3 fails)     │
                    │    rise 2 (mark up after 2 successes)   │
                    └─────────────────────────────────────────┘
```

### HA Behavior

| Scenario | Behavior |
|----------|----------|
| All 3 CPs healthy | Round-robin across cp0, cp1, cp2 |
| 1 CP down | haproxy detects in ~15s (3 x 5s), routes to remaining 2 |
| 2 CPs down | Routes all traffic to surviving CP; etcd still has quorum if 2/3 up |
| etcd quorum lost (2+ CPs down) | Apiserver becomes read-only, writes fail |

### Why Not Cilium for HA?

Cilium provides in-cluster service load balancing via eBPF, but it can't provide the initial apiserver endpoint because:
1. Cilium agent needs to connect to apiserver to get its configuration
2. kubelet needs apiserver to register the node before Cilium can run
3. The `kubernetes` ClusterIP (10.96.0.1) only works after Cilium networking is up

haproxy on the host bridge runs outside the cluster and is available before any VM boots.

## systemd Service Hardening

All K8s services inside the MicroVMs are hardened with systemd security directives, verified via `systemd-analyze security`. The goal is to apply the principle of least privilege — each service gets only the capabilities and filesystem access it actually needs.

### Security Scores

| Service | Before | After | Rating |
|---------|--------|-------|--------|
| etcd | 9.8 | 1.8 | UNSAFE → OK |
| kube-apiserver | 9.6 | 1.7 | UNSAFE → OK |
| kube-controller-manager | 9.6 | 1.7 | UNSAFE → OK |
| kube-scheduler | 9.6 | 1.7 | UNSAFE → OK |
| kubelet | 9.6 | 5.7 | UNSAFE → MEDIUM |
| containerd | 9.6 | 5.7 | UNSAFE → MEDIUM |

Scores are from `systemd-analyze security` (0 = fully locked down, 10 = no restrictions). Lower is better.

### Control Plane Services (etcd, apiserver, controller-manager, scheduler)

These are network services that read certificates, listen on TCP ports, and talk to each other. They don't need hardware access, kernel module loading, namespace creation, or any Linux capabilities (all ports > 1024). They receive full hardening:

- **Filesystem**: `ProtectSystem=full`, `ProtectHome`, `PrivateTmp`, `PrivateDevices`
- **Kernel**: `ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `ProtectControlGroups`
- **Isolation**: `ProtectClock`, `ProtectHostname`, `ProtectProc=invisible`, `ProcSubset=pid`
- **Privileges**: `NoNewPrivileges`, `CapabilityBoundingSet=""` (no capabilities at all)
- **Syscalls**: `SystemCallArchitectures=native`, `SystemCallFilter=@system-service ~@privileged ~@resources`
- **Namespaces**: `RestrictNamespaces` (cannot create any)
- **Network**: `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX` (TCP/UDP/Unix only)
- **Other**: `MemoryDenyWriteExecute`, `LockPersonality`, `RestrictRealtime`, `RestrictSUIDSGID`, `UMask=0077`

### Why kubelet and containerd Score Higher (5.7)

kubelet and containerd are the container runtime layer — they are responsible for creating, managing, and destroying containers on the node. This fundamentally requires elevated privileges:

- **CAP_SYS_ADMIN**: Creating cgroups for container resource limits, mounting filesystems for container volumes, managing Linux namespaces for container isolation
- **CAP_NET_ADMIN / CAP_NET_RAW**: Setting up container networking (veth pairs, routes, iptables rules for port mapping, ICMP for health checks)
- **CAP_CHOWN / CAP_FOWNER / CAP_DAC_OVERRIDE**: Setting file ownership inside container volumes, accessing files across user boundaries for volume mounts
- **CAP_SETUID / CAP_SETGID**: Running container processes as non-root users (the container's UID/GID, not the host's)
- **CAP_MKNOD**: Creating device nodes inside containers (e.g., `/dev/null`, `/dev/zero`)
- **CAP_SYS_CHROOT**: Container filesystem isolation via `chroot`/`pivot_root`
- **CAP_SYS_RESOURCE**: Setting resource limits (ulimits) for container processes
- **CAP_KILL**: Sending signals to container processes (stop, restart, health check timeouts)
- **CAP_SYSLOG**: Reading `/dev/kmsg` when `kernel.dmesg_restrict=1` (kubelet monitors kernel messages)
- **Namespace creation**: Cannot be restricted — containers *are* namespaces (pid, net, mnt, uts, ipc, cgroup)
- **Mount syscalls**: Containers require mounting overlayfs layers, tmpfs, procfs, sysfs, and bind mounts for volumes

These are not optional — without them, kubelet cannot create pods and containerd cannot run containers. The 5.7 MEDIUM score represents the inherent privilege floor for any container runtime. The hardening that *is* applied (ProtectHome, ProtectKernelModules, ProtectClock, ProtectHostname, MemoryDenyWriteExecute, LockPersonality, restricted address families, syscall filtering) still eliminates capabilities and attack surface that container management doesn't need.

### Verifying Scores

```bash
# Check scores on a running node
nix run .#k8s-vm-ssh -- --node=cp0 systemd-analyze security

# Detailed breakdown for a specific service
nix run .#k8s-vm-ssh -- --node=cp0 systemd-analyze security etcd.service
```

## TiDB Distributed SQL Database

The cluster includes a highly available [TiDB](https://github.com/pingcap/tidb) deployment — a MySQL-compatible distributed SQL database. TiDB survives any single K8s node failure.

### TiDB Architecture

```
              ┌───────────────────────────────────────────────────────┐
              │                    TiDB Cluster                       │
              │                                                       │
              │  ┌─────────┐  ┌─────────┐  ┌─────────┐              │
              │  │  PD-0   │  │  PD-1   │  │  PD-2   │  Placement   │
              │  │  (cp0)  │  │  (cp1)  │  │  (cp2)  │  Driver      │
              │  └────┬────┘  └────┬────┘  └────┬────┘  (Raft       │
              │       │            │            │        quorum)     │
              │       └────────────┼────────────┘                    │
              │                    │                                  │
              │  ┌─────────┐  ┌───┴─────┐  ┌─────────┐              │
              │  │ TiKV-0  │  │ TiKV-1  │  │ TiKV-2  │  Distributed │
              │  │  (cp1)  │  │  (cp2)  │  │  (w3)   │  KV Storage  │
              │  └─────────┘  └─────────┘  └─────────┘  (3-way      │
              │                                          replication)│
              │  ┌─────────┐  ┌─────────┐                           │
              │  │ TiDB-0  │  │ TiDB-1  │  Stateless SQL Layer      │
  MySQL ─────▶  │  (cp0)  │  │  (w3)   │  (MySQL protocol :4000)   │
  clients     │  └─────────┘  └─────────┘                           │
              └───────────────────────────────────────────────────────┘
```

- **PD** (Placement Driver): Cluster metadata and scheduling via Raft consensus. 3 instances for quorum — tolerates 1 PD failure.
- **TiKV**: Distributed key-value storage with automatic 3-way Raft replication. 3 instances — data survives 1 TiKV failure.
- **TiDB**: Stateless MySQL-compatible SQL layer. 2 instances — any single instance handles all queries.

### HA Failure Analysis

8 pods spread across 4 nodes with hard pod anti-affinity:

| Node fails | PD quorum | TiKV replicas | TiDB SQL | Status |
|------------|-----------|---------------|----------|--------|
| cp0 dies | 2/3 (ok) | 3/3 (all alive) | 1/2 | Online |
| cp1 dies | 2/3 (ok) | 2/3 (ok) | 2/2 | Online |
| cp2 dies | 2/3 (ok) | 2/3 (ok) | 2/2 | Online |
| w3 dies  | 3/3 (all) | 2/3 (ok) | 1/2 | Online |

### Benchmark

A sysbench Job is included in the manifests for OLTP read/write benchmarking:

```bash
# Generate manifests
nix build .#k8s-manifests

# Apply TiDB manifests to running cluster
nix run .#k8s-vm-ssh -- --node=cp0 kubectl apply -f /path/to/tidb/

# Watch pods come up (PD first, then TiKV, then TiDB)
nix run .#k8s-vm-ssh -- --node=cp0 kubectl get pods -n tidb -w

# Run the benchmark Job
nix run .#k8s-vm-ssh -- --node=cp0 kubectl apply -f /path/to/tidb/job-bench.yaml
nix run .#k8s-vm-ssh -- --node=cp0 kubectl logs -n tidb job/tidb-sysbench -f

# Interactive MySQL access (from dev shell)
mysql -h <node-ip> -P <nodeport> -u root -e "SELECT tidb_version();"
```

Benchmark parameters: 4 tables, 10K rows each, 4 threads, 60-second OLTP read/write mix.

## Examples

### Building individual VMs

```bash
# Build a single node
nix build .#k8s-microvm-cp0
nix build .#k8s-microvm-w3

# Run it directly (after network setup)
./result/bin/microvm-run
```

### SSH into nodes

```bash
# Interactive shell on control plane
nix run .#k8s-vm-ssh -- --node=cp0

# Run a command on a worker
nix run .#k8s-vm-ssh -- --node=w3 systemctl status kubelet

# Check etcd health
nix run .#k8s-vm-ssh -- --node=cp0 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/kubernetes/pki/etcd-ca.crt \
  --cert=/var/lib/kubernetes/pki/etcd-server.crt \
  --key=/var/lib/kubernetes/pki/etcd-server.key \
  endpoint health
```

### VM management

```bash
# List running VMs
nix run .#k8s-vm-check

# Stop all VMs (SIGTERM, then SIGKILL)
nix run .#k8s-vm-stop

# Connect to serial console for boot debugging
socat -,rawer tcp:127.0.0.1:25500    # cp0 serial (ttyS0)
socat -,rawer tcp:127.0.0.1:25501    # cp0 virtio (hvc0)
socat -,rawer tcp:127.0.0.1:25510    # cp1 serial
```

### GitOps manifests

```bash
# Generate all K8s YAML manifests from Nix
nix build .#k8s-manifests

# Inspect the output
ls result/
cat result/cilium/values.yaml
cat result/nginx/deployment.yaml
cat result/clickhouse/statefulset.yaml
```

### Lifecycle testing

```bash
# Test a single node (build → boot → console → SSH → cert verify → services → k8s health → shutdown)
nix run .#k8s-lifecycle-test-cp0
nix run .#k8s-lifecycle-test-cp1
nix run .#k8s-lifecycle-test-w3

# Test all nodes sequentially
nix run .#k8s-lifecycle-test-all
```

Each per-node lifecycle test verifies:
- **Phase 0**: Nix build succeeds
- **Phase 1**: QEMU process starts
- **Phase 2/2b**: Serial (ttyS0) and virtio (hvc0) consoles respond
- **Phase 3**: SSH is reachable
- **Phase 4**: Certificate files present and CA chains validate (33 files on CP, 10 on worker)
- **Phase 5**: systemd services active (containerd in per-node mode)
- **Phase 6**: K8s health checks (etcd, apiserver — requires cluster for quorum)
- **Phase 7/8**: Clean shutdown and process exit

Note: Per-node tests run each VM in isolation. Services requiring the cluster (etcd, apiserver, kubelet) are only tested when all 3 CPs are running together, since etcd needs 2/3 quorum.

#### Cluster-level test

The cluster test boots all 4 VMs together and verifies the K8s control plane forms correctly:

```bash
nix run .#k8s-cluster-test
```

| Phase | Name | Timeout | What it checks |
|-------|------|---------|----------------|
| C0 | Build All VMs | 900s | `nix build` for all 4 nodes |
| C1 | Start All VMs | 30s | Launch all 4 VMs, verify QEMU processes |
| C2 | SSH Ready | 90s | SSH connectivity to all 4 nodes |
| C3 | Etcd Quorum | 120s | `etcdctl endpoint health` on all 3 CPs + 3-member quorum |
| C4 | API Server Health | 120s | `/healthz` returns "ok" on all 3 CPs |
| C5 | Node Registration | 180s | `kubectl get nodes` shows 4 nodes registered |
| C6 | Shutdown All | 60s | Graceful poweroff all VMs |

The cluster test fills the gap between per-node infrastructure checks (VM boot, certs, containerd) and application-layer health (etcd quorum, apiserver, node registration). If any phase C1-C5 fails, the test still runs C6 to clean up VMs.

Note: Nodes register as `NotReady` until a CNI plugin (Cilium) is deployed — this is expected K8s behavior. The test verifies registration, not CNI readiness.

### Network management

```bash
# Check host prerequisites
nix run .#k8s-check-host

# Create network + haproxy LB (requires sudo)
sudo nix run .#k8s-network-setup

# Tear down network + haproxy (requires sudo)
sudo nix run .#k8s-network-teardown
```

### Certificate inspection

Certs are generated at Nix build time and embedded in VM images. For manual inspection:

```bash
# Copy build-time certs to ./certs/ for inspection
nix run .#k8s-gen-certs

# Inspect a cert
openssl x509 -in ./certs/apiserver.crt -text -noout | grep -A1 "Subject Alternative Name"

# Verify cert chain on a running node
nix run .#k8s-vm-ssh -- --node=cp0 openssl verify \
  -CAfile /var/lib/kubernetes/pki/ca.crt /var/lib/kubernetes/pki/apiserver.crt
```

## File Structure

```
flake.nix                        # Orchestrator — imports, mkK8sNode, packages, apps, devShell
nix/
├── constants.nix                # IPs, MACs, ports, serial ports, CIDRs, timeouts
├── nodes.nix                    # Node definitions (cp0, cp1, cp2, w3) with role + services
├── microvm.nix                  # mkK8sNode parametric generator (TAP, dual serial, 9p store)
├── k8s-module.nix               # NixOS module: etcd, apiserver, kubelet, containerd, scheduler
├── network-setup.nix            # Bridge + TAP + NAT + haproxy LB setup/teardown
├── certs.nix                    # Build-time PKI: 3 CAs + per-component certs, baked into VMs
├── cert-inject.nix              # Legacy: expect-driven cert transfer over virtio (manual use)
├── microvm-scripts.nix          # k8s-vm-check, k8s-vm-stop, k8s-vm-ssh, k8s-start-all
├── shell.nix                    # devShell: kubectl, helm, cilium-cli, step-cli, argocd, ...
├── test-lib.nix                 # Shared bash helpers (color, timing, assertions)
├── lifecycle/
│   ├── default.nix              # Lifecycle test orchestrator (per-node + test-all)
│   ├── lib.nix                  # Script generators (process, console, SSH, timing helpers)
│   ├── constants.nix            # Per-node services, health checks, timeouts
│   ├── k8s-checks.nix           # K8s verification (etcd health, apiserver /healthz, nodes Ready)
│   └── scripts/
│       ├── vm-lib.exp           # Shared expect library (login, run_cmd, retry)
│       ├── vm-cert-inject.exp   # Cert transfer over virtio console (base64 + md5 verify)
│       └── vm-k8s-verify.exp    # K8s service verification via console
└── gitops/
    ├── default.nix              # Manifest generator → nix build .#k8s-manifests
    └── env/
        ├── base.nix             # Namespaces, RBAC
        ├── argocd.nix           # ArgoCD Helm chart + self-managing Application
        ├── cilium.nix           # Cilium Helm chart (kube-proxy replacement, dual-stack, Hubble)
        ├── clickhouse.nix       # ClickHouse StatefulSet + headless Service + ConfigMap
        ├── nginx.nix            # Nginx Deployment + Service (hello world)
        └── tidb.nix             # TiDB HA cluster (3 PD + 3 TiKV + 2 TiDB + sysbench Job)
```

## Component Details

### microvm.nix — VM Generator
Parametric function `mkK8sNode { nodeName, role }` that produces a `microvm.declaredRunner`. Each VM gets:
- TAP networking with per-node MAC address
- Dual serial console: ttyS0 (TCP, early boot) + hvc0 (virtio, high-speed)
- 9p /nix/store share (read-only)
- systemd-networkd for dual-stack static IP
- Build-time PKI bundle deployed via NixOS activation script
- Resources: 4GB/4vCPU (control planes), 3GB/2vCPU (worker)

### k8s-module.nix — NixOS Module
`services.k8s` module configuring:
- **containerd** with systemd cgroup driver
- **kubelet** with dual-stack node-ip, containerd CRI endpoint, kubeconfig pointing to haproxy VIP
- **etcd** with TLS peer/client auth, 3-node cluster (control plane only)
- **kube-apiserver** with Node+RBAC authorization, etcd mTLS (control plane only)
- **kube-controller-manager** with leader election (control plane only)
- **kube-scheduler** with leader election (control plane only)
- Kernel modules: br_netfilter, overlay, ip_vs, nf_conntrack
- Sysctl: IP forwarding, bridge-nf-call-iptables
- No kube-proxy — Cilium handles it via eBPF

### certs.nix — Build-Time PKI
All certificates are generated at `nix build` time and baked directly into VM images:
- `pkiStore`: Nix derivation producing all certs (3 CAs, per-node certs, SA keypair) using step-cli and openssl
- `mkNodePki`: Assembles per-node bundles (certs + kubeconfigs) for embedding in VMs
- `genCerts`: Convenience script to copy build-time certs to `./certs/` for inspection
- No runtime cert injection needed — the `microvm.nix` activation script copies certs from `/nix/store` to `/var/lib/kubernetes/pki/` at boot
- All kubeconfigs target `https://10.33.33.1:6443` (haproxy VIP) for HA

### lifecycle/ — Test Framework
Per-node lifecycle test covering 9 phases: build → start → serial → virtio → SSH → cert verify → services → K8s health → shutdown → exit. Millisecond timing, colored output, summary table. `k8s-lifecycle-test-all` runs all nodes sequentially.

### gitops/ — Manifest Generator
Generates Kubernetes YAML from Nix:
- **ArgoCD**: Helm chart values + self-managing Application CR
- **Cilium**: kube-proxy replacement, dual-stack, Hubble observability, uses haproxy VIP for k8sServiceHost
- **TiDB**: HA distributed SQL database (3 PD + 3 TiKV + 2 TiDB), sysbench benchmark Job
- **ClickHouse**: StatefulSet with headless Service + ConfigMap
- **nginx**: Deployment with hello-world page

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| TAP-only networking | Nodes must communicate for etcd peering and kubelet registration |
| 3 CP + haproxy LB | 3-node etcd quorum tolerates 1 CP failure; haproxy on bridge IP provides apiserver HA |
| Host-side haproxy (not Cilium) | Apiserver endpoint must exist before Cilium boots (chicken-and-egg) |
| step-cli for CA | Cleaner `--san` flags vs cfssl JSON CSRs, path to step-ca auto-renewal |
| Build-time PKI | Certs baked into VM images via Nix — no runtime injection, fully reproducible |
| 3 separate CAs | Isolates trust domains: cluster, etcd, and front-proxy (K8s best practice) |
| Kubeconfigs → haproxy VIP | All components connect via LB, not directly to a single CP |
| Cilium replaces kube-proxy | eBPF-based, no iptables overhead, native dual-stack |
| containerd (not CRI-O) | Better NixOS/nixpkgs support, k8s default runtime |
| Dual serial consoles | ttyS0 for early boot debugging, hvc0 for high-speed data transfer |
| Per-node cert bundles | Workers get 10 files (no etcd/apiserver keys), CPs get 33 — least privilege |
| systemd hardening | Control plane services get CapabilityBoundingSet="" (score 1.7); kubelet/containerd keep only caps needed for container lifecycle (score 5.7) |
| TimeoutStopSec=15 | All K8s services stop within 15s on shutdown — prevents hung etcd peer reconnection from blocking VM exit |
| TiDB plain StatefulSets | Matches existing gitops pattern, no operator overhead, direct control over pod placement |
| TiDB 3 PD + 3 TiKV + 2 TiDB | Survives any single node failure: PD quorum (2/3), TiKV replication (2/3), stateless SQL (1/2) |
| 4GB CPs, 3GB worker | Headroom for TiDB components (~768Mi per node) alongside K8s services |
