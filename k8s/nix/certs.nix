# nix/certs.nix
#
# Certificate generation for K8s cluster.
#
# Two modes:
#   1. pkiStore: Nix derivation that generates all certs at build time.
#      Certs end up in /nix/store and are baked into VM images.
#   2. genCerts: Runtime script for manual generation to ./certs/
#
# pkiStore is used by microvm.nix to embed certs directly in VM images.
# genCerts is kept for manual/debugging use.
#
{ pkgs, lib ? pkgs.lib }:
let
  constants = import ./constants.nix;

  allIps4 = constants.allNodeIps4;
  allIps6 = constants.allNodeIps6;

  mkSans = sans: builtins.concatStringsSep " " (builtins.map (s: "--san ${s}") sans);

  apiserverSans = [
    "kubernetes" "kubernetes.default" "kubernetes.default.svc"
    "kubernetes.default.svc.${constants.k8s.clusterDomain}"
    constants.k8s.apiServiceIp constants.network.gateway4 "127.0.0.1" "::1"
  ] ++ allIps4 ++ allIps6;

  etcdSans = [ "localhost" "127.0.0.1" "::1" ] ++ allIps4 ++ allIps6;

  # ─── Build-time PKI derivation ──────────────────────────────────────
  # Generates ALL certs as a Nix store path. Deterministic (fixed seed not
  # needed — certs are regenerated on any input change via content hash).
  # Cert validity: 30 days for leaf certs, 10 years for CAs.
  # step-cli defaults to 24h which is too short for a dev cluster.
  leafNotAfter = "720h";   # 30 days
  caNotAfter = "87600h";   # 10 years

  pkiStore = pkgs.runCommand "k8s-pki" {
    nativeBuildInputs = with pkgs; [ step-cli openssl ];
  } ''
    mkdir -p $out

    # CAs
    step certificate create "k8s-cluster-ca" $out/ca.crt $out/ca.key \
      --profile root-ca --no-password --insecure --not-after=${caNotAfter}
    step certificate create "etcd-ca" $out/etcd-ca.crt $out/etcd-ca.key \
      --profile root-ca --no-password --insecure --not-after=${caNotAfter}
    step certificate create "front-proxy-ca" $out/front-proxy-ca.crt $out/front-proxy-ca.key \
      --profile root-ca --no-password --insecure --not-after=${caNotAfter}

    # Service account keypair
    openssl genrsa -out $out/sa.key 2048 2>/dev/null
    openssl rsa -in $out/sa.key -pubout -out $out/sa.pub 2>/dev/null

    # API Server
    step certificate create "kube-apiserver" $out/apiserver.crt $out/apiserver.key \
      --profile leaf --ca $out/ca.crt --ca-key $out/ca.key \
      --no-password --insecure --not-after=${leafNotAfter} \
      ${mkSans apiserverSans}

    # API Server -> Kubelet client
    step certificate create "apiserver-kubelet-client" \
      $out/apiserver-kubelet-client.crt $out/apiserver-kubelet-client.key \
      --profile leaf --ca $out/ca.crt --ca-key $out/ca.key \
      --no-password --insecure --not-after=${leafNotAfter} --san "apiserver-kubelet-client"

    # API Server -> etcd client
    step certificate create "apiserver-etcd-client" \
      $out/apiserver-etcd-client.crt $out/apiserver-etcd-client.key \
      --profile leaf --ca $out/etcd-ca.crt --ca-key $out/etcd-ca.key \
      --no-password --insecure --not-after=${leafNotAfter} --san "apiserver-etcd-client"

    # Front proxy client
    step certificate create "front-proxy-client" \
      $out/front-proxy-client.crt $out/front-proxy-client.key \
      --profile leaf --ca $out/front-proxy-ca.crt --ca-key $out/front-proxy-ca.key \
      --no-password --insecure --not-after=${leafNotAfter} --san "front-proxy-client"

    # Per-node etcd + kubelet certs
    ${builtins.concatStringsSep "\n" (builtins.map (n: let
      hostname = constants.getHostname n;
    in ''
    # etcd server + peer for ${n}
    step certificate create "etcd-server-${n}" \
      $out/etcd-server-${n}.crt $out/etcd-server-${n}.key \
      --profile leaf --ca $out/etcd-ca.crt --ca-key $out/etcd-ca.key \
      --no-password --insecure --not-after=${leafNotAfter} \
      ${mkSans etcdSans}
    step certificate create "etcd-peer-${n}" \
      $out/etcd-peer-${n}.crt $out/etcd-peer-${n}.key \
      --profile leaf --ca $out/etcd-ca.crt --ca-key $out/etcd-ca.key \
      --no-password --insecure --not-after=${leafNotAfter} \
      ${mkSans etcdSans}

    # kubelet for ${n} (O=system:nodes via openssl)
    openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
      -nodes -keyout $out/kubelet-${n}.key \
      -subj "/CN=system:node:${hostname}/O=system:nodes" \
      -addext "subjectAltName=DNS:${hostname},IP:${constants.network.ipv4.${n}},IP:${constants.network.ipv6.${n}}" \
      2>/dev/null | \
    openssl x509 -req -CA $out/ca.crt -CAkey $out/ca.key \
      -CAcreateserial -days 365 -copy_extensions copyall \
      -out $out/kubelet-${n}.crt 2>/dev/null
    '') constants.nodeNames)}

    # Controller Manager
    step certificate create "system:kube-controller-manager" \
      $out/controller-manager.crt $out/controller-manager.key \
      --profile leaf --ca $out/ca.crt --ca-key $out/ca.key \
      --no-password --insecure --not-after=${leafNotAfter} --san "system:kube-controller-manager"

    # Scheduler
    step certificate create "system:kube-scheduler" \
      $out/scheduler.crt $out/scheduler.key \
      --profile leaf --ca $out/ca.crt --ca-key $out/ca.key \
      --no-password --insecure --not-after=${leafNotAfter} --san "system:kube-scheduler"

    # Admin (O=system:masters)
    openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
      -nodes -keyout $out/admin.key \
      -subj "/CN=kubernetes-admin/O=system:masters" 2>/dev/null | \
    openssl x509 -req -CA $out/ca.crt -CAkey $out/ca.key \
      -CAcreateserial -days 365 -out $out/admin.crt 2>/dev/null
  '';

  # ─── Per-node PKI bundle ──────────────────────────────────────────────
  # Assembles the subset of certs + kubeconfigs needed by a specific node.
  # This is what gets mounted into the VM.
  mkNodePki = { nodeName, role }:
    let
      hostname = constants.getHostname nodeName;
      isControlPlane = role == "control-plane";
      pki = constants.k8s.pkiDir;

      mkKubeconfig = { user, certFile, keyFile }: pkgs.writeText "${user}-kubeconfig" ''
        apiVersion: v1
        kind: Config
        clusters:
        - cluster:
            certificate-authority: ${pki}/ca.crt
            server: https://${constants.network.gateway4}:6443
          name: kubernetes
        contexts:
        - context:
            cluster: kubernetes
            user: ${user}
          name: ${user}@kubernetes
        current-context: ${user}@kubernetes
        users:
        - name: ${user}
          user:
            client-certificate: ${pki}/${certFile}
            client-key: ${pki}/${keyFile}
      '';

      kubeletConfig = pkgs.writeText "kubelet-config.yaml" ''
        apiVersion: kubelet.config.k8s.io/v1beta1
        kind: KubeletConfiguration
        authentication:
          anonymous:
            enabled: false
          webhook:
            enabled: true
          x509:
            clientCAFile: ${pki}/ca.crt
        authorization:
          mode: Webhook
        clusterDNS:
        - ${constants.k8s.dnsServiceIp}
        clusterDomain: ${constants.k8s.clusterDomain}
        cgroupDriver: systemd
        containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
      '';

      kubeletKubeconfig = mkKubeconfig {
        user = "system:node:${hostname}";
        certFile = "kubelet.crt";
        keyFile = "kubelet.key";
      };

      controllerManagerKubeconfig = mkKubeconfig {
        user = "system:kube-controller-manager";
        certFile = "controller-manager.crt";
        keyFile = "controller-manager.key";
      };

      schedulerKubeconfig = mkKubeconfig {
        user = "system:kube-scheduler";
        certFile = "scheduler.crt";
        keyFile = "scheduler.key";
      };

      adminKubeconfig = mkKubeconfig {
        user = "kubernetes-admin";
        certFile = "admin.crt";
        keyFile = "admin.key";
      };
    in
    pkgs.runCommand "k8s-pki-${nodeName}" {} (''
      mkdir -p $out

      # Common certs (all nodes)
      cp ${pkiStore}/ca.crt ${pkiStore}/ca.key $out/
      cp ${pkiStore}/etcd-ca.crt $out/
      cp ${pkiStore}/front-proxy-ca.crt $out/
      cp ${pkiStore}/sa.pub ${pkiStore}/sa.key $out/
      cp ${pkiStore}/kubelet-${nodeName}.crt $out/kubelet.crt
      cp ${pkiStore}/kubelet-${nodeName}.key $out/kubelet.key

      # Kubeconfigs
      cp ${kubeletKubeconfig} $out/kubelet-kubeconfig
      cp ${kubeletConfig} $out/kubelet-config.yaml
    '' + lib.optionalString isControlPlane ''

      # Control plane certs
      cp ${pkiStore}/apiserver.crt ${pkiStore}/apiserver.key $out/
      cp ${pkiStore}/apiserver-kubelet-client.crt ${pkiStore}/apiserver-kubelet-client.key $out/
      cp ${pkiStore}/apiserver-etcd-client.crt ${pkiStore}/apiserver-etcd-client.key $out/
      cp ${pkiStore}/front-proxy-ca.key $out/
      cp ${pkiStore}/front-proxy-client.crt ${pkiStore}/front-proxy-client.key $out/
      cp ${pkiStore}/etcd-ca.key $out/
      cp ${pkiStore}/etcd-server-${nodeName}.crt $out/etcd-server.crt
      cp ${pkiStore}/etcd-server-${nodeName}.key $out/etcd-server.key
      cp ${pkiStore}/etcd-peer-${nodeName}.crt $out/etcd-peer.crt
      cp ${pkiStore}/etcd-peer-${nodeName}.key $out/etcd-peer.key
      cp ${pkiStore}/controller-manager.crt ${pkiStore}/controller-manager.key $out/
      cp ${pkiStore}/scheduler.crt ${pkiStore}/scheduler.key $out/
      cp ${pkiStore}/admin.crt ${pkiStore}/admin.key $out/

      # Control plane kubeconfigs
      cp ${controllerManagerKubeconfig} $out/controller-manager-kubeconfig
      cp ${schedulerKubeconfig} $out/scheduler-kubeconfig
      cp ${adminKubeconfig} $out/admin-kubeconfig
    '');

  # ─── Runtime script (kept for manual use) ──────────────────────────
  genCerts = pkgs.writeShellApplication {
    name = "k8s-gen-certs";
    runtimeInputs = with pkgs; [ step-cli coreutils openssl ];
    text = ''
      echo "=== K8s Certificate Generation ==="
      echo "Copying build-time certs to ./certs/"
      mkdir -p ./certs
      cp -v ${pkiStore}/* ./certs/
      chmod -R u+w ./certs/
      echo ""
      echo "=== Done: $(ls ./certs/ | wc -l) files ==="
    '';
  };
in
{
  inherit pkiStore mkNodePki genCerts;
}
