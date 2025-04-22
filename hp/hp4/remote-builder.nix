#
# /hp/hp4/remote-builder.nix
#
{ pkgs, config, ... }:
{
  # https://nix.dev/tutorials/nixos/distributed-builds-setup.html#set-up-the-remote-builder
  # sudo ssh remotebuild@hp4 -i /root/.ssh/remotebuild "echo hello"
  users.users.remotebuild = {
    isNormalUser = true;
    createHome = false;
    group = "remotebuild";

    openssh.authorizedKeys.keyFiles = [ ./authorizedKeys ];
  };

  users.groups.remotebuild = {};

  nix.settings.trusted-users = [ "remotebuild" ];
}