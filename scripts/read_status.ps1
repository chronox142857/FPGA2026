param([string]$Sdk='E:\fpga\SDK\2018.2')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$elf=Join-Path $root 'build/export/analyzer.elf'
$nm=Join-Path $Sdk 'gnu/aarch32/nt/gcc-arm-none-eabi/bin/arm-none-eabi-nm.exe'
$symbols=& $nm -n $elf
if($LASTEXITCODE -ne 0){throw 'Could not read firmware symbols'}
$addresses=foreach($symbol in @('screen_ok','state','last_paint','record','ui')) {
    $matchesFound=@($symbols | Select-String -Pattern "^([0-9a-fA-F]+) [bBdD] $symbol`$")
    if($matchesFound.Count -ne 1){throw "Missing or ambiguous firmware symbol: $symbol"}
    '0x'+$matchesFound[0].Matches[0].Groups[1].Value
}
$previousArch=$env:PROCESSOR_ARCHITECTURE
$env:PROCESSOR_ARCHITECTURE='AMD64'
$log=Join-Path $root 'build/integrated_status.log'
try {
    & "$Sdk/bin/xsct.bat" "$PSScriptRoot/read_status.tcl" @addresses *> $log
    $statusExit=$LASTEXITCODE
} finally {$env:PROCESSOR_ARCHITECTURE=$previousArch}
Get-Content $log
if($statusExit -ne 0 -or -not(Select-String -LiteralPath $log -SimpleMatch 'INTEGRATED_STATUS_VERIFIED' -Quiet)){
    throw 'Integrated status verification failed'
}
