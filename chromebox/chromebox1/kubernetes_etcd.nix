{ config, lib, pkgs, ... }:

with lib;

let
  # Get the hostname from the current system
  hostname = config.networking.hostName;

  # Extract node index from hostname (e.g., chromebox1 -> 1)
  nodeIndex = builtins.head (builtins.match ".*([0-9]+)" hostname);

  # Map hostname to actual IP address
  nodeIpMap = {
    "chromebox1" = "172.16.40.178";
    "chromebox2" = "172.16.40.217";
    "chromebox3" = "172.16.40.62";
  };

  # Get the current node's IP address
  currentNodeIp = nodeIpMap.${hostname};

  # Certificate paths
  pkiPath = "/etc/kubernetes/pki";

  # All nodes are both control plane and worker nodes
  isMaster = true;  # All nodes are control plane
in
{
  # etcd configuration for multi-master setup
  services.etcd = mkIf isMaster {
    enable = true;
    name = hostname;
    dataDir = "/var/lib/etcd";

    # etcd server certificates
    certFile = "${pkiPath}/etcd.pem";
    keyFile = "${pkiPath}/etcd-key.pem";
    trustedCaFile = "${pkiPath}/ca.pem";

    # etcd client certificates
    clientCertAuth = true;
    peerClientCertAuth = true;

    # Network configuration for multi-master with actual IPs
    listenClientUrls = [ "https://0.0.0.0:2379" ];
    listenPeerUrls = [ "https://0.0.0.0:2380" ];
    advertiseClientUrls = [ "https://${currentNodeIp}:2379" ];
    initialCluster = [
      "chromebox1=https://172.16.40.178:2380"
      "chromebox2=https://172.16.40.217:2380"
      "chromebox3=https://172.16.40.62:2380"
    ];
    initialAdvertisePeerUrls = [ "https://${currentNodeIp}:2380" ];
  };

  # Add etcd.local to hosts file for master nodes
  networking.extraHosts = mkIf isMaster ''
    127.0.0.1 etcd.cluster.local etcd.local
  '';
}
