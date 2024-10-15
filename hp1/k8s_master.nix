#
# https://nixos.wiki/wiki/Kubernetes
# https://nixos.org/manual/nixos/stable/index.html#sec-kubernetes
#
# https://github.com/NixOS/nixpkgs/blob/release-24.05/nixos/modules/services/cluster/kubernetes/default.nix
#
# export KUBECONFIG=/etc/kubernetes/cluster-admin.kubeconfig
#
# fix permissions
# https://github.com/akibahmed229/nixos/blob/b131cbbe637470cc69ce862ba271a393c03a925b/modules/predefiend/nixos/kubernetes/default.nix#L48
#
# *   comment kubernetes-related code in configuration.nix
# *    $ nixos-rebuild switch
# *   clean up filesystem
# *    $ rm -rf /var/lib/kubernetes/ /var/lib/etcd/ /var/lib/cfssl/ /var/lib/kubelet/
# *    $ rm -rf /etc/kube-flannel/ /etc/kubernetes/
# *   uncomment kubernetes-related code again
# *    $ nixos-rebuild switch
#
{ config, pkgs, ... }:
let
  # When using easyCerts=true the IP Address must resolve to the master on creation.
  # So use simply 127.0.0.1 in that case. Otherwise you will have errors like this https://github.com/NixOS/nixpkgs/issues/59364
  # kubeMasterIP = "10.1.1.2";
  # kubeMasterHostname = "api.kube";
  # kubeMasterAPIServerPort = 6443;
  # We already add this via hosts.nix
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
    openssl
    cfssl
    certmgr
    istioctl
  ];

  services.cfssl.enable = true;

  services.kubernetes = {
    # master = apiserver, controllerManager, scheduler, addonManager, kube-proxy and etcd
    # node = kubelet and kube-proxy only
    roles = ["master" "node"];
    masterAddress = kubeMasterHostname;
    apiserverAddress = "https://${kubeMasterHostname}:${toString kubeMasterAPIServerPort}";
    easyCerts = true;
    # flannel.enable = true; # flannel is enabled by default
    apiserver = {
      securePort = kubeMasterAPIServerPort;
      advertiseAddress = kubeMasterIP;
    };

    addonManager.enable = true;

    # use coredns
    addons.dns.enable = true;

    # needed if you use swap
    kubelet.extraOpts = "--fail-swap-on=false";
  };
}