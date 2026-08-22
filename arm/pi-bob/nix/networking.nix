#
# arm/pi-bob/nix/networking.nix
#
# By default the Pi gets its address over DHCP on the wired ethernet port
# (this is NixOS's implicit per-interface default; NetworkManager is off).
# mDNS via avahi makes `pi-bob.local` resolve on the LAN.
#
# A commented WPA2 WiFi example is provided so trying WiFi is obvious: fill in
# your SSID + password, uncomment, and rebuild.
#

{ ... }:

{
  networking.hostName = "pi-bob";

  # Ethernet DHCP is the implicit default; NetworkManager is not used.
  networking.networkmanager.enable = false;

  services.lldpd.enable = true;

  # mDNS so `pi-bob.local` resolves on the LAN.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    ipv4 = true;
    ipv6 = true;
    openFirewall = true;
  };

  # --- WiFi (optional) --------------------------------------------------------
  # The Pi defaults to DHCP on the WIRED ethernet port. To use WiFi instead,
  # uncomment the two lines below, put in your network name (SSID) and WPA2
  # password, then rebuild:
  #     sudo nixos-rebuild switch --flake .#pi-bob
  #
  # NOTE: the password is stored in cleartext in the Nix store (world-readable).
  # Fine for a demo/lab card; use a throwaway network if that matters to you.
  #
  # networking.wireless.enable = true;
  # networking.wireless.networks."YOUR_SSID_HERE".psk = "YOUR_WPA2_PASSWORD_HERE";
  #
  # (Alternatively, for an interactive UI-driven setup, drop the two lines above
  # and instead set `networking.networkmanager.enable = true;` then use `nmtui`.)
}
