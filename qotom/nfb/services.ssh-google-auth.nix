#
# nixos/qotom/nfb/services.ssh-google-auth.nix
#
# SSH authentication with Google Authenticator (TOTP) two-factor authentication
# This module configures PAM to use Google Authenticator for SSH logins
#
# References:
# - https://nixos.wiki/wiki/Google_Authenticator
# - https://github.com/google/google-authenticator-libpam
# - https://nixos.org/manual/nixos/stable/index.html#module-security-pam

{ config, pkgs, ... }:

{
  # Ensure google-authenticator-libpam package is available
  environment.systemPackages = with pkgs; [
    google-authenticator
    oath-toolkit  # Optional: CLI tools for managing OATH tokens
  ];

  # Configure PAM for SSH to use Google Authenticator
  security.pam.services.sshd = {
    # Enable Google Authenticator for SSH
    googleAuthenticator = {
      enable = true;
      # Allow users without TOTP configured (set to false to require TOTP for all users)
      # nullOk = false;
      # Show secret in QR code
      # secret = "";  # Per-user secrets stored in ~/.google_authenticator
    };

    # Configure PAM authentication stack
    # Order: password first, then TOTP
    # The googleAuthenticator option automatically adds the PAM module
    # but we can customize the text prompt
    # text = "Verification code: ";
  };

  # Note: The SSH configuration in services.ssh.nix must have:
  # - UsePAM = true (already set)
  # - KbdInteractiveAuthentication = true (already set)
  # - ChallengeResponseAuthentication = true (needs to be enabled)
}

