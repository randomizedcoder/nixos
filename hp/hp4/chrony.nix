#
# hp/hp4/chrony.nix
#
# NTP: hp4 syncs from a low-latency upstream and *serves* the mgmt LAN so the
# switches, gateway, APs and DHCP clients all keep the same clock. This replaces
# systemd-timesyncd (an SNTP *client* only — it cannot serve time). timesyncd is
# turned off in configuration.nix; enabling chrony would otherwise trip a nixpkgs
# assertion that the two time daemons conflict.
#
# Module source / options:
#   https://github.com/NixOS/nixpkgs/blob/nixos-26.05/nixos/modules/services/networking/chrony.nix
#   services.chrony.{enable,servers,serverOption,extraConfig}
# NixOS has no dedicated "allow"/"local" option, so the serve-side directives go
# in extraConfig verbatim (chrony.conf syntax).
{ config, lib, pkgs, ... }:

{
  services.chrony = {
    enable = true;

    # Upstream sync. Cloudflare + Google run anycast NTP that normally lands in a
    # nearby (LA) PoP — sub-20ms, low jitter — with the US pool as breadth/backup.
    # After deploy, run `chronyc sources -v` and prune this list to the closest
    # (<20ms delay) if any of these route far.
    servers = [
      "time.cloudflare.com"
      "time.google.com"
      "0.us.pool.ntp.org"
      "1.us.pool.ntp.org"
    ];
    serverOption = "iburst";  # burst on startup so first sync is fast

    extraConfig = ''
      # Serve time to the management LAN (dual-stack). chrony only opens a
      # server socket for the address families named in `allow`, so the v6 line
      # is what makes it listen on [::]:123 as well as 0.0.0.0:123.
      allow 172.16.50.0/24
      allow 2603:8002:ea00:6800::/64

      # Keep answering as a low-stratum server even if upstream is briefly
      # unreachable — the EX2200's RTC is dead, so it must never lose a source.
      local stratum 10

      # Allow chrony to step (not just slew) a large offset on startup.
      makestep 1.0 3
    '';
  };

  # The host firewall is currently disabled (firewall.nix), so this is a no-op
  # today; declared for correctness/future-proofing per house style (modules
  # co-locate their own port openings, cf. pdns-recursor.nix).
  networking.firewall.allowedUDPPorts = [ 123 ];
}
