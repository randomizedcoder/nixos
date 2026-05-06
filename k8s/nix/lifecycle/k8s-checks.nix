# nix/lifecycle/k8s-checks.nix
#
# K8s verification helpers for lifecycle testing.
# etcd health, apiserver /healthz, node readiness.
#
{ pkgs, lib }:
let
  mainConstants = import ../constants.nix;

  sshOpts = lib.concatStringsSep " " [
    "-o" "StrictHostKeyChecking=no"
    "-o" "UserKnownHostsFile=/dev/null"
    "-o" "ConnectTimeout=5"
    "-o" "LogLevel=ERROR"
    "-o" "PubkeyAuthentication=no"
  ];
in
{
  # Check if a service is active on a node via SSH
  mkCheckServiceScript = ''
    check_service() {
      local host="$1"
      local service="$2"
      sshpass -p ${mainConstants.ssh.password} ssh ${sshOpts} \
        "root@$host" "systemctl is-active $service" 2>/dev/null | grep -q "^active$"
    }

    wait_for_service() {
      local host="$1"
      local service="$2"
      local timeout="$3"
      local elapsed=0
      while [[ $elapsed -lt $timeout ]]; do
        local status
        status=$(sshpass -p ${mainConstants.ssh.password} ssh ${sshOpts} \
          "root@$host" "systemctl is-active $service" 2>/dev/null || echo "unknown")
        case "$status" in
          active) return 0 ;;
          failed) return 1 ;;
          *) sleep 1; elapsed=$((elapsed + 1)) ;;
        esac
      done
      return 1
    }
  '';

  # Check etcd health via SSH
  mkCheckEtcdScript = ''
    check_etcd_health() {
      local host="$1"
      sshpass -p ${mainConstants.ssh.password} ssh ${sshOpts} \
        "root@$host" "etcdctl --endpoints=https://127.0.0.1:2379 \
          --cacert=/var/lib/kubernetes/pki/etcd-ca.crt \
          --cert=/var/lib/kubernetes/pki/etcd-server.crt \
          --key=/var/lib/kubernetes/pki/etcd-server.key \
          endpoint health" 2>/dev/null | grep -q "is healthy"
    }
  '';

  # Check apiserver health via SSH
  mkCheckApiserverScript = ''
    check_apiserver_health() {
      local host="$1"
      sshpass -p ${mainConstants.ssh.password} ssh ${sshOpts} \
        "root@$host" "curl -sk https://127.0.0.1:6443/healthz" 2>/dev/null | grep -q "ok"
    }
  '';

  # Check etcd quorum (member count) via SSH
  mkCheckEtcdQuorumScript = ''
    check_etcd_quorum() {
      local host="$1"
      local expected="$2"
      local count
      count=$(sshpass -p ${mainConstants.ssh.password} ssh ${sshOpts} \
        "root@$host" "etcdctl --endpoints=https://127.0.0.1:2379 \
          --cacert=${mainConstants.k8s.pkiDir}/etcd-ca.crt \
          --cert=${mainConstants.k8s.pkiDir}/etcd-server.crt \
          --key=${mainConstants.k8s.pkiDir}/etcd-server.key \
          member list" 2>/dev/null | wc -l)
      [[ "$count" -ge "$expected" ]]
    }
  '';

  # Check all nodes Ready via kubectl
  mkCheckNodesReadyScript = ''
    check_nodes_ready() {
      local host="$1"
      local expected="$2"
      local count
      count=$(sshpass -p ${mainConstants.ssh.password} ssh ${sshOpts} \
        "root@$host" "kubectl --kubeconfig=${mainConstants.k8s.pkiDir}/admin-kubeconfig \
          get nodes --no-headers 2>/dev/null | grep -c ' Ready '" 2>/dev/null | tail -1)
      count="''${count:-0}"
      [[ "$count" -ge "$expected" ]]
    }
  '';

  # SSH helper
  mkSshHelper = ''
    ssh_cmd() {
      local host="$1"
      shift
      sshpass -p ${mainConstants.ssh.password} ssh ${sshOpts} \
        "root@$host" "$@" 2>/dev/null
    }

    wait_for_ssh() {
      local host="$1"
      local timeout="$2"
      local elapsed=0
      while [[ $elapsed -lt $timeout ]]; do
        if sshpass -p ${mainConstants.ssh.password} ssh ${sshOpts} \
          "root@$host" true 2>/dev/null; then
          return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
      done
      return 1
    }
  '';
}
