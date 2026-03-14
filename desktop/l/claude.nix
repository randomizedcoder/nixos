{ pkgs, lib, ... }:

let
  profiles = [ "personal" "work" ];
  defaultProfile = "personal";

  claude-statusline = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      input=$(cat)

      IFS=$'\t' read -r _MODEL PROJECT_DIR USED_PCT REMAINING_PCT < <(
        echo "$input" | jq -r '[
          (.model.display_name // "unknown"),
          (.workspace.project_dir // "unknown"),
          (.context_window.used_percentage // 0 | tostring),
          (.context_window.remaining_percentage // 100 | tostring)
        ] | @tsv'
      )

      # Integer percentages (strip any decimal)
      USED="''${USED_PCT%%.*}"
      REMAINING="''${REMAINING_PCT%%.*}"

      # ANSI colors
      GREEN='\033[32m'
      ORANGE='\033[33m'
      RED='\033[31m'
      CYAN='\033[36m'
      RESET='\033[0m'

      # Color by context usage
      if [ "$USED" -ge 80 ]; then
        CTX_COLOR="$RED"
      elif [ "$USED" -ge 50 ]; then
        CTX_COLOR="$ORANGE"
      else
        CTX_COLOR="$GREEN"
      fi

      DIR_NAME="''${PROJECT_DIR##*/}"

      printf '%b' "''${CYAN}''${DIR_NAME}''${RESET} | ''${CTX_COLOR}''${USED}%/''${REMAINING}%''${RESET}"
    '';
  };

  settingsFile = pkgs.writeText "claude-settings.json" (builtins.toJSON {
    model = "claude-opus-4-6";
    enabledPlugins = {
      "gopls-lsp@claude-plugins-official" = true;
      "rust-analyzer-lsp@claude-plugins-official" = true;
    };
    statusLine = {
      type = "command";
      command = "${claude-statusline}/bin/claude-statusline";
    };
  });
in
{
  home.packages = [ claude-statusline ];

  # claude-use: switch CLAUDE_CONFIG_DIR between OAuth profiles
  programs.bash.initExtra = ''
    claude-use() {
      local profiles_dir="$HOME/.claude/profiles"
      local name="''${1:-}"

      if [ -z "$name" ]; then
        echo "Claude profiles:"
        for p in ${lib.concatStringsSep " " profiles}; do
          local pdir="$profiles_dir/$p"
          if [ "''${CLAUDE_CONFIG_DIR:-}" = "$pdir" ]; then
            echo "  * $p (active)"
          else
            echo "    $p"
          fi
        done
        echo ""
        echo "Usage: claude-use <profile>"
        return 0
      fi

      local profile_dir="$profiles_dir/$name"
      if [ ! -d "$profile_dir" ]; then
        echo "Error: profile not found: $profile_dir" >&2
        echo "Available profiles: ${lib.concatStringsSep " " profiles}" >&2
        return 1
      fi

      export CLAUDE_CONFIG_DIR="$profile_dir"
      echo "Switched to profile: $name (CLAUDE_CONFIG_DIR=$profile_dir)"
    }

    claude-use-setup() {
      local name="''${1:-}"
      if [ -z "$name" ]; then
        echo "Usage: claude-use-setup <profile>"
        echo "Sets up OAuth login for a profile."
        return 1
      fi

      local profile_dir="$HOME/.claude/profiles/$name"
      if [ ! -d "$profile_dir" ]; then
        echo "Error: profile directory not found: $profile_dir" >&2
        echo "Run 'make' first to create profile directories." >&2
        return 1
      fi

      export CLAUDE_CONFIG_DIR="$profile_dir"
      echo "Setting up OAuth for profile: $name"
      echo "CLAUDE_CONFIG_DIR=$profile_dir"
      claude auth login
    }

    # Default profile
    if [ -z "''${CLAUDE_CONFIG_DIR:-}" ]; then
      export CLAUDE_CONFIG_DIR="$HOME/.claude/profiles/${defaultProfile}"
    fi
  '';

  # Create profile directories and deploy settings.json to each
  home.activation.claudeProfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${lib.concatMapStringsSep "\n    " (profile: ''
      mkdir -p "$HOME/.claude/profiles/${profile}"
      chmod 700 "$HOME/.claude/profiles/${profile}"
      install -m 644 ${settingsFile} "$HOME/.claude/profiles/${profile}/settings.json"
    '') profiles}
  '';
}
