#
# /hp/hp4/remote-builder.nix
#
{ pkgs, config, ... }:
{
  # https://nix.dev/tutorials/nixos/distributed-builds-setup.html#set-up-the-remote-builder
  # sudo ssh remotebuild@hp4 -i /root/.ssh/remotebuild "echo hello"
  # sudo ssh remotebuild@hp4.home -i /root/.ssh/remotebuild "echo hello"
  users.users.remotebuild = {
    isNormalUser = true;
    createHome = false;
    group = "remotebuild";

    # openssh.authorizedKeys.keyFiles = [ ./authorizedKeys ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINjiY/MIQUyp58JXt+fuy1mQWCZfFhbYoRK6jJN5ZxeV root@t"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMO7liZykpeI/ggPRBXQswdLAZWNWj+h8QA3hzQLi0ai das@hp1"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIBUWTELKL25XhSi+le+KNqaeAQvZ4Sh0/+lmRpiJzKn root@l"
    ];
  };

  users.groups.remotebuild = {};

  # https://nix.dev/tutorials/nixos/distributed-builds-setup.html#optimise-the-remote-builder-configuration
  # nix.settings.trusted-users = [ "remotebuild" ];
  nix = {
    nrBuildUsers = 64;
    settings = {
      trusted-users = [ "remotebuild" ];

      min-free = 10 * 1024 * 1024;
      max-free = 200 * 1024 * 1024;

      max-jobs = "auto";
      cores = 0;
    };
  };

  systemd.services.nix-daemon.serviceConfig = {
    MemoryAccounting = true;
    MemoryMax = "90%";
    OOMScoreAdjust = 500;
  };
}
