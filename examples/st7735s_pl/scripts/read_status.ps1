param([string]$Vivado='E:\fpga\Vivado\2018.2',[switch]$CaptureSpi)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$previousArch=$env:PROCESSOR_ARCHITECTURE
$env:PROCESSOR_ARCHITECTURE='AMD64'
try {
    $jobs=@(@{Name='read_status';Marker='LCD_JTAG_READBACK_END'})
    if($CaptureSpi){$jobs+=@{Name='capture_spi';Marker='LCD_SPI_TRACE_CAPTURED'}}
    foreach($job in $jobs){
        $name=$job.Name;$marker=$job.Marker
        $log=Join-Path $root "build/${name}_latest.log"
        $journal=Join-Path $root "build/${name}_latest.jou"
        & "$Vivado/bin/vivado.bat" -mode batch -notrace -source (Join-Path $PSScriptRoot "$name.tcl") -log $log -journal $journal
        if($LASTEXITCODE -ne 0 -or -not(Select-String -LiteralPath $log -SimpleMatch $marker -Quiet)){throw "LCD debug operation failed: $log"}
    }
} finally {$env:PROCESSOR_ARCHITECTURE=$previousArch}
