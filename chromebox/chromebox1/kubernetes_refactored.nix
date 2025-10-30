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

  # Define the cluster configuration with actual IP addresses
  clusterConfig = {
    # All nodes are control plane nodes with actual DHCP-assigned IPs
    masterAddresses = [
      "172.16.40.178"  # chromebox1
      "172.16.40.217"  # chromebox2
      "172.16.40.62"   # chromebox3
    ];
    clusterCidr = "10.244.0.0/16";
    serviceClusterIpRange = "10.96.0.0/12";
    dnsClusterIp = "10.96.0.10";
    clusterDomain = "cluster.local";
  };

  # Certificate paths
  pkiPath = "/etc/kubernetes/pki";

  # All nodes are both control plane and worker nodes
  isMaster = true;  # All nodes are control plane
  isWorker = true;  # All nodes are worker nodes

  # Define roles - all nodes are both master and worker
  roles = [ "master" "node" ];
in
{
  # Import modular components
  imports = [
    ./kubernetes_addonManager.nix
    ./kubernetes_etcd.nix
    ./kubernetes_networking.nix
    ./kubernetes_runtime.nix
  ];

  # Enable Kubernetes services
  services.kubernetes = {
    enable = true;
    roles = roles;

    # Disable automatic certificate generation
    easyCerts = false;
    pki.enable = false;

    # Cluster configuration - use current node's actual IP
    masterAddress = currentNodeIp;
    clusterCidr = clusterConfig.clusterCidr;
    serviceClusterIpRange = clusterConfig.serviceClusterIpRange;

    # API server configuration
    apiserver = mkIf isMaster {
      enable = true;
      advertiseAddress = currentNodeIp;  # Use node's actual IP
      bindAddress = "0.0.0.0";
      securePort = 6443;

      # Custom certificate paths
      tlsCertFile = "${pkiPath}/kube-apiserver.pem";
      tlsKeyFile = "${pkiPath}/kube-apiserver-key.pem";
      clientCaFile = "${pkiPath}/ca.pem";

      # Kubelet client certificates
      kubeletClientCertFile = "${pkiPath}/kube-apiserver-kubelet-client.pem";
      kubeletClientKeyFile = "${pkiPath}/kube-apiserver-kubelet-client-key.pem";
      kubeletClientCaFile = "${pkiPath}/ca.pem";

      # Proxy client certificates (legacy - will be replaced by Cilium)
      proxyClientCertFile = "${pkiPath}/kube-apiserver-proxy-client.pem";
      proxyClientKeyFile = "${pkiPath}/kube-apiserver-proxy-client-key.pem";

      # Service account certificates
      serviceAccountKeyFile = "${pkiPath}/service-account.pem";
      serviceAccountSigningKeyFile = "${pkiPath}/service-account-key.pem";

      # etcd client certificates
      etcd = {
        servers = [ "https://127.0.0.1:2379" ];
        certFile = "${pkiPath}/kube-apiserver-etcd-client.pem";
        keyFile = "${pkiPath}/kube-apiserver-etcd-client-key.pem";
        caFile = "${pkiPath}/ca.pem";
      };

      # Extra SANs for API server
      extraSANs = [
        "kubernetes"
        "kubernetes.default"
        "kubernetes.default.svc"
        "kubernetes.default.svc.${clusterConfig.clusterDomain}"
        "10.96.0.1"  # Kubernetes service IP
        "127.0.0.1"
        currentNodeIp
      ];
    };

    # Controller manager configuration
    controllerManager = mkIf isMaster {
      enable = true;
      bindAddress = "127.0.0.1";
      securePort = 10257;

      # Custom certificate paths
      tlsCertFile = "${pkiPath}/kube-controller-manager.pem";
      tlsKeyFile = "${pkiPath}/kube-controller-manager-key.pem";
      rootCaFile = "${pkiPath}/ca.pem";
      serviceAccountKeyFile = "${pkiPath}/service-account-key.pem";

      # Kubeconfig for API server authentication
      kubeconfig = {
        server = "https://${currentNodeIp}:6443";
        certFile = "${pkiPath}/kube-controller-manager-client.pem";
        keyFile = "${pkiPath}/kube-controller-manager-client-key.pem";
        caFile = "${pkiPath}/ca.pem";
      };
    };

    # Scheduler configuration
    scheduler = mkIf isMaster {
      enable = true;
      bindAddress = "127.0.0.1";
      port = 10259;

      # Kubeconfig for API server authentication
      kubeconfig = {
        server = "https://${currentNodeIp}:6443";
        certFile = "${pkiPath}/kube-scheduler-client.pem";
        keyFile = "${pkiPath}/kube-scheduler-client-key.pem";
        caFile = "${pkiPath}/ca.pem";
      };
    };

    # Kubelet configuration
    kubelet = {
      enable = true;
      hostname = hostname;
      address = "0.0.0.0";
      port = 10250;

      # Custom certificate paths
      tlsCertFile = "${pkiPath}/kubelet.pem";
      tlsKeyFile = "${pkiPath}/kubelet-key.pem";
      clientCaFile = "${pkiPath}/ca.pem";

      # Kubeconfig for API server authentication
      kubeconfig = {
        server = "https://${currentNodeIp}:6443";
        certFile = "${pkiPath}/kubelet-client.pem";
        keyFile = "${pkiPath}/kubelet-client-key.pem";
        caFile = "${pkiPath}/ca.pem";
      };

      # No taints - all nodes are both master and worker
      taints = { };
    };

    # DNS addon configuration
    addons.dns = {
      enable = true;
      clusterIP = clusterConfig.dnsClusterIp;
      clusterDomain = clusterConfig.clusterDomain;
    };

    # Note: Flannel and kube-proxy are replaced by Cilium
    # Cilium provides:
    # - CNI functionality (replaces flannel)
    # - Service mesh (replaces kube-proxy)
    # - LoadBalancer services with BGP
    # - eBPF dataplane for high performance
  };
}
