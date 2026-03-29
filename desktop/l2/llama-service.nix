#
# llama-cpp CUDA test configuration for RTX 3070
#
# Test:  curl http://localhost:8090/health
# Logs:  journalctl -u llama-cpp-rtx3070 -f
#
# To update the local repo
# nix flake update nixpkgs-local

{ config, lib, pkgs, nixpkgs-local, ... }:

let
  localPkgs = import nixpkgs-local {
    system = "x86_64-linux";
    config.allowUnfree = true;
    config.cudaSupport = true;
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
      hfRepo = "Qwen/Qwen2.5-3B-Instruct-GGUF";
      hfFile = "qwen2.5-3b-instruct-q4_k_m.gguf";
    };
  }) (lib.range 1 4));
in {
  disabledModules = [ "services/misc/llama-cpp.nix" ];
  imports = [ "${nixpkgs-local}/nixos/modules/services/misc/llama-cpp.nix" ];

  services.llama-cpp.instances = {

    # RTX 3070: 8GB VRAM - small model for testing
    rtx3070 = {
      enable = true;
      package = localPkgs.llama-cpp;

      host = "0.0.0.0";
      port = 8090;
      contextSize = 8192;
      flashAttention = "on";
      enableMetrics = true;
      openFirewall = true;

      hfRepo = "Qwen/Qwen2.5-3B-Instruct-GGUF";
      hfFile = "qwen2.5-3b-instruct-q4_k_m.gguf";
    };

  } // cpuInstances;
}
