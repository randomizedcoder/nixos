# nix/lifecycle/default.nix
#
# Entry point for K8s MicroVM lifecycle testing.
# Generates per-node tests and a cluster-wide test-all.
#
{ pkgs, lib }:
let
  constants = import ./constants.nix { };
  mainConstants = import ../constants.nix;
  lifecycleLib = import ./lib.nix { inherit pkgs lib; };
  k8sChecks = import ./k8s-checks.nix { inherit pkgs lib; };

  inherit (lifecycleLib) colorHelpers timingHelpers processHelpers consoleHelpers;
  inherit (lifecycleLib) commonInputs sshInputs;

  nodeNames = mainConstants.nodeNames;

  # Generate a full lifecycle test for a node
  mkFullTest = nodeName:
    let
      nodeConfig = constants.nodeConfigs.${nodeName};
      hostname = mainConstants.getHostname nodeName;
      consolePorts = mainConstants.getConsolePorts nodeName;
      nodeIp = mainConstants.network.ipv4.${nodeName};

      buildTimeout = mainConstants.getTimeout nodeName "build";
      processTimeout = mainConstants.getTimeout nodeName "processStart";
      serialTimeout = mainConstants.getTimeout nodeName "serialReady";
      virtioTimeout = mainConstants.getTimeout nodeName "virtioReady";
      sshTimeout = mainConstants.getTimeout nodeName "sshReady";
      certInjectTimeout = mainConstants.getTimeout nodeName "certInject";
      serviceTimeout = mainConstants.getTimeout nodeName "serviceReady";
      k8sHealthTimeout = mainConstants.getTimeout nodeName "k8sHealth";
      shutdownTimeout = mainConstants.getTimeout nodeName "shutdown";
      exitTimeout = mainConstants.getTimeout nodeName "waitExit";

      sshOpts = lib.concatStringsSep " " [
        "-o" "StrictHostKeyChecking=no"
        "-o" "UserKnownHostsFile=/dev/null"
        "-o" "ConnectTimeout=5"
        "-o" "LogLevel=ERROR"
        "-o" "PubkeyAuthentication=no"
      ];
    in
    pkgs.writeShellApplication {
      name = "k8s-lifecycle-test-${nodeName}";
      runtimeInputs = commonInputs ++ sshInputs ++ [ pkgs.curl pkgs.nix ];
      text = ''
        set +e

        ${colorHelpers}
        ${timingHelpers}
        ${processHelpers}
        ${consoleHelpers}
        ${k8sChecks.mkSshHelper}
        ${k8sChecks.mkCheckServiceScript}
        ${k8sChecks.mkCheckEtcdScript}
        ${k8sChecks.mkCheckApiserverScript}

        HOSTNAME="${hostname}"
        NODE="${nodeName}"
        NODE_IP="${nodeIp}"
        SERIAL_PORT=${toString consolePorts.serial}
        VIRTIO_PORT=${toString consolePorts.virtio}
        RESULT_LINK="result-lifecycle-$NODE"

        declare -A PHASE_TIMES
        TOTAL_START=$(time_ms)
        TOTAL_PASSED=0
        TOTAL_FAILED=0

        record_result() {
          local phase="$1"
          local passed="$2"
          local time_ms="$3"
          PHASE_TIMES["$phase"]=$time_ms
          if [[ "$passed" == "true" ]]; then
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
          else
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
          fi
        }

        bold "========================================"
        bold "  K8s Lifecycle Test ($NODE)"
        bold "========================================"
        echo ""
        info "Description: ${nodeConfig.description}"
        info "Hostname: $HOSTNAME"
        info "IP: $NODE_IP"
        echo ""

        # ─── Phase 0: Build VM ──────────────────────────────────────────
        phase_header "0" "Build VM" "${toString buildTimeout}"
        start_time=$(time_ms)
        rm -f "$RESULT_LINK"

        info "  Building k8s-microvm-$NODE..."
        if nix build ".#k8s-microvm-$NODE" -o "$RESULT_LINK" 2>&1 | while read -r line; do
          echo "    $line"
        done; then
          elapsed=$(elapsed_ms "$start_time")
          result_pass "VM built" "$elapsed"
          record_result "build" "true" "$elapsed"
        else
          elapsed=$(elapsed_ms "$start_time")
          result_fail "Build failed" "$elapsed"
          record_result "build" "false" "$elapsed"
          exit 1
        fi

        # ─── Phase 1: Start VM ──────────────────────────────────────────
        phase_header "1" "Start VM" "${toString processTimeout}"
        start_time=$(time_ms)

        if vm_is_running "$HOSTNAME"; then
          warn "  Killing existing VM..."
          kill_vm "$HOSTNAME"
          sleep 2
        fi

        info "  Starting $RESULT_LINK/bin/microvm-run..."
        "$RESULT_LINK/bin/microvm-run" &
        _bg_pid=$!

        if wait_for_process "$HOSTNAME" "${toString processTimeout}"; then
          elapsed=$(elapsed_ms "$start_time")
          qemu_pid=$(vm_pid "$HOSTNAME")
          result_pass "VM running (PID: $qemu_pid)" "$elapsed"
          record_result "start" "true" "$elapsed"
        else
          elapsed=$(elapsed_ms "$start_time")
          result_fail "VM process not found" "$elapsed"
          record_result "start" "false" "$elapsed"
          rm -f "$RESULT_LINK"
          exit 1
        fi

        # ─── Phase 2: Serial Console ────────────────────────────────────
        phase_header "2" "Serial Console" "${toString serialTimeout}"
        start_time=$(time_ms)

        if wait_for_console "$SERIAL_PORT" "${toString serialTimeout}"; then
          elapsed=$(elapsed_ms "$start_time")
          result_pass "Serial console (port $SERIAL_PORT)" "$elapsed"
          record_result "serial" "true" "$elapsed"
        else
          elapsed=$(elapsed_ms "$start_time")
          result_fail "Serial console not available" "$elapsed"
          record_result "serial" "false" "$elapsed"
        fi

        # ─── Phase 2b: Virtio Console ───────────────────────────────────
        phase_header "2b" "Virtio Console" "${toString virtioTimeout}"
        start_time=$(time_ms)

        if wait_for_console "$VIRTIO_PORT" "${toString virtioTimeout}"; then
          elapsed=$(elapsed_ms "$start_time")
          result_pass "Virtio console (port $VIRTIO_PORT)" "$elapsed"
          record_result "virtio" "true" "$elapsed"
        else
          elapsed=$(elapsed_ms "$start_time")
          result_fail "Virtio console not available" "$elapsed"
          record_result "virtio" "false" "$elapsed"
        fi

        # ─── Phase 3: SSH Ready ─────────────────────────────────────────
        phase_header "3" "SSH Ready" "${toString sshTimeout}"
        start_time=$(time_ms)

        if wait_for_ssh "$NODE_IP" "${toString sshTimeout}"; then
          elapsed=$(elapsed_ms "$start_time")
          result_pass "SSH connected" "$elapsed"
          record_result "ssh" "true" "$elapsed"
        else
          elapsed=$(elapsed_ms "$start_time")
          result_fail "SSH not available" "$elapsed"
          record_result "ssh" "false" "$elapsed"
        fi

        # ─── Phase 4: Cert Verify ───────────────────────────────────────
        # Certs are baked into the VM image at build time (certs.nix -> microvm.nix
        # activation script). This phase verifies they were deployed correctly.
        phase_header "4" "Cert Verify" "${toString certInjectTimeout}"
        start_time=$(time_ms)

        cert_ok=0
        cert_fail=0

        # Expected files for this node (common to all roles)
        expected_files=(
          "${mainConstants.k8s.pkiDir}/ca.crt"
          "${mainConstants.k8s.pkiDir}/ca.key"
          "${mainConstants.k8s.pkiDir}/etcd-ca.crt"
          "${mainConstants.k8s.pkiDir}/front-proxy-ca.crt"
          "${mainConstants.k8s.pkiDir}/sa.pub"
          "${mainConstants.k8s.pkiDir}/sa.key"
          "${mainConstants.k8s.pkiDir}/kubelet.crt"
          "${mainConstants.k8s.pkiDir}/kubelet.key"
          "${mainConstants.k8s.pkiDir}/kubelet-kubeconfig"
          "${mainConstants.k8s.pkiDir}/kubelet-config.yaml"
        )

        ${lib.optionalString (nodeConfig.role == "control-plane") ''
        # Control plane additional files
        expected_files+=(
          "${mainConstants.k8s.pkiDir}/apiserver.crt"
          "${mainConstants.k8s.pkiDir}/apiserver.key"
          "${mainConstants.k8s.pkiDir}/apiserver-kubelet-client.crt"
          "${mainConstants.k8s.pkiDir}/apiserver-kubelet-client.key"
          "${mainConstants.k8s.pkiDir}/apiserver-etcd-client.crt"
          "${mainConstants.k8s.pkiDir}/apiserver-etcd-client.key"
          "${mainConstants.k8s.pkiDir}/front-proxy-ca.key"
          "${mainConstants.k8s.pkiDir}/front-proxy-client.crt"
          "${mainConstants.k8s.pkiDir}/front-proxy-client.key"
          "${mainConstants.k8s.pkiDir}/etcd-ca.key"
          "${mainConstants.k8s.pkiDir}/etcd-server.crt"
          "${mainConstants.k8s.pkiDir}/etcd-server.key"
          "${mainConstants.k8s.pkiDir}/etcd-peer.crt"
          "${mainConstants.k8s.pkiDir}/etcd-peer.key"
          "${mainConstants.k8s.pkiDir}/controller-manager.crt"
          "${mainConstants.k8s.pkiDir}/controller-manager.key"
          "${mainConstants.k8s.pkiDir}/scheduler.crt"
          "${mainConstants.k8s.pkiDir}/scheduler.key"
          "${mainConstants.k8s.pkiDir}/admin.crt"
          "${mainConstants.k8s.pkiDir}/admin.key"
          "${mainConstants.k8s.pkiDir}/controller-manager-kubeconfig"
          "${mainConstants.k8s.pkiDir}/scheduler-kubeconfig"
          "${mainConstants.k8s.pkiDir}/admin-kubeconfig"
        )
        ''}

        for f in "''${expected_files[@]}"; do
          if ssh_cmd "$NODE_IP" "test -s $f"; then
            cert_ok=$((cert_ok + 1))
          else
            error "    Missing or empty: $f"
            cert_fail=$((cert_fail + 1))
          fi
        done

        # Verify CA cert can validate kubelet cert
        if ssh_cmd "$NODE_IP" "openssl verify -CAfile ${mainConstants.k8s.pkiDir}/ca.crt ${mainConstants.k8s.pkiDir}/kubelet.crt" 2>/dev/null | grep -q "OK"; then
          info "    CA -> kubelet.crt chain: valid"
        else
          error "    CA -> kubelet.crt chain: invalid"
          cert_fail=$((cert_fail + 1))
        fi

        ${lib.optionalString (nodeConfig.role == "control-plane") ''
        # Verify etcd CA -> etcd-server chain
        if ssh_cmd "$NODE_IP" "openssl verify -CAfile ${mainConstants.k8s.pkiDir}/etcd-ca.crt ${mainConstants.k8s.pkiDir}/etcd-server.crt" 2>/dev/null | grep -q "OK"; then
          info "    etcd-ca -> etcd-server.crt chain: valid"
        else
          error "    etcd-ca -> etcd-server.crt chain: invalid"
          cert_fail=$((cert_fail + 1))
        fi
        ''}

        elapsed=$(elapsed_ms "$start_time")
        if [[ $cert_fail -eq 0 ]]; then
          result_pass "All $cert_ok cert files present, chains valid" "$elapsed"
          record_result "certinject" "true" "$elapsed"
        else
          result_fail "$cert_fail cert issues found" "$elapsed"
          record_result "certinject" "false" "$elapsed"
        fi

        # ─── Phase 5: Services Ready ────────────────────────────────────
        phase_header "5" "Services Ready" "${toString serviceTimeout}"
        start_time=$(time_ms)

        service_passed=0
        service_failed=0

        ${lib.concatMapStringsSep "\n" (service: ''
          svc_start=$(time_ms)
          if wait_for_service "$NODE_IP" "${service}" 60; then
            result_pass "${service} active" "$(elapsed_ms "$svc_start")"
            service_passed=$((service_passed + 1))
          else
            result_fail "${service} not active" "$(elapsed_ms "$svc_start")"
            service_failed=$((service_failed + 1))
          fi
        '') nodeConfig.services}

        elapsed=$(elapsed_ms "$start_time")
        if [[ $service_failed -eq 0 ]]; then
          record_result "services" "true" "$elapsed"
        else
          record_result "services" "false" "$elapsed"
        fi

        # ─── Phase 6: K8s Health ────────────────────────────────────────
        phase_header "6" "K8s Health" "${toString k8sHealthTimeout}"
        start_time=$(time_ms)

        ${if nodeConfig.healthChecks == [] then ''
        info "  No health checks for worker node (covered by Phase 5)"
        record_result "k8shealth" "true" "$(elapsed_ms "$start_time")"
        '' else ''
        health_passed=0
        health_failed=0

        ${lib.concatMapStringsSep "\n" (check: ''
          hc_start=$(time_ms)
          hc_ok=false
          hc_deadline=$(($(date +%s) + ${toString k8sHealthTimeout}))

          while [[ $(date +%s) -lt $hc_deadline ]]; do
            if ${
              if check.name == "etcd" then ''check_etcd_health "$NODE_IP"''
              else if check.name == "apiserver" then ''check_apiserver_health "$NODE_IP"''
              else ''ssh_cmd "$NODE_IP" "curl -sk ${check.url}" 2>/dev/null | grep -q "ok"''
            }; then
              hc_ok=true
              break
            fi
            sleep 2
          done

          if [[ "$hc_ok" == "true" ]]; then
            result_pass "${check.name} healthy" "$(elapsed_ms "$hc_start")"
            health_passed=$((health_passed + 1))
          else
            result_fail "${check.name} not healthy" "$(elapsed_ms "$hc_start")"
            health_failed=$((health_failed + 1))
          fi
        '') nodeConfig.healthChecks}

        elapsed=$(elapsed_ms "$start_time")
        if [[ $health_failed -eq 0 ]]; then
          record_result "k8shealth" "true" "$elapsed"
        else
          record_result "k8shealth" "false" "$elapsed"
        fi
        ''}

        # ─── Phase 7: Shutdown ───────────────────────────────────────────
        phase_header "7" "Shutdown" "${toString shutdownTimeout}"
        start_time=$(time_ms)

        info "  Sending shutdown..."
        if ssh_cmd "$NODE_IP" "poweroff" 2>/dev/null; then
          elapsed=$(elapsed_ms "$start_time")
          result_pass "Shutdown sent" "$elapsed"
          record_result "shutdown" "true" "$elapsed"
        else
          elapsed=$(elapsed_ms "$start_time")
          warn "  SSH shutdown failed, killing..."
          kill_vm "$HOSTNAME"
          result_pass "VM killed" "$elapsed"
          record_result "shutdown" "true" "$elapsed"
        fi

        # ─── Phase 8: Wait Exit ──────────────────────────────────────────
        phase_header "8" "Wait Exit" "${toString exitTimeout}"
        start_time=$(time_ms)

        if wait_for_exit "$HOSTNAME" "${toString exitTimeout}"; then
          elapsed=$(elapsed_ms "$start_time")
          result_pass "VM exited cleanly" "$elapsed"
          record_result "exit" "true" "$elapsed"
        else
          elapsed=$(elapsed_ms "$start_time")
          result_fail "VM did not exit, force killing" "$elapsed"
          kill_vm "$HOSTNAME"
          record_result "exit" "false" "$elapsed"
        fi

        rm -f "$RESULT_LINK"

        # ─── Summary ────────────────────────────────────────────────────
        TOTAL_ELAPSED=$(elapsed_ms "$TOTAL_START")

        echo ""
        bold "  Timing Summary"
        echo "  $(printf '─%.0s' {1..37})"
        printf "  %-25s %10s\n" "Phase" "Time (ms)"
        echo "  $(printf '─%.0s' {1..37})"
        for phase in build start serial virtio ssh certinject services k8shealth shutdown exit; do
          if [[ -n "''${PHASE_TIMES[$phase]:-}" ]]; then
            printf "  %-25s %10s\n" "$phase" "''${PHASE_TIMES[$phase]}"
          fi
        done
        echo "  $(printf '─%.0s' {1..37})"
        printf "  %-25s %10s\n" "TOTAL" "$TOTAL_ELAPSED"
        echo ""

        bold "========================================"
        if [[ $TOTAL_FAILED -eq 0 ]]; then
          success "  Result: ALL PHASES PASSED"
          success "  Total time: $(format_ms "$TOTAL_ELAPSED")"
        else
          error "  Result: $TOTAL_FAILED PHASES FAILED"
        fi
        bold "========================================"

        [[ $TOTAL_FAILED -eq 0 ]]
      '';
    };

  # Test-all script
  mkTestAll = pkgs.writeShellApplication {
    name = "k8s-lifecycle-test-all";
    runtimeInputs = commonInputs ++ sshInputs ++ [ pkgs.curl pkgs.nix ];
    text = ''
      set +e

      ${colorHelpers}
      ${timingHelpers}

      bold "========================================"
      bold "  K8s MicroVM Lifecycle Test Suite"
      bold "========================================"
      echo ""

      NODES="${lib.concatStringsSep " " nodeNames}"

      declare -A RESULTS
      declare -A DURATIONS
      TOTAL_PASSED=0
      TOTAL_FAILED=0
      TOTAL_START=$(time_ms)

      for node in $NODES; do
        echo ""
        bold "════════════════════════════════════════"
        bold "  Testing: $node"
        bold "════════════════════════════════════════"

        variant_start=$(time_ms)

        test_script="k8s-lifecycle-test-$node"
        if nix run ".#$test_script" 2>/dev/null; then
          RESULTS[$node]="PASSED"
          TOTAL_PASSED=$((TOTAL_PASSED + 1))
        else
          RESULTS[$node]="FAILED"
          TOTAL_FAILED=$((TOTAL_FAILED + 1))
        fi

        DURATIONS[$node]=$(elapsed_ms "$variant_start")
      done

      TOTAL_ELAPSED=$(elapsed_ms "$TOTAL_START")

      echo ""
      bold "========================================"
      bold "  Test Suite Summary"
      bold "========================================"
      echo ""

      printf "%-12s %-15s %12s\n" "Node" "Result" "Duration"
      printf "%-12s %-15s %12s\n" "────" "──────" "────────"

      for node in $NODES; do
        result="''${RESULTS[$node]:-UNKNOWN}"
        duration="''${DURATIONS[$node]:-0}"

        if [[ "$result" == "PASSED" ]]; then
          printf "%-12s \033[32m%-15s\033[0m %12s\n" "$node" "$result" "$(format_ms "$duration")"
        elif [[ "$result" == "FAILED" ]]; then
          printf "%-12s \033[31m%-15s\033[0m %12s\n" "$node" "$result" "$(format_ms "$duration")"
        fi
      done

      echo ""
      echo "────────────────────────────────────────"
      echo "Total: $TOTAL_PASSED passed, $TOTAL_FAILED failed"
      echo "Total time: $(format_ms "$TOTAL_ELAPSED")"
      echo "────────────────────────────────────────"

      [[ $TOTAL_FAILED -eq 0 ]]
    '';
  };

  # ─── Cluster-Level Test ──────────────────────────────────────────
  # Boots all 4 VMs and verifies the K8s control plane forms:
  # etcd quorum, apiserver health, node registration.
  mkClusterTest = pkgs.writeShellApplication {
    name = "k8s-cluster-test";
    runtimeInputs = commonInputs ++ sshInputs ++ [ pkgs.curl pkgs.nix ];
    text = ''
      set +e

      ${colorHelpers}
      ${timingHelpers}
      ${processHelpers}
      ${k8sChecks.mkSshHelper}
      ${k8sChecks.mkCheckEtcdScript}
      ${k8sChecks.mkCheckEtcdQuorumScript}
      ${k8sChecks.mkCheckApiserverScript}
      ${k8sChecks.mkCheckNodesReadyScript}

      # Node definitions
      ALL_NODES="${lib.concatStringsSep " " nodeNames}"
      CP_NODES="${lib.concatStringsSep " " (lib.filter (n: n != "w3") nodeNames)}"

      declare -A NODE_IPS
      ${lib.concatMapStringsSep "\n" (n: ''NODE_IPS[${n}]="${mainConstants.network.ipv4.${n}}"'') nodeNames}

      declare -A NODE_HOSTNAMES
      ${lib.concatMapStringsSep "\n" (n: ''NODE_HOSTNAMES[${n}]="${mainConstants.getHostname n}"'') nodeNames}

      declare -A PHASE_TIMES
      TOTAL_START=$(time_ms)
      TOTAL_PASSED=0
      TOTAL_FAILED=0
      ABORT=false

      record_result() {
        local phase="$1"
        local passed="$2"
        local time_ms="$3"
        PHASE_TIMES["$phase"]=$time_ms
        if [[ "$passed" == "true" ]]; then
          TOTAL_PASSED=$((TOTAL_PASSED + 1))
        else
          TOTAL_FAILED=$((TOTAL_FAILED + 1))
          ABORT=true
        fi
      }

      # Cleanup function — always kill VMs on exit
      cleanup_vms() {
        warn "Cleaning up VMs..."
        for node in $ALL_NODES; do
          local hostname="''${NODE_HOSTNAMES[$node]}"
          if vm_is_running "$hostname"; then
            local ip="''${NODE_IPS[$node]}"
            ssh_cmd "$ip" "poweroff" 2>/dev/null || true
          fi
        done
        sleep 3
        for node in $ALL_NODES; do
          local hostname="''${NODE_HOSTNAMES[$node]}"
          if vm_is_running "$hostname"; then
            kill_vm "$hostname"
          fi
        done
        for node in $ALL_NODES; do
          rm -f "result-cluster-$node"
        done
      }

      bold "========================================"
      bold "  K8s Cluster-Level Test"
      bold "========================================"
      echo ""
      info "Topology: 3 control planes (cp0, cp1, cp2) + 1 worker (w3)"
      info "Tests: etcd quorum, apiserver health, node registration"
      echo ""

      # ─── Phase C0: Build All VMs ─────────────────────────────────────
      phase_header "C0" "Build All VMs" "900"
      start_time=$(time_ms)
      build_failed=false

      for node in $ALL_NODES; do
        info "  Building k8s-microvm-$node..."
        rm -f "result-cluster-$node"
        if ! nix build ".#k8s-microvm-$node" -o "result-cluster-$node" 2>&1 | while read -r line; do
          echo "    $line"
        done; then
          error "  Failed to build k8s-microvm-$node"
          build_failed=true
          break
        fi
      done

      elapsed=$(elapsed_ms "$start_time")
      if [[ "$build_failed" == "true" ]]; then
        result_fail "Build failed" "$elapsed"
        record_result "build" "false" "$elapsed"
        exit 1
      else
        result_pass "All 4 VMs built" "$elapsed"
        record_result "build" "true" "$elapsed"
      fi

      # ─── Phase C1: Start All VMs ─────────────────────────────────────
      phase_header "C1" "Start All VMs" "30"
      start_time=$(time_ms)
      start_failed=false

      # Kill any existing VMs first
      for node in $ALL_NODES; do
        hostname="''${NODE_HOSTNAMES[$node]}"
        if vm_is_running "$hostname"; then
          warn "  Killing existing $hostname..."
          kill_vm "$hostname"
          sleep 1
        fi
      done

      # Start all VMs
      for node in $ALL_NODES; do
        info "  Starting $node..."
        "result-cluster-$node/bin/microvm-run" &
      done

      # Wait for all QEMU processes
      sleep 2
      for node in $ALL_NODES; do
        hostname="''${NODE_HOSTNAMES[$node]}"
        if wait_for_process "$hostname" 30; then
          qemu_pid=$(vm_pid "$hostname")
          info "  $node running (PID: $qemu_pid)"
        else
          error "  $node process not found"
          start_failed=true
        fi
      done

      elapsed=$(elapsed_ms "$start_time")
      if [[ "$start_failed" == "true" ]]; then
        result_fail "Not all VMs started" "$elapsed"
        record_result "start" "false" "$elapsed"
      else
        result_pass "All 4 VMs running" "$elapsed"
        record_result "start" "true" "$elapsed"
      fi

      # ─── Phase C2: SSH Ready ──────────────────────────────────────────
      if [[ "$ABORT" != "true" ]]; then
        phase_header "C2" "SSH Ready" "90"
        start_time=$(time_ms)
        ssh_failed=false

        for node in $ALL_NODES; do
          ip="''${NODE_IPS[$node]}"
          if wait_for_ssh "$ip" 90; then
            info "  $node SSH ready"
          else
            error "  $node SSH not available"
            ssh_failed=true
          fi
        done

        elapsed=$(elapsed_ms "$start_time")
        if [[ "$ssh_failed" == "true" ]]; then
          result_fail "Not all nodes reachable via SSH" "$elapsed"
          record_result "ssh" "false" "$elapsed"
        else
          result_pass "All 4 nodes reachable via SSH" "$elapsed"
          record_result "ssh" "true" "$elapsed"
        fi
      fi

      # ─── Phase C3: Etcd Quorum ────────────────────────────────────────
      if [[ "$ABORT" != "true" ]]; then
        phase_header "C3" "Etcd Quorum" "120"
        start_time=$(time_ms)
        etcd_ok=false
        deadline=$(($(date +%s) + 120))

        while [[ $(date +%s) -lt $deadline ]]; do
          all_healthy=true
          for node in $CP_NODES; do
            ip="''${NODE_IPS[$node]}"
            if ! check_etcd_health "$ip"; then
              all_healthy=false
              break
            fi
          done

          if [[ "$all_healthy" == "true" ]]; then
            # All individual endpoints healthy, check quorum membership
            cp0_ip="''${NODE_IPS[cp0]}"
            if check_etcd_quorum "$cp0_ip" 3; then
              etcd_ok=true
              break
            fi
          fi
          sleep 3
        done

        elapsed=$(elapsed_ms "$start_time")
        if [[ "$etcd_ok" == "true" ]]; then
          result_pass "Etcd quorum: 3 members healthy" "$elapsed"
          record_result "etcd" "true" "$elapsed"
        else
          result_fail "Etcd quorum not formed" "$elapsed"
          record_result "etcd" "false" "$elapsed"
        fi
      fi

      # ─── Phase C4: API Server Health ──────────────────────────────────
      if [[ "$ABORT" != "true" ]]; then
        phase_header "C4" "API Server Health" "120"
        start_time=$(time_ms)
        api_ok=false
        deadline=$(($(date +%s) + 120))

        while [[ $(date +%s) -lt $deadline ]]; do
          all_healthy=true
          for node in $CP_NODES; do
            ip="''${NODE_IPS[$node]}"
            if ! check_apiserver_health "$ip"; then
              all_healthy=false
              break
            fi
          done

          if [[ "$all_healthy" == "true" ]]; then
            api_ok=true
            break
          fi
          sleep 3
        done

        elapsed=$(elapsed_ms "$start_time")
        if [[ "$api_ok" == "true" ]]; then
          result_pass "All 3 API servers healthy" "$elapsed"
          record_result "apiserver" "true" "$elapsed"
        else
          result_fail "Not all API servers healthy" "$elapsed"
          record_result "apiserver" "false" "$elapsed"
        fi
      fi

      # ─── Phase C5: Node Registration ──────────────────────────────────
      # Checks that all 4 nodes are registered with the apiserver.
      # Nodes will be NotReady until a CNI (Cilium) is deployed — that's
      # expected and not a failure for this test.
      if [[ "$ABORT" != "true" ]]; then
        phase_header "C5" "Node Registration" "180"
        start_time=$(time_ms)
        nodes_ok=false
        deadline=$(($(date +%s) + 180))
        cp0_ip="''${NODE_IPS[cp0]}"

        while [[ $(date +%s) -lt $deadline ]]; do
          node_count=$(ssh_cmd "$cp0_ip" "kubectl --kubeconfig=${mainConstants.k8s.pkiDir}/admin-kubeconfig \
            get nodes --no-headers 2>/dev/null | wc -l" 2>/dev/null | tail -1)
          node_count="''${node_count:-0}"
          if [[ "$node_count" -ge 4 ]]; then
            nodes_ok=true
            break
          fi
          sleep 5
        done

        elapsed=$(elapsed_ms "$start_time")
        if [[ "$nodes_ok" == "true" ]]; then
          # Print node list for visibility
          info "  Node status:"
          ssh_cmd "$cp0_ip" "kubectl --kubeconfig=${mainConstants.k8s.pkiDir}/admin-kubeconfig get nodes -o wide" 2>/dev/null | while read -r line; do
            info "    $line"
          done
          result_pass "All 4 nodes registered" "$elapsed"
          record_result "nodes" "true" "$elapsed"
        else
          result_fail "Not all nodes registered ($node_count/4)" "$elapsed"
          record_result "nodes" "false" "$elapsed"
        fi
      fi

      # ─── Phase C6: Shutdown All ────────────────────────────────────────
      phase_header "C6" "Shutdown All" "60"
      start_time=$(time_ms)
      shutdown_ok=true

      for node in $ALL_NODES; do
        ip="''${NODE_IPS[$node]}"
        hostname="''${NODE_HOSTNAMES[$node]}"
        if vm_is_running "$hostname"; then
          info "  Shutting down $node..."
          ssh_cmd "$ip" "poweroff" 2>/dev/null || true
        fi
      done

      # Wait for all VMs to exit
      for node in $ALL_NODES; do
        hostname="''${NODE_HOSTNAMES[$node]}"
        if ! wait_for_exit "$hostname" 60; then
          warn "  $node did not exit, force killing"
          kill_vm "$hostname"
          shutdown_ok=false
        fi
      done

      for node in $ALL_NODES; do
        rm -f "result-cluster-$node"
      done

      elapsed=$(elapsed_ms "$start_time")
      if [[ "$shutdown_ok" == "true" ]]; then
        result_pass "All VMs exited cleanly" "$elapsed"
        record_result "shutdown" "true" "$elapsed"
      else
        result_pass "All VMs stopped (some force-killed)" "$elapsed"
        record_result "shutdown" "true" "$elapsed"
      fi

      # ─── Summary ──────────────────────────────────────────────────────
      TOTAL_ELAPSED=$(elapsed_ms "$TOTAL_START")

      echo ""
      bold "  Timing Summary"
      echo "  $(printf '─%.0s' {1..37})"
      printf "  %-25s %10s\n" "Phase" "Time (ms)"
      echo "  $(printf '─%.0s' {1..37})"
      for phase in build start ssh etcd apiserver nodes shutdown; do
        if [[ -n "''${PHASE_TIMES[$phase]:-}" ]]; then
          printf "  %-25s %10s\n" "$phase" "''${PHASE_TIMES[$phase]}"
        fi
      done
      echo "  $(printf '─%.0s' {1..37})"
      printf "  %-25s %10s\n" "TOTAL" "$TOTAL_ELAPSED"
      echo ""

      bold "========================================"
      if [[ $TOTAL_FAILED -eq 0 ]]; then
        success "  Result: ALL CLUSTER CHECKS PASSED"
        success "  Total time: $(format_ms "$TOTAL_ELAPSED")"
      else
        error "  Result: $TOTAL_FAILED PHASES FAILED"
      fi
      bold "========================================"

      [[ $TOTAL_FAILED -eq 0 ]]
    '';
  };

  testsByNode = lib.genAttrs nodeNames (node: mkFullTest node);

in
{
  tests = testsByNode // {
    all = mkTestAll;
    cluster = mkClusterTest;
  };

  packages =
    let
      fullTests = lib.mapAttrs' (node: test:
        lib.nameValuePair "k8s-lifecycle-test-${node}" test
      ) testsByNode;
    in
    fullTests // {
      k8s-lifecycle-test-all = mkTestAll;
      k8s-cluster-test = mkClusterTest;
    };

  apps = lib.mapAttrs (name: pkg: {
    type = "app";
    program = "${pkg}/bin/${name}";
  }) (
    let
      fullTestApps = lib.foldl' (acc: node:
        acc // {
          "k8s-lifecycle-test-${node}" = testsByNode.${node};
        }
      ) {} nodeNames;
    in
    fullTestApps // {
      k8s-lifecycle-test-all = mkTestAll;
      k8s-cluster-test = mkClusterTest;
    }
  );
}
