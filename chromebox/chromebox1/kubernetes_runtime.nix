{ config, lib, pkgs, ... }:

with lib;

let
  # Certificate paths
  pkiPath = "/etc/kubernetes/pki";

  # Helm configuration following NixOS wiki best practices
  my-kubernetes-helm = with pkgs; wrapHelm kubernetes-helm {
    plugins = with kubernetes-helmPlugins; [
      helm-secrets
      helm-diff
      helm-s3
      helm-git
    ];
  };

  # Helmfile for advanced Helm management
  my-helmfile = pkgs.helmfile-wrapped.override {
    inherit (my-kubernetes-helm) pluginsDir;
  };
in
{
        # System packages for certificate management and cluster management
        environment.systemPackages = with pkgs; [
          cfssl
          cfssljson
          kubectl
          kubernetes
          cilium-cli
          my-kubernetes-helm
          my-helmfile
        ];

  # Create PKI directory
  systemd.tmpfiles.rules = [
    "d ${pkiPath} 0755 root root -"
    "d /var/lib/kubernetes 0755 kubernetes kubernetes -"
    "d /var/lib/etcd 0755 etcd etcd -"
  ];

  # Create kubernetes user and group
  users.users.kubernetes = {
    uid = config.ids.uids.kubernetes;
    description = "Kubernetes user";
    group = "kubernetes";
    home = "/var/lib/kubernetes";
    createHome = true;
    homeMode = "755";
  };

  users.groups.kubernetes.gid = config.ids.gids.kubernetes;

  # Container runtime (containerd)
  virtualisation.containerd = {
    enable = true;
    settings = {
      version = 2;
      root = "/var/lib/containerd";
      state = "/run/containerd";
      oom_score = 0;

      grpc = {
        address = "/run/containerd/containerd.sock";
      };

      plugins."io.containerd.grpc.v1.cri" = {
        sandbox_image = "pause:latest";

        cni = {
          bin_dir = "/opt/cni/bin";
          max_conf_num = 0;
        };

        containerd.runtimes.runc = {
          runtime_type = "io.containerd.runc.v2";
          options.SystemdCgroup = true;
        };
      };
    };
  };

  # Helm installation service for Cilium and Hubble
  systemd.services.helm-install-addons = {
    description = "Install Cilium and Hubble via Helm";
    after = [ "kubernetes-apiserver.service" "kubernetes-controller-manager.service" "kubernetes-scheduler.service" ];
    wants = [ "kubernetes-apiserver.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/home/das/nixos/chromebox/chromebox1/helm-install-addons.sh";
      User = "root";
      StandardOutput = "journal";
      StandardError = "journal";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
