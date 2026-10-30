param([string]$Vivado='E:\fpga\Vivado\2018.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$build=Join-Path $root 'build/sim'
New-Item -ItemType Directory -Path $build -Force | Out-Null
& python (Join-Path $PSScriptRoot 'check_slow_reference.py')
if($LASTEXITCODE -ne 0){throw 'Archived slow GPIO reference check failed'}
& python (Join-Path $PSScriptRoot 'check_stm32_reference.py')
if($LASTEXITCODE -ne 0){throw 'Original STM32 reference check failed'}
Copy-Item -LiteralPath "$root/reference/slow_gpio_init.hex" -Destination $build -Force
$previousArch=$env:PROCESSOR_ARCHITECTURE
$env:PROCESSOR_ARCHITECTURE='AMD64'
function Invoke-Checked([string]$program,[string[]]$arguments) {
    & $program @arguments
    if($LASTEXITCODE -ne 0){throw "Failed: $program"}
}
Push-Location $build
try {
    Invoke-Checked "$Vivado/bin/xvlog.bat" @("$root/st7735s_spi_byte.v","$root/st7735s_driver.v","$root/st7735s_readback.v","$root/st7735s_demo.v","$root/st7735s_font5x7.v","$root/st7735s_text_demo.v","$root/st7735s_top.v","$root/tb_st7735s_driver.v","$root/tb_st7735s_top.v","$root/tb_st7735s_readback.v","$root/tb_st7735s_slow.v","$root/tb_st7735s_stm32.v","$Vivado/data/verilog/src/glbl.v")
    foreach($top in @('tb_st7735s_driver','tb_st7735s_top','tb_st7735s_readback','tb_st7735s_slow','tb_st7735s_stm32')) {
        Invoke-Checked "$Vivado/bin/xelab.bat" @($top,'glbl','-L','unisims_ver','-s',"${top}_test",'-timescale','1ns/1ps')
        Invoke-Checked "$Vivado/bin/xsim.bat" @("${top}_test",'-runall')
        $marker=if($top -eq 'tb_st7735s_driver'){'PASS: ST7735S'}elseif($top -eq 'tb_st7735s_top'){'PASS: BOARD'}elseif($top -eq 'tb_st7735s_readback'){'PASS: READBACK'}elseif($top -eq 'tb_st7735s_slow'){'PASS: SLOW'}else{'PASS: STM32'}
        if(-not(Select-String -LiteralPath 'xsim.log' -SimpleMatch $marker -Quiet)){throw "Simulation did not report PASS: $top"}
        Copy-Item -LiteralPath 'xsim.log' -Destination "$top.log" -Force
    }
} finally {Pop-Location;$env:PROCESSOR_ARCHITECTURE=$previousArch}
