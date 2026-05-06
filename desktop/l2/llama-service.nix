#
# llama-cpp multi-GPU configuration for l2
#
# Instances:
#   llama-cpp-mi50    - MI50 (ROCm gfx906, 32GB), port 8095
#   llama-cpp-w5700   - W5700 (ROCm gfx1010, 8GB), port 8096
#   llama-cpp-cpu-1..4 - CPU-only, ports 8091-8094
#
# GPU device mapping (rocm-smi):
#   Device 0 (Node 2): WX 2100 (display only, 2GB) - not used
#   Device 1 (Node 3): W5700 (gfx1010, 8GB)  - ROCR_VISIBLE_DEVICES=1
#   Device 2 (Node 1): MI50 (gfx906, 32GB)   - ROCR_VISIBLE_DEVICES=2
#
# Note: RTX 3070 (CUDA) is on machine l, not l2
#
# Test:
#   curl http://localhost:8095/health
#   curl http://localhost:8096/health
#
# Logs:
#   journalctl -u llama-cpp-mi50 -f
#   journalctl -u llama-cpp-w5700 -f
#
# To update the local repo
# nix flake update nixpkgs-local

{ config, lib, pkgs, nixpkgs-local, ... }:

let
  #
  # === MODEL MODE ===
  # Set this to switch all instances at once: "code", "vision", "english", "general"
  #
  modelMode = "code";

  #
  # === MODEL CATALOG ===
  # Models organized by mode and VRAM tier.
  # To add a new model, add an entry here and it will be available to all instances.
  #
  models = {
    code = {
      # Qwen2.5-Coder: top-tier coding, matches GPT-4o on HumanEval
      large = { hfRepo = "bartowski/Qwen2.5-Coder-32B-Instruct-GGUF"; hfFile = "Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf"; }; # 19.85GB
      small = { hfRepo = "bartowski/Qwen2.5-Coder-7B-Instruct-GGUF";  hfFile = "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"; };  # 4.68GB
      cpu   = { hfRepo = "bartowski/Qwen2.5-Coder-7B-Instruct-GGUF";  hfFile = "Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"; };  # 4.68GB
    };
    vision = {
      # Qwen2.5-VL: officially supported in llama.cpp, strong vision understanding
      large = { hfRepo = "ggml-org/Qwen2.5-VL-32B-Instruct-GGUF"; hfFile = "Qwen2.5-VL-32B-Instruct-Q4_K_M.gguf"; }; # ~21GB
      small = { hfRepo = "ggml-org/Qwen2.5-VL-7B-Instruct-GGUF";  hfFile = "Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf"; };  # ~4.68GB
      cpu   = { hfRepo = "ggml-org/Qwen2.5-VL-3B-Instruct-GGUF";  hfFile = "Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"; };  # ~2GB
    };
    english = {
      # English-focused: Llama 3.1 (8 langs only), Phi-4-mini (~92% English training data)
      large = { hfRepo = "bartowski/Meta-Llama-3.1-70B-Instruct-GGUF"; hfFile = "Meta-Llama-3.1-70B-Instruct-Q4_K_M.gguf"; }; # ~40GB — needs quantization or partial offload
      small = { hfRepo = "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF";  hfFile = "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"; };  # ~4.9GB
      cpu   = { hfRepo = "bartowski/microsoft_Phi-4-mini-instruct-GGUF"; hfFile = "microsoft_Phi-4-mini-instruct-Q4_K_M.gguf"; }; # 2.49GB
    };
    general = {
      # Qwen3.5: best raw quality, multimodal, 201 languages
      large = { hfRepo = "unsloth/Qwen3.5-27B-GGUF"; hfFile = "Qwen3.5-27B-Q4_K_M.gguf"; }; # ~15GB
      small = { hfRepo = "unsloth/Qwen3.5-9B-GGUF";  hfFile = "Qwen3.5-9B-Q4_K_M.gguf"; };  # ~5.5GB
      cpu   = { hfRepo = "unsloth/Qwen3.5-4B-GGUF";  hfFile = "Qwen3.5-4B-Q4_K_M.gguf"; };  # ~2.5GB
    };
  };

  selected = models.${modelMode};

  rocmPkgs = import nixpkgs-local {
    system = "x86_64-linux";
    config.allowUnfree = true;
    config.rocmSupport = true;
  };

  cpuPkgs = import nixpkgs-local {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };

  cpuInstances = builtins.listToAttrs (map (i: {
    name = "cpu-${toString i}";
    value = {
      enable = true;
      package = cpuPkgs.llama-cpp;
      host = "0.0.0.0";
      port = 8090 + i;
      contextSize = 2048;
      enableMetrics = true;
      openFirewall = true;
      inherit (selected.cpu) hfRepo hfFile;
    };
  }) (lib.range 1 4));
in {
  disabledModules = [ "services/misc/llama-cpp.nix" ];
  imports = [ "${nixpkgs-local}/nixos/modules/services/misc/llama-cpp.nix" ];

  services.llama-cpp.instances = {

    # MI50: 32GB VRAM — uses "large" model from selected mode
    mi50 = {
      enable = true;
      package = rocmPkgs.llama-cpp;
      rocmGpuTargets = [ "gfx906" ];

      host = "0.0.0.0";
      port = 8095;
      contextSize = 32768;
      flashAttention = "on";
      enableMetrics = true;
      openFirewall = true;

      inherit (selected.large) hfRepo hfFile;
      environment.ROCR_VISIBLE_DEVICES = "2";
    };

    # W5700: 8GB VRAM — uses "small" model from selected mode
    w5700 = {
      enable = true;
      package = rocmPkgs.llama-cpp;
      rocmGpuTargets = [ "gfx1010" ];

      host = "0.0.0.0";
      port = 8096;
      contextSize = 8192;
      flashAttention = "on";
      enableMetrics = true;
      openFirewall = true;

      inherit (selected.small) hfRepo hfFile;
      environment.ROCR_VISIBLE_DEVICES = "1";
    };

  } // cpuInstances;
}
