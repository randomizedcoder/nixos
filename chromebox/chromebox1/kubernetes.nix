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

      # Proxy client certificates
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

    # Proxy configuration
    proxy = {
      enable = true;
      bindAddress = "0.0.0.0";
      hostname = hostname;

      # Kubeconfig for API server authentication
      kubeconfig = {
        server = "https://${currentNodeIp}:6443";
        certFile = "${pkiPath}/kube-proxy-client.pem";
        keyFile = "${pkiPath}/kube-proxy-client-key.pem";
        caFile = "${pkiPath}/ca.pem";
      };
    };

    # Flannel configuration
    flannel = {
      enable = true;
      openFirewallPorts = true;
    };

    # DNS addon configuration
    addons.dns = {
      enable = true;
      clusterIP = clusterConfig.dnsClusterIp;
      clusterDomain = clusterConfig.clusterDomain;
    };

    # Addon Manager configuration with k8nix integration
    addonManager = {
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

        cilium = rec {
          name = "cilium";
          version = "1.18.2";
          src = builtins.fetchurl {
            url = "https://raw.githubusercontent.com/cilium/cilium/v${version}/install/kubernetes/quick-install.yaml";
            sha256 = ""; # Populated after first build
          };
        };

        hubble = rec {
          name = "hubble";
          version = "1.18.2";
          src = builtins.fetchurl {
            url = "https://raw.githubusercontent.com/cilium/cilium/v${version}/install/kubernetes/hubble.yaml";
            sha256 = ""; # Populated after first build
          };
        };

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
  };

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
      8285  # flannel udp
      8472  # flannel vxlan
    ];
  };

  # System packages for certificate management and cluster management
  environment.systemPackages = with pkgs; [
    cfssl
    cfssljson
    kubectl
    kubernetes
    cilium-cli
    helm
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

  # CNI plugins
  services.kubernetes.kubelet.cni.packages = with pkgs; [
    cni-plugins
    cni-plugin-flannel
  ];

  # CNI configuration
  services.kubernetes.kubelet.cni.config = [
    {
      name = "mynet";
      type = "flannel";
      cniVersion = "0.3.1";
      delegate = {
        isDefaultGateway = true;
        hairpinMode = true;
        bridge = "mynet";
      };
    }
  ];

  # DHCP configuration to avoid conflicts with CNI
  networking.dhcpcd.denyInterfaces = [
    "mynet*"
    "flannel*"
  ];

  # Add etcd.local to hosts file for master nodes
  networking.extraHosts = mkIf isMaster ''
    127.0.0.1 etcd.${clusterConfig.clusterDomain} etcd.local
  '';
}
