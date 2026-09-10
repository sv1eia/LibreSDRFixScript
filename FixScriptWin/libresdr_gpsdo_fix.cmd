<# : batch part; the PowerShell code follows the end of this comment block
@echo off
rem Copyright (C) 2026 Christos Nikolaou (SV1EIA)
rem Christos Nikolaou can be reached by email at : sv1eia@gmail.com
rem SPDX-License-Identifier: GPL-3.0-or-later
rem
rem libresdr_gpsdo_fix.cmd - give a stock tezuka_fw v0.3.21 LibreSDR SD card the
rem fixed bitstream (dacxx11_spi DIN/SCLK timing fix) and the GPSDO acquisition
rem at boot (gpsdo_boot), from a plain Windows 10 PC. One file: this batch header
rem starts the PowerShell 5.1 code that follows it, with the execution policy
rem bypassed for this process only (no admin rights, no settings change).
rem
rem   libresdr_gpsdo_fix.cmd <action> -SD <drive letter>            card in a USB reader
rem   libresdr_gpsdo_fix.cmd <action> -Board <ip> [-Ramdisk]        running LibreSDR over SSH
rem   actions: install | uninstall | status | run | setup-key | remove-key     options: -Force
rem
rem Files needed in this folder: fix_top.bin, gpsdo_boot.sh, uramdisk.image.xz
setlocal
set "LSDR_HERE=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& ([ScriptBlock]::Create((Get-Content -LiteralPath '%~f0' -Raw))) %*"
set "RC=%ERRORLEVEL%"
if "%~1"=="" pause
endlocal & exit /b %RC%
#>
param(
    [Parameter(Position=0)] [ValidateSet('install','uninstall','status','run','setup-key','remove-key','help')] [string]$Action = 'help',
    [string]$SD = '',
    [string]$Board = '',
    [switch]$Ramdisk,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Here      = $env:LSDR_HERE.TrimEnd('\')   # folder of this .cmd, set by the batch header
$FixBin    = Join-Path $Here 'fix_top.bin'
$GpsdoSh   = Join-Path $Here 'gpsdo_boot.sh'
$RdFixed   = Join-Path $Here 'uramdisk.image.xz'
$StockBit  = 'c6a69779c8678d09f4881e8e276f890a'   # tezuka v0.3.21 libre system_top.bin
$FixMd5    = '3c29f12e04e3e1378d14ad028c478188'   # fix_top.bin
$StockRd   = '95fec71b1d8f2a1c60fdd1b5734129cf'   # stock v0.3.21 uramdisk.image.xz
$FixedRd   = '4e5eb63f343c021b9b6a82dca97a56d1'   # prebuilt uramdisk.image.xz with gpsdo_boot inside
$Hook      = '/mnt/jffs2/autorun.sh'
$HookMark  = 'gpsdo acquisition at boot (libresdr_gpsdo_fix)'
$HookLine  = '[ -f /boot/gpsdo/gpsdo_boot.sh ] && sh /boot/gpsdo/gpsdo_boot.sh >/dev/null 2>&1 &'

function Md5([string]$p) { (Get-FileHash -Algorithm MD5 -LiteralPath $p).Hash.ToLower() }
function Note([string]$m) { Write-Host "  $m" }
function Fail([string]$m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

function Show-Help {
@'
libresdr_gpsdo_fix.cmd - LibreSDR GPSDO fix installer for a stock tezuka_fw v0.3.21 card

  libresdr_gpsdo_fix.cmd <action> -SD <drive letter>            card in a USB reader
  libresdr_gpsdo_fix.cmd <action> -Board <ip> [-Ramdisk]        running LibreSDR over SSH
  actions: install | uninstall | status | run | setup-key | remove-key     options: -Force

Network mode asks for the board's password ("analog") once per action. Windows'
own OpenSSH cannot take a password from the command line; for prompt-free use
run "setup-key -Board <ip>" once (one prompt): it creates lsdr_key in this
folder and installs it on the board, and every later action uses it.
"remove-key" undoes that on the board and here.

Everything the script needs sits in its own folder:
  fix_top.bin, gpsdo_boot.sh, uramdisk.image.xz (prebuilt for v0.3.21), Readme.txt
'@
}

# ---- byte-exact edit of the bitstream_image line (no CRLF, no BOM) ---------
function Set-Bitstream([string]$uenv, [string]$name) {
    $bytes = [IO.File]::ReadAllBytes($uenv)
    $text  = [Text.Encoding]::ASCII.GetString($bytes)
    $new   = [regex]::Replace($text, '(?m)^bitstream_image=.*$', "bitstream_image=$name")
    [IO.File]::WriteAllBytes($uenv, [Text.Encoding]::ASCII.GetBytes($new))
}
function Get-Bitstream([string]$uenv) {
    $text = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($uenv))
    [regex]::Match($text, '(?m)^bitstream_image=.*$').Value
}

# ---- local files ------------------------------------------------------------
function Check-LocalFiles([bool]$needRd) {
    if (-not (Test-Path -LiteralPath $FixBin)) { Fail "missing $FixBin (must be in the same folder as this script)" }
    if ((Md5 $FixBin) -ne $FixMd5) { Fail "fix_top.bin has an unexpected md5 (expected $FixMd5)" }
    if (-not (Test-Path -LiteralPath $GpsdoSh)) { Fail "missing $GpsdoSh" }
    if ($needRd) {
        if (-not (Test-Path -LiteralPath $RdFixed)) { Fail "missing $RdFixed (the prebuilt ramdisk)" }
        if ((Md5 $RdFixed) -ne $FixedRd) { Fail "uramdisk.image.xz in this folder has an unexpected md5 (expected $FixedRd)" }
    }
}

# =========================================================== SD card (local)
function SD-Path([string]$sd) {
    $p = $sd.Trim()
    if ($p -match '^[A-Za-z]:$') { $p = $p + '\' }
    if (-not (Test-Path -LiteralPath $p)) { Fail "$p is not accessible (is the card in the reader?)" }
    return $p.TrimEnd('\')
}
function SD-Check([string]$p) {
    foreach ($f in 'BOOT.bin','uEnv.txt','uramdisk.image.xz','system_top.bin') {
        if (-not (Test-Path -LiteralPath (Join-Path $p $f))) { Fail "$p does not look like a LibreSDR boot partition (missing $f)" }
    }
    if (-not $Force -and -not (Test-Path -LiteralPath (Join-Path $p 'system_top.bin.orig'))) {
        $m = Md5 (Join-Path $p 'system_top.bin')
        if ($m -ne $StockBit) { Fail "system_top.bin is not the stock v0.3.21 bitstream (md5 $m); use -Force if you know what you are doing" }
    }
}
function SD-RamdiskState([string]$p) {
    $m = Md5 (Join-Path $p 'uramdisk.image.xz')
    if ($m -eq $StockRd) { return 'stock' } elseif ($m -eq $FixedRd) { return 'fixed' } else { return "other ($m)" }
}
function SD-Status([string]$p) {
    Write-Host "SD at $p"
    $bit = Md5 (Join-Path $p 'system_top.bin')
    Note ("system_top.bin  : $bit " + $(if ($bit -eq $StockBit) { '(stock v0.3.21)' } else { '(not the stock file)' }))
    $fp = Join-Path $p 'fix_top.bin'
    Note ("fix_top.bin     : " + $(if (Test-Path -LiteralPath $fp) { if ((Md5 $fp) -eq $FixMd5) { 'present, md5 OK' } else { 'present, md5 MISMATCH' } } else { 'absent' }))
    Note ("uEnv.txt        : " + (Get-Bitstream (Join-Path $p 'uEnv.txt')) + "   backup: " + $(if (Test-Path -LiteralPath (Join-Path $p 'uEnv.txt.orig')) { 'yes' } else { 'no' }))
    $rs = SD-RamdiskState $p
    Note ("ramdisk         : " + $(switch -Wildcard ($rs) { 'stock' { 'stock v0.3.21' } 'fixed' { 'fixed (contains S22gpsdo + gpsdo_boot.sh)' } default { "unknown $rs" } }) + "   backup: " + $(if (Test-Path -LiteralPath (Join-Path $p 'uramdisk.image.xz.orig')) { 'yes' } else { 'no' }))
    Note ("gpsdo\ on card  : " + $(if (Test-Path -LiteralPath (Join-Path $p 'gpsdo\gpsdo_boot.sh')) { 'gpsdo_boot.sh (hook method)' } else { 'none' }))
}
function SD-Install([string]$p) {
    Check-LocalFiles $true; SD-Check $p
    Write-Host "Installing on the SD at $p (ramdisk method) ..."
    $uenv = Join-Path $p 'uEnv.txt'
    if (-not (Test-Path -LiteralPath "$uenv.orig")) { Copy-Item -LiteralPath $uenv -Destination "$uenv.orig" }
    $fp = Join-Path $p 'fix_top.bin'
    if ((Test-Path -LiteralPath $fp) -and ((Md5 $fp) -eq $FixMd5)) { Note 'fix_top.bin already present' }
    else { Copy-Item -LiteralPath $FixBin -Destination $fp; if ((Md5 $fp) -ne $FixMd5) { Fail 'fix_top.bin copy failed (md5)' }; Note 'fix_top.bin copied and verified' }
    if ((Get-Bitstream $uenv) -eq 'bitstream_image=fix_top.bin') { Note 'uEnv.txt already selects fix_top.bin' }
    else { Set-Bitstream $uenv 'fix_top.bin'; if ((Get-Bitstream $uenv) -ne 'bitstream_image=fix_top.bin') { Fail 'uEnv.txt edit failed' }; Note 'uEnv.txt: bitstream_image=fix_top.bin' }
    $rd = Join-Path $p 'uramdisk.image.xz'
    $rs = SD-RamdiskState $p
    if ($rs -eq 'fixed') { Note 'ramdisk already contains gpsdo_boot' }
    elseif ($rs -eq 'stock') {
        if (-not (Test-Path -LiteralPath "$rd.orig")) { Copy-Item -LiteralPath $rd -Destination "$rd.orig" }
        Copy-Item -LiteralPath $RdFixed -Destination $rd
        if ((Md5 $rd) -ne $FixedRd) { Fail 'ramdisk copy failed (md5); restore uramdisk.image.xz from uramdisk.image.xz.orig' }
        Note 'uramdisk.image.xz replaced and verified (original kept as uramdisk.image.xz.orig)'
    } else { Fail "the card's ramdisk is neither the stock v0.3.21 one nor the fixed one ($rs); refusing to replace it (a wrong rootfs would not boot)" }
    SD-Status $p
    Write-Host 'Done. Eject the card from Windows, put it in the LibreSDR and boot.'
}
function SD-Uninstall([string]$p) {
    Write-Host "Uninstalling from the SD at $p ..."
    $uenv = Join-Path $p 'uEnv.txt'
    if (Test-Path -LiteralPath "$uenv.orig") { Copy-Item -LiteralPath "$uenv.orig" -Destination $uenv; Remove-Item -LiteralPath "$uenv.orig"; Note 'uEnv.txt restored' }
    elseif (Test-Path -LiteralPath $uenv) { Set-Bitstream $uenv 'system_top.bin'; Note 'uEnv.txt: bitstream_image=system_top.bin' }
    $rd = Join-Path $p 'uramdisk.image.xz'
    if (Test-Path -LiteralPath "$rd.orig") { Copy-Item -LiteralPath "$rd.orig" -Destination $rd; if ((Md5 $rd) -ne (Md5 "$rd.orig")) { Fail 'ramdisk restore failed (md5)' }; Remove-Item -LiteralPath "$rd.orig"; Note 'uramdisk.image.xz restored' }
    foreach ($f in 'fix_top.bin','system_top.bin.orig') { $x = Join-Path $p $f; if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x } }
    $g = Join-Path $p 'gpsdo'; if (Test-Path -LiteralPath $g) { Remove-Item -LiteralPath $g -Recurse }
    Note 'fix_top.bin and gpsdo\ removed'
    SD-Status $p
    Write-Host 'Done. Eject the card from Windows before removing it.'
}

# ================================================================ network
$SshExe = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
$TarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
$KeyFile = Join-Path $Here 'lsdr_key'
$SshBase = @('-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=NUL','-o','LogLevel=ERROR','-o','ConnectTimeout=15')
function Ssh-Opts { if (Test-Path -LiteralPath $KeyFile) { return $SshBase + @('-i',$KeyFile,'-o','IdentitiesOnly=yes') } else { return $SshBase } }
function Need-Ssh { if (-not (Test-Path -LiteralPath $SshExe)) { Fail 'the Windows OpenSSH client is not installed (Settings > Apps > Optional features > OpenSSH Client)' } }
function Prompt-Note { if (-not (Test-Path -LiteralPath $KeyFile)) { Write-Host "  (type the board's password, analog, when asked)" } }
# The remote script travels base64-encoded and is written to a file on the board
# before it runs: PowerShell does not escape embedded quotes for native programs,
# and running from a file keeps the SSH channel's standard input free for data.
function Remote-Wrap([string]$cmd) { $b = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(($cmd -replace "`r",""))); return "echo $b | base64 -d > /tmp/lsdr_cmd.sh && sh /tmp/lsdr_cmd.sh; r=`$?; rm -f /tmp/lsdr_cmd.sh; exit `$r" }
function Ssh-Run([string]$cmd) { $o = Ssh-Opts; & $SshExe @o "root@$Board" (Remote-Wrap $cmd); if ($LASTEXITCODE -ne 0) { Fail "ssh command failed (exit $LASTEXITCODE)" } }
# One SSH session: a tar stream of the given files (from $Here plus the remote
# script from %TEMP%) piped into ssh; the remote unpacks to /tmp/lsdr_in and runs
# lsdr_cmd.sh from there. cmd.exe does the piping (PowerShell 5.1 would mangle bytes).
function Ssh-Stream([string[]]$files, [string]$script) {
    $tmp = Join-Path $env:TEMP ("lsdr_" + [IO.Path]::GetRandomFileName().Replace('.',''))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $tmp 'lsdr_cmd.sh'), [Text.Encoding]::ASCII.GetBytes(($script -replace "`r","")))
    $o = (Ssh-Opts) -join ' '
    $list = ($files | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $remote = 'mkdir -p /tmp/lsdr_in && cd /tmp/lsdr_in && tar -xf - && sh ./lsdr_cmd.sh; r=$?; cd / && rm -rf /tmp/lsdr_in; exit $r'
    $bat = "@echo off`r`n`"$TarExe`" -cf - -C `"$Here`" $list -C `"$tmp`" lsdr_cmd.sh | `"$SshExe`" $o root@$Board `"$remote`"`r`nexit /b %ERRORLEVEL%`r`n"
    [IO.File]::WriteAllBytes((Join-Path $tmp 'run.cmd'), [Text.Encoding]::ASCII.GetBytes($bat))
    & cmd.exe /c (Join-Path $tmp 'run.cmd'); $rc = $LASTEXITCODE
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    if ($rc -ne 0) { Fail "install session failed (exit $rc)" }
}
$NetStatusCmd = @'
m=$(md5sum /boot/system_top.bin | cut -c1-32); echo "  system_top.bin  : $m $([ $m = __STOCKBIT__ ] && echo '(stock v0.3.21)' || echo '(not the stock file)')"
if [ -f /boot/fix_top.bin ]; then f=$(md5sum /boot/fix_top.bin | cut -c1-32); echo "  fix_top.bin     : present $([ $f = __FIXMD5__ ] && echo 'md5 OK' || echo 'md5 MISMATCH')"; else echo '  fix_top.bin     : absent'; fi
echo "  uEnv.txt        : $(grep '^bitstream_image=' /boot/uEnv.txt | head -1)   backup: $([ -f /boot/uEnv.txt.orig ] && echo yes || echo no)"
echo "  ramdisk backup  : $([ -f /boot/uramdisk.image.xz.orig ] && echo 'uramdisk.image.xz.orig present (ramdisk method)' || echo none)"
echo "  booted rootfs   : $([ -x /etc/init.d/S22gpsdo ] && echo 'has S22gpsdo (ramdisk method active)' || echo 'stock (no S22gpsdo)')"
echo "  gpsdo/ on card  : $([ -f /boot/gpsdo/gpsdo_boot.sh ] && echo 'gpsdo_boot.sh' || echo none)"
echo "  jffs2 hook      : $([ -f __HOOK__ ] && sed -n 2p __HOOK__ || echo none)"
echo "  xo_correction   : $(cat /sys/bus/iio/devices/iio:device0/xo_correction 2>/dev/null) (live)  $(fw_printenv -n xo_correction 2>/dev/null || echo unset) (env)"
st=$(devmem 0x43C00010 32); e=$(( $(devmem 0x43C00018 32) )); [ $e -ge 2147483648 ] && e=$((e-4294967296))
echo "  loop            : dac $(( $(devmem 0x43C00008 32) & 0xFFFF )) err $e counts locked=$(( st & 1 )) ref_present=$(( (st>>1) & 1 ))"
echo '  last acquisition:'; tail -4 /tmp/gpsdo_boot.log 2>/dev/null | sed 's/^/    /' || echo '    (no log)'
'@
function Net-StatusCmd { ($NetStatusCmd -creplace '__STOCKBIT__',$StockBit -creplace '__FIXMD5__',$FixMd5 -creplace '__HOOK__',$Hook) -replace "`r","" }
function Net-Status { Need-Ssh; Write-Host "LibreSDR ${Board}:"; Prompt-Note; Ssh-Run (Net-StatusCmd) }
function Net-Install {
    Need-Ssh; Check-LocalFiles $Ramdisk.IsPresent
    if (-not (Test-Path -LiteralPath $TarExe)) { Fail 'tar.exe is missing (it is part of Windows 10 since version 1803)' }
    $method = $(if ($Ramdisk) { 'ramdisk' } else { 'hook' })
    Write-Host "Installing on LibreSDR $Board (method: $method) ..."; Prompt-Note
    $gate = $(if ($Force) { '' } else { "if [ ! -f /boot/system_top.bin.orig ]; then m=`$(md5sum /boot/system_top.bin | cut -c1-32); [ `$m = $StockBit ] || { echo 'ERROR: system_top.bin is not the stock v0.3.21 bitstream (md5 '`$m'); use -Force'; exit 1; }; fi`n" })
    $s = "mount | grep -q ' /boot ' || { echo 'ERROR: /boot (SD FAT) is not mounted on the board'; exit 1; }`n$gate"
    $s += "f=`$(md5sum fix_top.bin | cut -c1-32); [ `$f = $FixMd5 ] || { echo 'ERROR: fix_top.bin arrived corrupted'; exit 1; }`n"
    $s += "[ -f /boot/uEnv.txt.orig ] || cp /boot/uEnv.txt /boot/uEnv.txt.orig`ncp -f fix_top.bin /boot/fix_top.bin && echo '  fix_top.bin copied'`n"
    $s += "grep -q '^bitstream_image=fix_top.bin' /boot/uEnv.txt || sed -i 's/^bitstream_image=.*/bitstream_image=fix_top.bin/' /boot/uEnv.txt; echo '  uEnv.txt: bitstream_image=fix_top.bin'`n"
    if ($method -eq 'hook') {
        $files = @('fix_top.bin','gpsdo_boot.sh')
        $s += "mkdir -p /boot/gpsdo && cp -f gpsdo_boot.sh /boot/gpsdo/gpsdo_boot.sh && echo '  gpsdo_boot.sh copied'`n"
        $s += "printf '#!/bin/sh\n# $HookMark $(Get-Date -Format yyyy-MM-dd)\n%s\n' '$HookLine' > $Hook && chmod +x $Hook && echo '  jffs2 hook written'`n"
    } else {
        $files = @('fix_top.bin','uramdisk.image.xz')
        $s += "r=`$(md5sum uramdisk.image.xz | cut -c1-32); [ `$r = $FixedRd ] || { echo 'ERROR: ramdisk arrived corrupted'; exit 1; }`n"
        $s += "[ -f /boot/uramdisk.image.xz.orig ] || cp /boot/uramdisk.image.xz /boot/uramdisk.image.xz.orig`ncp -f uramdisk.image.xz /boot/uramdisk.image.xz && echo '  prebuilt ramdisk copied'`n"
        $s += "r=`$(md5sum /boot/uramdisk.image.xz | cut -c1-32); [ `$r = $FixedRd ] || { echo 'ERROR: ramdisk md5 mismatch on the card - restoring'; cp /boot/uramdisk.image.xz.orig /boot/uramdisk.image.xz; exit 1; }; echo '  ramdisk verified'`n"
        $s += "rmdir /boot/gpsdo 2>/dev/null; grep -q '$HookMark' $Hook 2>/dev/null && rm -f $Hook`n"
    }
    $s += "sync; echo '  done'`necho 'LibreSDR status:'`n" + (Net-StatusCmd) + "`n"
    Ssh-Stream $files $s
    Write-Host 'Done. Reboot the LibreSDR to run the new bitstream and the acquisition.'
}
function Net-Uninstall {
    Need-Ssh; Write-Host "Uninstalling from LibreSDR $Board ..."; Prompt-Note
    $c = "if [ -f /boot/uEnv.txt.orig ]; then cp /boot/uEnv.txt.orig /boot/uEnv.txt && rm -f /boot/uEnv.txt.orig && echo '  uEnv.txt restored'; else sed -i 's/^bitstream_image=.*/bitstream_image=system_top.bin/' /boot/uEnv.txt && echo '  uEnv.txt: bitstream_image=system_top.bin'; fi; "
    $c += "[ -f /boot/uramdisk.image.xz.orig ] && cp /boot/uramdisk.image.xz.orig /boot/uramdisk.image.xz && rm -f /boot/uramdisk.image.xz.orig && echo '  uramdisk.image.xz restored'; "
    $c += "rm -f /boot/fix_top.bin /boot/system_top.bin.orig; rm -rf /boot/gpsdo; echo '  fix_top.bin and gpsdo/ removed'; "
    $c += "if [ -f $Hook ] && grep -q '$HookMark' $Hook; then rm -f $Hook; echo '  jffs2 hook removed'; elif [ -f $Hook ]; then echo '  jffs2 hook left in place (not written by this script)'; fi; sync"
    Ssh-Run ($c -replace "`r","")
    Net-Status; Write-Host 'Done. Reboot the LibreSDR to return to the stock state.'
}
function Net-Run {
    Need-Ssh; Prompt-Note
    Ssh-Run "if [ -x /usr/sbin/gpsdo_boot.sh ]; then s=/usr/sbin/gpsdo_boot.sh; elif [ -f /boot/gpsdo/gpsdo_boot.sh ]; then s='sh /boot/gpsdo/gpsdo_boot.sh'; else echo 'gpsdo_boot.sh is not installed'; exit 1; fi; echo `"running `$s ...`"; `$s; cat /tmp/gpsdo_boot.log"
}


# ---- prompt-free operation: a key pair in this folder, its public half on the board
$KeyGen = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh-keygen.exe'
$RemoteAuth = '/mnt/jffs2/etc/ssh/authorized_keys'   # restored to /root/.ssh at every boot by S21misc
function Net-SetupKey {
    Need-Ssh
    if (-not (Test-Path -LiteralPath $KeyFile)) {
        & $KeyGen -q -t ed25519 -N '""' -C 'lsdr_key' -f $KeyFile | Out-Null
        if (-not (Test-Path -LiteralPath $KeyFile)) { Fail 'ssh-keygen did not create the key' }
        # Windows OpenSSH refuses a private key readable by other users: keep it to this account only
        & icacls.exe $KeyFile /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
        Note "key pair created: $KeyFile (keep this folder private: it opens root on the board)"
    } else { Note "using the existing $KeyFile" }
    $pub = ([IO.File]::ReadAllText("$KeyFile.pub")).Trim()
    Write-Host "Installing the key on LibreSDR $Board (one password prompt) ..."
    $s = "mkdir -p /root/.ssh /mnt/jffs2/etc/ssh && chmod 700 /root/.ssh`n"
    $s += "for f in /root/.ssh/authorized_keys $RemoteAuth; do touch `$f; grep -v ' lsdr_key`$' `$f > `$f.new; echo '$pub' >> `$f.new; mv `$f.new `$f; chmod 600 `$f; done`n"
    $s += "sync; echo '  key installed (also in flash, restored at every boot)'"
    $o = $SshBase; & $SshExe @o "root@$Board" (Remote-Wrap $s); if ($LASTEXITCODE -ne 0) { Fail "ssh command failed (exit $LASTEXITCODE)" }
    Write-Host 'Checking prompt-free access ...'; Ssh-Run "echo '  prompt-free access OK'"
}
function Net-RemoveKey {
    Need-Ssh; Write-Host "Removing the key from LibreSDR $Board and from this folder ..."
    $s = "for f in /root/.ssh/authorized_keys $RemoteAuth; do [ -f `$f ] && { grep -v ' lsdr_key`$' `$f > `$f.new; mv `$f.new `$f; chmod 600 `$f; [ -s `$f ] || rm -f `$f; }; done; sync; echo '  key removed from the board'"
    Ssh-Run $s
    Remove-Item -LiteralPath $KeyFile, "$KeyFile.pub" -Force -ErrorAction SilentlyContinue
    Note 'local key files removed'
}

# ==================================================================== main
if ($Action -eq 'help') { Show-Help; exit 0 }
if ($SD -ne '') {
    $p = SD-Path $SD
    switch ($Action) { 'install' { SD-Install $p } 'uninstall' { SD-Uninstall $p } 'status' { SD-Status $p } default { Fail "$Action needs -Board <ip> (a running board)" } }
} elseif ($Board -ne '') {
    switch ($Action) { 'install' { Net-Install } 'uninstall' { Net-Uninstall } 'status' { Net-Status } 'run' { Net-Run } 'setup-key' { Net-SetupKey } 'remove-key' { Net-RemoveKey } }
} else { Show-Help; Fail 'give a target: -SD <drive letter> or -Board <ip>' }
exit 0
