# sshd-INSECURE.nix
#
# Root login via SSH key only (same key as user das).
# Password auth is disabled. Isolated lab network only.
#
# Added so that tooling (e.g. the MCP ssh server running on a sibling
# host) can drive the MT7925 TSF debugfs files directly as root, since
# those files live under /sys/kernel/debug which is mode 0600 root:root
# and cannot be reached with the normal "das" user + sudo-wrapped
# command allowlist. Keep scoped to the lab network.

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
