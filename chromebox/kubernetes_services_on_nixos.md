# Kubernetes on NixOS - Services and Networking Design

This document reviews the available NixOS Kubernetes services and integrates them with our advanced networking and ingress design. The deployment uses manual certificate management with ECDSA P-521 keys and implements a sophisticated traffic control architecture.

## Design Overview

Our Kubernetes cluster implements a **dual-plane networking architecture**:
- **L4 Fast Path**: Cilium eBPF for DNS and Kafka/Redpanda (high throughput, low latency)
- **L7 Feature Path**: NGINX Ingress for HTTP/HTTPS with TLS termination and caching
- **BGP Integration**: LoadBalancer VIPs advertised via Cilium GoBGP (lab environment simplified)
- **Certificate Management**: Manual ECDSA P-521 certificates with automated rotation

## NixOS kubernetes services

In the following folder are the nixpkgs .nix files for the kubernetes services.

/home/das/nixos/chromebox/nixpkgs_services_kubernetes/

These need to be reviewed to understand how certificates need to be disabled.  We need to find all the places that use the certificates and disable them.

## Summary Table

The following table summarizes the service, the .nix file, and the certificates that are used.

| Service | Nix File | Certificate Files | Certificate Purpose | Configuration Options |
|---------|----------|-------------------|---------------------|----------------------|
| **kube-apiserver** | `apiserver.nix` | `tlsCertFile`, `tlsKeyFile` | API server TLS termination | `--tls-cert-file`, `--tls-private-key-file` |
| | | `clientCaFile` | Client certificate validation | `--client-ca-file` |
| | | `kubeletClientCertFile`, `kubeletClientKeyFile` | Kubelet client authentication | `--kubelet-client-certificate`, `--kubelet-client-key` |
| | | `proxyClientCertFile`, `proxyClientKeyFile` | Proxy client authentication | `--proxy-client-cert-file`, `--proxy-client-key-file` |
| | | `serviceAccountKeyFile`, `serviceAccountSigningKeyFile` | Service account token signing | `--service-account-key-file`, `--service-account-signing-key-file` |
| | | `etcd.certFile`, `etcd.keyFile`, `etcd.caFile` | etcd client authentication | `--etcd-certfile`, `--etcd-keyfile`, `--etcd-cafile` |
| **kubelet** | `kubelet.nix` | `tlsCertFile`, `tlsKeyFile` | Kubelet server TLS | `--tls-cert-file`, `--tls-private-key-file` |
| | | `clientCaFile` | API server CA for client auth | `--client-ca-file` |
| | | `kubeconfig.certFile`, `kubeconfig.keyFile` | API server client authentication | Via kubeconfig |
| **kube-controller-manager** | `controller-manager.nix` | `tlsCertFile`, `tlsKeyFile` | Controller manager TLS | `--tls-cert-file`, `--tls-private-key-file` |
| | | `rootCaFile` | Root CA for service accounts | `--root-ca-file` |
| | | `serviceAccountKeyFile` | Service account token signing | `--service-account-private-key-file` |
| | | `kubeconfig.certFile`, `kubeconfig.keyFile` | API server client authentication | Via kubeconfig |
| **kube-scheduler** | `scheduler.nix` | `kubeconfig.certFile`, `kubeconfig.keyFile` | API server client authentication | Via kubeconfig |
| **kube-proxy** | `proxy.nix` | `kubeconfig.certFile`, `kubeconfig.keyFile` | API server client authentication | Via kubeconfig |
| **flannel** | `flannel.nix` | `kubeconfig.certFile`, `kubeconfig.keyFile` | API server client authentication | Via kubeconfig |
| **kube-addon-manager** | `addon-manager.nix` | `kubeconfig.certFile`, `kubeconfig.keyFile` | API server client authentication | Via kubeconfig |
| **etcd** | `pki.nix` | `certFile`, `keyFile`, `trustedCaFile` | etcd server TLS | etcd configuration |

## Certificate Generation Strategy

### Current NixOS Approach
The NixOS Kubernetes services use the `services.kubernetes.pki` module which:
1. **Automatically generates certificates** using CFSSL when `easyCerts = true`
2. **Creates certificate specifications** in `services.kubernetes.pki.certs`
3. **Uses certmgr** to manage certificate lifecycle
4. **Generates certificates** with RSA 2048-bit keys by default

### Manual Certificate Management Strategy
To use our custom certificate generation scripts, we need to:

1. **Disable automatic certificate generation**:
   ```nix
   services.kubernetes.easyCerts = false;
   services.kubernetes.pki.enable = false;
   ```

2. **Override certificate paths** in each service:
   ```nix
   services.kubernetes.apiserver = {
     tlsCertFile = "/etc/kubernetes/pki/kube-apiserver.pem";
     tlsKeyFile = "/etc/kubernetes/pki/kube-apiserver-key.pem";
     clientCaFile = "/etc/kubernetes/pki/ca.pem";
     # ... other certificate paths
   };
   ```

3. **Use our custom scripts** to generate certificates with:
   - ECDSA P-521 keys
   - Proper SANs for each service
   - Custom validity periods
   - Manual rotation strategy

## Key Configuration Points

### 1. API Server Certificates
- **TLS Certificate**: `--tls-cert-file`, `--tls-private-key-file`
- **Client CA**: `--client-ca-file` (for validating client certificates)
- **Kubelet Client**: `--kubelet-client-certificate`, `--kubelet-client-key`
- **Proxy Client**: `--proxy-client-cert-file`, `--proxy-client-key-file`
- **Service Account**: `--service-account-key-file`, `--service-account-signing-key-file`
- **etcd Client**: `--etcd-certfile`, `--etcd-keyfile`, `--etcd-cafile`

### 2. Kubelet Certificates
- **Server TLS**: `--tls-cert-file`, `--tls-private-key-file`
- **Client CA**: `--client-ca-file`
- **API Server Client**: Via kubeconfig

### 3. Controller Manager Certificates
- **Server TLS**: `--tls-cert-file`, `--tls-private-key-file`
- **Root CA**: `--root-ca-file`
- **Service Account Key**: `--service-account-private-key-file`
- **API Server Client**: Via kubeconfig

### 4. Other Services
- **Scheduler, Proxy, Flannel, Addon Manager**: All use kubeconfig for API server authentication

## Networking and Ingress Architecture

### Traffic Control Planes

#### 1. Cilium (eBPF Dataplane + GoBGP Control Plane)
- **Purpose**: L4 fast path for DNS (UDP/TCP 53) and Kafka/Redpanda (9093/TCP)
- **Features**:
  - eBPF-based socket load balancing (proxy-free)
  - BGP VIP advertisement for LoadBalancer services
  - Minimal latency and CPU overhead
- **Integration**: Replaces kube-proxy with eBPF acceleration

#### 2. NGINX Ingress Controller
- **Purpose**: L7 ingress for HTTP/HTTPS (ports 80/443)
- **Features**:
  - TLS termination with cert-manager integration
  - Advanced caching capabilities
  - HTTP header modification
  - Let's Encrypt ACME HTTP-01 challenges
- **Integration**: Classic Ingress API with full caching support

### Certificate Management Strategy

#### Manual Certificate Management (Control Plane)
- **Algorithm**: ECDSA P-521 (256-bit security strength)
- **Validity**: Root CA (40 years), Intermediate CAs (2 months), Service Certs (2 weeks)
- **Rotation**: Automated with node index-based jitter
- **Tools**: Custom CFSSL-based scripts with shellcheck compliance

#### ACME Certificate Management (Ingress)
- **Algorithm**: RSA/ECDSA via cert-manager
- **Provider**: Let's Encrypt with HTTP-01 challenges
- **Integration**: NGINX Ingress Controller with cert-manager
- **Automation**: Automatic issuance and renewal

### Addon Integration via k8nix

#### Required Addons
```nix
inputs.k8nix.url = "gitlab:luxzeitlos/k8nix";

services.kubernetes.addonManager.multiYamlAddons = {
  certManager = rec {
    name = "cert-manager";
    version = "1.19.1";
    src = builtins.fetchurl {
      url = "https://github.com/cert-manager/cert-manager/releases/download/v${version}/cert-manager.yaml";
      sha256 = ""; # Populated after first build
    };
  };

  cilium = rec {
    name = "cilium";
    version = "1.17.8";
    src = builtins.fetchurl {
      url = "https://github.com/cilium/cilium/releases/download/v${version}/cilium.yaml";
      sha256 = ""; # Populated after first build
    };
  };

  hubble = rec {
    name = "hubble";
    version = "1.18.0";
    src = builtins.fetchurl {
      url = "https://github.com/cilium/hubble/releases/download/v${version}/hubble.yaml";
      sha256 = ""; # Populated after first build
    };
  };

  kubernetesDashboard = rec {
    name = "kubernetes-dashboard";
    version = "7.13.0";
    src = builtins.fetchurl {
      url = "https://github.com/kubernetes/dashboard/releases/download/v${version}/kubernetes-dashboard.yaml";
      sha256 = ""; # Populated after first build
    };
  };

  nginxIngress = rec {
    name = "nginx-ingress";
    version = "1.13.3";
    src = builtins.fetchurl {
      url = "https://github.com/kubernetes/ingress-nginx/releases/download/v${version}/nginx-ingress.yaml";
      sha256 = ""; # Populated after first build
    };
  };

  prometheus = rec {
    name = "prometheus";
    version = "0.16.0";
    src = builtins.fetchurl {
      url = "https://github.com/prometheus-operator/kube-prometheus/releases/download/v${version}/kube-prometheus.yaml";
      sha256 = ""; # Populated after first build
    };
  };
};
```

## Implementation Plan

### Phase 1: Core Kubernetes Services
1. **Create NixOS configuration** that disables automatic certificate generation
2. **Override certificate paths** in each service configuration
3. **Use our certificate generation scripts** to create certificates
4. **Implement certificate rotation** using our custom scripts
5. **Test certificate validation** and service functionality

### Phase 2: Networking and Ingress
1. **Deploy Cilium** via k8nix multiYamlAddons
2. **Configure eBPF dataplane** for L4 fast path
3. **Deploy NGINX Ingress Controller** for L7 features
4. **Integrate cert-manager** for ACME certificate automation
5. **Configure BGP** (simplified for lab environment)

### Phase 3: Observability and Monitoring
1. **Deploy Hubble** for eBPF flow visibility
2. **Deploy Prometheus** for metrics collection
3. **Deploy Kubernetes Dashboard** for cluster management
4. **Configure observability** dashboards and alerting

### Phase 4: Performance Optimization
1. **Tune MTU** to 9216 bytes for maximum throughput
2. **Optimize eBPF** socket load balancing
3. **Configure NGINX caching** for optimal performance
4. **Implement health-aware routing** with Cilium
