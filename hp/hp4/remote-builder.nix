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
    ];
  };

  users.groups.remotebuild = {};

  nix.settings.trusted-users = [ "remotebuild" ];
}