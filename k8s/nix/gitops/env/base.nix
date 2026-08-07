# nix/gitops/env/base.nix
#
# Base cluster configuration: namespaces, RBAC.
#
{ pkgs, lib }:
{
  manifests = [
    {
      name = "base/namespaces.yaml";
      content = ''
        apiVersion: v1
        kind: Namespace
        metadata:
          name: argocd
        ---
        apiVersion: v1
        kind: Namespace
        metadata:
          name: kube-system
        ---
        apiVersion: v1
        kind: Namespace
        metadata:
          name: clickhouse
        ---
        apiVersion: v1
        kind: Namespace
        metadata:
          name: nginx
        ---
        apiVersion: v1
        kind: Namespace
        metadata:
          name: tidb
      '';
    }
    {
      name = "base/rbac.yaml";
      content = ''
        apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRoleBinding
        metadata:
          name: system:kube-apiserver
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: system:kube-apiserver-to-kubelet
        subjects:
        - apiGroup: rbac.authorization.k8s.io
          kind: User
          name: kube-apiserver
        ---
        apiVersion: rbac.authorization.k8s.io/v1
        kind: ClusterRole
        metadata:
          name: system:kube-apiserver-to-kubelet
        rules:
        - apiGroups: [""]
          resources: ["nodes/proxy", "nodes/stats", "nodes/log", "nodes/spec", "nodes/metrics"]
          verbs: ["*"]
      '';
    }
  ];
}
