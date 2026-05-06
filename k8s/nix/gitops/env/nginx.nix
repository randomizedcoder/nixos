# nix/gitops/env/nginx.nix
#
# Nginx Deployment + Service + ConfigMap (hello world).
#
{ pkgs, lib }:
{
  manifests = [
    {
      name = "nginx/configmap.yaml";
      content = ''
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: nginx-config
          namespace: nginx
        data:
          index.html: |
            <!DOCTYPE html>
            <html>
            <head><title>K8s MicroVM Cluster</title></head>
            <body>
              <h1>Hello from K8s MicroVM Cluster!</h1>
              <p>This page is served by nginx running on a NixOS MicroVM Kubernetes cluster.</p>
            </body>
            </html>
      '';
    }
    {
      name = "nginx/deployment.yaml";
      content = ''
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: nginx
          namespace: nginx
        spec:
          replicas: 1
          selector:
            matchLabels:
              app: nginx
          template:
            metadata:
              labels:
                app: nginx
            spec:
              containers:
              - name: nginx
                image: nginx:1.27-alpine
                ports:
                - containerPort: 80
                volumeMounts:
                - name: config
                  mountPath: /usr/share/nginx/html/index.html
                  subPath: index.html
                resources:
                  requests:
                    cpu: 50m
                    memory: 32Mi
              volumes:
              - name: config
                configMap:
                  name: nginx-config
      '';
    }
    {
      name = "nginx/service.yaml";
      content = ''
        apiVersion: v1
        kind: Service
        metadata:
          name: nginx
          namespace: nginx
        spec:
          selector:
            app: nginx
          ports:
          - port: 80
            targetPort: 80
          type: NodePort
      '';
    }
  ];
}
