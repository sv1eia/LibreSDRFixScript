<!--
Copyright (C) 2026 Christos Nikolaou (SV1EIA)
Christos Nikolaou can be reached by email at : sv1eia@gmail.com
-->

# NOTICE - third-party sources and upstream commits

This repository ships two **binaries built from other people's source code**.
This file records exactly which upstream commit each one was built from, what
was changed, and under which licence, so that anyone receiving a binary can get
its corresponding source.

```
  FixScript/
    libresdr_gpsdo_fix.sh    original work by SV1EIA    GPL-3.0-or-later
    gpsdo_boot.sh            original work by SV1EIA    GPL-3.0-or-later
    fix_top.bin              DERIVED  <-  F5OEO/maia-sdr            (section 1)

  FixScriptWin/
    libresdr_gpsdo_fix.cmd   original work by SV1EIA    GPL-3.0-or-later
    gpsdo_boot.sh            original work by SV1EIA    GPL-3.0-or-later
    fix_top.bin              DERIVED  <-  F5OEO/maia-sdr            (section 1)
    uramdisk.image.xz        DERIVED  <-  F5OEO/tezuka_fw v0.3.21   (section 2)
```

---

## 1. `fix_top.bin` - the corrected FPGA bitstream

**What it is.** The LibreSDR (`libre` board) bitstream of tezuka_fw v0.3.21,
resynthesised from the maia-sdr HDL with a single Verilog source file changed:
the DACx311 SPI driver that tunes the VCTCXO.

### Upstream source

- **Upstream project** - <https://github.com/maia-sdr/maia-sdr>
  (the `maia-hdl` subtree)

- **Fork actually used** - <https://github.com/F5OEO/maia-sdr>,
  branch `refactor`

- **File changed** -
  `maia-hdl/projects/common/libre-vctcxo-lock/src/dacxx11_spi.v`

- **Unmodified upstream state** - commit
  [`a62e8eb024ad`](https://github.com/F5OEO/maia-sdr/commit/a62e8eb024ad),
  by F5OEO on 2026-08-10, *"Add Vctxo to libre and gpios"* - blob `7273b7f`

- **Branch head the change is based on** -
  [`108aa43f`](https://github.com/F5OEO/maia-sdr/commit/108aa43fdd01f24c2d6212983290d37ffec7d6cc)
  (`F5OEO:refactor`, full sha `108aa43fdd01f24c2d6212983290d37ffec7d6cc`)

- **Modified source, i.e. the corresponding source for this binary** -
  [`96e848fc`](https://github.com/sv1eia/maia-sdr/commit/96e848fcd153385ade9edd4d234168c2d7ad8319)
  on <https://github.com/sv1eia/maia-sdr>, branch `refactor` - blob `ee4cb84`,
  full sha `96e848fcd153385ade9edd4d234168c2d7ad8319`

- **Submitted upstream as** -
  [F5OEO/maia-sdr#10](https://github.com/F5OEO/maia-sdr/pull/10),
  *"LibreSDR Rev5 external reference 10MHz issue dacxx11_spi fix"*
  (open as of 2026-09-10)

- **Toolchain** - Xilinx Vivado 2023.1

The complete corresponding source for `fix_top.bin` is the tree at
`sv1eia/maia-sdr` commit `96e848fc`, with the `adi-hdl` and
`XilinxUnisimLibrary` submodules at the revisions that commit pins. The change
itself is one file and can be read as a diff at
<https://github.com/F5OEO/maia-sdr/pull/10/files>.

### What was changed

`dacxx11_spi.v` was inherited from Ettus' `ltc2630_spi.v`, whose DAC samples DIN
on the **rising** SCLK edge. The DACx311 samples on the **falling** edge, so the
inherited code presented new data on the same edge the DAC captured it (~0 ns
hold against a 4.5 ns requirement, SBAS442D t5/t6). The DAC captured old-or-new
bits, `data[11]` landed on the PD0 power-down bit, and the effective code became
`data | (data << 1)` - a non-monotonic tune curve the reference loop can never
settle on.

The fix presents DIN on the SCLK **rising** edge via one extra flip-flop
(`mosi_r`), and restores the Ettus gating so SCLK idles low and toggles only
while nSYNC is low. No change to the frame, the DEVICE parameter, the sign, or
the loop.

### Licences inside this bitstream

- **`maia-hdl`** - MIT, Copyright (c) 2022-2024 Daniel Estevez
  <daniel@destevez.net>. See `maia-hdl/LICENSE` in the upstream tree.

- **`dacxx11_spi.v`** (the file changed here) -
  **`SPDX-License-Identifier: LGPL-3.0-or-later`**, Copyright 2015 Ettus
  Research, a National Instruments Company; modified by
  <https://github.com/Shawn-McSorley>; further modified by F5OEO; and modified
  2026-09-07 by Christos Nikolaou (SV1EIA). The SV1EIA modification is offered
  under the same LGPL-3.0-or-later terms, and its source is published at the
  commit linked above.

- **`maia-hdl/adi-hdl`** - submodule of
  <https://github.com/analogdevicesinc/hdl>, under Analog Devices' own HDL
  licence terms.

- **`maia-hdl/XilinxUnisimLibrary`** - submodule of
  <https://github.com/Xilinx/XilinxUnisimLibrary>, under AMD/Xilinx terms.

The MIT and LGPL notices above are reproduced here to satisfy the attribution
requirement of those licences for a binary distribution.

---

## 2. `uramdisk.image.xz` - the prebuilt ramdisk (Windows package only)

**What it is.** The stock tezuka_fw **v0.3.21** `libre` ramdisk with one file
added: `/usr/sbin/gpsdo_boot.sh` plus its `/etc/init.d` hook. Nothing is removed
and nothing else is modified. It is shipped prebuilt only because Windows has no
tools to repack a U-Boot ramdisk; the Linux package (`FixScript/`) builds the
same image locally with `xz`, `cpio`, `fakeroot` and `mkimage`.

### Upstream source

- **Upstream project** - <https://github.com/F5OEO/tezuka_fw>

- **Release** -
  [v0.3.21](https://github.com/F5OEO/tezuka_fw/releases/tag/v0.3.21),
  published 2026-08-30

- **Release commit** -
  [`833d5369`](https://github.com/F5OEO/tezuka_fw/commit/833d536940749a0983e18087d98918674a5eacf7)
  (full sha `833d536940749a0983e18087d98918674a5eacf7`)

- **Release asset the stock image comes from** -
  `tezuka-libre-v0.3.21-833d536.zip`

The installers refuse to touch a card that does not carry the stock v0.3.21
files, identified by these hashes:

```
95fec71b1d8f2a1c60fdd1b5734129cf  uramdisk.image.xz   (stock v0.3.21 ramdisk)
c6a69779c8678d09f4881e8e276f890a  system_top.bin      (stock v0.3.21 bitstream)
```

This image is a Buildroot root filesystem containing GPL- and other
free-software-licensed programs. **Its corresponding source is the tezuka_fw
tree at commit `833d5369`** together with the sources Buildroot fetches for that
configuration; the only delta introduced here is `gpsdo_boot.sh`, which is in
this repository under GPL-3.0-or-later. No upstream binary in the image was
recompiled or patched.

---

## 3. `gpsdo_boot.sh` and the installers - original work

`gpsdo_boot.sh`, `libresdr_gpsdo_fix.sh` and `libresdr_gpsdo_fix.cmd` are
original work.

`gpsdo_boot.sh` has been offered to tezuka_fw as a libre-board rootfs overlay
(`etc/init.d/S22gpsdo` + `usr/sbin/gpsdo_boot.sh`):

- **Pull request** -
  [F5OEO/tezuka_fw#446](https://github.com/F5OEO/tezuka_fw/pull/446)

- **Branch and commit** - `sv1eia:gpsdo_boot`,
  [`787ea649`](https://github.com/sv1eia/tezuka_fw/commit/787ea649dcdf48d33b4731b3a1f73ec3d9cadaa5)
  (full sha `787ea649dcdf48d33b4731b3a1f73ec3d9cadaa5`)

- **Based on** - tezuka_fw `f58e2617fb0f031aa3f667833f44b5947d9e2533`

Once a tezuka_fw release carries both PR #10 (maia-sdr) and PR #446
(tezuka_fw), the installers in this repository are no longer needed.

---

## 4. Reproducing the binaries

`fix_top.bin`:

```sh
git clone https://github.com/sv1eia/maia-sdr
cd maia-sdr
git checkout 96e848fcd153385ade9edd4d234168c2d7ad8319
git submodule update --init --recursive
# build the libre-vctcxo-lock project with Vivado 2023.1, then convert
# system_top.bit -> system_top.bin (bootgen / write_cfgmem)
```

`uramdisk.image.xz` - unpack the stock v0.3.21 ramdisk, add
`usr/sbin/gpsdo_boot.sh` (mode 0755) and its init hook, repack:

```sh
./FixScript/libresdr_gpsdo_fix.sh install --sd /mnt/e --ramdisk
```

---

## 5. Checksums of the files in this repository

Sizes in bytes:

```
   2611136  fix_top.bin
  21060424  uramdisk.image.xz
      4985  gpsdo_boot.sh
```

MD5 - verify from the repository root with `md5sum -c`:

```
3c29f12e04e3e1378d14ad028c478188  FixScript/fix_top.bin
3c29f12e04e3e1378d14ad028c478188  FixScriptWin/fix_top.bin
78cc7fa0d8385793f64a3e32f7e979c4  FixScript/gpsdo_boot.sh
78cc7fa0d8385793f64a3e32f7e979c4  FixScriptWin/gpsdo_boot.sh
4e5eb63f343c021b9b6a82dca97a56d1  FixScriptWin/uramdisk.image.xz
```

SHA-256 - verify from the repository root with `sha256sum -c`:

```
9bc219e33139aa694d7f5f78348541625ffa9d4ff8002fc95474218b6a8755b0  FixScript/fix_top.bin
9bc219e33139aa694d7f5f78348541625ffa9d4ff8002fc95474218b6a8755b0  FixScriptWin/fix_top.bin
1a7705c9fce579410b73c994d9b6dff5a75e0f6ff4846b857b98347b0213994f  FixScript/gpsdo_boot.sh
1a7705c9fce579410b73c994d9b6dff5a75e0f6ff4846b857b98347b0213994f  FixScriptWin/gpsdo_boot.sh
5b2795d830d8b5a6d0712e627a15ac9e39d9b625273a907c439d7f29f14e6e43  FixScriptWin/uramdisk.image.xz
```

`fix_top.bin` and `gpsdo_boot.sh` are byte-identical in `FixScript/` and
`FixScriptWin/`.
