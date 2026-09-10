LibreSDR GPSDO fix - one-shot installer for a stock tezuka_fw v0.3.21 SD card
Windows 10 edition
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
  libresdr_gpsdo_fix.cmd  the installer, one file: a batch header that runs
                          the PowerShell 5.1 code inside it (double-click for
                          help, or use it from a command prompt as below)
  fix_top.bin             the fixed bitstream for the libre board, v0.3.21 HDL
  gpsdo_boot.sh           the boot-time acquisition script (keep its Linux
                          line endings: do not open and save it with Notepad)
  uramdisk.image.xz       the v0.3.21 ramdisk with the acquisition built in
                          (prebuilt; Windows has no tools to repack one)
  Readme.txt              this file

Requirements
------------
  Windows 10 version 1803 or newer (this uses the OpenSSH client and
  PowerShell 5.1 that ship with Windows). No installation, no admin rights,
  no settings change: the .cmd starts PowerShell with the script policy
  bypassed for that one process, so it runs on a stock Windows where .ps1
  files are disabled. If you received this folder as a zip downloaded from
  the internet and Windows SmartScreen shows "Windows protected your PC" on
  double-click, choose "More info" > "Run anyway" (or run it from a command
  prompt, which does not trigger SmartScreen).
  For the network mode the OpenSSH client must be present: Settings > Apps >
  Optional features > "OpenSSH Client" (it is there by default on recent
  Windows 10). For the card mode nothing else is needed.

Usage - card in a USB reader (LibreSDR off)
-------------------------------------------
  Find the card's drive letter in Explorer (say F:), open a command prompt in
  this folder (shift + right-click > "Open PowerShell window here" or
  "Open command window here") and run:

      libresdr_gpsdo_fix.cmd status    -SD F:
      libresdr_gpsdo_fix.cmd install   -SD F:
      libresdr_gpsdo_fix.cmd uninstall -SD F:

  Then EJECT the card in Windows (notification area > "Safely remove") before
  pulling it, so the writes are flushed. Put it in the LibreSDR and boot.

Usage - running LibreSDR over the network
-----------------------------------------
      libresdr_gpsdo_fix.cmd status    -Board 192.168.1.13
      libresdr_gpsdo_fix.cmd install   -Board 192.168.1.13
      libresdr_gpsdo_fix.cmd run       -Board 192.168.1.13     (acquire now, no reboot)
      libresdr_gpsdo_fix.cmd uninstall -Board 192.168.1.13

  Each action opens one SSH session and asks once for the board's password:
  type "analog". (Windows' own OpenSSH has no way to take the password from
  the command line, so a -Pass option is not possible with stock Windows.)
  Add -Ramdisk to install the acquisition inside the SD's ramdisk (the
  prebuilt one is sent) instead of using the one-line hook in the board's
  flash. Reboot the LibreSDR after install or uninstall.

  Prompt-free operation (optional, recommended for repeated testing):
      libresdr_gpsdo_fix.cmd setup-key  -Board 192.168.1.13   (asks the password once)
  creates a key pair "lsdr_key" in this folder, installs its public half on
  the board (kept in the board's flash, so it survives reboots) and from then
  on every action of this tool runs without a prompt. When done:
      libresdr_gpsdo_fix.cmd remove-key -Board 192.168.1.13
  removes it from the board and deletes the local key files. Keep the folder
  private while the key exists: whoever has lsdr_key is root on the board.

How long it takes 
---------------------------------------
  Card in a USB reader:
      status      about 1 s (the 21 MB ramdisk is hashed to identify it)
      install     about 4 s (a 21 MB copy to the card), 1 s if already installed
      uninstall   about 2 s (the 21 MB original is copied back)
  A slow reader or a slow card makes all three longer, up to a minute.
  Over the network (plus the time to type the password, if no key):
      status      about 1.5 s
      install     about 2 s (hook method), about 10 s with -Ramdisk (21 MB)
      uninstall   about 2-3 s
      setup-key   about 2 s
      run         1 s when already locked, 10-25 s for a full acquisition
  After a reboot the LibreSDR answers on the network after about 45-50 s and
  the acquisition locks about 25-40 s after Linux starts.

Checks and safety
-----------------
  - install refuses a card whose system_top.bin is not the stock v0.3.21 file
    (md5 c6a69779c8678d09f4881e8e276f890a) unless -Force is given.
  - the ramdisk is replaced ONLY if it is the stock v0.3.21 one (md5
    95fec71b1d8f2a1c60fdd1b5734129cf) or already the fixed one; -Force does
    not override this, because a wrong rootfs would not boot.
  - every copy is verified by md5 (fix_top.bin 3c29f12e04e3e1378d14ad028c478188,
    fixed ramdisk 4e5eb63f343c021b9b6a82dca97a56d1).
  - uEnv.txt is edited byte for byte (one line changed, no line-ending or
    encoding change).
  - the card mode writes nothing anywhere except the card. The network hook
    method writes one line to the board's flash (/mnt/jffs2/autorun.sh),
    removed by uninstall; setup-key writes the public key to the board's
    flash (/mnt/jffs2/etc/ssh/authorized_keys), removed by remove-key.
  - If the board does not come up after a reboot: put the card in the reader
    and run "uninstall -SD F:", or copy uEnv.txt.orig over uEnv.txt.

After a reboot
--------------
  "status -Board <ip>" shows the live loop: expect locked=1 and an error of
  0 to +/-2 counts (1 count = 0.025 ppm) some 10-40 s after Linux is up, and
  the last acquisition log with two or three "iter" lines.
