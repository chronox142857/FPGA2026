param(
    [ValidateSet('Project','Hardware','Software','All')][string]$Stage='All',
    [string]$Vivado='E:\fpga\Vivado\2018.2',
    [string]$Sdk='E:\fpga\SDK\2018.2'
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$build=Join-Path $root build
New-Item -ItemType Directory -Force -Path $build | Out-Null
$env:PROCESSOR_ARCHITECTURE='AMD64'
$subst=Join-Path $env:SystemRoot 'System32/subst.exe'
$drive=$null
foreach($letter in @('T','U','V','W','X','Y','Z')){if(-not(Test-Path "${letter}:\")){$drive="${letter}:";break}}
if(-not $drive){throw 'No free T:..Z: drive for a temporary short build path'}
& $subst $drive $root
if($LASTEXITCODE -ne 0){throw 'Could not create temporary build drive'}
$previousRoot=$env:FPGA2026_ROOT
$env:FPGA2026_ROOT="$drive/"
Push-Location "$drive/build"
try {
    if($Stage -eq 'Project' -or $Stage -eq 'All') {
        & "$Vivado/bin/vivado.bat" -mode batch -notrace -source "$PSScriptRoot/create_project.tcl" -log project.log -journal project.jou
        if($LASTEXITCODE -ne 0){throw 'Project generation failed'}
    }
    if($Stage -eq 'Hardware' -or $Stage -eq 'All') {
        & "$Vivado/bin/vivado.bat" -mode batch -notrace -source "$PSScriptRoot/build_hardware.tcl" -log hardware.log -journal hardware.jou
        if($LASTEXITCODE -ne 0){throw 'Hardware build failed'}
    }
    if($Stage -eq 'Software' -or $Stage -eq 'All') {
        $softwareLog=Join-Path $build 'software-latest.log'
        & "$Sdk/bin/xsct.bat" "$PSScriptRoot/build_sdk.tcl" *> $softwareLog
        $softwareExit=$LASTEXITCODE
        Get-Content -LiteralPath $softwareLog
        # SDK 2018.2 can return zero even when its Tcl script failed.
        if($softwareExit -ne 0 -or -not(Select-String -LiteralPath $softwareLog -SimpleMatch 'FIRMWARE_READY=' -Quiet)){
            throw 'SDK build failed: completion marker missing'
        }
    }
    if($Stage -eq 'Hardware' -or $Stage -eq 'Software' -or $Stage -eq 'All') {
        $hashLines=foreach($name in @('system.bit','system.hdf','analyzer.elf','analyzer.map')) {
            $path=Join-Path $build "export/$name"
            if(Test-Path -LiteralPath $path){
                $fileHash=Get-FileHash -LiteralPath $path -Algorithm SHA256
                '{0}  {1}' -f $fileHash.Hash.ToLowerInvariant(),$name
            }
        }
        $hashLines | Set-Content -LiteralPath (Join-Path $build 'export/SHA256SUMS.txt') -Encoding ascii
    }
} finally {Pop-Location;$env:FPGA2026_ROOT=$previousRoot;& $subst $drive /D}
