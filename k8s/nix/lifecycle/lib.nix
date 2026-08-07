# nix/lifecycle/lib.nix
#
# Script generators for K8s MicroVM lifecycle testing.
#
{ pkgs, lib }:
let
  constants = import ./constants.nix { };
  mainConstants = import ../constants.nix;

  commonInputs = with pkgs; [
    coreutils gnugrep gnused gawk procps netcat-gnu socat expect bc util-linux
  ];

  sshInputs = with pkgs; [ openssh sshpass ];

  colorHelpers = ''
    _reset='\033[0m'
    _bold='\033[1m'
    _red='\033[31m'
    _green='\033[32m'
    _yellow='\033[33m'
    _cyan='\033[36m'

    info() { echo -e "''${_cyan}$*''${_reset}"; }
    success() { echo -e "''${_green}$*''${_reset}"; }
    warn() { echo -e "''${_yellow}$*''${_reset}"; }
    error() { echo -e "''${_red}$*''${_reset}"; }
    bold() { echo -e "''${_bold}$*''${_reset}"; }

    phase_header() {
      local phase="$1"
      local name="$2"
      local timeout="$3"
      echo ""
      echo -e "''${_bold}--- Phase $phase: $name (timeout: ''${timeout}s) ---''${_reset}"
    }

    result_pass() {
      local msg="$1"
      local time_ms="$2"
      echo -e "  ''${_green}PASS''${_reset}: $msg (''${time_ms}ms)"
    }

    result_fail() {
      local msg="$1"
      local time_ms="$2"
      echo -e "  ''${_red}FAIL''${_reset}: $msg (''${time_ms}ms)"
    }
  '';

  timingHelpers = ''
    time_ms() {
      echo $(($(date +%s%N) / 1000000))
    }

    elapsed_ms() {
      local start="$1"
      local now
      now=$(time_ms)
      echo $((now - start))
    }

    format_ms() {
      local ms="$1"
      if [[ $ms -lt 1000 ]]; then
        echo "''${ms}ms"
      elif [[ $ms -lt 60000 ]]; then
        echo "$((ms / 1000)).$((ms % 1000 / 100))s"
      else
        local mins=$((ms / 60000))
        local secs=$(((ms % 60000) / 1000))
        echo "''${mins}m''${secs}s"
      fi
    }
  '';

  processHelpers = ''
    vm_is_running() {
      local hostname="$1"
      pgrep -f "process=$hostname" >/dev/null 2>&1
    }

    vm_pid() {
      local hostname="$1"
      pgrep -f "process=$hostname" 2>/dev/null | head -1
    }

    wait_for_process() {
      local hostname="$1"
      local timeout="$2"
      local elapsed=0
      while [[ $elapsed -lt $timeout ]]; do
        if vm_is_running "$hostname"; then
          return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
      done
      return 1
    }

    wait_for_exit() {
      local hostname="$1"
      local timeout="$2"
      local elapsed=0
      while [[ $elapsed -lt $timeout ]]; do
        if ! vm_is_running "$hostname"; then
          return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
      done
      return 1
    }

    kill_vm() {
      local hostname="$1"
      local pid
      pid=$(vm_pid "$hostname")
      if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        sleep 1
        if vm_is_running "$hostname"; then
          kill -9 "$pid" 2>/dev/null || true
        fi
      fi
    }
  '';

  consoleHelpers = ''
    port_is_open() {
      local host="$1"
      local port="$2"
      nc -z "$host" "$port" 2>/dev/null
    }

    wait_for_console() {
      local port="$1"
      local timeout="$2"
      local elapsed=0
      while [[ $elapsed -lt $timeout ]]; do
        if port_is_open "127.0.0.1" "$port"; then
          return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
      done
      return 1
    }
  '';

in
{
  inherit constants mainConstants commonInputs sshInputs;
  inherit colorHelpers timingHelpers processHelpers consoleHelpers;
}
