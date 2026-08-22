#
# arm/pi-sebastian/nix/sshd.nix
#
# ============================================================================
# INSECURE DEMO - password SSH login is ENABLED.
#
# So that Sebastian can SSH in immediately with the demo passwords (see
# ./users.nix) even before adding an SSH key, password authentication is on and
# root may log in with a password. This is fine for a demo on an isolated lab
# network, but you should lock it down once keys are in place:
#   1. Add your public key under your user in ./users.nix.
#   2. Set `PasswordAuthentication = false;` (and ideally
#      `PermitRootLogin = "prohibit-password";`) below.
#   3. Rebuild:  sudo nixos-rebuild switch --flake .#pi-sebastian
# ============================================================================
#

{ ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes"; # INSECURE demo: root password login allowed.
      PasswordAuthentication = true; # INSECURE demo: password login over SSH.
    };
  };
}
