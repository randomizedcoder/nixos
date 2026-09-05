# hp/hp2/ptp.nix — PTP slave for design-40 one-way latency (LAB INFRA).
#
# PTP is lab time-sync infrastructure, deliberately NOT part of services.urp —
# it exists so the OWD histogram (design 40 §40.2) and the matrix runner can turn
# frame timestamps / RTT into a defensible one-way latency. hp2 slaves to the hp1
# grandmaster on the hp1<->hp2 link (enp1s0f0np0, 10.10.12.2; hp1 masters on its
# 10.10.12.1 side — see hp/hp1/ptp.nix, which runs a second GM instance on that
# link because hp1's two ports have SEPARATE PHCs, ptp0/ptp1).
#
# There is no services.ptp4l / services.linuxptp NixOS module, so these are raw
# systemd units. HW timestamping via the ConnectX-4 Lx PHC ( -H ); confirm with:
# ethtool -T enp1s0f0np0  (SOF_TIMESTAMPING_{TX,RX}_HARDWARE).
#
# Check sync locally: pmc -u -b 0 'GET CURRENT_DATA_SET' -> offsetFromMaster
# (sub-µs once locked), and: journalctl -u phc2sys -f  (offset -> 0).
{ pkgs, ... }:

let
  iface = "enp1s0f0np0";
  # priority1 = 255 keeps hp2 a slave; hp1 (127) wins the BMCA.
  ptp4lConf = pkgs.writeText "ptp4l-hp2.conf" ''
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

  # Slave: steer CLOCK_REALTIME from the ptp4l-disciplined NIC PHC so hp2's
  # system clock tracks the hp1 grandmaster.
  #
  # Explicit source/dest + `-O 0` (NOT `-a -r`): hp1's grandmaster phc2sys pushes
  # its UTC-disciplined CLOCK_REALTIME into the PHC with `-O 0`, so the whole PTP
  # domain's PHC holds UTC, not TAI. `phc2sys -a` auto-reads a nonzero
  # currentUtcOffset (~37 s) from ptp4l and subtracts it, driving the system clock
  # ~37 s off — and because that dwarfs the slew rate the servo rails and never
  # converges (design 40 PR-C found exactly this on hp3 post-reboot). Pinning
  # `-O 0` matches the grandmaster's zero-offset convention; the default
  # first_step_threshold (20 µs) steps the boot-time offset in one jump instead of
  # slewing. `-w` waits for ptp4l to lock before stepping.
  systemd.services.phc2sys = {
    description = "phc2sys — steer system clock <- ${iface} PHC (slave)";
    after = [ "ptp4l.service" ];
    wants = [ "ptp4l.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.linuxptp}/bin/phc2sys -s ${iface} -c CLOCK_REALTIME -w -O 0";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
