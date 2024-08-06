##
## Copyright 2023 Joel Holdsworth
##
## Redistribution and use in source and binary forms, with or without
## modification, are permitted provided that the following conditions are met:
##
## 1. Redistributions of source code must retain the above copyright notice, this
## list of conditions and the following disclaimer.
##
## 2. Redistributions in binary form must reproduce the above copyright notice,
## this list of conditions and the following disclaimer in the documentation
## and/or other materials provided with the distribution.
##
## 3. Neither the name of the copyright holder nor the names of its contributors
## may be used to endorse or promote products derived from this software without
## specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND
## ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
## WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
## DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
## FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
## DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
## SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
## CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
## OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
## OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
##

{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in {
        packages = rec {
          default = pkgs.dockerTools.buildLayeredImage {
            name = "docker-nix-bootstrap";
            tag = "latest";

            copyToRoot = pkgs.buildEnv {
              name = "image-root";
              pathsToLink = [ "/bin" "/etc" "/tmp" "/var" ];
              paths = with pkgs; [
                bashInteractive
                cacert
                coreutils
                git
                nix
                skopeo
                (pkgs.fakeNss.override {
                  extraPasswdLines = [
                    "nixbld1:x:997:996:Nix build user 1:/var/empty:/usr/sbin/nologin"
                    "nobody:x:65534:65524:nobody:/var/empty:/bin/sh"
                  ];
                  extraGroupLines = [
                    "nixbld:x:996:nixbld1"
                    "nobody:x:65534:"
                  ];
                })
                (writeTextDir "etc/nix/nix.conf" ''
                  sandbox = false
                  experimental-features = nix-command flakes
                '')
                (writeTextDir "etc/containers/policy.json" ''
                  { "default" : [ { "type": "insecureAcceptAnything" } ] }
                '')
                (runCommand "tmp" { } "mkdir -p $out/tmp $out/var/tmp")
                dockerTools.caCertificates
              ];
            };

            config = {
              Cmd = [ "${pkgs.bashInteractive}/bin/bash" ];
              Env = [
                "NIX_PAGER=cat"
                "USER=nobody"
              ];
            };
          };
        };

        devShells = {
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              skopeo
            ];
          };
        };
      });
}

