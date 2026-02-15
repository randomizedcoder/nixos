# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NixOS flake-based configuration for a high-performance workstation (`l`) with:
- AMD Ryzen Threadripper PRO 3945WX (12-core/24-thread)
- AMD MI50 (32GB VRAM, gfx906) - primary compute GPU
- AMD Radeon Pro W7500 (8GB VRAM, gfx1102) - secondary GPU
- Corsair Commander PRO fan controller

## Build Commands

```bash
make                    # Rebuild system (sudo nixos-rebuild switch --flake .)
make impure             # Rebuild with --impure flag
make rebuild_trace      # Rebuild with --show-trace for debugging
make update             # Update flake inputs (sudo nix flake update)
```

## Architecture

### Configuration Structure

`configuration.nix` imports 17+ modular service files:
- `hardware-configuration.nix` - Auto-generated hardware detection
- `sysctl.nix` - Kernel network parameters (TCP tuning, BBRv3-ready)
- `systemPackages.nix` - System-level packages
- Service files: `ollama-service.nix`, `llama-service.nix`, `litellm-service.nix`
- `fan2go.nix` - Hardware fan control via Corsair Commander PRO

`home.nix` - User configuration via Home Manager with 600+ packages

### Flake Inputs

- `nixpkgs`: NixOS unstable channel
- `nixpkgs_local`: Local nixpkgs fork at `/home/das/repos/nixpkgs` for testing custom modules (primarily llama-cpp with ROCm)
- Home Manager integration for user `das`

### LLM Infrastructure

Three-tier inference setup:

1. **Ollama** (port 11434)
   - ROCm on MI50, 128k context
   - Models: codellama:34b, qwen2.5-coder:32b, llama3-groq-tool-use:70b

2. **Llama.cpp** (dual instances via `llama-service.nix`)
   - MI50: port 8090, 32768 context, gfx906 target
   - W7500: port 8091, 8192 context, gfx1102 target

3. **LiteLLM** (port 4000)
   - OpenAI-compatible proxy routing to llama.cpp instances

**vLLM Status**: Currently non-functional due to AVX-512 vs AVX2 CPU incompatibility. See `vllm-design-doc.md` for details.

### Monitoring Stack

- Prometheus (port 9090) - 90-day retention
- Grafana (port 3000, localhost only) - admin/admin
- Node Exporter for system metrics
- Nginx (port 8080) - status page, Ollama proxy at `/ollama/`

### GPU Configuration

ROCm-based AMD GPU support requiring careful LD_LIBRARY_PATH management:
- LACT daemon for GPU monitoring/control
- Custom rocm-smi wrapper in home.nix handles library paths
- HIP_VISIBLE_DEVICES used to target specific GPUs per service

### Network Tuning

`sysctl.nix` contains extensive TCP optimization:
- BBRv3 congestion control module (`bbr3-module.nix`) - out-of-tree from L4S Team
- Large TCP buffers (1MB-16MB rmem/wmem)
- CAKE qdisc as default
- ECN, timestamps, SACK enabled

## Development Notes

- Follow the modular pattern: one service = one `.nix` file imported by `configuration.nix`
- GPU services need explicit HIP_VISIBLE_DEVICES or HSA_OVERRIDE_GFX_VERSION
- Check service logs: `journalctl -u <service-name>`
- MI50 uses gfx906, W7500 uses gfx1102 - different ROCm targets
- Local nixpkgs fork allows testing custom derivations before upstreaming
