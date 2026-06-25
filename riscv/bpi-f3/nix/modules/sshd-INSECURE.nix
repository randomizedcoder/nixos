# sshd-INSECURE.nix
#
# Root login via SSH key only (same key as user das), matching the other test
# hosts (hp*/pi5). Lets the series-3 perf orchestrator drive this box via
# `ssh root@bpi-f3`. Password auth disabled; lab network only.

{ ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t"
  ];
}
