# Default users and hostname for the BPI-F3 image.
#
# The default login is user `bpi` / password `bpi-f3` (yescrypt hash below).
# `das` is also created (same account we use on the other lab boards, e.g.
# arm/pi5-1) — a normal `wheel` user with the das@t SSH key, so `ssh das@bpi-f3`
# works key-only and `das` can `sudo`.
# CHANGE THIS before exposing the board to any network you don't trust.
let
  username = "bpi";
  hostname = "bpi-f3";
  # `mkpasswd -m yescrypt bpi-f3`
  hashedPassword = "$y$j9T$FswXaPHS5ES2MQdjZbQVC/$nuU8UvlPYXYOGgwFb2bF4zm0ZYuWugW2gzoyE8tUoL0";
in
{
  networking.hostName = hostname;

  users.users."${username}" = {
    inherit hashedPassword;
    isNormalUser = true;
    home = "/home/${username}";
    extraGroups = [
      "users"
      "networkmanager"
      "wheel"
    ];
    # Key access from l, declared so it survives PasswordAuthentication=false
    # (see sshd-INSECURE.nix). Same das key the other test hosts use.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };

  # `das` — same account as the other lab boards (arm/pi5-1). SSH is key-only
  # (see sshd-INSECURE.nix); the password is for the serial console / `sudo`.
  users.users.das = {
    isNormalUser = true;
    description = "das";
    password = "nixos";
    home = "/home/das";
    extraGroups = [
      "users"
      "networkmanager"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
    ];
  };
}
