#
# llama-cpp multi-GPU configuration for l2
#
# Instances:
#   llama-cpp-mi50    - MI50 (ROCm gfx906, 32GB), port 8095
#   llama-cpp-w5700   - W5700 (ROCm gfx1010, 8GB), port 8096
#   llama-cpp-cpu-1..4 - CPU-only, ports 8091-8094
#
# GPU device mapping (rocm-smi) — updated 2026-07-04:
#   Under kernel 7.2-rc1 the WX 2100 (gfx803) is no longer enumerated by the
#   ROCm runtime, so indices collapsed. ROCm now sees only two devices:
#   Device 0: W5700 (gfx1010, 8GB, PCI 0000:44:00.0)  - ROCR_VISIBLE_DEVICES=0
#   Device 1: MI50  (gfx906, 32GB, PCI 0000:63:00.0)  - ROCR_VISIBLE_DEVICES=1
#   (Previously WX2100=0, W5700=1, MI50=2. The old indices below pointed the
#   MI50 service at a non-existent index 2 -> "no ROCm-capable device" -> CPU.)
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
# Packages come from main nixpkgs (pkgs.path). The multi-instance module is
# vendored at ./llama-cpp-multi-instance.nix — no nixpkgs-local fork needed.

{ config, lib, pkgs, ... }:

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

  # Previous: built llama-cpp from nixpkgs-local fork at
  # /home/das/Downloads/nixpkgs. That fork lagged main nixpkgs
  # (rocm-runtime 7.2.0 vs 7.2.3 in main as of 2026-06-14). The
  # multi-instance services.llama-cpp.instances module is still
  # fork-only and remains imported above; only the *package* moves
  # to main nixpkgs.
  #rocmPkgs = import nixpkgs-local {
  #  system = "x86_64-linux";
  #  config.allowUnfree = true;
  #  config.rocmSupport = true;
  #};
  #cpuPkgs = import nixpkgs-local {
  #  system = "x86_64-linux";
  #  config.allowUnfree = true;
  #};
  # 2026-06-14: re-import the flake's nixpkgs (via pkgs.path) so
  # llama-cpp picks up ROCm 7.2.3 from main nixpkgs. NOTE: this
  # re-import does NOT carry flake.nix's rocm-runtime doorbell-type
  # overlay — but gfx803 (WX 2100) is masked off below via
  # ROCR_VISIBLE_DEVICES, so the unpatched HSA path is never hit
  # by either llama-cpp instance.
  rocmPkgs = import pkgs.path {
    system = "x86_64-linux";
    config.allowUnfree = true;
    config.rocmSupport = true;
  };

  cpuPkgs = import pkgs.path {
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
  # Replace mainline's single-instance services.llama-cpp with the vendored
  # multi-instance module (copied from the old nixpkgs fork; self-contained
  # NixOS glue, no fork packages/patches). The llama-cpp *packages* come from
  # main nixpkgs via pkgs.path above.
  disabledModules = [ "services/misc/llama-cpp.nix" ];
  imports = [ ./llama-cpp-multi-instance.nix ];

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
      environment.ROCR_VISIBLE_DEVICES = "1";
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
      environment.ROCR_VISIBLE_DEVICES = "0";
    };

  } // cpuInstances;
}
