# hp/hp3/ptp.nix — PTP slave for design-32 one-way latency (LAB INFRA).
#
# PTP is lab time-sync infrastructure, deliberately NOT part of
# services.urp — it exists only so the matrix runner can turn RTT into a
# defensible one-way estimate (design 32 §32.8). hp3 slaves to the hp1
# grandmaster on link B (enp1s0f1np1, 10.10.3.3); see hp/hp1/ptp.nix.
#
# There is no services.ptp4l / services.linuxptp NixOS module, so these are
# raw systemd units. HW timestamping via the ConnectX-4 Lx PHC ( -H );
# confirm with: ethtool -T enp1s0f1np1  (SOF_TIMESTAMPING_{TX,RX}_HARDWARE).
#
# Check sync locally: pmc -u -b 0 'GET CURRENT_DATA_SET' -> offsetFromMaster
# (sub-µs once locked => RTT/2 is a valid one-way estimate to within it).
{ pkgs, ... }:

let
  iface = "enp1s0f1np1";
  # priority1 = 255 keeps hp3 a slave; hp1 (127) wins the BMCA.
  ptp4lConf = pkgs.writeText "ptp4l-hp3.conf" ''
    [global]
    priority1               255
    tx_timestamp_timeout    10
    logging_level           6
    [${iface}]
  '';
in
{
  systemd.services.ptp4l = {
    description = "PTP ordinary clock (ptp4l) — slave on ${iface}";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.linuxptp}/bin/ptp4l -f ${ptp4lConf} -i ${iface} -H -s";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Slave: steer the system clock from the ptp4l-disciplined NIC PHC so
  # hp3's CLOCK_REALTIME tracks the hp1 grandmaster (-a follows ptp4l's
  # selected clock; -r allows the system clock to be a time source too).
  systemd.services.phc2sys = {
    description = "phc2sys — steer system clock <- ${iface} PHC (slave)";
    after = [ "ptp4l.service" ];
    wants = [ "ptp4l.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.linuxptp}/bin/phc2sys -a -r";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
