# nix/microvm-scripts.nix
#
# Helper scripts for managing K8s MicroVMs.
#
{ pkgs }:
let
  constants = import ./constants.nix;

  # Pattern to identify our K8s MicroVMs in process list
  vmPattern = "process=k8s-(cp0|cp1|cp2|w3)";
in
{
  check = pkgs.writeShellApplication {
    name = "k8s-vm-check";
    runtimeInputs = with pkgs; [ procps ];
    text = ''
      echo "=== K8s MicroVM Processes ==="
      echo

      if pgrep -af '${vmPattern}'; then
        echo
        echo "=== Count ==="
        pgrep -cf '${vmPattern}'
      else
        echo "(none running)"
        echo
        echo "=== Count ==="
        echo "0"
      fi
    '';
  };

  stop = pkgs.writeShellApplication {
    name = "k8s-vm-stop";
    runtimeInputs = with pkgs; [ procps ];
    text = ''
      echo "=== Stopping K8s MicroVMs ==="

      if ! pgrep -f '${vmPattern}' > /dev/null; then
        echo "No K8s MicroVMs running."
        exit 0
      fi

      echo "Found processes:"
      pgrep -af '${vmPattern}'

      echo
      echo "Sending SIGTERM..."
      pkill -f '${vmPattern}' || true

      sleep 2

      if pgrep -f '${vmPattern}' > /dev/null; then
        echo "Processes still running, sending SIGKILL..."
        pkill -9 -f '${vmPattern}' || true
      fi

      echo "Done."
    '';
  };

  ssh = pkgs.writeShellApplication {
    name = "k8s-vm-ssh";
    runtimeInputs = with pkgs; [ openssh sshpass ];
    text = ''
      unset SSH_AUTH_SOCK

      NODE="cp0"
      PASSTHROUGH_ARGS=()

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --node=*)
            NODE="''${1#--node=}"
            shift
            ;;
          *)
            PASSTHROUGH_ARGS+=("$1")
            shift
            ;;
        esac
      done

      case "$NODE" in
        cp0) HOST="${constants.network.ipv4.cp0}" ;;
        cp1) HOST="${constants.network.ipv4.cp1}" ;;
        cp2) HOST="${constants.network.ipv4.cp2}" ;;
        w3)  HOST="${constants.network.ipv4.w3}" ;;
        *)
          echo "Unknown node: $NODE"
          echo "Valid nodes: cp0, cp1, cp2, w3"
          exit 1
          ;;
      esac

      exec sshpass -p ${constants.ssh.password} ssh \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        "root@$HOST" "''${PASSTHROUGH_ARGS[@]}"
    '';
  };

  startAll = pkgs.writeShellApplication {
    name = "k8s-start-all";
    runtimeInputs = with pkgs; [ procps nix coreutils ];
    text = ''
      echo "=== Starting K8s Cluster (3 CP + 1 Worker) ==="

      # Start control planes first, then worker
      ${builtins.concatStringsSep "\n" (builtins.map (n: let
        hostname = constants.getHostname n;
      in ''
      echo ""
      echo "--- Starting ${n} ---"
      RESULT_LINK="result-k8s-${n}"
      rm -f "$RESULT_LINK"

      if pgrep -f "process=${hostname}" > /dev/null 2>&1; then
        echo "  ${n} already running, skipping"
      else
        nix build ".#k8s-microvm-${n}" -o "$RESULT_LINK"
        "$RESULT_LINK/bin/microvm-run" &
        echo "  ${n} started (PID: $!)"
        sleep 2
      fi
      '') constants.nodeNames)}

      echo ""
      echo "=== All nodes started ==="
      echo "Verify: nix run .#k8s-vm-ssh -- --node=cp0 kubectl get nodes"
    '';
  };
}
