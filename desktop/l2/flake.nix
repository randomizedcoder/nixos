#
# l2/flake.nix
#
{
  description = "l2 Flake";

  # https://nix.dev/manual/nix/2.24/command-ref/new-cli/nix3-flake.html#flake-inputs
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    #nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";

    # Local nixpkgs for testing llama-cpp module
    nixpkgs-local.url = "path:/home/das/Downloads/nixpkgs";

    # Custom nix with build telemetry
    nix-custom.url = "path:/home/das/Downloads/nix";
    nix-custom.inputs.nixpkgs.follows = "nixpkgs";

    # https://nixos-and-flakes.thiscute.world/nixos-with-flakes/start-using-home-manager
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # https://github.com/nix-community/disko/
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # CrowdSec - now in nixpkgs, third-party flake no longer needed
    # crowdsec = {
    #   url = "git+https://codeberg.org/kampka/nix-flake-crowdsec.git";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # WiFi TSF synchronisation — upstream mt76 PTP patches + daemon
    tsf-sync = {
      url = "github:randomizedcoder/tsf-sync/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # xdp2 physical-testbed NixOS module: CPU isolation, IRQ pinning,
    # NIC tuning, hugepages, lowJitter, disableNonEssentialServices.
    # flow-keys-compat-reorder branch (replaces the old xdp2-rs branch,
    # which predated the xdp2.nicTuning option needed for the mlx5_core
    # driver selection in configuration.nix). GitHub ref so the input
    # resolves identically on l and l2 (a machine-local git+file path
    # only exists on the host where the repo is checked out).
    xdp2 = {
      url = "github:randomizedcoder/xdp2/flow-keys-compat-reorder";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-local, disko, home-manager, nix-custom, tsf-sync, xdp2, ... }@inputs:
    let
      system = "x86_64-linux";

      lib = nixpkgs.lib;

      # Intel WiFi hostapd overlay (commented out - using default hostapd for MediaTek MT7915e)
      # overlays = {
      #   default = final: prev: {
      #     hostapd = prev.hostapd.overrideDerivation (old: {
      #       version = "2.10";
      #       src = final.fetchurl {
      #         url = "https://w1.fi/releases/hostapd-2.10.tar.gz";
      #         sha256 = "0pcik0a6yin9nib02frjhaglmg44hwik086iwg1751b7kdwpqvi0";
      #         # nix-prefetch-url https://w1.fi/releases/hostapd-2.10.tar.gz
      #       };
      #       patches = [
      #         (final.fetchpatch {
      #           url = "https://tildearrow.org/storage/hostapd-2.10-lar.patch";
      #           sha256 = "USiHBZH5QcUJfZSxGoFwUefq3ARc4S/KliwUm8SqvoI=";
      #         })
      #       ];
      #     });
      #   };
      # };

      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          # Patch rocm-runtime to fix multi-GPU init failure (fix-doorbell-type-exception)
          # GPUs with deprecated doorbell type (e.g. gfx803/Polaris) were aborting hsa_init()
          # for ALL devices. This patch makes them gracefully skipped instead.
          (final: prev: {
            rocmPackages = prev.rocmPackages.overrideScope (rfinal: rprev: {
              rocm-runtime = rprev.rocm-runtime.overrideAttrs (old: {
                patches = (old.patches or []) ++ [
                  ./fix-doorbell-type-exception.patch
                ];
              });
            });
          })
          # FIXME: nix-custom 2.35.0pre fails to build against newer lowdown
          # (LOWDOWN_TERM_NORELLINK renamed to LOWDOWN_NORELLINK).
          # Re-enable after updating /home/das/Downloads/nix.
          # (final: prev:
          #   let
          #     ps = nix-custom.lib.makeComponents { pkgs = final; };
          #   in {
          #     nix = (ps.nix-everything.overrideAttrs (old: {
          #       doCheck = false;
          #     }));
          #   }
          # )
        ];
        config.allowUnfree = true;
      };

    in {
      nixosConfigurations = {
        l2 = lib.nixosSystem {

          inherit system;

          specialArgs = { inherit nixpkgs-local inputs; };

          modules = [
            disko.nixosModules.disko
            # CrowdSec now in nixpkgs - use services.crowdsec in configuration.nix if needed
            # crowdsec.nixosModules.crowdsec
            # crowdsec.nixosModules.crowdsec-firewall-bouncer
            # xdp2 physical-testbed: same module hp5 uses; configured
            # via xdp2.testbed = { ... } in configuration.nix.
            xdp2.nixosModules.physical-testbed
            ./configuration.nix
            {
              nixpkgs.pkgs = pkgs;
            }
            home-manager.nixosModules.home-manager
            {
              home-manager.useUserPackages = true;
              home-manager.users.das = { config, pkgs, ... }: {
                imports = [ ./home.nix ];
              };
            }
          ];
        };
      };
    };
}

# end