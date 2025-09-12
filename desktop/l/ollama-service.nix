#
# ollama
#
# HIP_VISIBLE_DEVICES=GPU-0e54792172da5eeb OLLAMA_CONTEXT_LENGTH=131072 ollama serve
#
# https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/misc/ollama.nix
#

{ config, lib, pkgs, ... }:

let
  mi50euid = "GPU-0e54792172da5eeb";
  ctxLength = toString 131072; # 128k

in {

  services.open-webui = {
    enable = true;
    port = 8086; # default 8080
  };
  # https://github.com/open-webui/open-webui
  # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/misc/open-webui.nix

  services.ollama = {

    enable = true;
    host = "[::]";
    #port = 11434; # default

    acceleration = "rocm";

    environmentVariables = {
      HIP_VISIBLE_DEVICES = mi50euid;
      OLLAMA_CONTEXT_LENGTH = ctxLength;
      # OLLAMA_DEBUG = "1";
      # AMD_LOG_LEVEL = "3";
    };

    # https://github.com/ollama/ollama/blob/main/docs/troubleshooting.md#amd-gpu-discovery

    loadModels = [
      "nomic-embed-text:latest"
      "codellama:34b"
      "llama3.2:latest"
      "gpt-oss:20b"
      "deepseek-r1:32b"
      "llama3-groq-tool-use:70b-q2_K"
      "qwen2.5-coder:32b"
    ];

    # https://github.com/ollama/ollama/tree/main?tab=readme-ov-file#model-library
    # https://ollama.com/library
    #
    # https://www.marktechpost.com/2025/07/31/top-local-llms-for-coding-2025/
    #
    # https://ollama.com/library/codellama
    # https://www.hardware-corner.net/llm-database/CodeLlama/
    #
    # https://ollama.com/library/llama3.2
    #
    # https://ollama.com/library/gpt-oss
    #
    # https://ollama.com/library/deepseek-r1
    #
    # https://ollama.com/library/llama3-groq-tool-use/tags
    #
    # https://ollama.com/library/qwen2.5-coder
    #
    # [das@l:~/nixos]$ ollama list
    # NAME                       ID              SIZE      MODIFIED
    # nomic-embed-text:latest    0a109f422b47    274 MB    20 hours ago
    # codellama:latest           8fdf8f752f6e    3.8 GB    26 hours ago
    # qwq:latest                 009cb3f08d74    19 GB     2 days ago
    # llama3.1:latest            46e0c10c039e    4.9 GB    2 days ago
    # llama3.2:latest            a80c4f17acd5    2.0 GB    2 days ago
    # phi4-mini:latest           78fad5d182a7    2.5 GB    2 days ago
    # phi4:latest                ac896e5b8b34    9.1 GB    2 days ago

  };

}