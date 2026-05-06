# nix/gitops/env/tidb.nix
#
# TiDB distributed SQL database — HA deployment.
#
# Components:
#   PD (Placement Driver) x3 — Raft-based metadata/scheduling (quorum)
#   TiKV x3                  — Distributed KV storage (3-way replication)
#   TiDB x2                  — Stateless MySQL-compatible SQL layer
#
# All components use hard pod anti-affinity to spread across K8s nodes.
# Any single node failure keeps the database fully available.
#
{ pkgs, lib }:
let
  # TiDB version — all components must match
  version = "v8.5.0";

  # Headless service domain suffix
  ns = "tidb";
  domain = "svc.cluster.local";

  # PD peer URLs for initial cluster bootstrap
  pdPeers = lib.concatStringsSep ","
    (builtins.map (i: "pd-${toString i}=http://pd-${toString i}.pd-headless.${ns}.${domain}:2380")
      [ 0 1 2 ]);

  # PD client endpoints for TiKV and TiDB
  pdEndpoints = lib.concatStringsSep ","
    (builtins.map (i: "pd-${toString i}.pd-headless.${ns}.${domain}:2379")
      [ 0 1 2 ]);
in
{
  manifests = [
    # ─── PD ConfigMap ──────────────────────────────────────────────────
    {
      name = "tidb/configmap-pd.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: v1"
        "kind: ConfigMap"
        "metadata:"
        "  name: pd-config"
        "  namespace: ${ns}"
        "data:"
        "  start-pd.sh: |"
        "    #!/bin/sh"
        "    set -e"
        "    HOSTNAME=$(hostname)"
        "    exec /pd-server \\"
        "      --name=\${HOSTNAME} \\"
        "      --data-dir=/data/pd \\"
        "      --client-urls=http://0.0.0.0:2379 \\"
        "      --peer-urls=http://0.0.0.0:2380 \\"
        "      --advertise-client-urls=http://\${HOSTNAME}.pd-headless.${ns}.${domain}:2379 \\"
        "      --advertise-peer-urls=http://\${HOSTNAME}.pd-headless.${ns}.${domain}:2380 \\"
        "      --initial-cluster=${pdPeers}"
      ];
    }

    # ─── TiKV ConfigMap ────────────────────────────────────────────────
    {
      name = "tidb/configmap-tikv.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: v1"
        "kind: ConfigMap"
        "metadata:"
        "  name: tikv-config"
        "  namespace: ${ns}"
        "data:"
        "  start-tikv.sh: |"
        "    #!/bin/sh"
        "    set -e"
        "    HOSTNAME=$(hostname)"
        "    exec /tikv-server \\"
        "      --pd=${pdEndpoints} \\"
        "      --addr=0.0.0.0:20160 \\"
        "      --advertise-addr=\${HOSTNAME}.tikv-headless.${ns}.${domain}:20160 \\"
        "      --status-addr=0.0.0.0:20180 \\"
        "      --data-dir=/data/tikv"
      ];
    }

    # ─── TiDB ConfigMap ────────────────────────────────────────────────
    {
      name = "tidb/configmap-tidb.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: v1"
        "kind: ConfigMap"
        "metadata:"
        "  name: tidb-config"
        "  namespace: ${ns}"
        "data:"
        "  start-tidb.sh: |"
        "    #!/bin/sh"
        "    set -e"
        "    HOSTNAME=$(hostname)"
        "    exec /tidb-server \\"
        "      --store=tikv \\"
        "      --path=${pdEndpoints} \\"
        "      --advertise-address=\${HOSTNAME}.tidb-headless.${ns}.${domain}"
      ];
    }

    # ─── PD Headless Service ───────────────────────────────────────────
    {
      name = "tidb/service-pd-headless.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: v1"
        "kind: Service"
        "metadata:"
        "  name: pd-headless"
        "  namespace: ${ns}"
        "spec:"
        "  clusterIP: None"
        "  selector:"
        "    app: pd"
        "  ports:"
        "  - name: client"
        "    port: 2379"
        "    targetPort: 2379"
        "  - name: peer"
        "    port: 2380"
        "    targetPort: 2380"
      ];
    }

    # ─── PD Client Service ─────────────────────────────────────────────
    {
      name = "tidb/service-pd.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: v1"
        "kind: Service"
        "metadata:"
        "  name: pd"
        "  namespace: ${ns}"
        "spec:"
        "  selector:"
        "    app: pd"
        "  ports:"
        "  - name: client"
        "    port: 2379"
        "    targetPort: 2379"
      ];
    }

    # ─── TiKV Headless Service ─────────────────────────────────────────
    {
      name = "tidb/service-tikv-headless.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: v1"
        "kind: Service"
        "metadata:"
        "  name: tikv-headless"
        "  namespace: ${ns}"
        "spec:"
        "  clusterIP: None"
        "  selector:"
        "    app: tikv"
        "  ports:"
        "  - name: grpc"
        "    port: 20160"
        "    targetPort: 20160"
        "  - name: status"
        "    port: 20180"
        "    targetPort: 20180"
      ];
    }

    # ─── TiDB Headless Service ─────────────────────────────────────────
    {
      name = "tidb/service-tidb-headless.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: v1"
        "kind: Service"
        "metadata:"
        "  name: tidb-headless"
        "  namespace: ${ns}"
        "spec:"
        "  clusterIP: None"
        "  selector:"
        "    app: tidb-server"
        "  ports:"
        "  - name: mysql"
        "    port: 4000"
        "    targetPort: 4000"
        "  - name: status"
        "    port: 10080"
        "    targetPort: 10080"
      ];
    }

    # ─── TiDB Client Service ──────────────────────────────────────────
    {
      name = "tidb/service-tidb.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: v1"
        "kind: Service"
        "metadata:"
        "  name: tidb"
        "  namespace: ${ns}"
        "spec:"
        "  selector:"
        "    app: tidb-server"
        "  ports:"
        "  - name: mysql"
        "    port: 4000"
        "    targetPort: 4000"
        "  type: NodePort"
      ];
    }

    # ─── PD StatefulSet ────────────────────────────────────────────────
    {
      name = "tidb/statefulset-pd.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: apps/v1"
        "kind: StatefulSet"
        "metadata:"
        "  name: pd"
        "  namespace: ${ns}"
        "spec:"
        "  serviceName: pd-headless"
        "  replicas: 3"
        "  selector:"
        "    matchLabels:"
        "      app: pd"
        "  template:"
        "    metadata:"
        "      labels:"
        "        app: pd"
        "    spec:"
        "      affinity:"
        "        podAntiAffinity:"
        "          requiredDuringSchedulingIgnoredDuringExecution:"
        "          - labelSelector:"
        "              matchLabels:"
        "                app: pd"
        "            topologyKey: kubernetes.io/hostname"
        "      containers:"
        "      - name: pd"
        "        image: pingcap/pd:${version}"
        "        command: [\"/bin/sh\", \"/config/start-pd.sh\"]"
        "        ports:"
        "        - containerPort: 2379"
        "          name: client"
        "        - containerPort: 2380"
        "          name: peer"
        "        volumeMounts:"
        "        - name: config"
        "          mountPath: /config"
        "        - name: data"
        "          mountPath: /data/pd"
        "        resources:"
        "          requests:"
        "            cpu: 100m"
        "            memory: 256Mi"
        "          limits:"
        "            cpu: 500m"
        "            memory: 512Mi"
        "      volumes:"
        "      - name: config"
        "        configMap:"
        "          name: pd-config"
        "          defaultMode: 0755"
        "      - name: data"
        "        emptyDir: {}"
      ];
    }

    # ─── TiKV StatefulSet ──────────────────────────────────────────────
    {
      name = "tidb/statefulset-tikv.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: apps/v1"
        "kind: StatefulSet"
        "metadata:"
        "  name: tikv"
        "  namespace: ${ns}"
        "spec:"
        "  serviceName: tikv-headless"
        "  replicas: 3"
        "  selector:"
        "    matchLabels:"
        "      app: tikv"
        "  template:"
        "    metadata:"
        "      labels:"
        "        app: tikv"
        "    spec:"
        "      affinity:"
        "        podAntiAffinity:"
        "          requiredDuringSchedulingIgnoredDuringExecution:"
        "          - labelSelector:"
        "              matchLabels:"
        "                app: tikv"
        "            topologyKey: kubernetes.io/hostname"
        "      initContainers:"
        "      - name: wait-for-pd"
        "        image: busybox:1.36"
        "        command: ['sh', '-c', 'until wget -qO- http://pd-0.pd-headless.${ns}.${domain}:2379/pd/api/v1/health 2>/dev/null; do echo waiting for PD; sleep 2; done']"
        "      containers:"
        "      - name: tikv"
        "        image: pingcap/tikv:${version}"
        "        command: [\"/bin/sh\", \"/config/start-tikv.sh\"]"
        "        ports:"
        "        - containerPort: 20160"
        "          name: grpc"
        "        - containerPort: 20180"
        "          name: status"
        "        volumeMounts:"
        "        - name: config"
        "          mountPath: /config"
        "        - name: data"
        "          mountPath: /data/tikv"
        "        resources:"
        "          requests:"
        "            cpu: 200m"
        "            memory: 512Mi"
        "          limits:"
        "            cpu: '1'"
        "            memory: 1536Mi"
        "      volumes:"
        "      - name: config"
        "        configMap:"
        "          name: tikv-config"
        "          defaultMode: 0755"
        "      - name: data"
        "        emptyDir: {}"
      ];
    }

    # ─── TiDB StatefulSet ─────────────────────────────────────────────
    {
      name = "tidb/statefulset-tidb.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: apps/v1"
        "kind: StatefulSet"
        "metadata:"
        "  name: tidb"
        "  namespace: ${ns}"
        "spec:"
        "  serviceName: tidb-headless"
        "  replicas: 2"
        "  selector:"
        "    matchLabels:"
        "      app: tidb-server"
        "  template:"
        "    metadata:"
        "      labels:"
        "        app: tidb-server"
        "    spec:"
        "      affinity:"
        "        podAntiAffinity:"
        "          requiredDuringSchedulingIgnoredDuringExecution:"
        "          - labelSelector:"
        "              matchLabels:"
        "                app: tidb-server"
        "            topologyKey: kubernetes.io/hostname"
        "      initContainers:"
        "      - name: wait-for-pd"
        "        image: busybox:1.36"
        "        command: ['sh', '-c', 'until wget -qO- http://pd-0.pd-headless.${ns}.${domain}:2379/pd/api/v1/health 2>/dev/null; do echo waiting for PD; sleep 2; done']"
        "      containers:"
        "      - name: tidb"
        "        image: pingcap/tidb:${version}"
        "        command: [\"/bin/sh\", \"/config/start-tidb.sh\"]"
        "        ports:"
        "        - containerPort: 4000"
        "          name: mysql"
        "        - containerPort: 10080"
        "          name: status"
        "        volumeMounts:"
        "        - name: config"
        "          mountPath: /config"
        "        resources:"
        "          requests:"
        "            cpu: 200m"
        "            memory: 256Mi"
        "          limits:"
        "            cpu: '1'"
        "            memory: 512Mi"
        "      volumes:"
        "      - name: config"
        "        configMap:"
        "          name: tidb-config"
        "          defaultMode: 0755"
      ];
    }

    # ─── Sysbench Benchmark Job ────────────────────────────────────────
    {
      name = "tidb/job-bench.yaml";
      content = builtins.concatStringsSep "\n" [
        "apiVersion: batch/v1"
        "kind: Job"
        "metadata:"
        "  name: tidb-sysbench"
        "  namespace: ${ns}"
        "spec:"
        "  backoffLimit: 2"
        "  template:"
        "    metadata:"
        "      labels:"
        "        app: tidb-bench"
        "    spec:"
        "      restartPolicy: Never"
        "      initContainers:"
        "      - name: wait-for-tidb"
        "        image: busybox:1.36"
        "        command: ['sh', '-c', 'until wget -qO- http://tidb.${ns}.${domain}:10080/status 2>/dev/null; do echo waiting for TiDB; sleep 5; done']"
        "      containers:"
        "      - name: sysbench"
        "        image: severalnines/sysbench:latest"
        "        command: [\"/bin/sh\", \"-c\"]"
        "        args:"
        "        - |"
        "          set -e"
        "          TIDB_HOST=tidb.${ns}.${domain}"
        "          TIDB_PORT=4000"
        "          echo '=== Creating test database ==='"
        "          mysql -h $TIDB_HOST -P $TIDB_PORT -u root -e 'CREATE DATABASE IF NOT EXISTS sbtest;'"
        "          echo ''"
        "          echo '=== Preparing sysbench data (4 tables x 10K rows) ==='"
        "          sysbench oltp_read_write --mysql-host=$TIDB_HOST --mysql-port=$TIDB_PORT --mysql-user=root --mysql-db=sbtest --tables=4 --table-size=10000 --threads=4 prepare"
        "          echo ''"
        "          echo '=== Running OLTP read/write benchmark (60s) ==='"
        "          sysbench oltp_read_write --mysql-host=$TIDB_HOST --mysql-port=$TIDB_PORT --mysql-user=root --mysql-db=sbtest --tables=4 --table-size=10000 --threads=4 --time=60 --report-interval=10 run"
        "          echo ''"
        "          echo '=== Cleanup ==='"
        "          sysbench oltp_read_write --mysql-host=$TIDB_HOST --mysql-port=$TIDB_PORT --mysql-user=root --mysql-db=sbtest --tables=4 cleanup"
        "          echo ''"
        "          echo '=== Benchmark complete ==='"
        "        resources:"
        "          requests:"
        "            cpu: 100m"
        "            memory: 128Mi"
      ];
    }
  ];
}
