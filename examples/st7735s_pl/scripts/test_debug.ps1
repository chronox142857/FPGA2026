param([string]$Vivado='E:\fpga\Vivado\2018.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$build=Join-Path $root 'build/debug_sim'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$previousArch=$env:PROCESSOR_ARCHITECTURE
$env:PROCESSOR_ARCHITECTURE='AMD64'
Push-Location $build
try {
    & "$Vivado/bin/xvlog.bat" -d LCD_DEBUG "$root/st7735s_spi_byte.v" "$root/st7735s_driver.v" "$root/st7735s_readback.v" "$root/st7735s_demo.v" "$root/st7735s_top.v" "$root/tb_st7735s_debug.v" "$Vivado/data/verilog/src/glbl.v"
    if($LASTEXITCODE -ne 0){throw 'Debug simulation compile failed'}
    & "$Vivado/bin/xelab.bat" tb_st7735s_debug glbl -L unisims_ver -s debug_test -timescale 1ns/1ps
    if($LASTEXITCODE -ne 0){throw 'Debug simulation elaboration failed'}
    & "$Vivado/bin/xsim.bat" debug_test -runall
    if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath xsim.log -SimpleMatch 'PASS: DEBUG' -Quiet)){throw 'Debug simulation failed'}
} finally {Pop-Location;$env:PROCESSOR_ARCHITECTURE=$previousArch}
