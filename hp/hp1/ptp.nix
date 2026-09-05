# hp/hp1/ptp.nix — PTP grandmaster for design-40 one-way latency (LAB INFRA).
#
# PTP is lab time-sync infrastructure, deliberately NOT part of services.urp —
# it exists so the OWD histogram (design 40 §40.2) and the matrix runner can turn
# frame timestamps / RTT into a defensible one-way latency. hp1 is the grandmaster
# for the whole mesh, mastering on BOTH of its point-to-point links:
#   enp1s0f0np0 (10.10.13.1)  <-> hp3 (enp1s0f1np1, 10.10.13.3)
#   enp1s0f1np1 (10.10.12.1)  <-> hp2 (enp1s0f0np0, 10.10.12.2)
#
# The two ports have SEPARATE PHCs (ptp0 / ptp1), so rather than a single
# multi-port boundary clock (which needs `boundary_clock_jbod` + `phc2sys -a`, and
# `-a`'s automatic UTC-offset handling is exactly what broke hp3 in design 40 PR-C),
# we run two INDEPENDENT grandmaster instances — one per link, each mirroring the
# proven single-link pattern. The links are physically separate /29 segments, so
# the two instances never see each other (no BMCA conflict) despite sharing
# priority1 = 127.
#
# There is no services.ptp4l / services.linuxptp NixOS module, so these are raw
# systemd units. HW timestamping via the ConnectX-4 Lx PHC ( -H ).
# Check sync from a slave: pmc -u -b 0 'GET CURRENT_DATA_SET' -> offsetFromMaster.
{ pkgs, ... }:

let
  # priority1 = 127 makes hp1 win the BMCA and stay grandmaster on each link.
  mkConf = tag: iface: pkgs.writeText "ptp4l-hp1-${tag}.conf" ''
    [global]
    priority1               127
    tx_timestamp_timeout    10
    logging_level           6
    [${iface}]
  '';

  # A grandmaster instance for one link: ptp4l masters on `iface` and phc2sys
  # pushes hp1's UTC (NTP-disciplined) system clock into that port's PHC with
  # `-O 0`, so the PTP domain carries UTC (slaves then steer back with `-O 0`).
  gm = tag: iface: {
    "ptp4l-${tag}" = {
      description = "PTP grandmaster (ptp4l) — master on ${iface} (${tag})";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.linuxptp}/bin/ptp4l -f ${mkConf tag iface} -i ${iface} -H";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
    "phc2sys-${tag}" = {
      description = "phc2sys — push system clock -> ${iface} PHC (grandmaster, ${tag})";
      after = [ "ptp4l-${tag}.service" ];
      wants = [ "ptp4l-${tag}.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.linuxptp}/bin/phc2sys -s CLOCK_REALTIME -c ${iface} -w -O 0";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
  };
in
{
  # hp3 link keeps the historical unit names (ptp4l-hp3 / phc2sys-hp3); hp2 link
  # is the new second instance.
  systemd.services =
    (gm "hp3" "enp1s0f0np0")   # 10.10.13.1 <-> hp3
    // (gm "hp2" "enp1s0f1np1"); # 10.10.12.1 <-> hp2
}
