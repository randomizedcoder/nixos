#
# nixos/laptops/t/flake.nix
#
# Aligned with the hp1/hp3/chromebox1 benchmark-host pattern.
# Differences from the laptop's prior config: dropped hyprland +
# hyprland-plugins inputs (no Wayland compositor on a headless
# benchmark host), dropped the nixos-24.11 + unstable-overlay
# arrangement in favor of a single nixos-unstable pin (so the xdp2
# module evaluates against the same nixpkgs the other benchmark hosts
# use).
#
{
  description = "t (Intel Comet Lake-H benchmark host) Flake";

  inputs = {
    # Aligned with hp1/hp2/hp3/hp5/chromebox1 on nixos-unstable so the
    # xdp2 module evaluates against the same nixpkgs every benchmark
    # host uses.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # xdp2 provides nixosModules.physical-testbed for the benchmark-host
    # tuning. See xdp2 docs/physical-testbed.md §5–§7. On t the module
    # is applied with peerInterfaces=[] (WiFi-only; no peer DAC link)
    # but isolatedCpus is populated (Comet Lake-H has 8c/16t — plenty
    # of room to dedicate cores).
    xdp2 = {
      # merge/matrix-physical-testbed carries the nic-tuning module
      # split. Flip back to xdp2-rs / main once that branch is merged
      # forward.
      url = "github:randomizedcoder/xdp2/merge/matrix-physical-testbed";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, xdp2, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
      lib = nixpkgs.lib;
    in {
    nixosConfigurations.t = lib.nixosSystem {
      inherit system;
      modules = [
        ./configuration.nix
        xdp2.nixosModules.physical-testbed
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.das = import ./home.nix;
        }
      ];
    };
  };
}
