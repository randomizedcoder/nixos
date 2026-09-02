#
# ~/nixos/super/super-d/access.nix — management access model for the super nodes.
#
# Policy (Dave, 2026-08-30): NO root SSH. Operators reach the box as the `das`
# user via SSH key, and use *passwordless sudo* to run `nixos-rebuild` locally.
# The declarative flow is the Makefile in this dir: `make sync` (laptop → box),
# then `make` (on the box) = `sudo nixos-rebuild switch`.
#
# A hashed console password is set for `das` as the break-glass path: if the
# network is ever down, you can still log in at the iKVM/serial console. It lives
# in the nix store (world-readable) + git — acceptable for this internal fabric;
# move to agenix/sops-nix if you want it out of the store. Rotate with
# `mkpasswd -m sha-512` and re-run `make sync && make`.
#
{ ... }:
{
  # root is never reachable over SSH (no authorizedKeys anywhere + this).
  services.openssh.settings.PermitRootLogin = "no";

  # das (wheel) may sudo without a password → key-only SSH + `sudo nixos-rebuild`.
  security.sudo.wheelNeedsPassword = false;

  # Break-glass console login for das (SSH stays key-only). CHANGE ME:
  #   mkpasswd -m sha-512 'newpassword'  → paste below → make sync && make
  users.users.das.hashedPassword =
    "$6$Z5XdWh2fLUpN8Ir5$XEQH3zLu7d/eZQIK.7HAhrEb6acL0Jy4yT2P3Xm/N9RQ88pY0Ij4QT9ETJsO6fZIWhrLqaqfrHSy.NAoFn9.Y0";
}
