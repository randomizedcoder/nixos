# secrets.nix
#
# Recipient declaration for agenix-encrypted files in this directory.
# Each entry maps an .age file to the list of public keys allowed to decrypt it.
#
# Recipients:
#   d-host  — /etc/ssh/ssh_host_ed25519_key.pub on `d` (root@d), used for
#             activation-time decryption when nixos-rebuild runs.
#   das     — ~/.ssh/id_ed25519.pub (das@t), used so the user can edit secrets
#             with `agenix -e <file>` without needing root.
#
# Usage (when you add a secret):
#   1. Add an entry below: "<name>.age".publicKeys = recipients;
#   2. cd ~/nixos/laptops/d/secrets && agenix -e <name>.age
#   3. Reference it in a NixOS module:
#        age.secrets."<name>".file = ./secrets/<name>.age;
#      Then use config.age.secrets."<name>".path (decrypted to /run/agenix/<name>).
#   4. agenix -r   # re-encrypts all files (after key rotation)

let
  # TODO: replace with `cat /etc/ssh/ssh_host_ed25519_key.pub` from the d laptop
  # once it is provisioned. Until then this list is a placeholder; no secrets
  # are declared so it has no effect.
  d-host = "ssh-ed25519 REPLACE_WITH_D_HOST_KEY root@d";
  das    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t";

  recipients = [ d-host das ];
in
{
  # No secrets declared yet. Add entries here as needed, e.g.:
  #   "example.age".publicKeys = recipients;
}
