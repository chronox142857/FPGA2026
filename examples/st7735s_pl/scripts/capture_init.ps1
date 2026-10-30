param([string]$Vivado='E:\fpga\Vivado\2018.2',[string]$InitialColor='0000')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$previousArch=$env:PROCESSOR_ARCHITECTURE
$env:PROCESSOR_ARCHITECTURE='AMD64'
Push-Location $root
try {
    & "$Vivado/bin/vivado.bat" -mode batch -notrace -source "$PSScriptRoot/capture_init.tcl" -log build/init_capture.log -journal build/init_capture.jou
    if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath build/init_capture.log -SimpleMatch 'LCD_INIT_TRACE_CAPTURED' -Quiet)){throw 'FPGA initialization capture failed'}
    & python "$PSScriptRoot/decode_init_trace.py" --initial-color $InitialColor
    if($LASTEXITCODE -ne 0){throw 'Actual initialization does not match reference/timing'}
} finally {Pop-Location;$env:PROCESSOR_ARCHITECTURE=$previousArch}
