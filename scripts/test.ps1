param(
    [string]$Vivado = 'E:\fpga\Vivado\2018.2',
    [string]$Gcc = 'E:\DevC++\Dev-Cpp\MinGW64\bin\gcc.exe',
    [switch]$HostOnly
)
$ErrorActionPreference='Stop'
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root 'build/tests'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$env:PROCESSOR_ARCHITECTURE='AMD64'
function Invoke-Checked([string]$program,[string[]]$arguments) {
    & $program @arguments
    if($LASTEXITCODE -ne 0){throw "Failed: $program (exit $LASTEXITCODE)"}
}
Invoke-Checked $Gcc @('-std=c99','-O2','-Wall','-Wextra','-Werror','-I',"$root/firmware/include","$root/firmware/src/la.c","$root/firmware/src/ui.c","$root/firmware/src/tinyfmt.c","$root/tests/test_protocol.c",'-o',"$build/test_protocol.exe")
Invoke-Checked "$build/test_protocol.exe" @('--ui',"$build/ui-")
Invoke-Checked $Gcc @('-std=c99','-O2','-Wall','-Wextra','-Werror','-I',"$root/firmware/include","$root/firmware/src/la.c","$root/tests/test_uart_boundary.c",'-o',"$build/test_uart_boundary.exe")
Invoke-Checked "$build/test_uart_boundary.exe" @()
if(-not $HostOnly) {
    Push-Location $build
    try {
        $sources = @("$root/rtl/la_capture.v","$root/rtl/la_sample_ram.v","$root/rtl/la_testgen.v","$root/rtl/la_axi.v","$root/rtl/la_tft_pad.v","$root/tests/tb_tft_pad.v","$root/tests/tb_capture.v","$root/tests/tb_axi.v","$root/tests/tb_loopback.v","$Vivado/data/verilog/src/glbl.v")
        Invoke-Checked "$Vivado/bin/xvlog.bat" $sources
        foreach($top in @('tb_capture','tb_axi','tb_loopback','tb_tft_pad')) {
            Invoke-Checked "$Vivado/bin/xelab.bat" @($top,'glbl','-L','unisims_ver','-s',"${top}_sim",'-timescale','1ns/1ps')
            Invoke-Checked "$Vivado/bin/xsim.bat" @("${top}_sim",'-runall')
            if(-not (Select-String -LiteralPath 'xsim.log' -SimpleMatch "PASS ${top}:" -Quiet)){throw "No PASS marker for $top"}
            Copy-Item -LiteralPath 'xsim.log' -Destination "$top.log" -Force
        }
        Invoke-Checked "$build/test_protocol.exe" @('--rtl',"$build/loop_uart.hex",'1','0')
        Invoke-Checked "$build/test_protocol.exe" @('--rtl',"$build/loop_i2c.hex",'2','0')
        foreach($mode in 0..3){Invoke-Checked "$build/test_protocol.exe" @('--rtl',"$build/loop_spi$mode.hex",'3',"$mode")}
        Invoke-Checked "$build/test_protocol.exe" @('--rtl',"$build/loop_uart_error.hex",'1','1')
    } finally {Pop-Location}
}
if(-not $HostOnly) {
    & "$PSScriptRoot/test_display.ps1" -Vivado $Vivado -Gcc $Gcc
    if($LASTEXITCODE -ne 0){throw 'Integrated display tests failed'}
}
Write-Output 'ALL REQUESTED TESTS PASSED'
