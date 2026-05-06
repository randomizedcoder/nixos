# nix/cert-inject.nix
#
# Certificate injection into K8s MicroVMs via virtio console.
# Uses expect scripts for reliable transfer with md5sum verification.
#
{ pkgs }:
let
  constants = import ./constants.nix;
  nodes = (import ./nodes.nix { inherit constants; }).definitions;

  certDir = constants.k8s.certDir;
  pki = constants.k8s.pkiDir;

  # Generate kubeconfig content for a component
  mkKubeconfig = { name, certFile, keyFile, server ? "https://${constants.network.gateway4}:6443" }: ''
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: ${pki}/ca.crt
    server: ${server}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: ${name}
  name: ${name}@kubernetes
current-context: ${name}@kubernetes
users:
- name: ${name}
  user:
    client-certificate: ${pki}/${certFile}
    client-key: ${pki}/${keyFile}
'';

  # Kubelet config YAML
  mkKubeletConfig = nodeName: ''
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

  vmCertInjectExp = ./lifecycle/scripts/vm-cert-inject.exp;
in
{
  injectCerts = pkgs.writeShellApplication {
    name = "k8s-inject-certs";
    runtimeInputs = with pkgs; [ expect socat coreutils openssl ];
    text = ''
      set -euo pipefail

      CERT_DIR="${certDir}"
      echo "=== K8s Certificate Injection ==="

      if [[ ! -d "$CERT_DIR" ]]; then
        echo "ERROR: Certificate directory not found: $CERT_DIR"
        echo "  Run: nix run .#k8s-gen-certs"
        exit 1
      fi

      inject_to_node() {
        local node="$1"
        local virtio_port="$2"
        local role="$3"
        local node_hostname="$4"

        echo ""
        echo "--- Injecting certs to $node ($node_hostname, port $virtio_port) ---"

        # Common certs for all nodes
        local files_to_inject=(
          "$CERT_DIR/ca.crt:${pki}/ca.crt:0644"
          "$CERT_DIR/ca.key:${pki}/ca.key:0600"
          "$CERT_DIR/etcd-ca.crt:${pki}/etcd-ca.crt:0644"
          "$CERT_DIR/front-proxy-ca.crt:${pki}/front-proxy-ca.crt:0644"
          "$CERT_DIR/sa.pub:${pki}/sa.pub:0644"
          "$CERT_DIR/sa.key:${pki}/sa.key:0600"
          "$CERT_DIR/kubelet-$node.crt:${pki}/kubelet.crt:0644"
          "$CERT_DIR/kubelet-$node.key:${pki}/kubelet.key:0600"
        )

        # Control plane gets additional certs
        if [[ "$role" == "control-plane" ]]; then
          files_to_inject+=(
            "$CERT_DIR/apiserver.crt:${pki}/apiserver.crt:0644"
            "$CERT_DIR/apiserver.key:${pki}/apiserver.key:0600"
            "$CERT_DIR/apiserver-kubelet-client.crt:${pki}/apiserver-kubelet-client.crt:0644"
            "$CERT_DIR/apiserver-kubelet-client.key:${pki}/apiserver-kubelet-client.key:0600"
            "$CERT_DIR/apiserver-etcd-client.crt:${pki}/apiserver-etcd-client.crt:0644"
            "$CERT_DIR/apiserver-etcd-client.key:${pki}/apiserver-etcd-client.key:0600"
            "$CERT_DIR/front-proxy-client.crt:${pki}/front-proxy-client.crt:0644"
            "$CERT_DIR/front-proxy-client.key:${pki}/front-proxy-client.key:0600"
            "$CERT_DIR/etcd-server-$node.crt:${pki}/etcd-server.crt:0644"
            "$CERT_DIR/etcd-server-$node.key:${pki}/etcd-server.key:0600"
            "$CERT_DIR/etcd-peer-$node.crt:${pki}/etcd-peer.crt:0644"
            "$CERT_DIR/etcd-peer-$node.key:${pki}/etcd-peer.key:0600"
            "$CERT_DIR/controller-manager.crt:${pki}/controller-manager.crt:0644"
            "$CERT_DIR/controller-manager.key:${pki}/controller-manager.key:0600"
            "$CERT_DIR/scheduler.crt:${pki}/scheduler.crt:0644"
            "$CERT_DIR/scheduler.key:${pki}/scheduler.key:0600"
            "$CERT_DIR/admin.crt:${pki}/admin.crt:0644"
            "$CERT_DIR/admin.key:${pki}/admin.key:0600"
          )
        fi

        # Call expect script with each file as a separate argument
        expect ${vmCertInjectExp} \
          "$virtio_port" \
          "${constants.ssh.password}" \
          "$node_hostname" \
          "''${files_to_inject[@]}"

        # Generate and inject kubeconfigs
        echo "  Injecting kubeconfigs..."

        # Kubelet kubeconfig
        local kubelet_kc
        kubelet_kc=$(mktemp)
        cat > "$kubelet_kc" << 'KUBECFG'
      ${mkKubeconfig { name = "system:node:HOSTNAME_PLACEHOLDER"; certFile = "kubelet.crt"; keyFile = "kubelet.key"; }}
      KUBECFG
        sed -i "s/HOSTNAME_PLACEHOLDER/$node_hostname/g" "$kubelet_kc"

        expect ${vmCertInjectExp} \
          "$virtio_port" \
          "${constants.ssh.password}" \
          "$node_hostname" \
          "$kubelet_kc:${pki}/kubelet-kubeconfig:0600"
        rm -f "$kubelet_kc"

        # Kubelet config
        local kubelet_cfg
        kubelet_cfg=$(mktemp)
        cat > "$kubelet_cfg" << 'KUBELETCFG'
      ${mkKubeletConfig "PLACEHOLDER"}
      KUBELETCFG

        expect ${vmCertInjectExp} \
          "$virtio_port" \
          "${constants.ssh.password}" \
          "$node_hostname" \
          "$kubelet_cfg:${pki}/kubelet-config.yaml:0644"
        rm -f "$kubelet_cfg"

        if [[ "$role" == "control-plane" ]]; then
          # Controller Manager kubeconfig
          local cm_kc
          cm_kc=$(mktemp)
          cat > "$cm_kc" << 'CMKC'
      ${mkKubeconfig { name = "system:kube-controller-manager"; certFile = "controller-manager.crt"; keyFile = "controller-manager.key"; }}
      CMKC

          expect ${vmCertInjectExp} \
            "$virtio_port" \
            "${constants.ssh.password}" \
            "$node_hostname" \
            "$cm_kc:${pki}/controller-manager-kubeconfig:0600"
          rm -f "$cm_kc"

          # Scheduler kubeconfig
          local sched_kc
          sched_kc=$(mktemp)
          cat > "$sched_kc" << 'SCHEDKC'
      ${mkKubeconfig { name = "system:kube-scheduler"; certFile = "scheduler.crt"; keyFile = "scheduler.key"; }}
      SCHEDKC

          expect ${vmCertInjectExp} \
            "$virtio_port" \
            "${constants.ssh.password}" \
            "$node_hostname" \
            "$sched_kc:${pki}/scheduler-kubeconfig:0600"
          rm -f "$sched_kc"
        fi

        # Restart services
        echo "  Restarting services on $node..."
        expect ${vmCertInjectExp} \
          "$virtio_port" \
          "${constants.ssh.password}" \
          "$node_hostname" \
          "__CMD__:systemctl restart kubelet"

        if [[ "$role" == "control-plane" ]]; then
          expect ${vmCertInjectExp} \
            "$virtio_port" \
            "${constants.ssh.password}" \
            "$node_hostname" \
            "__CMD__:systemctl restart etcd"
        fi

        echo "  $node: done"
      }

      # Inject to all nodes
      ${builtins.concatStringsSep "\n" (builtins.map (n: let
        def = nodes.${n};
        consolePorts = constants.getConsolePorts n;
        hostname = constants.getHostname n;
      in ''
      inject_to_node "${n}" "${toString consolePorts.virtio}" "${def.role}" "${hostname}"
      '') constants.nodeNames)}

      echo ""
      echo "=== Certificate injection complete ==="
    '';
  };
}
