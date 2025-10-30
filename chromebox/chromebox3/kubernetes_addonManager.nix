{ config, lib, pkgs, ... }:

with lib;

let
  # Get the hostname from the current system
  hostname = config.networking.hostName;
in
{
  # Addon Manager configuration with k8nix integration
  services.kubernetes.addonManager = {
    enable = true;

    # k8nix multiYamlAddons for secure addon management
    multiYamlAddons = {
      certManager = rec {
        name = "cert-manager";
        version = "1.19.1";
        src = builtins.fetchurl {
          url = "https://github.com/cert-manager/cert-manager/releases/download/v${version}/cert-manager.yaml";
          sha256 = "sha256:10cf6gkbcq7iwa85ylgdzysi42dqvsrj8jqjyhcmdf1ngsjl2sl7";
        };
      };

      # Cilium and Hubble will be installed via Helm (see helm-install-addons.sh)
      # This is because Cilium doesn't provide single YAML files for installation

      kubernetesDashboard = rec {
        name = "kubernetes-dashboard";
        version = "7.13.0";
        src = builtins.fetchurl {
          url = "https://raw.githubusercontent.com/kubernetes/dashboard/v${version}/aio/deploy/recommended.yaml";
          sha256 = ""; # Populated after first build
        };
      };

      nginxIngress = rec {
        name = "nginx-ingress";
        version = "1.13.3";
        src = builtins.fetchurl {
          url = "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v${version}/deploy/static/provider/cloud/deploy.yaml";
          sha256 = ""; # Populated after first build
        };
      };

      prometheus = rec {
        name = "prometheus";
        version = "0.16.0";
        src = builtins.fetchurl {
          url = "https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/v${version}/manifests/setup.yaml";
          sha256 = ""; # Populated after first build
        };
      };
    };
  };
}
