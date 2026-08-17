# hp/hp1/ptp.nix — PTP grandmaster for design-32 one-way latency (LAB INFRA).
#
# PTP is lab time-sync infrastructure, deliberately NOT part of
# services.urp — it exists only so the matrix runner can turn RTT into a
# defensible one-way estimate (design 32 §32.8). hp1 is the PTP grandmaster
# on link B (enp1s0f1np1, 10.10.3.1); hp3 slaves to it (see hp/hp3/ptp.nix).
#
# There is no services.ptp4l / services.linuxptp NixOS module, so these are
# raw systemd units. HW timestamping via the ConnectX-4 Lx PHC ( -H );
# confirm with: ethtool -T enp1s0f1np1  (SOF_TIMESTAMPING_{TX,RX}_HARDWARE).
#
# Check sync from hp3: pmc -u -b 0 'GET CURRENT_DATA_SET' -> offsetFromMaster.
{ pkgs, ... }:

let
  iface = "enp1s0f1np1";
  # priority1 = 127 makes hp1 win the BMCA and stay grandmaster.
  ptp4lConf = pkgs.writeText "ptp4l-hp1.conf" ''
    [global]
    priority1               127
    tx_timestamp_timeout    10
    logging_level           6
    [${iface}]
  '';
in
{
  systemd.services.ptp4l = {
    description = "PTP boundary/ordinary clock (ptp4l) — grandmaster on ${iface}";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.linuxptp}/bin/ptp4l -f ${ptp4lConf} -i ${iface} -H";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Grandmaster: steer the NIC PHC from the system clock so the PTP domain
  # carries a sane absolute base (hp1's own clock is NTP-disciplined).
  systemd.services.phc2sys = {
    description = "phc2sys — push system clock -> ${iface} PHC (grandmaster)";
    after = [ "ptp4l.service" ];
    wants = [ "ptp4l.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.linuxptp}/bin/phc2sys -s CLOCK_REALTIME -c ${iface} -w -O 0";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
