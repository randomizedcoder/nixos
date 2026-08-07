# Base headless system config for the Banana Pi BPI-F3.
{
  lib,
  pkgs,
  config,
  ...
}:
{
  # Headless: serial is the primary console; disable the hvc0 getty that some
  # RISC-V profiles enable.
  systemd.services."serial-getty@hvc0".enable = false;

  services.openssh = {
    enable = lib.mkDefault true;
    settings.PasswordAuthentication = lib.mkDefault true;
    openFirewall = lib.mkDefault true;
  };

  # Headless box with no persisted RTC and a hostname that's easy to lose on a
  # busy LAN: advertise via LLDP so it shows up in switch/`lldpcli` neighbour
  # tables (find it without console access). Lightweight; no open ports.
  services.lldpd.enable = true;

  environment.systemPackages = with pkgs; [
    htop
    minicom
    lm_sensors
    i2c-tools
    dnsutils
    ethtool
    kmod
    git
    # series-3 perf-test fleet tooling (matches pi5/hp): perf for the Phase G
    # ksoftirqd cycles/pkt A/B, iperf3 for the Phase F receiver-side soak.
    config.boot.kernelPackages.perf
    iperf3
  ];

  # iperf3 server port for the Phase F receiver-side A/B (orchestrator runs
  # `iperf3 -s` on this DUT). TCP for control+TCP tests, UDP for UDP tests.
  networking.firewall.allowedTCPPorts = [ 5201 ];
  networking.firewall.allowedUDPPorts = [ 5201 ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "25.11";
}
