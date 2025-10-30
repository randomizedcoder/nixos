# Kubernetes Cluster Configuration

## Introduction

This document describes the design of a solution for using NixOS to configure a Kubernetes cluster.

This solution is designed to be used in a home environment, and is intended to be used as a reference for other users.

The solutions will use x3 Chromeboxes as the nodes (chromebox1, chromebox2, chromebox3) which will all be Kubernetes control and worker nodes.

## Key requirements

The solution should follow best practices for Kubernetes cluster configuration.

The solution will initially focus on making a working cluster, including the cerficiate authority and certificate management, following the best practices at:

https://kubernetes.io/docs/setup/best-practices/certificates/

The solution will not use k3s, which we do have some old testing configuration that's commented out in k3s_master.nix.  The k3s worked, but this isn't the fully fledged kubernetes, so now looking to make the full complete kubernetes using all the standard services, including the real etcd.

## Steps

The steps will be:
1. Update the chromebox1, chromebox2, chromebox3 NixOS configurations, stored in ./chromebox1/flake.nix, ./chromebox2/flake.nix, ./chromebox3/flake.nix, to add the required packages (etcd, services.kubrnetes), per https://nixos.wiki/wiki/Kubernetes.  The kubernetes config will go into a new file in each chromebox folder kubernetes.nix
2. Create a bash script to manually create the certificate authority and certificates for the cluster.  These will be created locally on the machine and then copied to the nodes.  Services restarted and it should work.
3. Testing to verify that the cluster is working, including testing the certificate authority and certificates.
3. Following this, we'll work on automation using agenix ( https://github.com/ryantm/agenix ) or sop-nix ( https://github.com/Mic92/sop-nix ).


## Key design decisions

### Network Topology and Addressing

**Cluster Network Design:**
- **Control Plane Nodes**: chromebox1, chromebox2, chromebox3 (all acting as both control plane and worker nodes)
- **Network Segment**: 172.16.40.x/24 (existing network)
- **API Server Endpoint**: Load-balanced across all three nodes
- **Pod Network**: CNI plugin (Calico or Flannel) for pod-to-pod communication
- **Service Network**: 10.96.0.0/12 (default Kubernetes service CIDR)

**Node Roles:**
- All three chromeboxes will be configured as both control plane and worker nodes
- This provides high availability for the control plane while maximizing resource utilization
- Each node will run: kube-apiserver, kube-controller-manager, kube-scheduler, kubelet, kube-proxy

### Certificate Authority (CA) and PKI Infrastructure

**Hierarchical PKI Strategy:**
- **External Root CA**: Root CA stored securely on a separate, offline machine (not part of the cluster)
- **Intermediate CAs**: Each chromebox will have its own intermediate CA signed by the root CA
- **Certificate Chain**: Root CA → Intermediate CA → Service Certificates
- **Revocation Capability**: Individual intermediate CAs can be revoked without affecting other nodes

**PKI Hierarchy:**
```
Root CA (External, Offline)
├── chromebox1 Intermediate CA
│   ├── etcd-server-chromebox1
│   ├── kube-apiserver-chromebox1
│   ├── kubelet-chromebox1
│   └── service certificates for chromebox1
├── chromebox2 Intermediate CA
│   ├── etcd-server-chromebox2
│   ├── kube-apiserver-chromebox2
│   ├── kubelet-chromebox2
│   └── service certificates for chromebox2
└── chromebox3 Intermediate CA
    ├── etcd-server-chromebox3
    ├── kube-apiserver-chromebox3
    ├── kubelet-chromebox3
    └── service certificates for chromebox3
```

**Certificate Types Required:**
1. **Root CA Certificate**: Self-signed root certificate authority (external)
   - **Validity**: 40 years (rarely rotated)
2. **Intermediate CA Certificates**:
   - chromebox1-intermediate-ca (signed by root CA)
   - chromebox2-intermediate-ca (signed by root CA)
   - chromebox3-intermediate-ca (signed by root CA)
   - **Validity**: 2 months (rotated monthly)
3. **etcd Certificates** (per node):
   - etcd-server certificates signed by node's intermediate CA
   - etcd-peer certificates signed by node's intermediate CA
   - etcd-client certificates signed by node's intermediate CA
   - **Validity**: 2 weeks (rotated weekly)
4. **Kubernetes API Server Certificates** (per node):
   - kube-apiserver certificates signed by node's intermediate CA
   - kube-apiserver-etcd-client certificates
   - kube-apiserver-kubelet-client certificates
   - **Validity**: 2 weeks (rotated weekly)
5. **Service Account Certificates** (per node):
   - kube-controller-manager certificates
   - kube-scheduler certificates
   - kube-proxy certificates
   - **Validity**: 2 weeks (rotated weekly)
6. **Node Certificates** (per node):
   - kubelet certificates signed by node's intermediate CA
   - kubelet-client certificates signed by node's intermediate CA
   - **Validity**: 2 weeks (rotated weekly)

**Certificate Validation Strategy:**

**Public vs Private Keys:**
- **Root CA Certificate** (`/etc/kubernetes/pki/ca.crt`): **PUBLIC** certificate (contains public key)
- **Root CA Private Key**: Stored securely on external machine, **NEVER** distributed to cluster nodes
- **Intermediate CA Certificate** (`/etc/kubernetes/pki/intermediate-ca.crt`): **PUBLIC** certificate (contains public key)
- **Intermediate CA Private Key**: Stored on the respective node, used to sign service certificates

**Certificate Validation Process:**
1. **Service Certificate Validation**: When a service certificate is presented (e.g., kube-apiserver connecting to etcd):
   - The validator checks if the service certificate is signed by the node's intermediate CA
   - The validator checks if the intermediate CA certificate is signed by the root CA
   - This creates a trust chain: Service Cert → Intermediate CA → Root CA

2. **Trust Store**: Each node needs:
   - **Root CA Public Certificate** (`/etc/kubernetes/pki/ca.crt`) - for validating the chain
   - **Node's Intermediate CA Public Certificate** (`/etc/kubernetes/pki/intermediate-ca.crt`) - for validating service certificates
   - **Node's Intermediate CA Private Key** (`/etc/kubernetes/pki/intermediate-ca.key`) - for signing new service certificates

3. **Cross-Node Validation**: When chromebox1 needs to validate a certificate from chromebox2:
   - chromebox1 uses its root CA certificate to validate chromebox2's intermediate CA certificate
   - chromebox1 uses chromebox2's intermediate CA certificate to validate chromebox2's service certificates

**File Structure on Each Node:**
```
/etc/kubernetes/pki/
├── ca.crt                    # Root CA PUBLIC certificate (same on all nodes)
├── intermediate-ca.crt      # This node's intermediate CA PUBLIC certificate
├── intermediate-ca.key      # This node's intermediate CA PRIVATE key
├── etcd-server.crt          # etcd server certificate (signed by intermediate CA)
├── etcd-server.key          # etcd server private key
├── kube-apiserver.crt       # API server certificate (signed by intermediate CA)
├── kube-apiserver.key       # API server private key
└── ... (other service certificates)
```

**Security Model:**
- **Root CA Private Key**: Only on external machine, used only to sign intermediate CAs
- **Intermediate CA Private Key**: Only on the respective node, used to sign that node's service certificates
- **Service Certificate Private Keys**: Only on the respective node, used by the service
- **Public Certificates**: Can be freely distributed for validation purposes

**Concrete Example - Certificate Validation:**

**Scenario**: chromebox1's kube-apiserver needs to connect to chromebox2's etcd server

**Validation Process**:
1. **chromebox2's etcd server** presents its certificate (`etcd-server-chromebox2.crt`)
2. **chromebox1's kube-apiserver** validates this certificate by:
   - Checking if `etcd-server-chromebox2.crt` is signed by `chromebox2-intermediate-ca.crt`
   - Checking if `chromebox2-intermediate-ca.crt` is signed by `root-ca.crt`
   - If both checks pass, the certificate is trusted

**What Each Node Stores**:

**chromebox1**:
```
/etc/kubernetes/pki/
├── ca.crt                           # Root CA public cert (for validation)
├── chromebox1-intermediate-ca.crt  # chromebox1's intermediate CA public cert
├── chromebox1-intermediate-ca.key   # chromebox1's intermediate CA private key
├── chromebox2-intermediate-ca.crt  # chromebox2's intermediate CA public cert (for validation)
├── chromebox3-intermediate-ca.crt  # chromebox3's intermediate CA public cert (for validation)
├── etcd-server.crt                 # etcd server cert (signed by chromebox1's intermediate CA)
├── etcd-server.key                  # etcd server private key
├── kube-apiserver.crt              # API server cert (signed by chromebox1's intermediate CA)
└── kube-apiserver.key              # API server private key
```

**Key Point**: Each node has the **public certificates** of all other nodes' intermediate CAs, but only has the **private key** of its own intermediate CA.

**Security Benefits:**
- **Isolation**: Compromise of one node's intermediate CA doesn't affect other nodes
- **Revocation**: Individual intermediate CAs can be revoked via CRL or OCSP
- **Rotation**: Intermediate CAs can be rotated periodically for enhanced security
- **Disaster Recovery**: Failed nodes can be rebuilt with new intermediate CAs
- **Offline Root**: Root CA remains offline, reducing attack surface

### Certificate Validity Periods

**Validity Period Strategy:**
- **Certificate Validity = 2 × Rotation Period**
- Provides safety buffer for rotation failures
- Ensures certificates remain valid during rotation process
- Allows for rotation delays without service interruption

**Specific Validity Periods:**

1. **Root CA Certificate**: 40 years
   - **Rationale**: Rarely rotated, long-term trust anchor
   - **Rotation**: Only in case of compromise or major security incident

2. **Intermediate CA Certificates**: 2 months
   - **Rotation Period**: Monthly
   - **Safety Buffer**: 1 month (2x rotation period)
   - **Rationale**: Provides time for rotation failures and manual intervention

3. **Service Certificates**: 2 weeks
   - **Rotation Period**: Weekly
   - **Safety Buffer**: 1 week (2x rotation period)
   - **Rationale**: Frequent rotation with safety margin for automation failures

**Validity Period Benefits:**
- **Safety Buffer**: Certificates remain valid during rotation process
- **Failure Recovery**: Time to fix rotation issues before expiration
- **Automation Resilience**: Handles temporary automation failures
- **Manual Intervention**: Time for human intervention if needed
- **Service Continuity**: Prevents service interruption during rotation

### etcd Cluster Configuration

**etcd Cluster Design:**
- **High Availability**: 3-node etcd cluster (one per chromebox)
- **Data Replication**: 3 replicas for fault tolerance
- **Network**: etcd will listen on all interfaces for cluster communication
- **Ports**: 2379 (client), 2380 (peer communication)
- **Storage**: Local storage on each node (SSD recommended)

**etcd Security:**
- Client certificates for kube-apiserver to etcd communication
- Peer certificates for etcd cluster member communication
- TLS encryption for all etcd traffic

### Kubernetes Control Plane Services

**API Server Configuration:**
- **High Availability**: API server running on all three nodes
- **Load Balancing**: External load balancer or DNS round-robin
- **Authentication**: Certificate-based authentication
- **Authorization**: RBAC (Role-Based Access Control)
- **Admission Controllers**: Standard set including NodeRestriction, ServiceAccount

**Controller Manager & Scheduler:**
- **Leader Election**: Only one instance active at a time
- **High Availability**: Multiple instances with leader election
- **Configuration**: Standard Kubernetes configuration with appropriate resource limits

### Security Considerations

**Network Security:**
- Firewall rules to restrict access to Kubernetes ports
- Network segmentation for control plane traffic
- Secure communication between all components

**Certificate Management:**
- Regular certificate rotation (annual or as needed)
- Secure storage of private keys
- Backup of CA certificates and keys
- Certificate monitoring and alerting

**Access Control:**
- RBAC policies for different user roles
- Service account management
- Network policies for pod-to-pod communication

### Deployment Strategy

**Bootstrap Process:**
1. Generate root CA and initial certificates on chromebox1
2. Configure etcd cluster starting with chromebox1
3. Bootstrap first control plane node (chromebox1)
4. Add additional control plane nodes (chromebox2, chromebox3)
5. Configure worker node functionality on all nodes
6. Deploy CNI plugin for pod networking
7. Verify cluster functionality and certificate validation

**Certificate Distribution:**
- Manual distribution during initial setup
- Future automation using agenix or sop-nix for secret management
- Secure transfer using SSH and proper file permissions

### Certificate Lifecycle Management

**Certificate Rotation Strategy:**

**Two-Tier Rotation Approach:**
1. **Intermediate CA Rotation**: Monthly rotation of intermediate CAs
2. **Service Certificate Rotation**: Weekly rotation of service certificates

**Intermediate CA Rotation (Monthly):**
- **Schedule**: Monthly rotation with 1-6 hour jitter per node
- **Process**:
  1. Generate new intermediate CA on external machine
  2. Securely copy to target node
  3. Generate new service certificates using new intermediate CA
  4. Deploy new certificates
  5. Restart services
  6. Revoke old intermediate CA
- **Jitter**: Each node rotates at different times (1-6 hours apart)
- **Zero Downtime**: New certificates deployed before old ones are revoked

**Service Certificate Rotation (Weekly):**
- **Schedule**: Weekly rotation with 1-6 hour jitter per node
- **Process**:
  1. Generate new service certificates using existing intermediate CA
  2. Deploy new certificates
  3. Restart affected services
- **Jitter**: Each node rotates at different times (1-6 hours apart)
- **Automation**: Can be fully automated on each node

**Service Restart Strategy:**
- **etcd**: Restart etcd service (cluster remains available with other nodes)
- **kube-apiserver**: Restart API server (load balancer handles failover)
- **kube-controller-manager**: Restart controller manager
- **kube-scheduler**: Restart scheduler
- **kubelet**: Restart kubelet service
- **kube-proxy**: Restart kube-proxy service

**Certificate Revocation:**
- **CRL (Certificate Revocation List)**: Maintained by root CA, distributed to all nodes
- **OCSP (Online Certificate Status Protocol)**: Optional real-time certificate validation
- **Revocation Triggers**: Node compromise, certificate expiration, security incidents
- **Revocation Process**: Add intermediate CA to CRL → Distribute updated CRL → Restart services

**Disaster Recovery for Node Failures:**
1. **Node Failure Scenario**: Complete loss of chromebox (hardware failure, etc.)
2. **Recovery Process**:
   - Revoke the failed node's intermediate CA via CRL
   - Generate new intermediate CA for replacement node
   - Sign new service certificates for replacement node
   - Deploy new node with fresh intermediate CA
   - Update cluster configuration to include new node
3. **Certificate Cleanup**: Old intermediate CA remains in CRL for security

**External Root CA Management:**
- **Location**: Root CA stored on secure, offline machine (separate from cluster)
- **Access**: Root CA only accessed for intermediate CA generation and CRL updates
- **Backup**: Root CA private key backed up securely (encrypted, multiple locations)
- **Rotation**: Root CA can be rotated (rare, typically 10+ year validity)
- **Security**: Root CA machine should be air-gapped when not in use

**Automation Strategy:**
- **Initial Setup**: Manual certificate generation and distribution
- **Phase 2**: Implement agenix/sop-nix for automated certificate distribution
- **Phase 3**: Implement automated certificate rotation and renewal
- **Monitoring**: Certificate expiration monitoring and alerting
- **Compliance**: Audit logging for all certificate operations

## Certificate Generation Tools

### Tool Comparison and Recommendations

**Rust-Based Tools (Security-Focused):**

1. **rcgen** (Pure Rust)
   - **Pros**: Pure Rust implementation, memory safety, supports RSA/ECDSA/Ed25519
   - **Cons**: Lower-level library, requires more custom development
   - **Best For**: Building custom PKI tools with maximum security
   - **Production Readiness**: ⚠️ Requires significant custom development

2. **x509-parser** + **rustls** (Pure Rust)
   - **Pros**: Pure Rust implementation, memory safety, modern crypto
   - **Cons**: Requires building custom PKI management tools
   - **Best For**: Custom certificate management with Rust safety guarantees
   - **Production Readiness**: ⚠️ Requires extensive custom development

3. **step-ca** (Go-based, but Rust-compatible)
   - **Pros**: Modern design, excellent security practices, ACME support, Kubernetes integration
   - **Cons**: Not pure Rust, but designed with security-first principles
   - **Best For**: Production environments requiring modern PKI management
   - **Production Readiness**: ✅ Mature and widely adopted

**Note**: certkit is primarily designed for Let's Encrypt integration and public certificate management, not suitable for internal PKI scenarios.

**Established Tools (Production-Ready):**

3. **CFSSL** (Go-based)
   - **Pros**: Mature, widely adopted, comprehensive features, JSON configuration
   - **Cons**: Go-based (not Rust), requires more setup
   - **Best For**: Production environments requiring proven reliability
   - **Production Readiness**: ✅ Battle-tested in production

4. **OpenSSL** (C-based)
   - **Pros**: Most mature, extensive features, universal compatibility
   - **Cons**: C-based (memory safety concerns), complex CLI
   - **Best For**: Maximum compatibility and feature completeness
   - **Production Readiness**: ✅ Industry standard

### **Recommended Approach for Your Use Case:**

**Primary Recommendation: CFSSL**
- **Why**: Mature, production-ready, excellent for hierarchical PKI
- **Security**: Good security practices, widely audited
- **Features**: Perfect for your intermediate CA setup
- **Documentation**: Extensive documentation and examples

**Alternative: step-ca**
- **Why**: Modern design, excellent security, future-proof
- **Security**: Built with security-first principles
- **Features**: Great for automation and Kubernetes integration
- **Learning Curve**: Slightly steeper but more powerful

**Rust Alternative: rcgen + Custom Scripts**
- **Why**: Pure Rust, memory safety, aligns with your preferences
- **Security**: Maximum security through Rust's guarantees
- **Trade-off**: Requires significant custom development
- **Production**: Use with caution, test extensively

### **Implementation Strategy:**

**Phase 1: CFSSL (Recommended)**
```bash
# Install CFSSL
go install github.com/cloudflare/cfssl/cmd/cfssl@latest
go install github.com/cloudflare/cfssl/cmd/cfssljson@latest

# Generate root CA (40 year validity)
cfssl gencert -initca ca-config.json | cfssljson -bare ca

# Generate intermediate CA for chromebox1 (2 month validity)
cfssl gencert -initca intermediate-ca-config.json | cfssljson -bare chromebox1-intermediate-ca
cfssl sign -ca ca.pem -ca-key ca-key.pem -config cfssl-config.json -profile intermediate_ca chromebox1-intermediate-ca.csr | cfssljson -bare chromebox1-intermediate-ca

# Generate service certificates (2 week validity)
cfssl gencert -ca chromebox1-intermediate-ca.pem -ca-key chromebox1-intermediate-ca-key.pem -config service-config.json -profile etcd-server etcd-server.json | cfssljson -bare etcd-server
cfssl gencert -ca chromebox1-intermediate-ca.pem -ca-key chromebox1-intermediate-ca-key.pem -config service-config.json -profile kube-apiserver kube-apiserver.json | cfssljson -bare kube-apiserver
```

**CFSSL Configuration Examples:**

**Root CA Configuration (ca-config.json):**
```json
{
  "CN": "Kubernetes Root CA",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "C": "US",
      "L": "San Francisco",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "CA"
    }
  ],
  "ca": {
    "expiry": "350400h"
  }
}
```

**Intermediate CA Configuration (intermediate-ca-config.json):**
```json
{
  "CN": "Kubernetes Intermediate CA - chromebox1",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "C": "US",
      "L": "San Francisco",
      "O": "Kubernetes",
      "OU": "Intermediate CA",
      "ST": "CA"
    }
  ],
  "ca": {
    "expiry": "1460h"
  }
}
```

**Service Certificate Configuration (service-config.json):**
```json
{
  "signing": {
    "default": {
      "expiry": "336h"
    },
    "profiles": {
      "etcd-server": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "server auth", "client auth"]
      },
      "kube-apiserver": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "server auth", "client auth"]
      },
      "kubelet": {
        "expiry": "336h",
        "usages": ["signing", "key encipherment", "server auth", "client auth"]
      }
    }
  }
}
```

**Phase 2: Migration to step-ca (Optional)**
- Implement step-ca for automated certificate management
- Migrate from CFSSL-generated certificates
- Implement automated renewal and rotation

**Phase 3: Rust Implementation (Future)**
- Develop custom Rust tools using rcgen and x509-parser
- Implement advanced security features
- Create automated certificate lifecycle management

### **Security Considerations:**

**CFSSL Advantages:**
- Proven in production environments
- Comprehensive security features
- Excellent documentation and community support
- JSON-based configuration for automation

**Rust Advantages:**
- Memory safety eliminates entire classes of vulnerabilities
- Performance benefits
- Modern cryptographic implementations
- Type safety reduces configuration errors

**Hybrid Approach:**
- Use CFSSL for initial setup and validation
- Develop Rust-based automation tools
- Implement Rust-based monitoring and alerting
- Gradually migrate to pure Rust implementation

## Cryptographic Algorithms and Security

### **Algorithm Selection Strategy**

**Current Implementation: ECDSA P-521**
- **Root CA**: ECDSA P-521 (40-year validity)
- **Intermediate CAs**: ECDSA P-521 (2-month validity)
- **Service Certificates**: ECDSA P-521 (2-week validity)

**Why ECDSA P-521:**
- **Security**: Equivalent to RSA 15360 bits (256-bit security strength)
- **Performance**: Still faster than RSA 4096
- **Compatibility**: Full support in CFSSL and Kubernetes
- **Future-Proof**: Higher security margin for long-term certificates
- **Efficiency**: 521-bit keys vs 4096-bit RSA (still more efficient)

### **Algorithm Comparison**

| Algorithm | Security Level | Performance | Key Size | Compatibility | Recommendation |
|-----------|---------------|-------------|---------|---------------|----------------|
| **RSA 4096** | Very High | Slow | 4096 bits | Universal | Legacy systems |
| **RSA 3072** | High | Medium | 3072 bits | Universal | Balanced choice |
| **ECDSA P-256** | High | Fast | 256 bits | Modern systems | Standard choice |
| **ECDSA P-384** | Very High | Fast | 384 bits | Modern systems | High security |
| **ECDSA P-521** | Very High | Fast | 521 bits | Modern systems | **Current choice** |
| **Ed25519** | Very High | Very Fast | 256 bits | Limited | Future consideration |

### **Post-Quantum Cryptography Considerations**

**Current State (2024):**
- **Hybrid Schemes**: Kubernetes v1.33+ supports hybrid post-quantum key exchange
- **X25519MLKEM768**: Default hybrid scheme in Go 1.24+
- **TLS Integration**: Post-quantum algorithms integrated into TLS stack
- **Certificate Authorities**: Still using classical algorithms (ECDSA/RSA)

**Future Migration Path:**

**Phase 1: Current Implementation (2024-2025)**
- Use ECDSA P-521 for all certificates
- Monitor post-quantum developments
- Prepare for hybrid certificate support

**Phase 2: Hybrid Certificates (2025-2026)**
- Implement hybrid classical + post-quantum certificates
- Use ECDSA P-521 + post-quantum signature algorithm
- Maintain backward compatibility

**Phase 3: Full Post-Quantum (2026+)**
- Migrate to pure post-quantum algorithms
- Update all certificate types
- Ensure ecosystem compatibility

### **Post-Quantum Algorithm Options**

**Signature Algorithms:**
1. **Dilithium**: NIST standardized, good performance
2. **Falcon**: NIST standardized, compact signatures
3. **SPHINCS+**: NIST standardized, hash-based security

**Key Exchange Algorithms:**
1. **Kyber**: NIST standardized, lattice-based
2. **NTRU**: Alternative lattice-based option
3. **SABER**: Lightweight option

**Hybrid Implementation Strategy:**
```json
{
  "key": {
    "algo": "hybrid",
    "classical": "ecdsa",
    "classical_size": 256,
    "post_quantum": "dilithium3"
  }
}
```

### **Migration Timeline**

**2024-2025: Classical Cryptography**
- ECDSA P-521 for all certificates
- Monitor post-quantum developments
- Test hybrid implementations

**2025-2026: Hybrid Implementation**
- Deploy hybrid classical + post-quantum certificates
- Maintain ECDSA P-521 compatibility
- Gradual migration of certificate types

**2026+: Post-Quantum Ready**
- Full post-quantum certificate support
- Legacy classical certificate support
- Complete ecosystem compatibility

### **Security Considerations**

**Current Threats:**
- **Classical Attacks**: ECDSA P-521 provides very strong protection
- **Side-Channel Attacks**: Proper key generation and storage
- **Certificate Theft**: Frequent rotation mitigates risk

**Future Threats:**
- **Quantum Attacks**: Post-quantum algorithms provide protection
- **Hybrid Attacks**: Classical + post-quantum provides defense in depth
- **Algorithm Transition**: Gradual migration reduces risk

### **Implementation Recommendations**

**Immediate Actions (2024):**
1. Use ECDSA P-521 for all new certificates
2. Implement certificate rotation with ECDSA P-521
3. Monitor post-quantum algorithm developments

**Medium-term Actions (2025):**
1. Test hybrid certificate implementations
2. Evaluate post-quantum algorithm performance
3. Plan migration strategy for existing certificates

**Long-term Actions (2026+):**
1. Implement hybrid certificates
2. Migrate to post-quantum algorithms
3. Maintain backward compatibility

### **CFSSL Configuration for Post-Quantum**

**Current ECDSA Configuration:**
```json
{
  "key": {
    "algo": "ecdsa",
    "size": 521
  }
}
```

**Future Hybrid Configuration:**
```json
{
  "key": {
    "algo": "hybrid",
    "classical": "ecdsa",
    "classical_size": 521,
    "post_quantum": "dilithium3"
  }
}
```

**Post-Quantum Only Configuration:**
```json
{
  "key": {
    "algo": "dilithium3"
  }
}
```

### **Monitoring and Updates**

**Algorithm Monitoring:**
- Track NIST post-quantum standardization
- Monitor Kubernetes post-quantum support
- Evaluate performance of new algorithms

**Certificate Lifecycle:**
- Regular algorithm reviews
- Gradual migration of certificate types
- Backward compatibility maintenance

**Security Updates:**
- Algorithm vulnerability monitoring
- Performance impact assessment
- Compatibility testing with new algorithms

## Certificate Rotation Implementation

### **Automated Rotation Strategy**

**Monthly Intermediate CA Rotation:**
```bash
# External machine (root CA)
# 1. Generate new intermediate CA for chromebox1
cfssl gencert -initca intermediate-ca-config.json | cfssljson -bare chromebox1-intermediate-ca-new
cfssl sign -ca root-ca.pem -ca-key root-ca-key.pem -config cfssl-config.json -profile intermediate_ca chromebox1-intermediate-ca-new.csr | cfssljson -bare chromebox1-intermediate-ca-new

# 2. Securely copy to chromebox1
scp chromebox1-intermediate-ca-new.pem chromebox1:/etc/kubernetes/pki/intermediate-ca-new.crt
scp chromebox1-intermediate-ca-new-key.pem chromebox1:/etc/kubernetes/pki/intermediate-ca-new.key

# 3. On chromebox1, generate new service certificates
cfssl gencert -ca intermediate-ca-new.crt -ca-key intermediate-ca-new.key -config service-config.json -profile etcd-server etcd-server.json | cfssljson -bare etcd-server-new
cfssl gencert -ca intermediate-ca-new.crt -ca-key intermediate-ca-new.key -config service-config.json -profile kube-apiserver kube-apiserver.json | cfssljson -bare kube-apiserver-new

# 4. Deploy new certificates and restart services
systemctl restart etcd kube-apiserver kube-controller-manager kube-scheduler kubelet kube-proxy
```

**Weekly Service Certificate Rotation:**
```bash
# On each node (automated via cron/systemd timer)
# 1. Generate new service certificates using existing intermediate CA
cfssl gencert -ca intermediate-ca.crt -ca-key intermediate-ca.key -config service-config.json -profile etcd-server etcd-server.json | cfssljson -bare etcd-server-new
cfssl gencert -ca intermediate-ca.crt -ca-key intermediate-ca.key -config service-config.json -profile kube-apiserver kube-apiserver.json | cfssljson -bare kube-apiserver-new

# 2. Deploy new certificates
cp etcd-server-new.pem /etc/kubernetes/pki/etcd-server.crt
cp etcd-server-new-key.pem /etc/kubernetes/pki/etcd-server.key
cp kube-apiserver-new.pem /etc/kubernetes/pki/kube-apiserver.crt
cp kube-apiserver-new-key.pem /etc/kubernetes/pki/kube-apiserver.key

# 3. Restart services
systemctl restart etcd kube-apiserver kube-controller-manager kube-scheduler kubelet kube-proxy
```

### **Jitter Implementation**

**Node Index-Based Jitter:**
```bash
# Extract node index from hostname (chromebox1 -> 1, chromebox2 -> 2, etc.)
NODE_INDEX=$(hostname | grep -oE '[0-9]+$')
if [ -z "$NODE_INDEX" ]; then
    echo "ERROR: Could not extract node index from hostname"
    exit 1
fi

# Calculate jitter window for this node
# Node 1: 0-1 hour (0-3600 seconds)
# Node 2: 1-2 hours (3600-7200 seconds)
# Node 3: 2-3 hours (7200-10800 seconds)
# etc.

# Base delay = (NODE_INDEX - 1) * 3600 seconds
BASE_DELAY=$(( (NODE_INDEX - 1) * 3600 ))

# Random jitter within the hour (5 minutes safety margin = 300 seconds)
# Jitter range: 300-3300 seconds (5-55 minutes)
JITTER=$(( RANDOM % 3000 + 300 ))

# Total delay = base delay + jitter
TOTAL_DELAY=$(( BASE_DELAY + JITTER ))

echo "Node $NODE_INDEX: Waiting $TOTAL_DELAY seconds ($(($TOTAL_DELAY/60)) minutes)"
sleep $TOTAL_DELAY

# Then proceed with certificate rotation
```

**Systemd Timer with Node Index Jitter:**
```ini
# /etc/systemd/system/cert-rotation-weekly.timer
[Unit]
Description=Weekly Certificate Rotation with Node Index Jitter
Requires=cert-rotation-weekly.service

[Timer]
OnCalendar=weekly
# No RandomizedDelaySec - we handle jitter in the service script
Persistent=true

[Install]
WantedBy=timers.target
```

**Service Script with Node Index Jitter:**
```bash
#!/bin/bash
# /etc/systemd/system/cert-rotation-weekly.service

[Unit]
Description=Weekly Certificate Rotation
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cert-rotation-with-jitter.sh
User=root
Group=root

[Install]
WantedBy=multi-user.target
```

**Jitter Script:**
```bash
#!/bin/bash
# /usr/local/bin/cert-rotation-with-jitter.sh

# Extract node index from hostname
NODE_INDEX=$(hostname | grep -oE '[0-9]+$')
if [ -z "$NODE_INDEX" ]; then
    echo "ERROR: Could not extract node index from hostname: $(hostname)"
    exit 1
fi

# Calculate jitter window for this node
BASE_DELAY=$(( (NODE_INDEX - 1) * 3600 ))
JITTER=$(( RANDOM % 3000 + 300 ))  # 5-55 minutes
TOTAL_DELAY=$(( BASE_DELAY + JITTER ))

echo "Node $NODE_INDEX: Waiting $TOTAL_DELAY seconds ($(($TOTAL_DELAY/60)) minutes)"
sleep $TOTAL_DELAY

# Proceed with certificate rotation
echo "Starting certificate rotation for node $NODE_INDEX"
# ... certificate rotation logic here ...
```

**Jitter Schedule Example:**
- **chromebox1**: 5-55 minutes after rotation trigger
- **chromebox2**: 1h5m - 1h55m after rotation trigger
- **chromebox3**: 2h5m - 2h55m after rotation trigger
- **chromebox4**: 3h5m - 3h55m after rotation trigger (future expansion)

### **Service Restart Strategy**

**Graceful Service Restart:**
```bash
# 1. Restart etcd (cluster remains available)
systemctl restart etcd
sleep 30  # Wait for etcd to stabilize

# 2. Restart API server (load balancer handles failover)
systemctl restart kube-apiserver
sleep 30  # Wait for API server to stabilize

# 3. Restart control plane components
systemctl restart kube-controller-manager kube-scheduler
sleep 30  # Wait for components to stabilize

# 4. Restart node components
systemctl restart kubelet kube-proxy
sleep 30  # Wait for components to stabilize
```

### **Monitoring and Alerting**

**Certificate Expiration Monitoring:**
```bash
# Check certificate expiration
openssl x509 -in /etc/kubernetes/pki/etcd-server.crt -noout -dates
openssl x509 -in /etc/kubernetes/pki/kube-apiserver.crt -noout -dates

# Alert if certificate expires within 7 days
if [ $(date -d "$(openssl x509 -in /etc/kubernetes/pki/etcd-server.crt -noout -enddate | cut -d= -f2)" +%s) -lt $(date -d "+7 days" +%s) ]; then
    echo "WARNING: etcd-server certificate expires soon"
fi
```

**Rotation Success Verification:**
```bash
# Verify new certificates are valid
openssl verify -CAfile /etc/kubernetes/pki/ca.crt -untrusted /etc/kubernetes/pki/intermediate-ca.crt /etc/kubernetes/pki/etcd-server.crt

# Verify services are running
systemctl is-active etcd kube-apiserver kube-controller-manager kube-scheduler kubelet kube-proxy
```

### **Security Benefits of This Approach**

1. **Frequent Rotation**: Weekly service certificate rotation limits exposure window
2. **Intermediate CA Rotation**: Monthly intermediate CA rotation provides additional security
3. **Jitter**: Prevents coordinated attacks during rotation windows
4. **Automation**: Reduces human error and ensures consistent rotation
5. **Monitoring**: Early warning of certificate issues
6. **Zero Downtime**: Services remain available during rotation