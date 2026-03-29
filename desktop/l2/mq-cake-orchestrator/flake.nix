{
  description = "MQ-CAKE Performance Testing Orchestrator";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.buildGoModule {
          pname = "mq-cake-orchestrator";
          version = "0.1.0";
          src = ./.;
          vendorHash = "sha256-xwMzxLsWzED66ghs3f0PiQKWtuyphPRs0DCw6IFpvkg=";

          ldflags = [ "-s" "-w" ];
          subPackages = [ "cmd/orchestrator" ];

          # CGO disabled via environment
          env.CGO_ENABLED = "0";

          postInstall = ''
            mv $out/bin/orchestrator $out/bin/mq-cake-orchestrator
          '';

          meta = with pkgs.lib; {
            description = "MQ-CAKE qdisc performance testing orchestrator";
            license = licenses.mit;
            mainProgram = "mq-cake-orchestrator";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            gopls
            golangci-lint
          ];
        };
      }
    );
}
