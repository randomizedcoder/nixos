# nix/gitops/env/cilium.nix
#
# Cilium Helm chart values (kube-proxy replacement, dual-stack, Hubble).
#
{ pkgs, lib }:
let
  constants = import ../../constants.nix;
in
{
  manifests = [
    {
      name = "cilium/values.yaml";
      content = ''
        # Cilium Helm chart values
        # Install via: helm install cilium cilium/cilium -n kube-system -f values.yaml
        kubeProxyReplacement: true
        k8sServiceHost: "${constants.network.gateway4}"
        k8sServicePort: "6443"

        ipam:
          mode: kubernetes

        ipv4:
          enabled: true
        ipv6:
          enabled: true

        hubble:
          enabled: true
          relay:
            enabled: true
          ui:
            enabled: true

        operator:
          replicas: 1
          resources:
            requests:
              cpu: 50m
              memory: 128Mi

        resources:
          requests:
            cpu: 100m
            memory: 256Mi
      '';
    }
    {
      name = "cilium/application.yaml";
      content = ''
        apiVersion: argoproj.io/v1alpha1
        kind: Application
        metadata:
          name: cilium
          namespace: argocd
        spec:
          project: default
          source:
            repoURL: https://helm.cilium.io/
            chart: cilium
            targetRevision: "1.*"
            helm:
              valueFiles:
              - values.yaml
          destination:
            server: https://kubernetes.default.svc
            namespace: kube-system
          syncPolicy:
            automated:
              prune: true
              selfHeal: true
      '';
    }
  ];
}
