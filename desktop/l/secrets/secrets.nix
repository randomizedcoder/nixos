# secrets.nix
#
# Recipient declaration for agenix-encrypted files in this directory.
# Each entry maps an .age file to the list of public keys allowed to decrypt it.
#
# Recipients:
#   l-host  — /etc/ssh/ssh_host_ed25519_key.pub on `l` (root@nixos), used for
#             activation-time decryption when nixos-rebuild runs.
#   das     — ~/.ssh/id_ed25519.pub (das@t), used so the user can edit secrets
#             with `agenix -e <file>` without needing root.
#
# Usage (when you add a secret):
#   1. Add an entry below: "<name>.age".publicKeys = recipients;
#   2. cd ~/nixos/desktop/l/secrets && agenix -e <name>.age
#   3. Reference it in a NixOS module:
#        age.secrets."<name>".file = ./secrets/<name>.age;
#      Then use config.age.secrets."<name>".path (decrypted to /run/agenix/<name>).
#   4. agenix -r   # re-encrypts all files (after key rotation)
#
# NOTE: NordLayer credentials are NOT stored here — the official client
# handles login interactively (`nordlayer login`) and persists state in
# /var/lib/nordlayer/nordlayer.db.

let
  l-host = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJRv6KgNhQCXDd6JkR3i5lCax75ShowO1x4UIs7YmD48 root@nixos";
  das    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGMCFUMSCFJX95eLfm7P9r72NBp9I1FiXwNwJ+x/HGPV das@t";

  recipients = [ l-host das ];
in
{
  # No secrets declared yet. Add entries here as needed, e.g.:
  #   "example.age".publicKeys = recipients;
}
