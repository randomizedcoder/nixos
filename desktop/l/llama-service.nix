#
# llama-cpp multi-instance configuration
#
# Services:
#   llama-cpp-mi50  - MI50 (gfx906, 32GB), port 8090, large model
#   llama-cpp-w7500 - W7500 (gfx1102, 8GB), port 8091, small model
#
# Test:
#   curl http://localhost:8090/health
#   curl http://localhost:8091/health
#
# Logs:
#   journalctl -u llama-cpp-mi50 -f
#   journalctl -u llama-cpp-w7500 -f
#
# Model selection sources (reviewed 2026-03-23):
#   https://huggingface.co/spaces/open-llm-leaderboard/open_llm_leaderboard#/
#   https://localaimaster.com/models/best-local-ai-coding-models
#   https://onyx.app/open-llm-leaderboard
#   https://www.sitepoint.com/best-local-llm-models-2026/
#   https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF
#   https://huggingface.co/unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF
#   https://huggingface.co/bartowski/Llama-3.3-70B-Instruct-GGUF
#

{ config, lib, pkgs, nixpkgs-local, ... }:

let
  localPkgs = import nixpkgs-local {
    system = "x86_64-linux";
    config.allowUnfree = true;
    config.rocmSupport = true;
  };
in {
  disabledModules = [ "services/misc/llama-cpp.nix" ];
  imports = [ "${nixpkgs-local}/nixos/modules/services/misc/llama-cpp.nix" ];

  services.llama-cpp.instances = {

    # MI50: 32GB VRAM - large model
    # Text comprehension / reasoning (active)
    mi50 = {
      enable = true;
      package = localPkgs.llama-cpp;
      rocmGpuTargets = [ "gfx906" ];

      host = "0.0.0.0";
      port = 8090;
      contextSize = 32768;
      flashAttention = "on";
      enableMetrics = true;
      openFirewall = true;

      # Text review: Qwen3-30B-A3B MoE (~17GB Q4), strong reasoning & comprehension
      hfRepo = "unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF";
      # Coding: Qwen3-Coder-30B-A3B MoE (~17GB Q4), top coding model at this tier
      # hfRepo = "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF";
      environment.ROCR_VISIBLE_DEVICES = "1";
    };

    # W7500: 8GB VRAM - small model
    # Text comprehension / reasoning (active)
    w7500 = {
      enable = true;
      package = localPkgs.llama-cpp;
      rocmGpuTargets = [ "gfx1102" ];

      host = "0.0.0.0";
      port = 8091;
      contextSize = 8192;
      flashAttention = "on";
      enableMetrics = true;
      openFirewall = true;

      # Text review: Qwen2.5-7B-Instruct (~5.5GB Q5), good comprehension for 8GB card
      hfRepo = "Qwen/Qwen2.5-7B-Instruct-GGUF";
      hfFile = "qwen2.5-7b-instruct-q5_k_m-00001-of-00002.gguf";
      # Coding: Qwen2.5-Coder-7B-Instruct (~5.5GB Q5), best coding model for 8GB VRAM
      # hfRepo = "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF";
      # hfFile = "qwen2.5-coder-7b-instruct-q5_k_m.gguf";
      environment.ROCR_VISIBLE_DEVICES = "0";
    };

  };
}
