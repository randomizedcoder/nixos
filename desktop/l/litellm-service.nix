{ config, lib, pkgs, ... }:

{
  services.litellm = {
    enable = true;
    host = "0.0.0.0";
    port = 4000;

    settings = {
      model_list = [
        {
          model_name = "qwen3-coder-30b";
          litellm_params = {
            model = "openai/qwen3-coder-30b";
            api_base = "http://localhost:8090/v1";
            api_key = "sk-1";
          };
        }
      ];
    };
  };
}
