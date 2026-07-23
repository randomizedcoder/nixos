#
# l2/ollama-service.nix
#
# ollama serving the AMD Instinct MI50 (gfx906, 32GB) over VULKAN, on :11434.
#
# WHY VULKAN, not ROCm. gfx906 left ROCm official support at 5.7; ROCm 7.2.3
# SIGSEGVs at HIP getDeviceKernel on it, and `ollama-rocm` rejects gfx906 at
# runtime regardless of build flags. The Vulkan (RADV) backend drives the DRM
# render node directly, never touching libamdhip64, and it WORKS: verified
# 2026-07-22 running qwen2.5-coder:32b fully on the GPU
# (`offloaded 65/65 layers`, 18.5GB weights + 8GB KV = 26.3GB VRAM on the MI50) —
# a model l's 8GB RTX 3070 cannot run.
#
# PREREQUISITE — the W5700 must be OUT. That card (gfx1010, PCI 44:00.x, its USB
# controller died every boot) wedged the whole GPU stack: any tool enumerating all
# GPUs (vulkaninfo/rocminfo/ollama) hung on it and rebooted the box, on BOTH the
# net-next and a stable 6.18 kernel. With it removed, the MI50 works on the NORMAL
# net-next kernel — no stable-kernel specialisation needed (gpu-stable.nix is now
# just a spare boot entry).
#
# COOLING. The MI50 (a passive datacenter card by default) has a fan directly
# attached here, driven by fan2go (configured + tested — see fan2go.nix), so a 30B
# at ~150-225W is fine. Removing the adjacent W5700 should make it run cooler, not
# hotter. No action needed; noted only because a bare MI50 elsewhere would need it.
#
{ config, lib, pkgs, ... }:

let
  # llama3.1:8b is ~5GB; its KV cache is small, so 32k context fits with the 32GB
  # card barely touched. Raise freely here — the constraint on this card is NOT
  # VRAM (see the model note below). Watch VRAM if you swap in something large:
  # `cat /sys/class/drm/card0/device/mem_info_vram_used`.
  ctxLength = toString 32768;
in
{
  services.ollama = {
    enable = true;

    # The Vulkan build. `ollama-rocm` would be rejected by gfx906's runtime
    # allowlist; `ollama-vulkan` is a different backend and is not subject to it.
    package = pkgs.ollama-vulkan;

    # Reachable from the LAN (l dials this endpoint). NO authentication — an open
    # inference port for anyone who can route to it. Acceptable only on this
    # private lab network. openFirewall opens 11434 (l2's firewall is otherwise on;
    # agent-seam.nix opens 50100).
    host = "0.0.0.0";
    openFirewall = true;

    environmentVariables = {
      # Force the Vulkan runner (matches the verified manual bring-up).
      OLLAMA_VULKAN = "1";
      # Select the MI50 and EXCLUDE the 2GB Quadro P620 (the display GPU, which
      # RADV/NVK also exposes as a Vulkan device). Index 1 = the MI50 in Vulkan
      # enumeration order on this box; confirm with the ollama startup log
      # (`description="AMD Radeon Graphics (RADV VEGA20)" pci_id=0000:63:00.0`).
      GGML_VK_VISIBLE_DEVICES = "1";
      OLLAMA_CONTEXT_LENGTH = ctxLength;
      OLLAMA_KEEP_ALIVE = "5m";
      # 32GB fits one 30B at a time; keeping two resident would thrash.
      OLLAMA_MAX_LOADED_MODELS = "1";
      # OLLAMA_DEBUG = "1";
    };

    # Pulled in the background by ollama-model-loader.service on activation.
    #
    # WHY 8B AND NOT A BIG MODEL — the surprising part. The MI50's 32GB is NOT the
    # constraint (a 70B q2 loaded 81/81 layers here fine). The constraint is
    # tool-calling THROUGH OLLAMA'S OPENAI-COMPAT ENDPOINT, which agent-seddon
    # speaks. Verified 2026-07-22 against this very service:
    #   - qwen3-coder:30b EMITS a correct tool call
    #     (`<function=write_file>…</function>`) but ollama's /v1/chat/completions
    #     returns it as prose with tool_calls:null — its parser only runs on the
    #     NATIVE /api/chat endpoint. Agent sees prose, writes nothing.
    #   - qwen2.5-coder (7b/32b): same, worse (no parser at all).
    #   - llama3-groq-tool-use:70b-q2_K: loads on the GPU but the 2-bit quant is so
    #     degraded it replies "I do not have the capability to perform this task".
    #   - llama3.1:8b: TOOL-CALLS and completes the task (e2e-live PASS — wrote and
    #     compiled a C program on the MI50). So it is the reliable choice today.
    # Net: with ollama + OpenAI-compat, stick to a model whose tool format ollama
    # translates — llama-family OR mistral. Tested against this service:
    #   - mistral-small:24b — tool-calls fine, and writes CORRECT code. Given a
    #     "wordcount.py + sample + run it" task it produced a working script;
    #     llama3.1:8b on the same task wrote a syntactically broken regex and
    #     failed. Loads 41/41 layers on the MI50 (~18.5GB), so it fits with room.
    #     This is the one that actually earns the 32GB card. e2e-live PASSes.
    #   - llama3.1:8b — tool-calls + passes e2e-live, but too weak for real code
    #     (breaks on anything non-trivial). Kept as a small/fast fallback.
    # mistral-small is first so it is the default the agent picks.
    loadModels = [
      "mistral-small:24b" # ~14GB — capable agent model; writes correct code
      "llama3.1:8b" # 4.9GB — small/fast fallback (weak on real tasks)
      # Embeddings — feeds agent-seddon's Embedder seam.
      "nomic-embed-text:latest" # 0.3GB
    ];
  };
}
