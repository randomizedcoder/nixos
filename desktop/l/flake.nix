{ 
  description = "l Flake";

  # https://nix.dev/manual/nix/2.24/command-ref/new-cli/nix3-flake.html#flake-inputs
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Local nixpkgs for testing llama-cpp module changes
    nixpkgs-local.url = "path:/home/das/Downloads/nixpkgs";

    # Local nixpkgs for onnxruntime ROCm + obs-backgroundremoval
    nixpkgs-onnx.url = "path:/home/das/Downloads/onnx/nixpkgs";

    # Local nixpkgs for OBS plugin updates
    nixpkgs-obs.url = "path:/home/das/Downloads/n/nixpkgs";

    # Local nixpkgs for testing PCP package and module
    #nixpkgs-pcp.url = "path:/home/das/Downloads/n/nixpkgs";

    # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # hyprland.url = "github:hyprwm/Hyprland";
    # hyprland-plugins = {
    #   url = "github:hyprwm/hyprland-plugins";
    #   inputs.hyprland.follows = "hyprland";
    # };
  };

  #outputs = inputs@{ nixpkgs, home-manager, hyprland, ... }:
  #outputs = { self, nixpkgs, home-manager, hyprland, ... }:
  #outputs = { self, nixpkgs, nixpkgs-local, nixpkgs-pcp, home-manager, ... }:
  outputs = { self, nixpkgs, nixpkgs-local, nixpkgs-onnx, nixpkgs-obs, home-manager, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
            # "nvidia-x11"
            # "nvidia-settings"
            # "nvidia-persistenced"
            "google-chrome"
            "android-studio"
            "android-studio-stable"
            "vscode"
            ];
        };
      };
      lib = nixpkgs.lib;
    in {
    nixosConfigurations = {
      l = lib.nixosSystem rec {
        inherit system;
        specialArgs = {
          unstable = pkgs;
          inherit nixpkgs-local;
        };
        modules = [
          ./configuration.nix
          # PCP module from local nixpkgs-pcp
          #(nixpkgs-pcp + "/nixos/modules/services/monitoring/pcp.nix")
          #{ nixpkgs.overlays = [ (final: prev: {
          #    pcp = (import nixpkgs-pcp { system = system; }).pcp;
          #  })];
          #}
          #hyprland.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            nixpkgs.overlays = [
              (final: prev:
                let
                  pkgsRocm = import nixpkgs-onnx {
                    system = "x86_64-linux";
                    config = prev.config // { rocmSupport = true; };
                  };
                  pkgsObs = import nixpkgs-obs {
                    system = "x86_64-linux";
                    config = prev.config;
                  };
                in {
                  onnxruntime = pkgsRocm.onnxruntime;
                  obs-studio-plugins = prev.obs-studio-plugins // {
                    obs-backgroundremoval = pkgsRocm.obs-studio-plugins.obs-backgroundremoval;
                    # Plugin updates from nixpkgs-obs
                    obs-move-transition = pkgsObs.obs-studio-plugins.obs-move-transition;
                    obs-source-clone = pkgsObs.obs-studio-plugins.obs-source-clone;
                    obs-stroke-glow-shadow = pkgsObs.obs-studio-plugins.obs-stroke-glow-shadow;
                    obs-multi-rtmp = pkgsObs.obs-studio-plugins.obs-multi-rtmp;
                    advanced-scene-switcher = pkgsObs.obs-studio-plugins.advanced-scene-switcher;
                    obs-livesplit-one = pkgsObs.obs-studio-plugins.obs-livesplit-one;
                  };
                })
            ];

            # Allow unfree packages
            nixpkgs.config.allowUnfree = true;
            nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
              "google-chrome"
              "android-studio"
              "android-studio-stable"
              "vscode"
            ];

            # https://nix-community.github.io/home-manager/nixos-options.xhtml#nixos-opt-home-manager.useGlobalPkgs
            home-manager.useGlobalPkgs = true; # This disables the Home Manager options nixpkgs.*.
            home-manager.useUserPackages = true;
            home-manager.users.das = { config, pkgs, ... }: {
              imports = [
                ./home.nix
              ];
            };
            home-manager.extraSpecialArgs = specialArgs;
            # see also: https://github.com/HeinzDev/Hyprland-dotfiles/blob/main/flake.nix
          }
        ];
      };
    };
  };
}
