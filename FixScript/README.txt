LibreSDR GPSDO fix - one-shot installer for a stock tezuka_fw v0.3.21 SD card
==============================================================================

Copyright (C) 2026 Christos Nikolaou (SV1EIA)
Christos Nikolaou can be reached by email at : sv1eia@gmail.com

What it does
------------
Gives a LibreSDR Rev.5 running tezuka_fw v0.3.21 two things, without a
firmware rebuild:

  1. a fixed FPGA bitstream (fix_top.bin) in which the VCTCXO tune DAC is
     driven with correct SPI timing - on the stock bitstream the DAC's top bit
     acted as a power-down and the tune curve was non-monotonic, which made
     the external-reference loop hunt once per second (the "1 Hz wobble");
  2. a small script (gpsdo_boot.sh) run at boot that locks the VCTCXO to the
     10 MHz reference within seconds instead of up to an hour.

The stock files stay on the card (uEnv.txt.orig, uramdisk.image.xz.orig,
system_top.bin untouched), so "uninstall" returns the card to stock.

Files in this folder (keep them together)
-----------------------------------------
  libresdr_gpsdo_fix.sh   the installer (bash, run on a Linux PC or WSL)
  fix_top.bin             the fixed bitstream for the libre board, v0.3.21 HDL
  gpsdo_boot.sh           the boot-time acquisition script (POSIX sh)
  README.txt              this file

Requirements on the PC
----------------------
  ssh and scp (OpenSSH), plus sshpass (recommended) - the board's password is
  "analog". For the card-reader / --ramdisk method also: xz, cpio, fakeroot,
  mkimage (package u-boot-tools). On Debian/Ubuntu/WSL:
      sudo apt install sshpass xz-utils cpio fakeroot u-boot-tools

Usage
-----
  Over the network, board running (default method: script on the card + a
  one-line boot hook in the board's flash):
      ./libresdr_gpsdo_fix.sh install   --host 192.168.1.13
      ./libresdr_gpsdo_fix.sh status    --host 192.168.1.13
      ./libresdr_gpsdo_fix.sh run       --host 192.168.1.13     (acquire now, no reboot)
      ./libresdr_gpsdo_fix.sh uninstall --host 192.168.1.13
  Add --ramdisk to install the script inside the SD's ramdisk instead of using
  the flash hook (same layout as the firmware patch; flash untouched).

  On the SD card in a USB reader (board off; the ramdisk method is used):
      sudo mkdir -p /mnt/e && sudo mount -t drvfs E: /mnt/e      (WSL; E: = the card)
      ./libresdr_gpsdo_fix.sh install --sd /mnt/e
      sudo umount /mnt/e
  On a native Linux PC mount the card's FAT partition and pass its path.

  Reboot the LibreSDR after install or uninstall.

How long it takes (card reader mode, measured on a USB reader
mounted in WSL; a fast reader or a native Linux mount is quicker, a slow one
slower - the 21 MB ramdisk is read and written through the reader)
      status      about 1 s on a stock card, 3-5 s on an installed card
      install     about 3 minutes (about 50 s of that is repacking the ramdisk)
      uninstall   a few seconds
  Network mode (measured on a LibreSDR over 1G Ethernet):
      status                about 1 s
      install               about 5 s (hook method)  /  about 55 s with --ramdisk
      run                   1 s when already locked, 10-25 s for a full acquisition
      uninstall             1-3 s
      reboot until SSH answers   about 45-50 s; the acquisition locks about
                            25 s (ramdisk method) or 40 s (hook method) after
                            the kernel starts

Checks and safety
-----------------
  - install refuses a card whose system_top.bin is not the stock v0.3.21 file
    (md5 c6a69779c8678d09f4881e8e276f890a) unless --force is given; the fixed
    bitstream was built from the v0.3.21 HDL and must not be used elsewhere.
  - fix_top.bin is md5-verified (3c29f12e04e3e1378d14ad028c478188) before and
    after copying.
  - Nothing in the QSPI flash is written except, in the default network
    method, the one-line hook /mnt/jffs2/autorun.sh (removed by uninstall).
  - If the board does not come up after a reboot: put the card in a reader
    and either run "uninstall --sd <path>" or copy uEnv.txt.orig over uEnv.txt.

After a reboot
--------------
  "status --host <ip>" shows the live loop: expect locked=1 and an error of
  0 to +/-2 counts (1 count = 0.025 ppm) some 10-40 s after Linux is up, and
  the last acquisition log with two or three "iter" lines.
