param(
    [string]$Vivado='E:\fpga\Vivado\2018.2',
    [string]$Gcc='E:\DevC++\Dev-Cpp\MinGW64\bin\gcc.exe'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$build=Join-Path $root 'build/tests'
New-Item -ItemType Directory -Force -Path $build | Out-Null
function Invoke-Checked([string]$program,[string[]]$arguments) {
    & $program @arguments
    if($LASTEXITCODE -ne 0){throw "Failed: $program"}
}
if(-not(Test-Path "$build/loop_uart.hex")){throw 'Run scripts/test.ps1 first to create the real RTL capture fixture'}
Invoke-Checked python @("$root/examples/st7735s_pl/scripts/check_stm32_reference.py",$Gcc)
$init=Get-Content "$root/examples/st7735s_pl/build/sim/stm32_wire_stream.hex" -TotalCount 77
Set-Content -LiteralPath "$build/display_init.hex" -Value $init -Encoding ascii
Invoke-Checked $Gcc @('-std=c99','-O2','-Wall','-Wextra','-Werror','-I',"$root/tests/display_host",'-I',"$root/firmware/include",
    "$root/firmware/src/tft.c","$root/firmware/src/la.c","$root/firmware/src/ui.c","$root/firmware/src/tinyfmt.c",
    "$root/tests/test_display.c",'-o',"$build/test_display.exe")
$previousArch=$env:PROCESSOR_ARCHITECTURE
$env:PROCESSOR_ARCHITECTURE='AMD64'
Push-Location $build
try {
    Invoke-Checked "$build/test_display.exe" @()
    Invoke-Checked "$Vivado/bin/xvlog.bat" @("$root/rtl/la_display.v","$root/examples/st7735s_pl/st7735s_driver.v",
        "$root/examples/st7735s_pl/st7735s_spi_byte.v","$root/tests/tb_display.v")
    Invoke-Checked "$Vivado/bin/xelab.bat" @('tb_display','-s','tb_display_sim','-timescale','1ns/1ps')
    Invoke-Checked "$Vivado/bin/xsim.bat" @('tb_display_sim','-runall')
    if(-not(Select-String -LiteralPath xsim.log -SimpleMatch 'PASS tb_display:' -Quiet)){throw 'Integrated display test did not pass'}
    Copy-Item xsim.log tb_display.log -Force
} finally {Pop-Location;$env:PROCESSOR_ARCHITECTURE=$previousArch}
