param([string]$Vivado='E:\fpga\Vivado\2018.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
& python "$PSScriptRoot/make_text_reference.py"
if($LASTEXITCODE -ne 0){throw 'Text reference failed'}
$previousArch=$env:PROCESSOR_ARCHITECTURE
$env:PROCESSOR_ARCHITECTURE='AMD64'
Push-Location "$root/build/sim"
try {
    & "$Vivado/bin/xvlog.bat" "$root/st7735s_spi_byte.v" "$root/st7735s_driver.v" "$root/st7735s_font5x7.v" "$root/st7735s_text_demo.v" "$root/tb_st7735s_text.v"
    if($LASTEXITCODE -ne 0){throw 'Text compilation failed'}
    & "$Vivado/bin/xelab.bat" tb_st7735s_text -s text_test -timescale 1ns/1ps
    if($LASTEXITCODE -ne 0){throw 'Text elaboration failed'}
    & "$Vivado/bin/xsim.bat" text_test -runall
    if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath xsim.log -SimpleMatch 'PASS: TEXT' -Quiet)){throw 'Text simulation failed'}
    Copy-Item -LiteralPath xsim.log -Destination tb_st7735s_text.log -Force
} finally {Pop-Location;$env:PROCESSOR_ARCHITECTURE=$previousArch}
