#
# https://nixos.wiki/wiki/Kubernetes
# https://nixos.org/manual/nixos/stable/index.html#sec-kubernetes
#
# https://github.com/NixOS/nixpkgs/blob/release-24.05/nixos/modules/services/cluster/kubernetes/default.nix
#
{ config, pkgs, ... }:
let
  kubeMasterIP = "172.16.40.142";
  kubeMasterHostname = "hp1.home";
  kubeMasterAPIServerPort = 6443;
in
{
  # resolve master hostname
  networking.extraHosts = "${kubeMasterIP} ${kubeMasterHostname}";

  # packages for administration tasks
  environment.systemPackages = with pkgs; [
    kompose
    kubectl
    kubernetes
    istioctl
  ];

  services.kubernetes = let
    api = "https://${kubeMasterHostname}:${toString kubeMasterAPIServerPort}";
  in
  {
    roles = ["node"];
    masterAddress = kubeMasterHostname;
    easyCerts = true;

    # point kubelet and other services to kube-apiserver
    kubelet.kubeconfig.server = api;
    apiserverAddress = api;

    #addonManager.enable = true;

    # use coredns
    addons.dns.enable = true;

    # needed if you use swap
    kubelet.extraOpts = "--fail-swap-on=false";
  };
}