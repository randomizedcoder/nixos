#
# ollama
#
# HIP_VISIBLE_DEVICES=GPU-0e54792172da5eeb OLLAMA_CONTEXT_LENGTH=131072 ollama serve
#
# https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/misc/ollama.nix
#

#sudo rocm-smi --showmeminfo vram 2>&1 && echo && journalctl -u ollama --since "5 minutes ago" 2>&1 | grep -iE "(gpu|rocm|hip|memory|gfx|found|detect|vram)" | head -20

{ config, lib, pkgs, ... }:

let
  mi50euid = "GPU-0e54792172da5eeb";
  # Context length determines how much text the model can "see" at once
  # KV cache memory scales linearly with context: 128k ≈ 14GB, 192k ≈ 21GB, 256k ≈ 28GB
  # With 32GB VRAM: 128k works for most models, but 32b+ models (19GB) barely fit
  # Native limits: llama3.2=128k, codellama=16-100k, qwen2.5-coder=32-128k
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
    #port = 11435;

    # acceleration option was removed - use package instead
    # See: https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/misc/ollama.nix
    package = pkgs.ollama-rocm;

    environmentVariables = {
      HIP_VISIBLE_DEVICES = mi50euid;
      OLLAMA_CONTEXT_LENGTH = ctxLength;
      # OLLAMA_DEBUG = "1";
      # AMD_LOG_LEVEL = "3";
    };

    # https://github.com/ollama/ollama/blob/main/docs/troubleshooting.md#amd-gpu-discovery


    # sudo systemctl status ollama-model-loader.service
    # sudo systemctl restart ollama-model-loader.service

    # ollama list

    loadModels = [
      "gpt-oss:latest"
      #https://ollama.com/library/nemotron-3-nano
      "nemotron-3-nano:latest"
      "nomic-embed-text:latest"
      "codellama:34b"
      #"codellama:13b"
      #"codellama:7b"
      #"llama3.2:latest"
      #"llama3.2:3b"                     # https://ollama.com/library/llama3.2
      #"llama4:latest" # too big!
      #"gpt-oss:20b"
      #"deepseek-r1:32b"
      #"deepseek-r1:1.5b"
      "llama3-groq-tool-use:70b-q2_K"
      "qwen2.5-coder:32b"
      "qwen3-coder:30b"
      "gpt-oss:20b" # https://ollama.com/library/gpt-oss
      #"gemini-3-flash-preview:latest" # https://ollama.com/library/gemini-3-flash-preview
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

# rocminfo 2>&1 | grep -i -E '(agent|name|uuid)'

# [das@l:~/nixos/desktop/l]$ systemctl restart ollama-model-loader.service

# [das@l:~/nixos/desktop/l]$ systemctl status ollama-model-loader.service
# ○ ollama-model-loader.service - Download ollama models in the background
#      Loaded: loaded (/etc/systemd/system/ollama-model-loader.service; enabled; preset: ignored)
#      Active: inactive (dead) since Fri 2025-09-12 11:29:58 PDT; 5s ago
#    Duration: 413ms
#  Invocation: 54354297f7de43299bbebd26460adefe
#     Process: 551044 ExecStart=/nix/store/if3rc0z8v3f1h468klz4varj3jgn7isc-unit-script-ollama-model-loader-start/bin/ollama-model-loader-start (code=exited, status=0/SUCCESS)
#    Main PID: 551044 (code=exited, status=0/SUCCESS)
#          IP: 16.9K in, 12.9K out
#          IO: 0B read, 0B written
#    Mem peak: 60.8M
#         CPU: 184ms

# Sep 12 11:29:58 l ollama-model-loader-start[551054]: [122B blob data]
# Sep 12 11:29:58 l ollama-model-loader-start[551054]: [122B blob data]
# Sep 12 11:29:58 l ollama-model-loader-start[551054]: [122B blob data]
# Sep 12 11:29:58 l ollama-model-loader-start[551054]: [122B blob data]
# Sep 12 11:29:58 l ollama-model-loader-start[551054]: [122B blob data]
# Sep 12 11:29:58 l ollama-model-loader-start[551054]: [27B blob data]
# Sep 12 11:29:58 l ollama-model-loader-start[551054]: [20B blob data]
# Sep 12 11:29:58 l ollama-model-loader-start[551054]: [25B blob data]
# Sep 12 11:29:58 l systemd[1]: ollama-model-loader.service: Deactivated successfully.
# Sep 12 11:29:58 l systemd[1]: ollama-model-loader.service: Consumed 184ms CPU time, 60.8M memory peak, 16.9K incoming IP traffic, 12.9K outgoing IP traffic.

# [das@l:~/nixos/desktop/l]$ ollama list
# NAME                             ID              SIZE      MODIFIED
# llama3.2:3b                      a80c4f17acd5    2.0 GB    14 seconds ago
# llama3.2:latest                  a80c4f17acd5    2.0 GB    14 seconds ago
# nomic-embed-text:latest          0a109f422b47    274 MB    14 seconds ago
# qwen2.5-coder:32b                b92d6a0bd47e    19 GB     14 seconds ago
# codellama:34b                    685be00e1532    19 GB     14 seconds ago
# deepseek-r1:32b                  edba8017331d    19 GB     14 seconds ago
# gpt-oss:20b                      aa4295ac10c3    13 GB     14 seconds ago
# llama3-groq-tool-use:70b-q2_K    dab8a158f092    26 GB     14 seconds ago

# [das@l:~/nixos/desktop/l]$

# [das@l:~/nixos/desktop/l]$ rocm-smi --alldevices --showallinfo


# ============================ ROCm System Management Interface ============================
# ============================== Version of System Component ===============================
# Driver version: 6.16.5
# ==========================================================================================
# =========================================== ID ===========================================
# GPU[0]          : Device Name:          TBD VEGA20 CARD
# GPU[0]          : Device ID:            0x66a1
# GPU[0]          : Device Rev:           0x00
# GPU[0]          : Subsystem ID:         0x1002
# GPU[0]          : GUID:                 33678
# GPU[1]          : Device Name:          0x1002
# GPU[1]          : Device ID:            0x7312
# GPU[1]          : Device Rev:           0x00
# GPU[1]          : Subsystem ID:         0x1002
# GPU[1]          : GUID:                 11012
