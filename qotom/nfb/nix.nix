#
# qotom/nfb/nix.nix
#
{ config, ... }:

{
  # https://nixos.wiki/wiki/Nix_Cookbook
  nix = {
    nrBuildUsers = 64;
    settings = {
      auto-optimise-store = true;
      #experimental-features = [ "nix-command" "flakes" ];
      experimental-features = [ "nix-command" "flakes" "configurable-impure-env" ];
      #impure-env = "GOPROXY=http://localhost:3000";
      #impure-env = "GOPROXY=http://localhost:8888";

      download-buffer-size = "100000000";

      # https://nix.dev/tutorials/nixos/distributed-builds-setup.html#set-up-the-remote-builder
      # https://nix.dev/tutorials/nixos/distributed-builds-setup.html#optimise-the-remote-builder-configuration
      # https://nix.dev/manual/nix/2.23/command-ref/conf-file
      #trusted-users = [ "remotebuild" ]; # this moved to remote-builder.nix

      min-free = 10 * 1024 * 1024;
      max-free = 200 * 1024 * 1024;
      max-jobs = "auto";
      cores = 0;

      #nix.settings.experimental-features = [ "configurable-impure-env" ];
      #nix.settings.impure-env = "GOPROXY=http://localhost:3000";
    };

    gc = {
      automatic = true;                  # Enable automatic execution of the task
      dates = "weekly";                  # Schedule the task to run weekly
      options = "--delete-older-than 10d";  # Specify options for the task: delete files older than 10 days
      randomizedDelaySec = "14m";        # Introduce a randomized delay of up to 14 minutes before executing the task
    };
  };
}