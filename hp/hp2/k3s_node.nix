# https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/cluster/k3s/docs/USAGE.md
{ config, pkgs, ... }:
let
  kubeMasterIP = "172.16.40.142";
  kubeMasterHostname = "hp1";
  kubeMasterAPIServerPort = 6443;
in
{
  networking.firewall.allowedTCPPorts = [
    6443 # k3s: required so that pods can reach the API server (running on port 6443 by default)
    # 2379 # k3s, etcd clients: required if using a "High Availability Embedded etcd" configuration
    # 2380 # k3s, etcd peers: required if using a "High Availability Embedded etcd" configuration
  ];
  networking.firewall.allowedUDPPorts = [
    # 8472 # k3s, flannel: required if using multi-node for inter-node networking
  ];
  services.k3s = {
    enable = true;
    role = "server";
    # extraFlags = toString [
    #   # "--debug" # Optionally add additional args to k3s
    # ];
    token = "notSecureToken"; # FIX ME use tokenFile
    clusterInit = true; # must be false for "agent"
    serverAddr = "https://${kubeMasterHostname}:${toString kubeMasterAPIServerPort}";
  };
  # packages for administration tasks
  environment.systemPackages = with pkgs; [
    kompose
    kubectl
    openssl
    cfssl
    certmgr
    istioctl
    krew
    kubevirt
    #
    kubeshark
    # kubectl-ktop
    kubectl-klock
    kube-capacity
    kubectl-images
    kubectl-gadget
    # this is very old
    #kubectl-doctor
    # https://github.com/boz/kail
    kail
    ktop
    # https://github.com/kdash-rs/kdash
    kdash
    # # https://github.com/int128/kubelogin
    # kubelogin-oidc
    # k9s --kubeconfig=dev-d.kubeconfig
    k9s
    #
    (wrapHelm kubernetes-helm {
      plugins = with pkgs.kubernetes-helmPlugins; [
        helm-secrets
        helm-diff
        helm-s3
        helm-git
      ];
    })
    #
    fluxcd
    fluxctl
  ];
}

# sudo chown root:wheel /etc/rancher/k3s/k3s.yaml
# sudo chmod 640 /etc/rancher/k3s/k3s.yaml
# sudo chown root:wheel /etc/rancher/k3s/k3s.yaml && sudo chmod 640 /etc/rancher/k3s/k3s.yaml
# export KUBECONFIG=/etc/rancher/k3s/k3s.yaml