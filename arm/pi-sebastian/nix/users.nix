#
# arm/pi-sebastian/nix/users.nix
#
# ============================================================================
# INSECURE DEMO PASSWORDS - CHANGE THESE.
#
# This is a demo/lab card. Every account below ships with a trivial cleartext
# password so it is obvious how to log in AND obvious how to change it. These
# passwords are WORLD-READABLE in the Nix store. Before using this Pi anywhere
# that matters:
#   1. Edit the `password = "...";` lines below (and the root password).
#   2. Rebuild:  sudo nixos-rebuild switch --flake .#pi-sebastian
# Better still, switch to SSH keys and turn password auth off in ./sshd.nix.
# ============================================================================
#
# All three users are in the `wheel` group, so they can `sudo`.
#

{ ... }:

let
  # das (the person who built and mailed this card) logs in by SSH key.
  dasKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t";
in
{
  users.users.bob = {
    isNormalUser = true;
    description = "Bob";
    password = "bob"; # INSECURE demo password - change me.
    extraGroups = [
      "wheel"
      "video"
    ];
    openssh.authorizedKeys.keys = [
      # < paste ssh public key here >
    ];
  };

  users.users.sebastian = {
    isNormalUser = true;
    description = "Sebastian";
    password = "sebastian"; # INSECURE demo password - change me.
    extraGroups = [
      "wheel"
      "video"
    ];
    openssh.authorizedKeys.keys = [
      # < paste ssh public key here >
    ];
  };

  # das (the person who built and mailed this card). Logs in by key, but also
  # gets the same trivial demo password as everyone else for console access.
  users.users.das = {
    isNormalUser = true;
    description = "das";
    password = "das"; # INSECURE demo password - change me.
    extraGroups = [
      "wheel"
      "video"
    ];
    openssh.authorizedKeys.keys = [ dasKey ];
  };

  # PLEASE UPDATE THE ROOT PASSWORD ASAP
  users.users.root.password = "root"; # INSECURE demo password - change me.
  users.users.root.openssh.authorizedKeys.keys = [ dasKey ];
}
