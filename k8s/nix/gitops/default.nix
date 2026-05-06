# nix/gitops/default.nix
#
# GitOps manifest generator.
# Generates Kubernetes YAML manifests from Nix using nixidy patterns.
# Output: nix build .#k8s-manifests -> result/ directory of YAML files
#
{ pkgs, lib, nixidy ? null }:
let
  envDir = ./env;

  # Import all environment modules
  base = import (envDir + "/base.nix") { inherit pkgs lib; };
  argocd = import (envDir + "/argocd.nix") { inherit pkgs lib; };
  cilium = import (envDir + "/cilium.nix") { inherit pkgs lib; };
  clickhouse = import (envDir + "/clickhouse.nix") { inherit pkgs lib; };
  nginx = import (envDir + "/nginx.nix") { inherit pkgs lib; };
  tidb = import (envDir + "/tidb.nix") { inherit pkgs lib; };

  # Combine all manifests
  allManifests = base.manifests ++ argocd.manifests ++ cilium.manifests
    ++ clickhouse.manifests ++ nginx.manifests ++ tidb.manifests;

  # Write each manifest to a file
  manifestDerivation = pkgs.runCommand "k8s-manifests" {} ''
    mkdir -p $out

    ${lib.concatMapStringsSep "\n" (m: ''
      mkdir -p $out/$(dirname "${m.name}")
      cat > $out/${m.name} << 'MANIFEST_EOF'
    ${m.content}
    MANIFEST_EOF
    '') allManifests}

    echo "Generated ${toString (builtins.length allManifests)} manifests" > $out/README
  '';
in
{
  packages = {
    k8s-manifests = manifestDerivation;
  };
}
