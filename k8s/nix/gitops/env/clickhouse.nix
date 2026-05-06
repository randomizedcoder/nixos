# nix/gitops/env/clickhouse.nix
#
# ClickHouse StatefulSet + Services + ConfigMap.
#
{ pkgs, lib }:
{
  manifests = [
    {
      name = "clickhouse/configmap.yaml";
      content = ''
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: clickhouse-config
          namespace: clickhouse
        data:
          config.xml: |
            <clickhouse>
              <logger>
                <level>information</level>
                <console>1</console>
              </logger>
              <listen_host>0.0.0.0</listen_host>
              <http_port>8123</http_port>
              <tcp_port>9000</tcp_port>
              <interserver_http_port>9009</interserver_http_port>
              <remote_servers>
                <default>
                  <shard>
                    <replica>
                      <host>clickhouse-0.clickhouse-headless.clickhouse.svc.cluster.local</host>
                      <port>9000</port>
                    </replica>
                  </shard>
                </default>
              </remote_servers>
            </clickhouse>
      '';
    }
    {
      name = "clickhouse/service-headless.yaml";
      content = ''
        apiVersion: v1
        kind: Service
        metadata:
          name: clickhouse-headless
          namespace: clickhouse
        spec:
          clusterIP: None
          selector:
            app: clickhouse
          ports:
          - name: http
            port: 8123
            targetPort: 8123
          - name: native
            port: 9000
            targetPort: 9000
          - name: interserver
            port: 9009
            targetPort: 9009
      '';
    }
    {
      name = "clickhouse/service.yaml";
      content = ''
        apiVersion: v1
        kind: Service
        metadata:
          name: clickhouse
          namespace: clickhouse
        spec:
          selector:
            app: clickhouse
          ports:
          - name: http
            port: 8123
            targetPort: 8123
          - name: native
            port: 9000
            targetPort: 9000
      '';
    }
    {
      name = "clickhouse/statefulset.yaml";
      content = ''
        apiVersion: apps/v1
        kind: StatefulSet
        metadata:
          name: clickhouse
          namespace: clickhouse
        spec:
          serviceName: clickhouse-headless
          replicas: 1
          selector:
            matchLabels:
              app: clickhouse
          template:
            metadata:
              labels:
                app: clickhouse
            spec:
              containers:
              - name: clickhouse
                image: clickhouse/clickhouse-server:24.3
                ports:
                - containerPort: 8123
                  name: http
                - containerPort: 9000
                  name: native
                - containerPort: 9009
                  name: interserver
                volumeMounts:
                - name: config
                  mountPath: /etc/clickhouse-server/config.d/cluster.xml
                  subPath: config.xml
                - name: data
                  mountPath: /var/lib/clickhouse
                resources:
                  requests:
                    cpu: 100m
                    memory: 256Mi
              volumes:
              - name: config
                configMap:
                  name: clickhouse-config
          volumeClaimTemplates:
          - metadata:
              name: data
            spec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 1Gi
      '';
    }
  ];
}
