# nix/k8s-module.nix
#
# NixOS module for Kubernetes services.
# Configures etcd, apiserver, controller-manager, scheduler, containerd, kubelet.
# Cilium deployed via GitOps (only prereqs configured here).
# No kube-proxy (Cilium replaces it).
#
{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.services.k8s;
  constants = import ./constants.nix;

  isControlPlane = cfg.role == "control-plane";

  # etcd cluster: all control plane nodes (cp0, cp1, cp2)
  controlPlaneNodes = builtins.filter (n:
    (import ./nodes.nix { inherit constants; }).definitions.${n}.role == "control-plane"
  ) constants.nodeNames;

  etcdInitialCluster = concatStringsSep "," (map (n:
    "${n}=https://${constants.network.ipv4.${n}}:2380"
  ) controlPlaneNodes);

  etcdEndpoints = concatStringsSep "," (map (n:
    "https://${constants.network.ipv4.${n}}:2379"
  ) controlPlaneNodes);

  # All apiserver SANs for cert generation
  apiserverSANs = [
    "kubernetes" "kubernetes.default" "kubernetes.default.svc"
    "kubernetes.default.svc.${constants.k8s.clusterDomain}"
    constants.k8s.apiServiceIp "127.0.0.1" "::1"
  ] ++ constants.allNodeIps4 ++ constants.allNodeIps6;

  pki = constants.k8s.pkiDir;

  # ─── Shared systemd hardening ────────────────────────────────────
  # Common security directives for all K8s services.
  # These are safe for any network service that doesn't need hardware
  # access, kernel module loading, or namespace creation.
  commonHardening = {
    ProtectSystem = "full";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    NoNewPrivileges = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    RestrictRealtime = true;
    RestrictNamespaces = true;
    MemoryDenyWriteExecute = true;
    SystemCallArchitectures = "native";
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
    UMask = "0077";
    ProtectProc = "invisible";
    ProcSubset = "pid";
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
      "~@resources"
    ];
    CapabilityBoundingSet = "";
    DevicePolicy = "closed";
  };
in
{
  options.services.k8s = {
    enable = mkEnableOption "Kubernetes services";

    role = mkOption {
      type = types.enum [ "control-plane" "worker" ];
      description = "Node role in the cluster";
    };

    nodeName = mkOption {
      type = types.str;
      description = "Node name (hostname)";
    };

    nodeIp4 = mkOption {
      type = types.str;
      description = "Node IPv4 address";
    };

    nodeIp6 = mkOption {
      type = types.str;
      description = "Node IPv6 address";
    };
  };

  config = mkIf cfg.enable {
    # ─── Required kernel modules for K8s + Cilium ─────────────────────
    boot.kernelModules = [
      "br_netfilter"
      "overlay"
      "ip_vs"
      "ip_vs_rr"
      "ip_vs_wrr"
      "ip_vs_sh"
      "nf_conntrack"
    ];

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
    };

    # ─── PKI directory ────────────────────────────────────────────────
    systemd.tmpfiles.rules = [
      "d ${pki} 0755 root root -"
    ];

    # ─── containerd ───────────────────────────────────────────────────
    virtualisation.containerd = {
      enable = true;
      settings = {
        version = 2;
        plugins."io.containerd.grpc.v1.cri" = {
          sandbox_image = "registry.k8s.io/pause:3.10";
          containerd.runtimes.runc = {
            runtime_type = "io.containerd.runc.v2";
            options.SystemdCgroup = true;
          };
          cni.bin_dir = "/opt/cni/bin";
          cni.conf_dir = "/etc/cni/net.d";
        };
      };
    };

    # CNI plugins
    environment.systemPackages = with pkgs; [
      cni-plugins
      kubectl
      iptables
      iproute2
      conntrack-tools
      socat
      ethtool
      util-linux
      openssl
      etcd  # for etcdctl
    ];

    # Symlink CNI plugins to expected location
    system.activationScripts.cni-plugins = ''
      mkdir -p /opt/cni/bin
      for f in ${pkgs.cni-plugins}/bin/*; do
        ln -sf "$f" /opt/cni/bin/
      done
    '';

    # ─── kubelet ──────────────────────────────────────────────────────
    systemd.services.kubelet = {
      description = "Kubernetes Kubelet";
      wantedBy = [ "multi-user.target" ];
      after = [ "containerd.service" ] ++ optionals isControlPlane [ "kube-apiserver.service" ];
      requires = [ "containerd.service" ];
      path = with pkgs; [ iptables iproute2 mount util-linux ];
      serviceConfig = {
        ExecStart = concatStringsSep " " ([
          "${pkgs.kubernetes}/bin/kubelet"
          "--container-runtime-endpoint=unix:///run/containerd/containerd.sock"
          "--kubeconfig=${pki}/kubelet-kubeconfig"
          "--config=${pki}/kubelet-config.yaml"
          "--node-ip=${cfg.nodeIp4},${cfg.nodeIp6}"
          "--hostname-override=${constants.getHostname cfg.nodeName}"
          "--register-node=true"
          "--v=2"
        ]);
        Restart = "on-failure";
        RestartSec = "10";
        TimeoutStopSec = "15";
        # kubelet needs extensive privileges for container management
        # but we restrict everything it doesn't need
        ProtectHome = true;
        ProtectKernelModules = true;
        # Note: ProtectKernelLogs omitted — kubelet needs /dev/kmsg access
        ProtectClock = true;
        ProtectHostname = true;
        PrivateTmp = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RestrictRealtime = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        UMask = "0077";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
        # kubelet needs: SYS_ADMIN (cgroups/mounts), NET_ADMIN (pod networking),
        # KILL (signal containers), CHOWN/FOWNER/DAC_OVERRIDE (volume perms),
        # SETUID/SETGID (container users), MKNOD (device nodes), SYS_CHROOT,
        # SYS_RESOURCE (rlimits), NET_BIND_SERVICE, NET_RAW (health checks),
        # SYSLOG (/dev/kmsg when dmesg_restrict=1)
        CapabilityBoundingSet = [
          "CAP_SYS_ADMIN" "CAP_NET_ADMIN" "CAP_NET_BIND_SERVICE" "CAP_NET_RAW"
          "CAP_DAC_OVERRIDE" "CAP_DAC_READ_SEARCH" "CAP_FOWNER" "CAP_CHOWN"
          "CAP_FSETID" "CAP_SETUID" "CAP_SETGID" "CAP_SETPCAP"
          "CAP_KILL" "CAP_MKNOD" "CAP_SYS_CHROOT" "CAP_SYS_RESOURCE"
          "CAP_SYSLOG"
        ];
        SystemCallFilter = [
          "@system-service" "@mount" "@privileged"
          "~@obsolete" "~@cpu-emulation" "~@swap" "~@reboot" "~@raw-io"
        ];
      };
    };

    # ─── etcd (control plane only) ────────────────────────────────────
    systemd.services.etcd = mkIf isControlPlane {
      description = "etcd - distributed key-value store";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = commonHardening // {
        ExecStart = concatStringsSep " " [
          "${pkgs.etcd}/bin/etcd"
          "--name=${cfg.nodeName}"
          "--data-dir=/var/lib/etcd"
          "--listen-client-urls=https://${cfg.nodeIp4}:2379,https://127.0.0.1:2379"
          "--advertise-client-urls=https://${cfg.nodeIp4}:2379"
          "--listen-peer-urls=https://${cfg.nodeIp4}:2380"
          "--initial-advertise-peer-urls=https://${cfg.nodeIp4}:2380"
          "--initial-cluster=${etcdInitialCluster}"
          "--initial-cluster-state=new"
          "--initial-cluster-token=k8s-etcd-cluster"
          "--client-cert-auth=true"
          "--trusted-ca-file=${pki}/etcd-ca.crt"
          "--cert-file=${pki}/etcd-server.crt"
          "--key-file=${pki}/etcd-server.key"
          "--peer-client-cert-auth=true"
          "--peer-trusted-ca-file=${pki}/etcd-ca.crt"
          "--peer-cert-file=${pki}/etcd-peer.crt"
          "--peer-key-file=${pki}/etcd-peer.key"
        ];
        Restart = "on-failure";
        RestartSec = "5";
        TimeoutStopSec = "15";
        StateDirectory = "etcd";
        Type = "notify";
        NotifyAccess = "all";
        ReadWritePaths = [ "/var/lib/etcd" ];
      };
    };

    # ─── kube-apiserver (control plane only) ──────────────────────────
    systemd.services.kube-apiserver = mkIf isControlPlane {
      description = "Kubernetes API Server";
      wantedBy = [ "multi-user.target" ];
      after = [ "etcd.service" ];
      requires = [ "etcd.service" ];
      serviceConfig = commonHardening // {
        ExecStart = concatStringsSep " " [
          "${pkgs.kubernetes}/bin/kube-apiserver"
          "--advertise-address=${cfg.nodeIp4}"
          "--allow-privileged=true"
          "--authorization-mode=Node,RBAC"
          "--client-ca-file=${pki}/ca.crt"
          "--enable-admission-plugins=NodeRestriction"
          "--etcd-servers=${etcdEndpoints}"
          "--etcd-cafile=${pki}/etcd-ca.crt"
          "--etcd-certfile=${pki}/apiserver-etcd-client.crt"
          "--etcd-keyfile=${pki}/apiserver-etcd-client.key"
          "--kubelet-client-certificate=${pki}/apiserver-kubelet-client.crt"
          "--kubelet-client-key=${pki}/apiserver-kubelet-client.key"
          "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname"
          "--proxy-client-cert-file=${pki}/front-proxy-client.crt"
          "--proxy-client-key-file=${pki}/front-proxy-client.key"
          "--requestheader-allowed-names=front-proxy-client"
          "--requestheader-client-ca-file=${pki}/front-proxy-ca.crt"
          "--requestheader-extra-headers-prefix=X-Remote-Extra-"
          "--requestheader-group-headers=X-Remote-Group"
          "--requestheader-username-headers=X-Remote-User"
          "--secure-port=6443"
          "--service-account-issuer=https://kubernetes.default.svc.${constants.k8s.clusterDomain}"
          "--service-account-key-file=${pki}/sa.pub"
          "--service-account-signing-key-file=${pki}/sa.key"
          "--service-cluster-ip-range=${constants.k8s.serviceCidr4},${constants.k8s.serviceCidr6}"
          "--tls-cert-file=${pki}/apiserver.crt"
          "--tls-private-key-file=${pki}/apiserver.key"
          "--v=2"
        ];
        Restart = "on-failure";
        RestartSec = "10";
        TimeoutStopSec = "15";
      };
    };

    # ─── kube-controller-manager (control plane only) ─────────────────
    systemd.services.kube-controller-manager = mkIf isControlPlane {
      description = "Kubernetes Controller Manager";
      wantedBy = [ "multi-user.target" ];
      after = [ "kube-apiserver.service" ];
      requires = [ "kube-apiserver.service" ];
      serviceConfig = commonHardening // {
        ExecStart = concatStringsSep " " [
          "${pkgs.kubernetes}/bin/kube-controller-manager"
          "--kubeconfig=${pki}/controller-manager-kubeconfig"
          "--bind-address=0.0.0.0"
          "--cluster-cidr=${constants.k8s.podCidr4},${constants.k8s.podCidr6}"
          "--cluster-name=kubernetes"
          "--cluster-signing-cert-file=${pki}/ca.crt"
          "--cluster-signing-key-file=${pki}/ca.key"
          "--controllers=*,bootstrapsigner,tokencleaner"
          "--leader-elect=true"
          "--root-ca-file=${pki}/ca.crt"
          "--service-account-private-key-file=${pki}/sa.key"
          "--service-cluster-ip-range=${constants.k8s.serviceCidr4},${constants.k8s.serviceCidr6}"
          "--use-service-account-credentials=true"
          "--allocate-node-cidrs=true"
          "--node-cidr-mask-size-ipv4=24"
          "--node-cidr-mask-size-ipv6=64"
          "--v=2"
        ];
        Restart = "on-failure";
        RestartSec = "10";
        TimeoutStopSec = "15";
      };
    };

    # ─── kube-scheduler (control plane only) ──────────────────────────
    systemd.services.kube-scheduler = mkIf isControlPlane {
      description = "Kubernetes Scheduler";
      wantedBy = [ "multi-user.target" ];
      after = [ "kube-apiserver.service" ];
      requires = [ "kube-apiserver.service" ];
      serviceConfig = commonHardening // {
        ExecStart = concatStringsSep " " [
          "${pkgs.kubernetes}/bin/kube-scheduler"
          "--kubeconfig=${pki}/scheduler-kubeconfig"
          "--leader-elect=true"
          "--v=2"
        ];
        Restart = "on-failure";
        RestartSec = "10";
        TimeoutStopSec = "15";
      };
    };

    # ─── containerd hardening ────────────────────────────────────────
    # containerd is configured by virtualisation.containerd above;
    # overlay additional security directives on its service.
    # containerd is a container runtime — it must be able to grant any
    # capability to containers, so CapabilityBoundingSet is left unrestricted.
    # We still apply non-capability hardening where it doesn't break containers.
    systemd.services.containerd.serviceConfig = {
      ProtectHome = true;
      ProtectKernelModules = true;
      ProtectClock = true;
      ProtectHostname = true;
      PrivateTmp = true;
      LockPersonality = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      UMask = "0077";
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
    };

    # ─── Firewall ─────────────────────────────────────────────────────
    networking.firewall.enable = false;
  };
}
