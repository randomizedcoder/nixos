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

#CUDA_VISIBLE_DEVICES=0,1,2,3,4 /mnt/sda/llamav2/llama.cpp/build/bin/llama-server -m /mnt/sda/llamav2/llama.cpp/models/Qwen3CoderNext/Qwen3-Coder-Next-MXFP4_MOE.gguf --ctx-size 130000 --cache-type-k q8_0 --cache-type-v q8_0 --parallel 1 --batch-size 4096 --ubatch-size 4096 --flash-attn auto --fit on --host 0.0.0.0 --port 8000 --api-key YOUR_API_KEY_HERE -a Qwen3Coder --temp 1.0 --top-p 0.95 --top-k 40 --min-p 0.01 --jinja
# https://huggingface.co/unsloth/Qwen3-Coder-Next-GGUF/tree/main

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

      hfRepo = "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF";
      environment.ROCR_VISIBLE_DEVICES = "1";
    };

    # W7500: 8GB VRAM - small model
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

      hfRepo = "Qwen/Qwen2.5-3B-Instruct-GGUF";
      hfFile = "qwen2.5-3b-instruct-q4_k_m.gguf";
      environment.ROCR_VISIBLE_DEVICES = "0";
    };

  };
}
