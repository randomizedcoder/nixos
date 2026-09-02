#!/usr/bin/env bash
#
# ~/nixos/super/storcli-90pct-vds.sh
#
# Recreate the SAS3108 (MegaRAID) VDs as 90%-of-raw single-drive RAID0 with
# battery-backed WriteBack — the storcli PRE-STEP before nixos-anywhere/disko.
# This is the "make every Samsung/Micron VD 90%" task. disko CANNOT do this
# (it's controller-level); run it in the booted NixOS-minimal installer.
#
# *** DESTRUCTIVE *** — deletes VDs and erases drives. DRY-RUN by default;
# pass --commit to actually execute. Run per drive.
#
# Why 90%: leaves 10% of the SSD unconfigured as spare cells → endurance. But
# MegaRAID RAID0 does NOT pass TRIM, so the 10% is only truly free if the drive
# is blkdiscard'd (full-drive TRIM) *before* the smaller VD is created. Do NOT
# use storcli `start erase` (it pattern-writes = fills flash).
#
# 90% sizes (design doc §4):
#   Samsung 870 2TB (1862 GiB)            → 1676GB
#   Micron 5200 / Intel D3-S4510 1.92TB   → 1608GB
#   SK hynix 512GB (476 GiB)              → 428GB
#
# Usage:
#   ./storcli-90pct-vds.sh show
#   ./storcli-90pct-vds.sh plan   <e:s> <sizeGB> <name>          # print the steps
#   ./storcli-90pct-vds.sh commit <e:s> <sizeGB> <name>          # run them (asks y/N)
# e.g.
#   ./storcli-90pct-vds.sh commit 252:0 1676 root      # Samsung → OS+tank slice
#   ./storcli-90pct-vds.sh commit 252:1 1608 data      # Micron  → tank
#
set -euo pipefail

CTRL="${CTRL:-/c0}"
STORCLI="${STORCLI:-storcli}"

show() {
  sudo "$STORCLI" "$CTRL" show
  echo; echo "=== PHYSICAL DRIVES ==="; sudo "$STORCLI" "$CTRL/eall/sall" show
  echo; echo "=== VIRTUAL DRIVES ===";  sudo "$STORCLI" "$CTRL/vall" show
}

steps() {
  local es="$1" size="$2" name="$3" enc="${1%%:*}" slot="${1##*:}"
  cat <<EOF
# --- drive $es  →  ${size}GB VD "$name" ---------------------------------
# 1) delete any VD currently on this drive (identify its /vX from 'show'):
#    sudo $STORCLI $CTRL/vX del force
# 2) expose the raw drive so the OS can TRIM it:
sudo $STORCLI $CTRL set jbod=on
sudo $STORCLI $CTRL/e$enc/s$slot set jbod
# 3) full-drive TRIM (frees the 10% OP). Find the dev with: ls -l /dev/disk/by-id
#    then (DOUBLE-CHECK the device!):
#    sudo blkdiscard /dev/disk/by-id/<the-raw-drive-for-$es>
# 4) back to RAID-Mode and make the 90% VD with WriteBack:
sudo $STORCLI $CTRL set jbod=off
sudo $STORCLI $CTRL add vd type=raid0 drives=$es size=${size}GB \\
     wrcache=AWB rdcache=RA iopolicy=cached pdcache=off name=$name
EOF
}

case "${1:-}" in
  show) show ;;
  plan)
    [ $# -eq 4 ] || { echo "usage: $0 plan <e:s> <sizeGB> <name>" >&2; exit 2; }
    steps "$2" "$3" "$4"
    ;;
  commit)
    [ $# -eq 4 ] || { echo "usage: $0 commit <e:s> <sizeGB> <name>" >&2; exit 2; }
    echo "About to DESTROY data on drive $2 and create a ${3}GB VD '$4' on $CTRL."
    echo "Steps that will run (blkdiscard is left MANUAL — see step 3):"; echo
    steps "$2" "$3" "$4"; echo
    read -r -p "Proceed with the storcli delete/jbod/create (NOT blkdiscard)? [y/N] " ans
    [ "$ans" = "y" ] || { echo "aborted"; exit 1; }
    echo ">>> run the delete (step 1) manually if a VD exists, then blkdiscard (step 3)."
    echo ">>> this command only runs steps 2 and 4:"
    sudo "$STORCLI" "$CTRL" set jbod=on
    enc="${2%%:*}"; slot="${2##*:}"
    sudo "$STORCLI" "$CTRL/e$enc/s$slot" set jbod
    echo ">>> NOW blkdiscard the raw drive (step 3), then press Enter to create the VD."
    read -r _
    sudo "$STORCLI" "$CTRL" set jbod=off
    sudo "$STORCLI" "$CTRL" add vd type=raid0 drives="$2" size="${3}GB" \
      wrcache=AWB rdcache=RA iopolicy=cached pdcache=off name="$4"
    echo "done — verify: $0 show"
    ;;
  *)
    echo "usage: $0 {show | plan <e:s> <sizeGB> <name> | commit <e:s> <sizeGB> <name>}" >&2
    exit 2
    ;;
esac
