# Kubernetes Ingress and Traffic Control Design

## Goals
- **Max throughput and low latency** for Layer 4 (DNS, Kafka/Redpanda).
- **Rich Layer 7 features** (TLS termination, caching) for HTTP(S).
- **Separation of concerns** for easier multi-ingress operations.
- **Router-based ECMP per-flow** load distribution via BGP.
- **Max throughput** Increase MTU on the NixOS interfaces to 9216 bytes

---

## Traffic Split & Control Planes

### Cilium (eBPF Dataplane + GoBGP Control Plane)
- Handles **UDP/TCP 53** (PowerDNS) and **Kafka/Redpanda 9093/TCP** as **pure L4**.
- Exposes these services via `Service: LoadBalancer` VIPs.
- Cilium **advertises VIPs over BGP** to upstream routers.
- Avoids L7 proxies to keep latency and CPU overhead minimal.

### NGINX (Edge HTTP[S] with Caching)
- Dedicated ingress controller for **HTTP/HTTPS on port 80 and 443**.
( 80 to allow Let's Encrypt integration with ACME and the cert manager )
- Provides TLS termination, **cert-manager** integration, and **advanced caching**.
  - **NGINX Ingress Controller (classic Ingress API)** – stable, full caching support.
- Nginx also allows for mondifiation of HTTP headers

---

## Certificate Management (ACME via cert-manager)
- Uses **ACME HTTP-01** challenges through the NGINX edge.
- cert-manager automates certificate issuance and renewal.
- Certificates stored in Kubernetes Secrets for use by NGINX listeners.
- Centralized management of certificate lifecycles across all domains.

---

## BGP & ECMP Routing
- **Cilium BGP Control Plane (GoBGP)** peers directly with upstream routers.
- Advertises LoadBalancer VIPs from multiple nodes.
- Routers perform **per-flow ECMP** load sharing using 5-tuple hashing.
- Key design choices:
  - Limit advertising nodes per VIP to respect ECMP path limits.
  - Optionally enable **BFD** and **graceful restart** if routers support them.
  - Use deterministic communities/local-pref for multi-router or multi-DC setups.

We will leave this BGP requirement out for the Chromebox lab environment for now.

---

## Data Path Principles
- **L4 Fast Path (DNS, Kafka)**
  - Proxy-free, eBPF-based socket load balancing.
  - Minimal latency and CPU usage.

- **L7 Feature Path (HTTP/gRPC)**
  - TLS termination, caching, and policies handled at NGINX.
  - Gateway API recommended for new clusters; Ingress for full caching feature parity.

---

## Resiliency & Correctness
- **Health-aware routing** – Cilium only advertises healthy endpoints.
- **Preserve client IPs** – use `externalTrafficPolicy: Local` when ACLs depend on source IPs.
- **Failure domain awareness** – prefer local backends; limit cross-AZ hairpins.
- **Graceful drain** – withdraw BGP routes during maintenance to prevent blackholes.

---

## Security Posture
- **Edge TLS** termination via NGINX using cert-manager-managed certificates.
- **End-to-end encryption** maintained for Kafka brokers (no TLS offload).
- **DNS hardening** – allow TCP/53 for large payloads (DNSSEC, AXFR).

---

## Observability & Operations
- **Cilium/Hubble** – deep visibility into L3/L4 flows and policies.
- **NGINX metrics** – cache hit ratios, upstream latency, and saturation.
- **BGP telemetry** – monitor session state, prefixes, ECMP path counts, and churn.
- **Progressive rollout** – use separate IngressClass/GatewayClass for canaries.
- **Upgrade strategy** – update CRDs → controllers → dataplane sequentially.

---

## Performance Tuning
- **MTU alignment** – adjust for overlay networks to avoid fragmentation.
- **Node-local backends** – reduce latency and avoid cross-node traffic.
- **NGINX caching optimization** – tune cache keys, TTLs, and revalidation.
- **Kafka tuning** – align listener buffer and connection parameters with LB fan-out.

---

## Why This Works
- DNS and Kafka remain on a **lean, eBPF-accelerated L4 path** for maximum throughput.
- HTTP/gRPC ingress gains **feature-rich L7 capabilities** with NGINX and cert-manager.
- **Cilium BGP integration** offloads load distribution to the routers, enabling scalable and resilient ECMP across nodes.

✅ Summary Table
Component	Purpose	Key Role	Notes
Cilium	CNI + eBPF dataplane	L3/L4 networking, BGP announcements	kube-proxy-free, GoBGP integrated
Cilium BGP Control Plane	External routing	ECMP load distribution to routers	GoBGP backend, integrated in Cilium
NGINX (Ingress or Gateway Fabric)	L7 ingress	TLS termination, caching, cert-manager integration	Choose classic or Gateway API flavor
cert-manager	Certificates	ACME + secret management	Required for TLS automation
Hubble / Hubble UI	Observability	Flow tracing, DNS visibility	Comes with Cilium
Prometheus / Grafana	Metrics	L7/L4 telemetry dashboards	Optional but recommended
external-dns	DNS automation	Dynamic DNS records for ingress VIPs	Optional convenience layer


## Enabling More AddOns

To enable the kubernetes add on, we want a secure and nix style solution, where the k8nix repo provides a method for applying addons with a secure hash.  e.g. This enforces integirty so the yaml can't be changed malliciously or otherwise.

We will need to add the new input to each of the flake.nix files

inputs.k8nix.url = "gitlab:luxzeitlos/k8nix";

https://gitlab.com/luxzeitlos/k8nix

Then we will need to create the multiYamlAddons to add cilium.  The sha256 can be left blank initially, so that we can run the flake and nix will tell us the sha256 for the cilium .yaml

While we are here we can also add the certManager.  Here is the example of using multiYamlAddons to add cert manager, but looking at https://github.com/cert-manager/cert-manager/tags there is a newer version v1.19.1, so we can upgrade to this, leaving the sha256 blank, so we can populate this with the correct hash after trying to use the flake.

```
services.kubernetes.addonManager.multiYamlAddons.certManager = rec {
  name = "cert-manager";
  version = "1.18.2";
  src = builtins.fetchurl {
    url = "https://github.com/cert-manager/cert-manager/releases/download/v${version}/cert-manager.yaml";
    sha256 = "sha256:0vx1nfyhl0rzb6psfxplq8pfp18mrrdk83n8rj2ph8q6r15vcih5";
  };
};
```

## AddOns to enable

Addon we want to enable via multiYamlAddons are:
- certManager https://github.com/cert-manager/cert-manager/v1.19.1
- Cilium https://github.com/cilium/cilium/ 1.17.8
- Hubble https://github.com/cilium/hubble v1.18.0
- Kubernetes dashboard https://github.com/kubernetes/dashboard#kubernetes-dashboard kubernetes-dashboard-7.13.0
- Nginx ingess https://github.com/kubernetes/ingress-nginx v1.13.3
- Prometheus https://github.com/prometheus-operator/kube-prometheus v0.16.0