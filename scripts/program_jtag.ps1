param([string]$Sdk='E:\fpga\SDK\2018.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$build=Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$log=Join-Path $build 'jtag_download.log'
$xsct=Join-Path $Sdk 'bin/xsct.bat'
if(-not(Test-Path -LiteralPath $xsct)){throw "SDK executable missing: $xsct"}
$previousArch=$env:PROCESSOR_ARCHITECTURE
$env:PROCESSOR_ARCHITECTURE='AMD64'
try {
    & $xsct (Join-Path $PSScriptRoot 'program_jtag.tcl') *> $log
    $downloadExit=$LASTEXITCODE
} finally {$env:PROCESSOR_ARCHITECTURE=$previousArch}
Get-Content -LiteralPath $log
# SDK 2018.2 may discard the Tcl exit code; require explicit completion too.
$complete=Select-String -LiteralPath $log -SimpleMatch 'JTAG image loaded. UART 115200'
if($downloadExit -ne 0 -or -not $complete){throw "JTAG download failed; inspect $log"}
