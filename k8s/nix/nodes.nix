# nix/nodes.nix
#
# Node definitions for the K8s cluster.
# 3 control planes + 1 worker (HA configuration).
#
{ constants }:
rec {
  definitions = {
    cp0 = {
      role = "control-plane";
      nodeIndex = 0;
      description = "Control plane 0 (etcd, apiserver, controller-manager, scheduler)";
      services = [
        "etcd" "kube-apiserver" "kube-controller-manager" "kube-scheduler"
        "containerd" "kubelet"
      ];
    };

    cp1 = {
      role = "control-plane";
      nodeIndex = 1;
      description = "Control plane 1 (etcd, apiserver, controller-manager, scheduler)";
      services = [
        "etcd" "kube-apiserver" "kube-controller-manager" "kube-scheduler"
        "containerd" "kubelet"
      ];
    };

    cp2 = {
      role = "control-plane";
      nodeIndex = 2;
      description = "Control plane 2 (etcd, apiserver, controller-manager, scheduler)";
      services = [
        "etcd" "kube-apiserver" "kube-controller-manager" "kube-scheduler"
        "containerd" "kubelet"
      ];
    };

    w3 = {
      role = "worker";
      nodeIndex = 3;
      description = "Worker node";
      services = [ "containerd" "kubelet" ];
    };
  };

  nodeNames = builtins.attrNames definitions;
}
