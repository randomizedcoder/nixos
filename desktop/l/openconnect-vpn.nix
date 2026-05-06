# openconnect-vpn.nix
#
# On-demand AnyConnect VPN via OpenConnect
#
# CLI usage:
#   vpn-up                                         # Connect with saved credentials
#   vpn-up vpn.nfbconsulting.com/NFB-Office        # Connect to Signal Hill
#   vpn-down                                       # Disconnect
#   sudo openconnect ladcvpn.nfbconsulting.com     # Interactive (no saved creds)
#
# GUI usage:
#   NetworkManager → VPN → Add → Cisco AnyConnect Compatible VPN
#   Gateway: ladcvpn.nfbconsulting.com
#
# Servers:
#   ladcvpn.nfbconsulting.com        — LA Data Center VPN
#   vpn.nfbconsulting.com/NFB-Office — Signal Hill VPN
#
# Credentials setup (one-time):
#   mkdir -p ~/.config/openconnect
#   chmod 700 ~/.config/openconnect
#   cat > ~/.config/openconnect/credentials <<EOF
#   user=your_username
#   password=your_password
#   EOF
#   chmod 600 ~/.config/openconnect/credentials

{ pkgs, ... }:

let
  credFile = "/home/das/.config/openconnect/credentials";
in
{
  environment.systemPackages = with pkgs; [
    openconnect
    (writeShellScriptBin "vpn-up" ''
      CRED_FILE="${credFile}"
      SERVER="''${1:-ladcvpn.nfbconsulting.com}"

      if [ ! -f "$CRED_FILE" ]; then
        echo "No credentials file at $CRED_FILE"
        echo "Create it with:"
        echo "  mkdir -p ~/.config/openconnect && chmod 700 ~/.config/openconnect"
        echo "  cat > $CRED_FILE <<EOF"
        echo "  user=your_username"
        echo "  password=your_password"
        echo "  EOF"
        echo "  chmod 600 $CRED_FILE"
        echo ""
        echo "Falling back to interactive login..."
        sudo ${openconnect}/bin/openconnect \
          --protocol=anyconnect \
          --pid-file=/run/openconnect.pid \
          --servercert pin-sha256:aNfEKIY9ehZZezYXwvUGYf+9OtI4K4LNlcqRfGPfDn8= \
          "$SERVER"
        exit $?
      fi

      VPN_USER=$(${pkgs.gnugrep}/bin/grep '^user=' "$CRED_FILE" | ${pkgs.gnused}/bin/sed 's/^user=//')
      VPN_PASS=$(${pkgs.gnugrep}/bin/grep '^password=' "$CRED_FILE" | ${pkgs.gnused}/bin/sed 's/^password=//')

      printf '%s\n' "$VPN_PASS" | sudo ${openconnect}/bin/openconnect \
        --protocol=anyconnect \
        --background \
        --pid-file=/run/openconnect.pid \
        --servercert pin-sha256:aNfEKIY9ehZZezYXwvUGYf+9OtI4K4LNlcqRfGPfDn8= \
        --authgroup=NFB-LADC \
        --user="$VPN_USER" \
        --passwd-on-stdin \
        "$SERVER"
    '')
    (writeShellScriptBin "vpn-down" ''
      if [ -f /run/openconnect.pid ]; then
        sudo kill "$(cat /run/openconnect.pid)" && sudo rm -f /run/openconnect.pid
      else
        sudo pkill openconnect
      fi
    '')
  ];

  networking.networkmanager.plugins = with pkgs; [
    networkmanager-openconnect
  ];
}
