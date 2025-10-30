#
# nixos/qotom/nfb/services.ssh.nix
#
{ pkgs, config, ... }:
{
  # https://nixos.wiki/wiki/SSH
  # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/ssh/sshd.nix
  # https://github.com/NixOS/nixpkgs/blob/47457869d5b12bdd72303d6d2ba4bfcc26fe8531/nixos/modules/services/security/sshguard.nix
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      # default key algos: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/networking/ssh/sshd.nix#L546
      # KexAlgorithms = [
      #   "mlkem768x25519-sha256"
      #   "sntrup761x25519-sha512"
      #   "sntrup761x25519-sha512@openssh.com"
      #   "curve25519-sha256"
      #   "curve25519-sha256@libssh.org"
      #   "diffie-hellman-group-exchange-sha256"
      # ];
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes128-gcm@openssh.com"
        # shortned default list
      ];
      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
        "umac-128-etm@openssh.com"
      ];
      # HostKeyAlgorithms = [
      #   "ssh-ed25519-cert-v01@openssh.com"
      #   "sk-ssh-ed25519-cert-v01@openssh.com"
      #   "rsa-sha2-512-cert-v01@openssh.com"
      #   "rsa-sha2-256-cert-v01@openssh.com"
      #   "ssh-ed25519"
      #   "sk-ssh-ed25519@openssh.com"
      #   "rsa-sha2-512"
      #   "rsa-sha2-256"
      # ];
      UsePAM = true;
      KbdInteractiveAuthentication = true;
      PermitRootLogin = "prohibit-password";
      #PasswordAuthentication = false;
      ChallengeResponseAuthentication = false;
      #X11Forwarding = false;
      #GatewayPorts = "no";
    };
  };

  services.sshguard.enable = true;
}