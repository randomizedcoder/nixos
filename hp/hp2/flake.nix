{
  description = "HP2 Flake";

  inputs = {
    # Converged with hp5 on nixos-unstable so both benchmark hosts run
    # matching kernels (xdp2 docs/physical-testbed.md §3, 2026-04-20).
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
    home-manager = {
      url = "github:nix-community/home-manager/master";
      # The `follows` keyword in inputs is used for inheritance.
      # Here, `inputs.nixpkgs` of home-manager is kept consistent with
      # the `inputs.nixpkgs` of the current flake,
      # to avoid problems caused by different versions of nixpkgs.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # xdp2 provides nixosModules.physical-testbed for the benchmark-host
    # tuning (kernel params, NIC ethtool, IRQ pinning, noise suppression).
    # See xdp2 docs/physical-testbed.md §5–§7.
    # After pushing new xdp2 changes, refresh on hp2 with:
    #   nix flake update xdp2 && sudo nixos-rebuild switch --flake .#hp2
    xdp2 = {
      # merge/matrix-physical-testbed carries the nic-tuning module split
      # (xdp2.nicTuning.driver option, mlx5_core branch). Matches hp1/hp3.
      # Flip back to xdp2-rs / main once that branch is merged forward.
      url = "github:randomizedcoder/xdp2/merge/matrix-physical-testbed";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # uds-rdma-proxy provides nixosModules.urp: builds urp.ko against this
    # host's kernel (linuxPackages_latest), loads the RDMA stack, and
    # materialises the declarative urp endpoints (design 32 real-hardware
    # integration). Added 2026-08-31 when hp2 joined the RoCEv2 mesh.
    # Refresh after pushing new urp changes with:
    #   nix flake update uds-rdma-proxy && sudo nixos-rebuild switch --flake .#hp2
    uds-rdma-proxy = {
      url = "github:randomizedcoder/uds-rdma-proxy/main";
      inputs.nixpkgs.follows = "nixpkgs";
      # NB: do NOT `follows`-prune redpanda/microvm. nixosModules.urp forces
      # the flake's `packages` attrset (for urp-cli), which spreads in
      # `microvms.packages` and `redpandaUdsTest`; those guards are not
      # follows-safe, so pruning breaks eval. Both inputs are only *fetched*
      # (source), never built into this host's closure.
    };
  };

  outputs = inputs@{ nixpkgs, home-manager, xdp2, uds-rdma-proxy, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = { allowUnfree = true; };
      };
      lib = nixpkgs.lib;
    in {
    nixosConfigurations = {
      hp2 = lib.nixosSystem {
        #system ="x86_64-linux";
        inherit system;
        modules = [
          ./configuration.nix
          xdp2.nixosModules.physical-testbed
          uds-rdma-proxy.nixosModules.urp
          uds-rdma-proxy.nixosModules.urp-exporter
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.das = import ./home.nix;

            # Optionally, use home-manager.extraSpecialArgs to pass
            # arguments to home.nix
          }
        ];
      };
    };
  };
}
