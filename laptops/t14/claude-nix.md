# claude.nix - Claude Code Configuration Module

Home Manager module that provides API key switching and a Nix-managed status line for Claude Code.

## Features

### 1. `claude-use` - API Key Switcher

A bash function that switches `ANTHROPIC_API_KEY` by reading key files from `~/.claude/api-keys/`.

- Keys are plain text files containing a single API key each
- The function exports to the current shell (not a subshell), so `claude` invoked afterwards picks it up
- Running without arguments lists available keys, marking the active one with `*`
- The `~/.claude/api-keys/` directory is created automatically with `chmod 700`

### 2. `claude-statusline` - Context-Aware Status Line

A shell script piped JSON from Claude Code's status line system. It displays:

```
myproject | 84k/200k~=42%
```

- **Directory name** (cyan) - basename of the current project directory
- **Token usage** (color-coded) - input tokens / context window size ~= percentage used
  - Green: < 50%
  - Orange: 50-79%
  - Red: >= 80%

The script is built with `writeShellApplication`, so it gets shellcheck validation at build time and `jq` is provided automatically via `runtimeInputs`.

### 3. Nix-Managed `settings.json`

On each `make` rebuild, `~/.claude/settings.json` is overwritten with a known-good config:

- Model: `claude-opus-4-6`
- Plugins: `gopls-lsp`, `rust-analyzer-lsp`
- Status line: points to the Nix store path of `claude-statusline`

The file is installed as a regular writable file (not a symlink), so Claude Code can modify it at runtime. Changes are reset on the next rebuild.

## Quickstart

### 1. Rebuild

```bash
cd /home/das/nixos/desktop/l && make
```

### 2. Get API Keys from Anthropic Console

API keys come from the **Anthropic Console** (not claude.ai, which is the consumer chat product):

1. Go to https://console.anthropic.com/settings/keys
2. Sign in (or ask your employer for access to their organization's account)
3. Navigate to **Settings > API Keys**
4. Click **Create Key**, give it a name, and copy the key immediately (it is only shown once)

If your employer uses an **organization account**, they need to have invited you to their org in the Anthropic Console. The API key you create there will bill to the org. Ask your admin if you don't see the org when you log in.

### 3. Save API Keys

Create one file per API key. The filename becomes the key name used by `claude-use`:

```bash
echo "sk-ant-api03-YOUR-KEY-HERE" > ~/.claude/api-keys/personal
echo "sk-ant-api03-WORK-KEY-HERE" > ~/.claude/api-keys/work
chmod 600 ~/.claude/api-keys/*
```

### 4. Switch Keys

```bash
# List available keys
claude-use

# Switch to a key
claude-use personal

# Verify
echo $ANTHROPIC_API_KEY
```

### 5. Use Claude Code

```bash
claude-use personal
claude
```

The status line appears automatically at the bottom of the Claude Code TUI.

### 6. Test the Status Line Manually

```bash
echo '{"model":{"display_name":"Opus"},"workspace":{"project_dir":"/home/das/myproject"},"context_window":{"used_percentage":42,"context_window_size":200000,"total_input_tokens":84000}}' | claude-statusline
```

Expected output (with ANSI colors): `myproject | 84k/200k~=42%`

## File Layout

```
~/.claude/
  settings.json        # Nix-managed (writable copy, reset on rebuild)
  api-keys/            # chmod 700
    personal           # plain text API key file
    work               # plain text API key file

/home/das/nixos/desktop/l/
  claude.nix           # Home Manager module (source of truth)
  home.nix             # imports ./claude.nix
```

## How It Merges

`claude.nix` defines `programs.bash.initExtra` for the `claude-use` function. Home Manager's module system merges this with the existing `programs.bash` block in `home.nix` (which defines `enable`, `enableCompletion`, `shellAliases`, and `profileExtra`). There are no conflicts because they set different options.
