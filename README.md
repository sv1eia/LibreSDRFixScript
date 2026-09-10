<!--
Copyright (C) 2026 Christos Nikolaou (SV1EIA)
Christos Nikolaou can be reached by email at : sv1eia@gmail.com
-->

# LibreSDR GPSDO fix

One-shot installers that give a **LibreSDR Rev.5** running **tezuka_fw v0.3.21**
a working external 10 MHz reference (GPSDO) - without rebuilding the firmware.

## The problem

On the stock v0.3.21 bitstream the VCTCXO tune DAC (TI DACx311) is driven with
wrong SPI timing: data changes on the same clock edge the DAC samples it. The
DAC's top data bit lands on its power-down bit and the tune curve becomes
non-monotonic, so the reference loop can never settle and hunts once per
second - the transmit frequency steps by hundreds of Hz every second while
"locked". On top of that, even a correct loop starts from a fixed default at
every boot and needs up to an hour to reach the reference.

## The fix

Two parts, both in this repository:

1. **`fix_top.bin`** - the v0.3.21 bitstream rebuilt with the DAC SPI driver
   corrected (`dacxx11_spi.v`: data presented on the SCLK rising edge, SCLK
   idle low). The DAC becomes a clean, monotonic 12-bit converter.
2. **`gpsdo_boot.sh`** - a small script run once at boot that measures the
   VCTCXO against the reference, computes the right DAC code in two or three
   steps (about 8 s) and hands it to the loop with its integrator compensated.
   The board is locked to the GPSDO within about a minute of power-on.

The installers keep the stock files on the SD card (`*.orig`), so
**uninstall returns the card to stock**. The QSPI flash is never written,
except for an optional one-line boot hook and an optional SSH key, both
removed by the tools.

## Packages

| folder | for | needs |
|---|---|---|
| `FixScript/` | Linux (or WSL) | bash, ssh/scp (+ sshpass); for the card-reader mode: xz, cpio, fakeroot, mkimage |
| `FixScriptWin/` | Windows 10 (1803 or newer), stock | nothing to install: the built-in OpenSSH client and PowerShell, driven by one `.cmd` file |

Each folder is self-contained and has its own README with the exact
commands, timings and safety notes. Keep the files of a folder together.

## Quick start

Over the network, on a running board (default IP 192.168.1.13, password `analog`):

```
Linux:    ./libresdr_gpsdo_fix.sh install --host 192.168.1.13
Windows:  libresdr_gpsdo_fix.cmd install -Board 192.168.1.13
```

then reboot the LibreSDR. `status` shows the live loop (expect `locked=1`
and an error of a few counts, 1 count = 0.025 ppm); `uninstall` and a reboot
return to stock. With the SD card in a USB reader instead:

```
Linux:    ./libresdr_gpsdo_fix.sh install --sd /mnt/e          (card mounted at /mnt/e)
Windows:  libresdr_gpsdo_fix.cmd install -SD F:                 (card at drive F:)
```

## Safety

- The tools refuse a card that does not carry the stock v0.3.21 bitstream
  (md5 `c6a69779c8678d09f4881e8e276f890a`); the fixed bitstream was built from
  the v0.3.21 HDL and must not be used with other releases.
- Every copied file is verified by md5. `uEnv.txt` is edited byte for byte
  (one line: `bitstream_image=fix_top.bin`).
- If the board does not come up after a reboot: put the card in a reader and
  run `uninstall` in card mode, or copy `uEnv.txt.orig` over `uEnv.txt`.

## Upstream

The same changes are offered to the upstream projects: the SPI driver fix to
F5OEO/maia-sdr (branch `refactor`, file
`maia-hdl/projects/common/libre-vctcxo-lock/src/dacxx11_spi.v`) and the boot
acquisition to F5OEO/tezuka_fw (a libre-board overlay with `S22gpsdo` and
`/usr/sbin/gpsdo_boot.sh`). Once a tezuka_fw release carries both, these
installers are no longer needed.

## Measured on board

- DAC before the fix: top bit dead, an 8 ppm step in the middle of the range,
  no code able to reach the reference frequency.
- DAC after the fix: linear to 0.16 ppm over the full range, 0.0077 ppm per
  code, zero crossing reachable.
- Boot to lock with `gpsdo_boot.sh`: about 25 s (init script in the rootfs)
  or 40 s (SD hook) after the kernel starts; steady state 0 to 2 counts.
- On air: the 1 Hz steps are gone; a transmitted tone holds within a few Hz
  at 2.4 GHz.

## Author and license

Christos Nikolaou, SV1EIA.

Licensed under the GNU General Public License, version 3 (see `LICENSE`),
the same license as tezuka_fw, whose v0.3.21 firmware these tools modify.
The fixed bitstream is built from the F5OEO/maia-sdr HDL with the SPI driver
correction; `gpsdo_boot.sh` and the installers are original work.
