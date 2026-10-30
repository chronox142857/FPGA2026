param([string]$Vivado='E:\fpga\Vivado\2018.2',[switch]$DebugLcd,[switch]$ReadPanel)
$ErrorActionPreference='Stop'
if($ReadPanel -and -not $DebugLcd){throw '-ReadPanel requires -DebugLcd'}
$root=Split-Path $PSScriptRoot -Parent
$build=Join-Path $root 'build'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$previousArch=$env:PROCESSOR_ARCHITECTURE
$env:PROCESSOR_ARCHITECTURE='AMD64'
$previousDebug=$env:LCD_DEBUG
$previousReadback=$env:LCD_READBACK
$env:LCD_DEBUG=if($DebugLcd){'1'}else{'0'}
$env:LCD_READBACK=if($ReadPanel){'1'}else{'0'}
Push-Location $build
try {
    & "$Vivado/bin/vivado.bat" -mode batch -notrace -source "$PSScriptRoot/build.tcl" -log build.log -journal build.jou
    if($LASTEXITCODE -ne 0){throw 'Vivado build failed'}
    if(-not(Select-String -LiteralPath 'build.log' -SimpleMatch 'BUILD_PASSED=' -Quiet)){throw 'Vivado did not report a complete build'}
    $digest=(Get-FileHash -LiteralPath 'st7735s_top.bit' -Algorithm SHA256).Hash.ToLowerInvariant()
    "$digest  st7735s_top.bit" | Set-Content -LiteralPath 'SHA256SUMS.txt' -Encoding ASCII
} finally {Pop-Location;$env:PROCESSOR_ARCHITECTURE=$previousArch;$env:LCD_DEBUG=$previousDebug;$env:LCD_READBACK=$previousReadback}
