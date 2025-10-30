{ config, lib, pkgs, ... }:

with lib;

let
  # Get the hostname from the current system
  hostname = config.networking.hostName;

  # Define the cluster configuration
  clusterConfig = {
    clusterCidr = "10.244.0.0/16";
    clusterDomain = "cluster.local";
  };
in
{
  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      6443  # Kubernetes API server
      2379  # etcd client
      2380  # etcd peer
      10250 # kubelet
      10257 # controller manager
      10259 # scheduler
    ];
    allowedUDPPorts = [
      8285  # flannel udp (legacy, will be removed by Cilium)
      8472  # flannel vxlan (legacy, will be removed by Cilium)
    ];
  };

  # Kernel modules for networking
  boot.kernelModules = [
    "br_netfilter"
    "overlay"
  ];

  # Sysctl settings for Kubernetes
  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.ipv4.ip_forward" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
  };

  # CNI plugins - Cilium will replace these
  services.kubernetes.kubelet.cni.packages = with pkgs; [
    cni-plugins
    # Note: Cilium will replace kube-proxy and provide CNI functionality
  ];

  # CNI configuration - Cilium will handle this
  services.kubernetes.kubelet.cni.config = [
    {
      name = "cilium";
      type = "cilium";
      cniVersion = "0.3.1";
    }
  ];

  # DHCP configuration to avoid conflicts with CNI
  networking.dhcpcd.denyInterfaces = [
    "cilium*"
    "lxc*"
    "veth*"
  ];
}
