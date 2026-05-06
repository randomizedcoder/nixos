#
# l2/tsf-sync.nix — WiFi TSF synchronisation via upstream mt76 PTP patches
#
# Applies kernel patches to expose /dev/ptpN on the MT7925 cards:
#   0001: generic mt76 PTP infrastructure (ptp.c, mt76_ptp_ops)
#   0004: mt792x chipset callbacks (mt7921/mt7922/mt7925)
#   0005: mt7925 tsf_probe debugfs (diagnostic-only; confirms whether
#         mac80211 ops->get_tsf also returns 0 on mt7925)
#   0006: mt7925 tsf_set debugfs (diagnostic-only; write-path companion
#         to 0005 — determines whether mt792x_set_tsf reaches the chip
#         even though the LPON read mirror is dead)
#
# Then enables the tsf-sync daemon to synchronise TSF counters across
# the four co-located radios using phc2sys.
#
{ config, lib, pkgs, inputs, ... }:

let
  tsfSrc = inputs.tsf-sync;
  patchDir = "${tsfSrc}/patches/net-next/mt76";
in
{
  imports = [ inputs.tsf-sync.nixosModules.default ];

  boot.kernelPatches = [
    {
      name = "mt76-ptp-infra";
      patch = "${patchDir}/0001-wifi-mt76-add-ptp-hardware-clock-for-tsf.patch";
      structuredExtraConfig = with lib.kernel; {
        PTP_1588_CLOCK = yes;
      };
    }
    {
      name = "mt76-ptp-mt792x";
      patch = "${patchDir}/0004-wifi-mt76-register-ptp-ops-for-mt792x.patch";
    }
    {
      name = "mt7925-tsf-probe-debugfs";
      patch = "${patchDir}/0005-wifi-mt76-add-mt7925-tsf-probe-debugfs.patch";
    }
    {
      name = "mt7925-tsf-set-debugfs";
      patch = "${patchDir}/0006-wifi-mt76-add-mt7925-tsf-set-debugfs.patch";
    }
  ];

  services.tsf-sync = {
    enable = true;
    primaryCard = "auto";
    interval = "10s";
    adjtimeThresholdNs = 5000;
    logLevel = "info";
    # In-tree patches provide /dev/ptpN directly; no need for the
    # out-of-tree tsf_ptp.ko fallback module.
    loadKernelModule = false;
  };
}
