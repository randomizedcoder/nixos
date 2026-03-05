{ pkgs, lib, ... }:

let
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

  # claude-use function: switch ANTHROPIC_API_KEY from ~/.claude/api-keys/<name>
  programs.bash.initExtra = ''
    claude-use() {
      local keys_dir="$HOME/.claude/api-keys"
      local name="''${1:-}"

      if [ -z "$name" ]; then
        echo "Available API keys:"
        if [ -d "$keys_dir" ]; then
          for f in "$keys_dir"/*; do
            [ -f "$f" ] || continue
            local bname
            bname="$(basename "$f")"
            if [ -n "''${ANTHROPIC_API_KEY:-}" ]; then
              local file_key
              file_key="$(tr -d '[:space:]' < "$f")"
              if [ "$file_key" = "$ANTHROPIC_API_KEY" ]; then
                echo "  * $bname (active)"
                continue
              fi
            fi
            echo "    $bname"
          done
        else
          echo "  (no keys directory at $keys_dir)"
        fi
        echo ""
        echo "Usage: claude-use <name>"
        return 0
      fi

      local key_file="$keys_dir/$name"
      if [ ! -f "$key_file" ]; then
        echo "Error: key file not found: $key_file" >&2
        echo "Available keys:" >&2
        ls "$keys_dir" 2>/dev/null || echo "  (none)" >&2
        return 1
      fi

      local key
      key="$(tr -d '[:space:]' < "$key_file")"
      if [ -z "$key" ]; then
        echo "Error: key file is empty: $key_file" >&2
        return 1
      fi

      export ANTHROPIC_API_KEY="$key"
      echo "Switched to API key: $name"
    }
  '';

  # Copy writable settings.json on activation (allows runtime edits, reset on rebuild)
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    install -m 644 ${settingsFile} "$HOME/.claude/settings.json"
  '';

  # Create api-keys directory with restricted permissions
  home.activation.createClaudeApiKeysDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.claude/api-keys"
    chmod 700 "$HOME/.claude/api-keys"
  '';
}
