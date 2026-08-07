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
      # Qwen3-30B-A3B-Instruct-2507 — the qwen that ACTUALLY tool-calls through the
      # pinned llama.cpp (b9503) OpenAI-compat endpoint with `--jinja`. Verified live on
      # the MI50 (Vulkan): a write_file request returns structured `tool_calls` with the
      # correct `arguments` key — exactly what agent-seddon (OpenAI-compat) consumes.
      #
      # Why NOT the Coder variant: Qwen3-*Coder*-30B emits its tool calls in the custom
      # `<function=…><parameter=…>` XML format, and the parser for that format postdates
      # our pinned llama.cpp b9503 — so `--jinja` returns `tool_calls: null` and the agent
      # writes no files (empirically confirmed on this exact build). Qwen3-*Instruct* uses
      # the standard `<tool_call>`-wrapped JSON that b9503 parses today. To go back to the
      # Coder you must bump llama.cpp to a build carrying the `<function=>` parser (a
      # nixpkgs flake bump — bigger blast radius), then re-verify tool_calls.
      #
      # Instruct-2507 is a strong general 30B-A3B MoE (good, if not specialist, at code)
      # and is ALREADY in the MI50 cache. ~18GB at Q4_K_M — fits 32GB with KV headroom.
      #   history: Qwen2.5-Coder-32B (great coder, bare-JSON tool calls, unparseable);
      #            Qwen3-Coder-30B (custom XML tool calls, needs newer llama.cpp).
      large = { hfRepo = "unsloth/Qwen3-30B-A3B-Instruct-2507-GGUF"; hfFile = "Qwen3-30B-A3B-Instruct-2507-Q4_K_M.gguf"; }; # ~18GB, tool-calls on b9503
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
  # NOTE (2026-07-05): the doorbell overlay was REMOVED — it was the wrong fix.
  # The WX2100 (gfx803) is physically gone (display is now an NVIDIA P620), and
  # the actual crash is a SIGSEGV at HIP `getDeviceKernel` during model warmup
  # (see coredump), i.e. ROCm 7.2.3's runtime cannot launch kernels on the
  # legacy gfx906 (MI50) / gfx1010 (W5700) GPUs. Fix is a ROCm rollback or a
  # switch to the Vulkan backend — see docs/pipeline notes.
  rocmPkgs = import pkgs.path {
    system = "x86_64-linux";
    config.allowUnfree = true;
    config.rocmSupport = true;
  };

  cpuPkgs = import pkgs.path {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };

  # Vulkan (RADV) llama.cpp for the MI50 (gfx906). ROCm 7.2.3 SIGSEGVs at HIP
  # getDeviceKernel on gfx906 (see the note above + ollama-service.nix), so the
  # GPU instances must NOT use the ROCm package on this card. The Vulkan backend
  # drives the DRM render node directly and WORKS on gfx906 — this is the same
  # backend ollama-vulkan uses for the MI50. Select the card with
  # GGML_VK_VISIBLE_DEVICES (index 1 = MI50; index 0 = the P620 display GPU).
  vulkanLlamaCpp = pkgs.llama-cpp.override { vulkanSupport = true; };

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

    # MI50: 32GB VRAM — uses "large" model from selected mode, over VULKAN (not ROCm,
    # which crashes on gfx906). `jinja = "on"` enables llama.cpp's chat-template tool
    # parsing so the OpenAI-compat endpoint returns structured tool_calls — the whole
    # point of moving the coder here (ollama's /v1 parser can't do it for qwen).
    #
    # GPU SHARING: the MI50 is also driven by ollama-vulkan (ollama-service.nix). The
    # 32GB holds ONE ~18-20GB coder at a time — so with llama.cpp resident here, keep
    # ollama to embeddings/small (its KEEP_ALIVE unloads idle models). Running a big
    # model on BOTH at once will OOM the card.
    mi50 = {
      enable = true;
      package = vulkanLlamaCpp;

      host = "0.0.0.0";
      port = 8095;
      contextSize = 32768;
      flashAttention = "on";
      enableMetrics = true;
      openFirewall = true;

      # `--jinja` turns on llama.cpp's chat-template tool-call parsing (there is no
      # dedicated `jinja` instance option — it goes through extraFlags).
      extraFlags = [ "--jinja" ];

      inherit (selected.large) hfRepo hfFile;
      # Select the MI50 (Vulkan index 1); exclude the P620 display GPU (index 0).
      environment.GGML_VK_VISIBLE_DEVICES = "1";
    };

    # W5700 (gfx1010) instance removed — the card was faulty and has been pulled.
    # CPU instances (`cpuInstances`) are not wired in: this host's only job here is
    # the MI50 Vulkan coder above. Re-add `// cpuInstances` to bring them back.
  };
}
