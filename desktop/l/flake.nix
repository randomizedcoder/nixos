{
  description = "l Flake";

  # https://nix.dev/manual/nix/2.24/command-ref/new-cli/nix3-flake.html#flake-inputs
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

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
  outputs = { self, nixpkgs, home-manager, ... }:
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
        };
        modules = [
          ./configuration.nix
          #hyprland.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            # Apply the overlay to NixOS
            nixpkgs.overlays = [
              (final: prev: {
                onnxruntime = final.callPackage ./custom-packages/onnxruntime/package.nix {
                  rocmSupport = true;
                  rcclSupport = true;
                };
                python313Packages = prev.python313Packages.override (old: {
                  overrides = prev.lib.composeManyExtensions [
                    (final: prev: {
                      onnxruntime = final.callPackage ./custom-packages/python-onnxruntime/default.nix {
                        onnxruntime = final.onnxruntime;
                      };
                    })
                    old.overrides or (final: prev: { })
                  ];
                });
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
