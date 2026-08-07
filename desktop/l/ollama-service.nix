#
# ollama — LLM inference on l's RTX 3070 (CUDA, 8GB)
#
# https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/misc/ollama.nix
#
# ⚠ THEY DO NOT COEXIST ON THIS CARD. llama-service.nix runs llama.cpp against
# the same 3070 and holds its model resident PERMANENTLY — measured at 6.3GiB of
# the 7.7GiB total, leaving 1.3GiB. Ollama then loads entirely into system RAM:
#
#   load_tensors: offloaded 0/33 layers to GPU
#   load_tensors:   CPU_Mapped model buffer size = 4685.30 MiB
#
# It still answers correctly, just far slower, and nothing announces the
# downgrade. Ollama unloading after OLLAMA_KEEP_ALIVE does not help — it is
# llama.cpp that never lets go.
#
# So pick one owner for the GPU:
#   - agent / tool-calling work  -> disable services.llama-cpp, let ollama have it
#   - llama.cpp on :8090         -> expect ollama here to be a CPU workload
# Longer term the answer is l2's 32GB MI50, once its ROCm stack is stable.
#
#   systemctl status ollama
#   ollama list
#   curl http://localhost:11434/api/tags
#
# NOTE: this file was previously written for the MI50 (32GB, ROCm) and pinned
# HIP_VISIBLE_DEVICES to it. That card now lives in l2, so the config was both
# orphaned (never imported) and wrong for this machine — every model it listed
# (codellama:34b, qwen2.5-coder:32b, llama3-groq-tool-use:70b-q2_K at 26GB)
# needs several times the VRAM l actually has. Rewritten for the 3070.

{ config, lib, pkgs, ... }:

let
  # KV-cache sizing, not a preference. llama3.1:8b Q4_K_M is ~4.9GB resident.
  # Its KV cache costs ~128KB/token (32 layers x 8 KV heads x 128 dim x 2 x fp16),
  # so 16k tokens ~= 2GB and the pair fits in 8GB with headroom. 32k would need
  # ~4GB and push the total past the card, forcing a partial CPU offload that is
  # dramatically slower. Raise this only alongside a smaller model.
  ctxLength = toString 16384;
in
{
  services.ollama = {
    enable = true;

    # RTX 3070 = NVIDIA/CUDA. The `acceleration` option was removed upstream;
    # the package selects the backend now. (l also has an AMD card, but it drives
    # the display — ollama-cuda simply will not see it.)
    package = pkgs.ollama-cuda;

    # Reachable from the LAN so l2 (and any other host) can use this endpoint.
    # There is NO authentication on this port — it is an open inference endpoint
    # for anyone who can route to it. That is consistent with llama-cpp on :8090,
    # and acceptable only because this is a private lab network.
    host = "0.0.0.0";
    # port = 11434;  # default
    openFirewall = true;

    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = ctxLength;
      # Unload after 5 minutes idle so the GPU is free for llama-cpp on :8090
      # rather than being held by a model nobody is using.
      OLLAMA_KEEP_ALIVE = "5m";
      # 8GB fits exactly one 7-8B model at a time; letting ollama try to keep two
      # resident causes thrashing instead of an honest queue.
      OLLAMA_MAX_LOADED_MODELS = "1";
      # OLLAMA_DEBUG = "1";
    };

    # Pulled in the background by ollama-model-loader.service on activation.
    #
    # THE SELECTION RULE IS VRAM. This card has 7.7GiB usable. A Q4 7-8B model is
    # ~4-5GB and fits; anything above ~6GB does not, and ollama silently falls
    # back to CPU rather than failing — you get correct answers at a fraction of
    # the speed, with nothing in the log saying "this is now a CPU workload"
    # except an `offloaded 0/33 layers to GPU` line.
    #
    # Measured 2026-07-22: 176GB of models were on disk here, 9 of 15 too big to
    # run on this card (codellama:34b 19.1GB, qwen2.5-coder:32b 19.9GB,
    # llama3-groq-tool-use:70b-q2_K 26.4GB, deepseek-r1:32b 19.9GB, …). Those are
    # MI50-era leftovers from when this file targeted a 32GB card. They belong on
    # l2, not here.
    #
    # NOTE `loadModels` only PULLS; it never removes. Declaring a short list does
    # not reclaim the disk taken by models pulled under an older config — that
    # still needs an imperative `ollama rm <name>`, as the module has no prune.
    loadModels = [
      # Verified doing real tool calls end-to-end with agent-seddon. That property
      # is the whole point and it is NOT implied by a model advertising `tools`:
      # qwen2.5-coder:7b advertises tool support and, tested twice, emitted
      # tool-call-shaped JSON as prose instead — the agent then finishes with a
      # confident answer and an empty directory. Verify any substitute on a task
      # whose result you can actually check.
      "llama3.1:latest" # 4.9GB — the default for agent work
      # Small + fast, for latency-sensitive or trivial calls.
      "llama3.2:3b" # 2.0GB
      # Embeddings — feeds agent-seddon's Embedder seam, which otherwise falls
      # back to dependency-free feature hashing.
      "nomic-embed-text:latest" # 0.3GB
    ];

    # Deliberately NOT declared, and why. Re-add on a host with the VRAM:
    #   qwen2.5-coder:32b, qwen3-coder:30b, codellama:34b, deepseek-r1:32b,
    #   gpt-oss:20b, llama3-groq-tool-use:70b-q2_K, nemotron-3-nano
    # All need 13-27GB. l2's MI50 has 32GB and would run any of them — but its
    # ROCm stack is currently crash-looping on the net-next kernel (see
    # l2/llama-service.nix), so that is blocked, not merely unconfigured.
  };
}
