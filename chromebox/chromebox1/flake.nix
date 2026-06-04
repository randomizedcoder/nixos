#
# nixos/chromebox/chromebox1/flake.nix
#
# Aligned with ~/nixos/hp/hp1/flake.nix so chromebox1 joins the xdp2
# benchmark host fleet. Differences vs the hp pattern:
#   - Keeps disko as the disk source (existing install was provisioned
#     via nixos-anywhere + disko).
#   - Drops k8nix (no kubernetes on the benchmark profile).
#
# example: https://github.com/nix-community/nixos-anywhere-examples/blob/main/flake.nix
#
{
  description = "chromebox1 Flake";

  inputs = {
    # Aligned with hp1/hp2/hp3/hp5 on nixos-unstable so the xdp2 module
    # eval works against the same nixpkgs the testbed pair uses.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # https://github.com/nix-community/disko/
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    # xdp2 provides nixosModules.physical-testbed for the benchmark-host
    # tuning. See xdp2 docs/physical-testbed.md §5–§7. On chromebox1 the
    # module is applied with peerInterfaces=[] / isolatedCpus=[] so only
    # the kernel-cmdline tunings (mitigations=off, hugepages,
    # processor.max_cstate=1, audit=0) take effect — no NIC/IRQ wiring
    # because chromebox1 has no peer DAC link.
    xdp2 = {
      # merge/matrix-physical-testbed carries the nic-tuning module
      # split. Flip back to xdp2-rs / main once that branch is merged
      # forward.
      url = "github:randomizedcoder/xdp2/merge/matrix-physical-testbed";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ nixpkgs, disko, home-manager, xdp2, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
      lib = nixpkgs.lib;
    in {
    nixosConfigurations.chromebox1 = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
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
