#!/usr/bin/env bash
#
# Copyright (C) 2026 Christos Nikolaou (SV1EIA)
# Christos Nikolaou can be reached by email at : sv1eia@gmail.com
# SPDX-License-Identifier: GPL-3.0-or-later
#
# libresdr_gpsdo_fix.sh - give a stock tezuka_fw v0.3.21 LibreSDR SD card the
# fixed bitstream (dacxx11_spi DIN/SCLK timing fix) and the GPSDO acquisition
# at boot (gpsdo_boot), without a firmware rebuild. Everything it replaces is
# kept beside the new file (*.orig), so uninstall restores the stock card.
#
# Usage
#   ./libresdr_gpsdo_fix.sh <action> --host <ip> [--ramdisk] [--force]
#   ./libresdr_gpsdo_fix.sh <action> --sd <mounted FAT path> [--force]
#
# Actions
#   install     add fix_top.bin, select it in uEnv.txt, add the GPSDO boot script
#   uninstall   restore the stock files and remove everything this script added
#   status      show what is installed (and, over the network, the live state)
#   run         (network only) run the acquisition on the board now, show its log
#
# Targets
#   --host <ip>  a running LibreSDR over SSH (root, password "analog"; needs
#                scp -O because the board has no SFTP server). Default method:
#                --hook  the acquisition script goes to /boot/gpsdo/ and a one-line
#                        hook to /mnt/jffs2/autorun.sh (QSPI flash; tested).
#                --ramdisk  instead, the script and its init script are added
#                        INSIDE the SD's ramdisk (uramdisk.image.xz), the same
#                        layout as the firmware patch; QSPI is not touched.
#   --sd <path>  the SD card's FAT partition mounted on this PC (card reader):
#                the ramdisk method is used (the jffs2 hook is not on the card).
#                WSL example:  sudo mkdir -p /mnt/e && sudo mount -t drvfs E: /mnt/e
#                              ./libresdr_gpsdo_fix.sh install --sd /mnt/e
#                              sudo umount /mnt/e
#
# Options
#   --force      skip the check that the card holds the stock v0.3.21 bitstream
#   --pass <pw>  SSH password (default analog); LIBRESDR_PASS also works
#
# What install changes on the card
#   system_top.bin      untouched          (the stock bitstream stays)
#   fix_top.bin         NEW                (the fixed bitstream, shipped in this folder)
#   uEnv.txt            bitstream_image=fix_top.bin   (uEnv.txt.orig kept)
#   gpsdo/gpsdo_boot.sh NEW  (--hook)      plus /mnt/jffs2/autorun.sh on the board
#   uramdisk.image.xz   repacked (--ramdisk / --sd) with /etc/init.d/S22gpsdo,
#                       /usr/sbin/gpsdo_boot.sh, /etc/default/gpsdo  (uramdisk.image.xz.orig kept)
# xo_correction in the U-Boot env is NOT changed: gpsdo_boot.sh writes the
# nominal value at every boot. Reboot after install or uninstall.
#
# Needs on this PC: bash, ssh/scp (and sshpass or setsid), and for the ramdisk
# method xz, cpio, fakeroot, mkimage (u-boot-tools).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Everything the script needs sits in its own directory (hand the folder as is):
#   libresdr_gpsdo_fix.sh  fix_top.bin  gpsdo_boot.sh  README.txt
FIX_BIN="$HERE/fix_top.bin"
GPSDO_SH="$HERE/gpsdo_boot.sh"
STOCK_MD5=c6a69779c8678d09f4881e8e276f890a   # tezuka v0.3.21 libre system_top.bin
FIX_MD5=3c29f12e04e3e1378d14ad028c478188     # GPSDO/fix_top.bin (dacxx11_spi fix, Vivado 2023.1)
HOOK=/mnt/jffs2/autorun.sh
HOOK_MARK="gpsdo acquisition at boot (libresdr_gpsdo_fix.sh)"
HOOK_LINE='[ -f /boot/gpsdo/gpsdo_boot.sh ] && sh /boot/gpsdo/gpsdo_boot.sh >/dev/null 2>&1 &'
TMP="${TMPDIR:-/tmp}/libresdr_gpsdo_fix.$$"

# --- files that go inside the ramdisk (mirror of tezuka_fw commit 34315f6) ---
read -r -d '' S22GPSDO <<'EOS' || true
#!/bin/sh
#
# Copyright (C) 2026 Christos Nikolaou (SV1EIA)
# Christos Nikolaou can be reached by email at : sv1eia@gmail.com
#
# libre board: acquire the external 10 MHz reference for the vctcxo_lock
# loop right after the PL is reachable (see /usr/sbin/gpsdo_boot.sh).
# Runs in the background; boot is not delayed.

case "$1" in
  start)
	printf "Starting GPSDO acquisition (gpsdo_boot): "
	/usr/sbin/gpsdo_boot.sh >/dev/null 2>&1 &
	echo "OK"
	;;
  stop)
	;;
  restart|reload)
	"$0" start
	;;
  *)
	echo "Usage: $0 {start|stop|restart}"
	exit 1
esac

exit 0
EOS
read -r -d '' DEFAULT_GPSDO <<'EOS' || true
# Tunables for /usr/sbin/gpsdo_boot.sh (libre board). Sourced by the script;
# the values below are the measured ones for LibreSDR Rev.5 with the fixed
# dacxx11_spi driver. Adjust CENTER_DEFAULT if a unit's zero crossing differs.
CENTER_DEFAULT=35570
CODES_PER_COUNT=52
EOS

# ------------------------------------------------------------------ helpers
die() { echo "ERROR: $*" >&2; exit 1; }
note() { echo "  $*"; }
md5of() { md5sum "$1" | awk '{print $1}'; }
cleanup() { [ -d "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

# set_bitstream <uEnv.txt path> <name>: rewrite the bitstream_image line without
# sed -i (on a FAT card mounted through WSL drvfs, sed -i's temp file cannot
# have its permissions preserved and sed prints a warning).
set_bitstream() { mkdir -p "$TMP"; sed "s/^bitstream_image=.*/bitstream_image=$2/" "$1" > "$TMP/uEnv.edit" && cat "$TMP/uEnv.edit" > "$1"; }

usage() { sed -n '/^# Usage/,/^# Needs on this PC/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

check_local_files() {
    [ -f "$FIX_BIN" ] || die "missing $FIX_BIN (fix_top.bin must be in the same folder as this script)"
    [ "$(md5of "$FIX_BIN")" = "$FIX_MD5" ] || die "$FIX_BIN has an unexpected md5 (expected $FIX_MD5)"
    [ -f "$GPSDO_SH" ] || die "missing $GPSDO_SH (gpsdo_boot.sh must be in the same folder as this script)"
}

# ramdisk_add <in uramdisk.image.xz> <out uramdisk.image.xz>
# Unpacks the legacy U-Boot ramdisk image (64-byte header + xz + newc cpio),
# adds the three files, repacks with the same format (single-block xz, CRC32).
ramdisk_add() {
    local in="$1" out="$2" w="$TMP/rd"
    for t in xz cpio fakeroot mkimage; do command -v $t >/dev/null || die "need $t for the ramdisk method (apt install xz-utils cpio fakeroot u-boot-tools)"; done
    rm -rf "$w"; mkdir -p "$w/root"
    [ "$(head -c 4 "$in" | od -An -tx1 | tr -d ' ')" = "27051956" ] || die "$in is not a U-Boot legacy image"
    dd if="$in" bs=64 skip=1 of="$w/rootfs.cpio.xz" 2>/dev/null
    xz -dc "$w/rootfs.cpio.xz" > "$w/rootfs.cpio" || die "xz decompression failed"
    [ "$(head -c 6 "$w/rootfs.cpio")" = "070701" ] || die "ramdisk payload is not a newc cpio"
    cp "$GPSDO_SH" "$w/gpsdo_boot.sh"; printf '%s\n' "$S22GPSDO" > "$w/S22gpsdo"; printf '%s\n' "$DEFAULT_GPSDO" > "$w/gpsdo.default"
    fakeroot -- sh -e -c '
        cd "$1/root"
        cpio -idm --quiet --no-absolute-filenames < ../rootfs.cpio
        install -m 755 -o 0 -g 0 ../S22gpsdo etc/init.d/S22gpsdo
        install -m 755 -o 0 -g 0 ../gpsdo_boot.sh usr/sbin/gpsdo_boot.sh
        install -D -m 644 -o 0 -g 0 ../gpsdo.default etc/default/gpsdo
        find . -mindepth 1 -printf "%P\n" | sort | cpio -o -H newc --quiet --reproducible > ../new.cpio
    ' sh "$w" || die "cpio unpack/repack failed"
    xz -9 -C crc32 -c "$w/new.cpio" > "$w/new.cpio.xz" || die "xz compression failed"
    mkimage -A arm -T ramdisk -C none -d "$w/new.cpio.xz" "$out" >/dev/null || die "mkimage failed"
    note "ramdisk repacked: $(stat -c %s "$in") -> $(stat -c %s "$out") bytes, $(cpio -t < "$w/new.cpio" 2>/dev/null | wc -l) entries"
}

# ramdisk_has_gpsdo <uramdisk.image.xz>  -> 0 if S22gpsdo is inside
ramdisk_has_gpsdo() { dd if="$1" bs=64 skip=1 2>/dev/null | xz -dc 2>/dev/null | cpio -t 2>/dev/null | grep -q '^etc/init.d/S22gpsdo$'; }

# --------------------------------------------------------------- SD (local)
sd_check() {
    local p="$1"
    for f in BOOT.bin uEnv.txt uramdisk.image.xz system_top.bin; do [ -f "$p/$f" ] || die "$p does not look like a LibreSDR boot partition (missing $f)"; done
    if [ "$FORCE" = 0 ] && [ ! -f "$p/system_top.bin.orig" ]; then
        [ "$(md5of "$p/system_top.bin")" = "$STOCK_MD5" ] || die "system_top.bin is not the stock v0.3.21 bitstream (md5 $(md5of "$p/system_top.bin")); use --force if you know what you are doing"
    fi
}
sd_status() {
    local p="$1"
    echo "SD at $p:"
    note "system_top.bin  : $(md5of "$p/system_top.bin") $([ "$(md5of "$p/system_top.bin")" = "$STOCK_MD5" ] && echo '(stock v0.3.21)' || echo '(not the stock file)')"
    note "fix_top.bin     : $([ -f "$p/fix_top.bin" ] && { [ "$(md5of "$p/fix_top.bin")" = "$FIX_MD5" ] && echo present, md5 OK || echo 'present, md5 MISMATCH'; } || echo absent)"
    note "uEnv.txt        : $(grep '^bitstream_image=' "$p/uEnv.txt" | head -1)   backup: $([ -f "$p/uEnv.txt.orig" ] && echo yes || echo no)"
    # The full scan of the 21 MB ramdisk costs about a minute through a card
    # reader; a card this script installed on always has the backup file, so
    # without it the ramdisk is reported as stock without scanning.
    if [ -f "$p/uramdisk.image.xz.orig" ]; then
        note "ramdisk         : $(ramdisk_has_gpsdo "$p/uramdisk.image.xz" && echo 'contains S22gpsdo + gpsdo_boot.sh' || echo 'MODIFIED but without S22gpsdo')   backup: yes"
    else
        note "ramdisk         : stock (no backup file, not scanned)   backup: no"
    fi
    note "gpsdo/ on card  : $([ -f "$p/gpsdo/gpsdo_boot.sh" ] && echo 'gpsdo_boot.sh (hook method)' || echo none)"
}
sd_install() {
    local p="$1"; check_local_files; sd_check "$p"
    echo "Installing on the SD at $p (ramdisk method) ..."
    [ -f "$p/uEnv.txt.orig" ] || cp "$p/uEnv.txt" "$p/uEnv.txt.orig"
    if [ -f "$p/fix_top.bin" ] && [ "$(md5of "$p/fix_top.bin")" = "$FIX_MD5" ]; then note "fix_top.bin already present"; else cp "$FIX_BIN" "$p/fix_top.bin"; note "fix_top.bin copied"; fi
    if grep -q '^bitstream_image=fix_top.bin' "$p/uEnv.txt"; then note "uEnv.txt already selects fix_top.bin"; else
        set_bitstream "$p/uEnv.txt" fix_top.bin; grep -q '^bitstream_image=fix_top.bin' "$p/uEnv.txt" || die "uEnv.txt edit failed"; note "uEnv.txt: bitstream_image=fix_top.bin"; fi
    if ramdisk_has_gpsdo "$p/uramdisk.image.xz"; then note "ramdisk already contains gpsdo_boot"; else
        [ -f "$p/uramdisk.image.xz.orig" ] || cp "$p/uramdisk.image.xz" "$p/uramdisk.image.xz.orig"
        mkdir -p "$TMP"; ramdisk_add "$p/uramdisk.image.xz.orig" "$TMP/uramdisk.new"
        cp "$TMP/uramdisk.new" "$p/uramdisk.image.xz"; note "uramdisk.image.xz replaced (original kept as uramdisk.image.xz.orig)"; fi
    sync; sd_status "$p"; echo "Done. Put the card back and boot."
}
sd_uninstall() {
    local p="$1"; echo "Uninstalling from the SD at $p ..."
    [ -f "$p/uEnv.txt.orig" ] && { cp "$p/uEnv.txt.orig" "$p/uEnv.txt"; rm -f "$p/uEnv.txt.orig"; note "uEnv.txt restored"; } || { set_bitstream "$p/uEnv.txt" system_top.bin; note "uEnv.txt: bitstream_image=system_top.bin"; }
    [ -f "$p/uramdisk.image.xz.orig" ] && { cp "$p/uramdisk.image.xz.orig" "$p/uramdisk.image.xz"; rm -f "$p/uramdisk.image.xz.orig"; note "uramdisk.image.xz restored"; }
    rm -f "$p/fix_top.bin"; rm -rf "$p/gpsdo"; sync; note "fix_top.bin and gpsdo/ removed"; sd_status "$p"
}

# ---------------------------------------------------------------- network
SSHOPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=15"
askpass() { local ap; ap="$(mktemp)"; printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$PASS" > "$ap"; chmod 700 "$ap"; echo "$ap"; }
ssh_run() { if command -v sshpass >/dev/null; then sshpass -p "$PASS" ssh $SSHOPTS "root@$HOST" "$1"; else local ap; ap=$(askpass); SSH_ASKPASS="$ap" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 setsid -w ssh -n $SSHOPTS "root@$HOST" "$1"; local rc=$?; rm -f "$ap"; return $rc; fi; }
scp_put() { if command -v sshpass >/dev/null; then sshpass -p "$PASS" scp -O $SSHOPTS "$1" "root@$HOST:$2"; else local ap; ap=$(askpass); SSH_ASKPASS="$ap" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 setsid -w scp -O $SSHOPTS "$1" "root@$HOST:$2"; local rc=$?; rm -f "$ap"; return $rc; fi; }
scp_get() { if command -v sshpass >/dev/null; then sshpass -p "$PASS" scp -O $SSHOPTS "root@$HOST:$1" "$2"; else local ap; ap=$(askpass); SSH_ASKPASS="$ap" SSH_ASKPASS_REQUIRE=force DISPLAY=:0 setsid -w scp -O $SSHOPTS "root@$HOST:$1" "$2"; local rc=$?; rm -f "$ap"; return $rc; fi; }

net_status() {
    echo "LibreSDR $HOST:"
    ssh_run "
      m=\$(md5sum /boot/system_top.bin | cut -c1-32); echo \"  system_top.bin  : \$m \$([ \$m = $STOCK_MD5 ] && echo '(stock v0.3.21)' || echo '(not the stock file)')\"
      if [ -f /boot/fix_top.bin ]; then f=\$(md5sum /boot/fix_top.bin | cut -c1-32); echo \"  fix_top.bin     : present \$([ \$f = $FIX_MD5 ] && echo 'md5 OK' || echo 'md5 MISMATCH')\"; else echo '  fix_top.bin     : absent'; fi
      echo \"  uEnv.txt        : \$(grep '^bitstream_image=' /boot/uEnv.txt | head -1)   backup: \$([ -f /boot/uEnv.txt.orig ] && echo yes || echo no)\"
      echo \"  ramdisk backup  : \$([ -f /boot/uramdisk.image.xz.orig ] && echo 'uramdisk.image.xz.orig present (ramdisk method)' || echo none)\"
      echo \"  booted rootfs   : \$([ -x /etc/init.d/S22gpsdo ] && echo 'has S22gpsdo (ramdisk method active)' || echo 'stock (no S22gpsdo)')\"
      echo \"  gpsdo/ on card  : \$([ -f /boot/gpsdo/gpsdo_boot.sh ] && echo 'gpsdo_boot.sh' || echo none)\"
      echo \"  jffs2 hook      : \$([ -f $HOOK ] && sed -n 2p $HOOK || echo none)\"
      echo \"  xo_correction   : \$(cat /sys/bus/iio/devices/iio:device0/xo_correction 2>/dev/null) (live)  \$(fw_printenv -n xo_correction 2>/dev/null || echo unset) (env)\"
      st=\$(devmem 0x43C00010 32); e=\$(( \$(devmem 0x43C00018 32) )); [ \$e -ge 2147483648 ] && e=\$((e-4294967296))
      echo \"  loop            : dac \$(( \$(devmem 0x43C00008 32) & 0xFFFF )) err \$e counts locked=\$(( st & 1 )) ref_present=\$(( (st>>1) & 1 ))\"
      echo '  last acquisition:'; tail -4 /tmp/gpsdo_boot.log 2>/dev/null | sed 's/^/    /' || echo '    (no log)'
    "
}
net_install() {
    check_local_files
    echo "Installing on LibreSDR $HOST (method: $METHOD) ..."
    ssh_run "mount | grep -q ' /boot ' || { echo 'ERROR: /boot (SD FAT) is not mounted on the board'; exit 1; }" || exit 1
    if [ "$FORCE" = 0 ]; then
        m=$(ssh_run "[ -f /boot/system_top.bin.orig ] && echo skip || md5sum /boot/system_top.bin | cut -c1-32")
        [ "$m" = skip ] || [ "$m" = "$STOCK_MD5" ] || die "board's system_top.bin is not the stock v0.3.21 bitstream (md5 $m); use --force if you know what you are doing"
    fi
    ssh_run "[ -f /boot/uEnv.txt.orig ] || cp /boot/uEnv.txt /boot/uEnv.txt.orig"
    f=$(ssh_run "[ -f /boot/fix_top.bin ] && md5sum /boot/fix_top.bin | cut -c1-32 || echo none")
    if [ "$f" = "$FIX_MD5" ]; then note "fix_top.bin already present"; else
        scp_put "$FIX_BIN" /boot/fix_top.bin || die "copy of fix_top.bin failed"
        [ "$(ssh_run "md5sum /boot/fix_top.bin | cut -c1-32")" = "$FIX_MD5" ] || die "fix_top.bin md5 mismatch after copy"; note "fix_top.bin copied and verified"; fi
    ssh_run "grep -q '^bitstream_image=fix_top.bin' /boot/uEnv.txt && echo '  uEnv.txt already selects fix_top.bin' || { sed -i 's/^bitstream_image=.*/bitstream_image=fix_top.bin/' /boot/uEnv.txt && grep -q '^bitstream_image=fix_top.bin' /boot/uEnv.txt && echo '  uEnv.txt: bitstream_image=fix_top.bin'; }"
    if [ "$METHOD" = hook ]; then
        ssh_run "mkdir -p /boot/gpsdo" && scp_put "$GPSDO_SH" /boot/gpsdo/gpsdo_boot.sh || die "copy of gpsdo_boot.sh failed"
        ssh_run "printf '#!/bin/sh\n# $HOOK_MARK $(date +%Y-%m-%d)\n%s\n' '$HOOK_LINE' > $HOOK && chmod +x $HOOK && echo '  jffs2 hook written'"
    else
        if ssh_run "[ -f /boot/uramdisk.image.xz.orig ]"; then note "ramdisk backup exists; using it as the stock source"; else ssh_run "cp /boot/uramdisk.image.xz /boot/uramdisk.image.xz.orig"; fi
        mkdir -p "$TMP"; scp_get /boot/uramdisk.image.xz.orig "$TMP/uramdisk.orig" || die "fetch of the ramdisk failed"
        ramdisk_add "$TMP/uramdisk.orig" "$TMP/uramdisk.new"
        scp_put "$TMP/uramdisk.new" /boot/uramdisk.image.xz || die "copy of the ramdisk failed"
        [ "$(ssh_run "md5sum /boot/uramdisk.image.xz | cut -c1-32")" = "$(md5of "$TMP/uramdisk.new")" ] || die "ramdisk md5 mismatch after copy"
        note "uramdisk.image.xz replaced and verified (original kept as uramdisk.image.xz.orig)"
        ssh_run "grep -q '$HOOK_MARK' $HOOK 2>/dev/null && rm -f $HOOK && echo '  jffs2 hook of the hook method removed (not needed with the ramdisk method)'" || true
    fi
    ssh_run "sync"; net_status; echo "Done. Reboot the LibreSDR to run the new bitstream and the acquisition."
}
net_uninstall() {
    echo "Uninstalling from LibreSDR $HOST ..."
    ssh_run "
      if [ -f /boot/uEnv.txt.orig ]; then cp /boot/uEnv.txt.orig /boot/uEnv.txt && rm -f /boot/uEnv.txt.orig && echo '  uEnv.txt restored'; else sed -i 's/^bitstream_image=.*/bitstream_image=system_top.bin/' /boot/uEnv.txt && echo '  uEnv.txt: bitstream_image=system_top.bin'; fi
      [ -f /boot/uramdisk.image.xz.orig ] && cp /boot/uramdisk.image.xz.orig /boot/uramdisk.image.xz && rm -f /boot/uramdisk.image.xz.orig && echo '  uramdisk.image.xz restored'
      rm -f /boot/fix_top.bin /boot/system_top.bin.orig; rm -rf /boot/gpsdo; echo '  fix_top.bin and gpsdo/ removed'
      if [ -f $HOOK ] && grep -q '$HOOK_MARK' $HOOK; then rm -f $HOOK; echo '  jffs2 hook removed'; elif [ -f $HOOK ]; then echo '  jffs2 hook left in place (not written by this script)'; fi
      sync"
    net_status; echo "Done. Reboot the LibreSDR to return to the stock state."
}
net_run() {
    ssh_run "if [ -x /usr/sbin/gpsdo_boot.sh ]; then s=/usr/sbin/gpsdo_boot.sh; elif [ -f /boot/gpsdo/gpsdo_boot.sh ]; then s='sh /boot/gpsdo/gpsdo_boot.sh'; else echo 'gpsdo_boot.sh is not installed'; exit 1; fi; echo \"running \$s ...\"; \$s; cat /tmp/gpsdo_boot.log"
}

# ------------------------------------------------------------------- main
ACTION=""; HOST=""; SD=""; METHOD=hook; FORCE=0; PASS="${LIBRESDR_PASS:-analog}"
while [ $# -gt 0 ]; do
    case "$1" in
        install|uninstall|status|run) ACTION="$1" ;;
        --host) HOST="${2:-}"; shift ;;
        --sd) SD="${2:-}"; shift ;;
        --ramdisk) METHOD=ramdisk ;;
        --hook) METHOD=hook ;;
        --force) FORCE=1 ;;
        --pass) PASS="${2:-}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1"; usage; exit 1 ;;
    esac; shift
done
[ -n "$ACTION" ] || { usage; exit 1; }
if [ -n "$SD" ]; then
    [ -d "$SD" ] || die "$SD is not a directory (mount the card's FAT partition first)"
    case "$ACTION" in install) sd_install "$SD" ;; uninstall) sd_uninstall "$SD" ;; status) sd_status "$SD" ;; run) die "run needs --host (a running board)" ;; esac
elif [ -n "$HOST" ]; then
    case "$ACTION" in install) net_install ;; uninstall) net_uninstall ;; status) net_status ;; run) net_run ;; esac
else
    die "give a target: --host <ip> or --sd <path>"
fi
