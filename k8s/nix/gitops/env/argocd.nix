# nix/gitops/env/argocd.nix
#
# ArgoCD Helm chart values + self-managing Application CR.
#
{ pkgs, lib }:
{
  manifests = [
    {
      name = "argocd/values.yaml";
      content = ''
        # ArgoCD Helm chart values
        # Install via: helm install argocd argo/argo-cd -n argocd -f values.yaml
        server:
          service:
            type: NodePort
            nodePortHttps: 30443
        configs:
          params:
            server.insecure: true
        controller:
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
        redis:
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
      '';
    }
    {
      name = "argocd/application-self.yaml";
      content = ''
        apiVersion: argoproj.io/v1alpha1
        kind: Application
        metadata:
          name: argocd
          namespace: argocd
        spec:
          project: default
          source:
            repoURL: https://argoproj.github.io/argo-helm
            chart: argo-cd
            targetRevision: "7.*"
            helm:
              valueFiles:
              - values.yaml
          destination:
            server: https://kubernetes.default.svc
            namespace: argocd
          syncPolicy:
            automated:
              prune: true
              selfHeal: true
      '';
    }
  ];
}
