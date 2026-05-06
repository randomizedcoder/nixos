# nix/lifecycle/constants.nix
#
# Lifecycle testing configuration for K8s MicroVMs.
# Per-node service checks, health checks, and timeouts.
#
{ }:
let
  mainConstants = import ../constants.nix;
  nodes = (import ../nodes.nix { constants = mainConstants; }).definitions;
in
rec {
  inherit (mainConstants)
    network console k8s
    getConsolePorts getHostname getProcessName getTimeout
    lifecycle;

  # Per-node definitions for lifecycle testing
  nodeConfigs = {
    # Per-node tests only check services that work in isolation.
    # kubelet, etcd, apiserver, controller-manager, scheduler all require
    # the cluster (apiserver or etcd quorum) and are tested at cluster level.
    # Only containerd works standalone.
    cp0 = {
      description = nodes.cp0.description;
      role = "control-plane";
      services = [ "containerd" ];
      healthChecks = [];
    };

    cp1 = {
      description = nodes.cp1.description;
      role = "control-plane";
      services = [ "containerd" ];
      healthChecks = [];
    };

    cp2 = {
      description = nodes.cp2.description;
      role = "control-plane";
      services = [ "containerd" ];
      healthChecks = [];
    };

    w3 = {
      description = nodes.w3.description;
      role = "worker";
      services = [ "containerd" ];
      healthChecks = [];
    };
  };

  phases = {
    "0"  = { name = "Build VM"; };
    "1"  = { name = "Start VM"; };
    "2"  = { name = "Serial Console"; };
    "2b" = { name = "Virtio Console"; };
    "3"  = { name = "SSH Ready"; };
    "4"  = { name = "Cert Verify"; };
    "5"  = { name = "Services Ready"; };
    "6"  = { name = "K8s Health"; };
    "7"  = { name = "Shutdown"; };
    "8"  = { name = "Wait Exit"; };
  };

  clusterPhases = {
    "C0" = { name = "Build All VMs"; };
    "C1" = { name = "Start All VMs"; };
    "C2" = { name = "SSH Ready"; };
    "C3" = { name = "Etcd Quorum"; };
    "C4" = { name = "API Server Health"; };
    "C5" = { name = "Node Registration"; };
    "C6" = { name = "Shutdown All"; };
  };

  expect = {
    loginPrompt = "login:";
    shellPromptPattern = "root@k8s-.*:.*#";
    username = "root";
    password = mainConstants.ssh.password;
    defaultTimeout = 30;
  };
}
