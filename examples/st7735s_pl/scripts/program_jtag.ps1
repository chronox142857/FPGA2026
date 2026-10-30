param([string]$Sdk='E:\fpga\SDK\2018.2',[string]$Vivado='E:\fpga\Vivado\2018.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$log=Join-Path $root 'build/jtag_download.log'
$previousArch=$env:PROCESSOR_ARCHITECTURE
$env:PROCESSOR_ARCHITECTURE='AMD64'
try {
    & "$Sdk/bin/xsct.bat" (Join-Path $PSScriptRoot 'program_jtag.tcl') *> $log
    $downloadExit=$LASTEXITCODE
    Get-Content -LiteralPath $log
    # Some old xsct.bat failures still return zero: also require the Tcl marker.
    if($downloadExit -ne 0 -or -not(Select-String -LiteralPath $log -SimpleMatch 'LCD_FPGA_LOADED_PL_ONLY:' -Quiet)) {
        throw "LCD download failed; inspect $log"
    }
    $verifyLog=Join-Path $root 'build/jtag_config_check.log'
    $journal=Join-Path $root 'build/jtag_config_check.jou'
    & "$Vivado/bin/vivado.bat" -mode batch -notrace -source (Join-Path $PSScriptRoot 'check_config.tcl') -log $verifyLog -journal $journal
    if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath $verifyLog -SimpleMatch 'LCD_FPGA_CONFIG_VERIFIED' -Quiet)) {
        throw "LCD configuration/startup check failed; inspect $verifyLog"
    }
} finally {$env:PROCESSOR_ARCHITECTURE=$previousArch}
