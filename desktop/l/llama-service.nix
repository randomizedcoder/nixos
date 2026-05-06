#
# llama-cpp CUDA configuration for l
#
# Services:
#   llama-cpp - RTX 3070 (CUDA, 8GB), port 8090
#
# Test:
#   curl http://localhost:8090/health
#
# Logs:
#   journalctl -u llama-cpp -f
#
# Model selection sources (reviewed 2026-04-12):
#   https://huggingface.co/spaces/open-llm-leaderboard/open_llm_leaderboard#/
#   https://localaimaster.com/models/best-local-ai-coding-models
#   https://onyx.app/open-llm-leaderboard
#   https://www.sitepoint.com/best-local-llm-models-2026/
#

{ config, lib, pkgs, ... }:

let
  #
  # === MODEL MODE ===
  # Set this to switch the active model: "code", "vision", "english", "general"
  #
  modelMode = "code";

  #
  # === MODEL CATALOG ===
  # RTX 3070 (8GB) — uses ~7B Q4_K_M quants.
  #
  models = {
    # Qwen2.5-Coder: top-tier coding, matches GPT-4o on HumanEval
    code    = { hfRepo = "bartowski/Qwen2.5-Coder-7B-Instruct-GGUF";  hfFile = "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"; }; # 4.68GB
    # Qwen2.5-VL: officially supported in llama.cpp, strong vision understanding
    vision  = { hfRepo = "ggml-org/Qwen2.5-VL-7B-Instruct-GGUF";      hfFile = "Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"; };    # ~4.68GB
    # Llama 3.1: only 8 languages, most English-focused major model
    english = { hfRepo = "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF"; hfFile = "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"; }; # ~4.9GB
    # Qwen3.5: best raw quality, multimodal, 201 languages
    general = { hfRepo = "unsloth/Qwen3.5-9B-GGUF";                   hfFile = "Qwen3.5-9B-Q4_K_M.gguf"; };                 # ~5.5GB
  };

  selected = models.${modelMode};

  # Build llama-cpp with CUDA. Re-import nixpkgs with cudaSupport so the
  # override propagates to all CUDA-using transitive dependencies.
  cudaPkgs = import pkgs.path {
    system = "x86_64-linux";
    config.allowUnfree = true;
    config.cudaSupport = true;
  };
in {
  services.llama-cpp = {
    enable = true;
    package = cudaPkgs.llama-cpp;
    host = "0.0.0.0";
    port = 8090;
    openFirewall = true;
    extraFlags = [
      "--hf-repo" selected.hfRepo
      "--hf-file" selected.hfFile
      "--flash-attn" "on"
      "--metrics"
    ];
  };
}
