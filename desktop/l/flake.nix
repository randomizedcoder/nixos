{ 
  description = "l Flake";

  # https://nix.dev/manual/nix/2.24/command-ref/new-cli/nix3-flake.html#flake-inputs
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Local nixpkgs for onnxruntime ROCm + obs-backgroundremoval
    #nixpkgs-onnx.url = "path:/home/das/Downloads/onnx/nixpkgs";

    # Local nixpkgs for OBS plugin updates
    #nixpkgs-obs.url = "path:/home/das/Downloads/n/nixpkgs";

    # Local nixpkgs for testing PCP package and module
    #nixpkgs-pcp.url = "path:/home/das/Downloads/n/nixpkgs";

    # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management — encrypts files with age + ssh-ed25519 keys
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # xdp2 — provides nixosModules.physical-testbed (NIC tuning, CPU
    # isolation, static testbed addressing) for the l <-> l2 25 GbE
    # perf-testing pair. Points at the LOCAL checkout because l uses the
    # new xdp2.testbed.dedicatedHost = false generator-lite option, which
    # is not yet on the pushed branch. Once it merges, switch to:
    #   xdp2.url = "github:randomizedcoder/xdp2/flow-keys-compat-reorder";
    xdp2 = {
      url = "git+file:///home/das/Downloads/xdp2";
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
  #outputs = { self, nixpkgs, nixpkgs-local, nixpkgs-onnx, nixpkgs-obs, home-manager, ... }:
  outputs = inputs@{ self, nixpkgs, home-manager, agenix, xdp2, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
            "nvidia-x11"
            "nvidia-settings"
            "nvidia-persistenced"
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
          inherit agenix;
          inherit inputs;
        };
        modules = [
          ./configuration.nix
          agenix.nixosModules.default
          # xdp2 physical-testbed: NIC tuning + static testbed addressing
          # for the 25 GbE l <-> l2 pair. Options set in configuration.nix
          # (xdp2.testbed generator-lite profile).
          xdp2.nixosModules.physical-testbed
          # PCP module from local nixpkgs-pcp
          #(nixpkgs-pcp + "/nixos/modules/services/monitoring/pcp.nix")
          #{ nixpkgs.overlays = [ (final: prev: {
          #    pcp = (import nixpkgs-pcp { system = system; }).pcp;
          #  })];
          #}
          #hyprland.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            #nixpkgs.overlays = [
            #  (final: prev:
            #    let
            #    in {
            #      };
            #    })
            #];

            # Allow unfree packages
            nixpkgs.config.allowUnfree = true;
            nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
              "nvidia-x11"
              "nvidia-settings"
              "nvidia-persistenced"
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
