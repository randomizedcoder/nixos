#
# latops/t/distributed-builds.nix
#
# https://nix.dev/tutorials/nixos/distributed-builds-setup.html#set-up-distributed-builds
# https://docs.nixbuild.net/getting-started/#quick-nixos-configuration
{ pkgs, ... }:
{
  nix.distributedBuilds = true;
  nix.settings.builders-use-substitutes = true;

  nix.buildMachines = [
    {
      hostName = "hp4.home";
      sshUser = "remotebuild";
      sshKey = "/root/.ssh/remotebuild";
      system = pkgs.stdenv.hostPlatform.system;
      maxJobs = 100;
      supportedFeatures = [ "nixos-test" "big-parallel" "kvm" ];
    }
  ];
}

# https://docs.nixbuild.net/getting-started/#your-first-build
# nix-build \
#   --max-jobs 0 \
#   --builders "ssh://hp4 x86_64-linux - 100 1 big-parallel,benchmark" \
#   -I nixpkgs=channel:nixos-20.03 \
#   --expr '((import <nixpkgs> {}).runCommand "test${toString builtins.currentTime}" {} "echo Hello nixbuild.net; touch $out")'