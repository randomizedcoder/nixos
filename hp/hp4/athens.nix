{ pkgs, config, ... }:
{
  services.athens = {
    enable = true;
    #openFirewall = true; # this doesn't exist any more?
    port = 8888;
    logLevel = "debug";
    # storageType = "disk"; # disk is default
    # diskStorageRoot = "/var/lib/athens";
    #goBinary = unstable.go;
    # https://mynixos.com/nixpkgs/option/services.athens.goBinary
    goGetWorkers = 32; # default 10
    indexType = "memory"; # default none
    statsExporter = "prometheus";
  };
  # https://mynixos.com/nixpkgs/options/services.athens
  # https://github.com/ditsuke/nixpkgs-compat/blob/master/nixos/modules/services/development/athens.md
  # https://github.com/ditsuke/nixpkgs-compat/blob/master/nixos/modules/services/development/athens.nix
  # journalctl -u athens.service -f
}