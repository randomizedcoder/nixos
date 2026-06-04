{ pkgs, lib, ... }:

# Notes for future-me (last checked 2026-04-12, Claude Code docs at
# https://code.claude.com/docs/en/statusline):
#
# Statusline JSON fields currently exposed on stdin:
#   model.*, workspace.*, cost.*, context_window.*, rate_limits.*,
#   session_id, session_name, transcript_path, version,
#   output_style.name, exceeds_200k_tokens, worktree.*
# Session (5-hour) rate limit lives at rate_limits.five_hour.used_percentage
# and only appears for Pro/Max subscribers after the first API response.
#
# Env vars Claude Code sets in the child shell:
#   CLAUDECODE=1, CLAUDE_CONFIG_DIR, CLAUDE_CODE_ENTRYPOINT, CLAUDE_CODE_EXECPATH
#
# Plan mode: plans are written to $CLAUDE_CONFIG_DIR/plans/<slug>.md but
# Claude Code does NOT expose the active plan's path via env var or
# statusline JSON. $CLAUDE_CONFIG_DIR/session-env/<session_id>/ directories
# exist but were empty on this machine — likely reserved for future use.
# Re-check both (env + statusline fields) if you want a plan-file segment:
# a CLAUDE_PLAN_FILE env var or a new statusline field would be the clean hook.

let
  profiles = [ "personal" "siden" "runpod" ];
  defaultProfile = "runpod";

  # Per-profile model selection — exported as ANTHROPIC_MODEL by claude-use.
  profileModels = {
    personal = "claude-opus-4-7";
    siden = "claude-opus-4-7";
    runpod = "claude-opus-4-7";
  };
  defaultModel = profileModels.${defaultProfile};

  # Generate a bash case statement mapping profile names to model IDs.
  modelCaseArms = lib.concatStringsSep "\n        " (lib.mapAttrsToList
    (name: model: ''${name}) _model="${model}" ;;'')
    profileModels);

  # Which statusline to wire into settings.json. The shell version stays
  # installed either way so they can be compared side-by-side.
  #   "shell" -> claude-statusline      (jq + bash, ~10–20ms per invocation)
  #   "rust"  -> claude-statusline-rs   (single static binary, sub-ms)
  statuslineImpl = "rust";

  # Rust statusline, compiled from a single .rs file with plain rustc.
  # No Cargo.toml, no Cargo.lock, no vendoring — just nix driving rustc.
  claude-statusline-rs = pkgs.runCommandLocal "claude-statusline-rs" {
    # rustc invokes `cc` to link; stdenv.cc provides the wrapper.
    nativeBuildInputs = [ pkgs.rustc pkgs.stdenv.cc ];
  } ''
    mkdir -p $out/bin
    rustc --edition 2021 -C opt-level=3 -C lto=fat -C codegen-units=1 \
          -C strip=symbols -C panic=abort \
          -o $out/bin/claude-statusline-rs ${./claude-statusline.rs}
  '';

  claude-statusline = pkgs.writeShellApplication {
    name = "claude-statusline";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      input=$(cat)

      # Context percentages come through as pre-calculated integers/floats.
      # Session (5-hour rate limit) is only present for Pro/Max after the first
      # API response; fall back to empty and handle below.
      IFS=$'\t' read -r PROJECT_DIR CTX_USED_PCT CTX_REMAIN_PCT SESS_USED_PCT MODEL_NAME EFFORT_LVL < <(
        echo "$input" | jq -r '[
          (.workspace.project_dir // "unknown"),
          (.context_window.used_percentage // 0 | tostring),
          (.context_window.remaining_percentage // 100 | tostring),
          (.rate_limits.five_hour.used_percentage // "" | tostring),
          (.model.display_name // .model.id // "" | tostring),
          (.effort.level // "" | tostring)
        ] | @tsv'
      )

      # Integer percentages (strip any decimal)
      CTX_USED="''${CTX_USED_PCT%%.*}"
      CTX_REMAIN="''${CTX_REMAIN_PCT%%.*}"

      # Profile from CLAUDE_CONFIG_DIR basename; "default" if unset/non-profile.
      PROFILE="default"
      if [ -n "''${CLAUDE_CONFIG_DIR:-}" ]; then
        PROFILE="''${CLAUDE_CONFIG_DIR##*/}"
      fi

      # ANSI colors. Two palettes so c (context) and s (session) are visually
      # distinct at a glance, while each still grades independently by usage:
      #   context: warm traditional — green → orange → red
      #   session: cool bright     — bright blue → bright magenta → bright red
      CYAN='\033[36m'
      MAGENTA='\033[35m'
      RESET='\033[0m'

      # Context palette (warm)
      CTX_LOW='\033[32m'        # green
      CTX_MID='\033[33m'        # orange/yellow
      CTX_HIGH='\033[31m'       # red

      # Session palette (cool/bright)
      SESS_LOW='\033[94m'       # bright blue
      SESS_MID='\033[95m'       # bright magenta
      SESS_HIGH='\033[91m'      # bright red

      color_for_pct() {
        local pct="$1" low="$2" mid="$3" high="$4"
        if [ "$pct" -ge 80 ]; then
          printf '%s' "$high"
        elif [ "$pct" -ge 50 ]; then
          printf '%s' "$mid"
        else
          printf '%s' "$low"
        fi
      }

      CTX_COLOR=$(color_for_pct "$CTX_USED" "$CTX_LOW" "$CTX_MID" "$CTX_HIGH")

      DIR_NAME="''${PROJECT_DIR##*/}"

      # Git branch from .git/HEAD (fast, no subprocess)
      BRANCH=""
      YELLOW='\033[33m'
      DIM='\033[2m'
      if [ -f "$PROJECT_DIR/.git/HEAD" ]; then
        _head=$(< "$PROJECT_DIR/.git/HEAD")
        _head="''${_head%$'\n'}"
        if [[ "$_head" == ref:\ refs/heads/* ]]; then
          BRANCH="''${_head#ref: refs/heads/}"
        elif [ ''${#_head} -ge 7 ]; then
          BRANCH="''${_head:0:7}"
        fi
      fi

      # Effort abbreviation
      EFFORT_ABBREV=""
      case "$EFFORT_LVL" in
        low) EFFORT_ABBREV="lo" ;;
        medium) EFFORT_ABBREV="med" ;;
        high) EFFORT_ABBREV="hi" ;;
        xhigh) EFFORT_ABBREV="xhi" ;;
        max) EFFORT_ABBREV="max" ;;
        ?*) EFFORT_ABBREV="$EFFORT_LVL" ;;
      esac

      # Build session segment only when rate_limits is present.
      SESS_SEGMENT=""
      if [ -n "$SESS_USED_PCT" ]; then
        SESS_USED="''${SESS_USED_PCT%%.*}"
        SESS_REMAIN=$(( 100 - SESS_USED ))
        SESS_COLOR=$(color_for_pct "$SESS_USED" "$SESS_LOW" "$SESS_MID" "$SESS_HIGH")
        SESS_SEGMENT=$(printf ' | %bs:%d%%/%d%%%b' \
          "$SESS_COLOR" "$SESS_USED" "$SESS_REMAIN" "$RESET")
      fi

      # Branch segment
      BRANCH_SEGMENT=""
      if [ -n "$BRANCH" ]; then
        BRANCH_SEGMENT=$(printf ' %b%s%b' "$YELLOW" "$BRANCH" "$RESET")
      fi

      # Model + effort segment
      MODEL_SEGMENT=""
      if [ -n "$MODEL_NAME" ]; then
        MODEL_SEGMENT=$(printf ' | %b%s%b' "$DIM" "$MODEL_NAME" "$RESET")
        if [ -n "$EFFORT_ABBREV" ]; then
          MODEL_SEGMENT=$(printf '%s %b%s%b' "$MODEL_SEGMENT" "$DIM" "$EFFORT_ABBREV" "$RESET")
        fi
      fi

      printf '%b%s%b %b%s%b%b | %bc:%s%%/%s%%%b%b%b' \
        "$MAGENTA" "$PROFILE" "$RESET" \
        "$CYAN" "$DIR_NAME" "$RESET" \
        "$BRANCH_SEGMENT" \
        "$CTX_COLOR" "$CTX_USED" "$CTX_REMAIN" "$RESET" \
        "$SESS_SEGMENT" \
        "$MODEL_SEGMENT"
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
      command =
        if statuslineImpl == "rust"
        then "${claude-statusline-rs}/bin/claude-statusline-rs"
        else "${claude-statusline}/bin/claude-statusline";
    };
  });
in
{
  # Both binaries installed so you can benchmark / swap via statuslineImpl.
  # Try: time (echo '<json>' | claude-statusline) vs time (... | claude-statusline-rs)
  home.packages = [ claude-statusline claude-statusline-rs ];

  # claude-use: switch CLAUDE_CONFIG_DIR between OAuth profiles.
  # Profiles are discovered from disk so adding one is just a new directory
  # under ~/.claude/profiles/ — no Nix rebuild needed to use it.
  programs.bash.initExtra = ''
    claude-use() {
      local profiles_dir="$HOME/.claude/profiles"
      local name="''${1:-}"

      if [ -z "$name" ]; then
        echo "Claude profiles (in $profiles_dir):"
        if [ -d "$profiles_dir" ]; then
          local found=0
          for pdir in "$profiles_dir"/*/; do
            [ -d "$pdir" ] || continue
            found=1
            local p="''${pdir%/}"; p="''${p##*/}"
            if [ "''${CLAUDE_CONFIG_DIR:-}" = "''${pdir%/}" ]; then
              echo "  * $p (active)"
            else
              echo "    $p"
            fi
          done
          [ "$found" = 0 ] && echo "  (no profiles found — run 'claude-use-setup <name>')"
        else
          echo "  (profiles dir missing — run 'make' or 'claude-use-setup <name>')"
        fi
        echo ""
        echo "Usage: claude-use <profile>"
        return 0
      fi

      local profile_dir="$profiles_dir/$name"
      if [ ! -d "$profile_dir" ]; then
        echo "Error: profile not found: $profile_dir" >&2
        echo "Create it with: claude-use-setup $name" >&2
        return 1
      fi

      export CLAUDE_CONFIG_DIR="$profile_dir"

      # Set ANTHROPIC_MODEL based on profile name.
      local _model="${defaultModel}"
      case "$name" in
        ${modelCaseArms}
        *) ;;
      esac
      export ANTHROPIC_MODEL="$_model"

      echo "Switched to profile: $name (CLAUDE_CONFIG_DIR=$profile_dir, ANTHROPIC_MODEL=$_model)"
    }

    claude-use-setup() {
      local name="''${1:-}"
      if [ -z "$name" ]; then
        echo "Usage: claude-use-setup <profile>"
        echo "Creates the profile dir (if needed) and runs OAuth login."
        return 1
      fi

      local profile_dir="$HOME/.claude/profiles/$name"
      if [ ! -d "$profile_dir" ]; then
        mkdir -p "$profile_dir"
        chmod 700 "$profile_dir"
        echo "Created profile dir: $profile_dir"
      fi
      # Ensure the profile has the managed settings.json (statusline, etc.)
      install -m 644 ${settingsFile} "$profile_dir/settings.json"

      export CLAUDE_CONFIG_DIR="$profile_dir"

      # Set ANTHROPIC_MODEL based on profile name.
      local _model="${defaultModel}"
      case "$name" in
        ${modelCaseArms}
        *) ;;
      esac
      export ANTHROPIC_MODEL="$_model"

      echo "Setting up OAuth for profile: $name"
      echo "CLAUDE_CONFIG_DIR=$profile_dir"
      echo "ANTHROPIC_MODEL=$_model"
      claude auth login
    }

    # Default profile and model
    if [ -z "''${CLAUDE_CONFIG_DIR:-}" ]; then
      export CLAUDE_CONFIG_DIR="$HOME/.claude/profiles/${defaultProfile}"
    fi
    if [ -z "''${ANTHROPIC_MODEL:-}" ]; then
      export ANTHROPIC_MODEL="${defaultModel}"
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
