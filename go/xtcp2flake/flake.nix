{
  description = "minimalist Configurable Homelab Start Page";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05";
  };

  outputs = {nixpkgs, ...}: let
    # you can also put any architecture you want to support here
    # i.e. aarch64-darwin for never M1/2 macbooks
    system = "x86_64-linux";
    pname = "float";
  in {
    packages.${system} = let
      pkgs = nixpkgs.legacyPackages.${system}; # this gives us access to nixpkgs as we are used to
    in {
      default = pkgs.buildGoModule {
        name = pname;
        src = fetchFromGitHub {
          owner = "randomizedcoder";
          repo = "xtcp2";
          rev = "latest";
          #rev = "v2.0.0";
          sha256 = pkgs.lib.fakeSha256;
        };

        vendorSha256 = pkgs.lib.fakeSha256;
      };
    };
  };
}