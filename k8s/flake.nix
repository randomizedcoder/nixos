#
# flake.nix - 4-Node HA Kubernetes Cluster via NixOS MicroVMs
#
# HA K8s cluster (3 control planes + 1 worker) running as lightweight QEMU
# MicroVMs with TAP networking. PKI generated at build time and baked into
# VM images. Uses Cilium CNI (replacing kube-proxy), dual-stack IPv4/IPv6,
# host-side haproxy for apiserver HA, and GitOps deployment via ArgoCD.
#
# Architecture:
#   Host ─── k8sbr0 (bridge) ─┬─ k8stap0 → cp0  10.33.33.10  (etcd, apiserver, scheduler, CM)
#            haproxy:6443 ──┐  ├─ k8stap1 → cp1  10.33.33.11  (etcd, apiserver, scheduler, CM)
#            (LB → 3 CPs)  │  ├─ k8stap2 → cp2  10.33.33.12  (etcd, apiserver, scheduler, CM)
#                           └──└─ k8stap3 → w3   10.33.33.13  (kubelet, containerd)
#
# Quick Start:
#   nix develop                           # Dev shell (kubectl, helm, cilium-cli, step-cli, ...)
#   nix run .#k8s-check-host             # Verify host prereqs (tun, vhost-net, bridge)
#   sudo nix run .#k8s-network-setup    # Create bridge + 4 TAPs + NAT + haproxy LB
#   nix run .#k8s-start-all             # Build + start all 4 VMs (CPs first, then worker)
#   nix run .#k8s-vm-ssh -- --node=cp0 kubectl get nodes
#   nix run .#k8s-lifecycle-test-all    # Automated end-to-end test suite
#
# Teardown:
#   nix run .#k8s-vm-stop               # Stop all VMs
#   sudo nix run .#k8s-network-teardown # Remove bridge, TAPs, NAT, haproxy
#
# File Structure:
#   flake.nix                  # This file — orchestrator
#   nix/constants.nix          # IPs, MACs, ports, CIDRs, timeouts
#   nix/nodes.nix              # Node definitions (cp0, cp1, cp2, w3)
#   nix/microvm.nix            # mkK8sNode parametric VM generator
#   nix/k8s-module.nix         # NixOS module: etcd, apiserver, kubelet, containerd
#   nix/network-setup.nix      # Bridge + TAP + NAT + haproxy setup/teardown
#   nix/certs.nix              # Build-time PKI: 3 CAs + per-component certs
#   nix/cert-inject.nix        # Legacy: expect-driven cert transfer via virtio
#   nix/microvm-scripts.nix    # VM management (check, stop, ssh, start-all)
#   nix/shell.nix              # Dev shell
#   nix/lifecycle/             # Lifecycle test framework (per-node + cluster)
#   nix/gitops/                # Manifest generator (ArgoCD, Cilium, ClickHouse, nginx)
#
{
  description = "HA Kubernetes cluster (3 CP + 1 worker) via NixOS MicroVMs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      microvm,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        nixDir = ./nix;
        pkgs = nixpkgs.legacyPackages.${system};
        lib = pkgs.lib;

        constants = import (nixDir + "/constants.nix");
        nodes = import (nixDir + "/nodes.nix") { inherit constants; };
        k8sModule = import (nixDir + "/k8s-module.nix");

        # Import cert generation (build-time PKI)
        certs = import (nixDir + "/certs.nix") { inherit pkgs lib; };

        # ─── MicroVM Generator ───────────────────────────────────────────
        mkK8sNode = { nodeName, role }:
          import (nixDir + "/microvm.nix") {
            inherit pkgs lib microvm k8sModule nixpkgs system;
            inherit nodeName role;
            nodePki = certs.mkNodePki { inherit nodeName role; };
          };

        # Generate MicroVM packages for all nodes
        vmPackages = lib.mapAttrs' (name: def:
          lib.nameValuePair "k8s-microvm-${name}" (mkK8sNode {
            nodeName = name;
            inherit (def) role;
          })
        ) nodes.definitions;

        # Import lifecycle testing framework (Linux only)
        lifecycle = lib.optionalAttrs pkgs.stdenv.isLinux (
          import (nixDir + "/lifecycle") { inherit pkgs lib; }
        );

        # Import GitOps manifest generator (Linux only)
        gitops = lib.optionalAttrs pkgs.stdenv.isLinux (
          import (nixDir + "/gitops") { inherit pkgs lib; }
        );

      in
      {
        packages = vmPackages // lib.optionalAttrs pkgs.stdenv.isLinux (
          # Lifecycle test packages
          (lifecycle.packages or {})
          # GitOps manifests
          // (gitops.packages or {})
          # Cert generation (copies build-time certs to ./certs/ for inspection)
          // { k8s-gen-certs = certs.genCerts; }
          # Raw PKI store (all certs)
          // { k8s-pki = certs.pkiStore; }
        );

        devShells.default = import (nixDir + "/shell.nix") { inherit pkgs; };

        # ─── Apps (Linux only) ─────────────────────────────────────────
        apps = lib.optionalAttrs pkgs.stdenv.isLinux (
          let
            networkScripts = import (nixDir + "/network-setup.nix") { inherit pkgs; };
            vmScripts = import (nixDir + "/microvm-scripts.nix") { inherit pkgs; };
          in
          {
            # Network management
            k8s-check-host = {
              type = "app";
              program = "${networkScripts.check}/bin/k8s-check-host";
            };
            k8s-network-setup = {
              type = "app";
              program = "${networkScripts.setup}/bin/k8s-network-setup";
            };
            k8s-network-teardown = {
              type = "app";
              program = "${networkScripts.teardown}/bin/k8s-network-teardown";
            };

            # VM management
            k8s-vm-check = {
              type = "app";
              program = "${vmScripts.check}/bin/k8s-vm-check";
            };
            k8s-vm-stop = {
              type = "app";
              program = "${vmScripts.stop}/bin/k8s-vm-stop";
            };
            k8s-vm-ssh = {
              type = "app";
              program = "${vmScripts.ssh}/bin/k8s-vm-ssh";
            };
            k8s-start-all = {
              type = "app";
              program = "${vmScripts.startAll}/bin/k8s-start-all";
            };

            # Certificates (copies build-time certs to ./certs/ for inspection)
            k8s-gen-certs = {
              type = "app";
              program = "${certs.genCerts}/bin/k8s-gen-certs";
            };
          }
          # Lifecycle test apps
          // (lifecycle.apps or {})
        );
      }
    );
}
