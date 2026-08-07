# nix/test-lib.nix
#
# Shared bash helpers for K8s test scripts.
# Provides color output, timing, polling, and assertions.
#
{ }:
rec {
  colorHelpers = ''
    _reset='\033[0m'
    _bold='\033[1m'
    _red='\033[31m'
    _green='\033[32m'
    _yellow='\033[33m'
    _blue='\033[34m'
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
      local time_ms="''${2:-}"
      if [[ -n "$time_ms" ]]; then
        echo -e "  ''${_green}PASS''${_reset}: $msg (''${time_ms}ms)"
      else
        echo -e "  ''${_green}PASS''${_reset}: $msg"
      fi
    }

    result_fail() {
      local msg="$1"
      local time_ms="''${2:-}"
      if [[ -n "$time_ms" ]]; then
        echo -e "  ''${_red}FAIL''${_reset}: $msg (''${time_ms}ms)"
      else
        echo -e "  ''${_red}FAIL''${_reset}: $msg"
      fi
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

  allHelpers = colorHelpers + "\n" + timingHelpers;
}
