param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z]$')][string]$DriveLetter
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$letter=$DriveLetter.ToUpperInvariant()
$volume=Get-Volume -DriveLetter $letter
if($volume.DriveType -ne 'Removable' -or $volume.FileSystemType -ne 'FAT32') {
    throw 'Target must be the user-selected removable FAT32 card; this script never formats disks'
}
if($volume.Size -lt 16GB -or $volume.Size -gt 64GB) {
    throw 'Target capacity is outside the checked 32GB-card range'
}
$source=Join-Path $root 'build/sd_boot/BOOT.bin'
$manifest=Get-Content -LiteralPath (Join-Path $root 'build/sd_boot/manifest.json') -Raw | ConvertFrom-Json
$expected=$manifest.files.'BOOT.bin'
if((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'BOOT.bin differs from build manifest'
}
$destination=[IO.Path]::GetFullPath("${letter}:\BOOT.bin")
if($destination -ne "${letter}:\BOOT.bin") {throw 'Unexpected resolved destination'}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
if(Test-Path -LiteralPath $destination) {
    $backupDir=Join-Path $root "build/sd_card_backup/$stamp"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $backup=Join-Path $backupDir 'BOOT.bin'
    Copy-Item -LiteralPath $destination -Destination $backup
    if((Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath $backup).Hash) {
        throw 'Existing boot file backup verification failed'
    }
    Write-Output "Previous BOOT.bin backed up to $backup"
}
$temporary="${letter}:\BOOT_$stamp.tmp"
$stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {
    $bytes=[IO.File]::ReadAllBytes($source)
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Flush($true)
} finally {$stream.Dispose()}
if((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'Card temporary-file readback verification failed'
}
Move-Item -LiteralPath $temporary -Destination $destination -Force
if((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'Card BOOT.bin readback verification failed'
}
$result=[ordered]@{drive=$letter;filesystem=[string]$volume.FileSystemType;capacity=$volume.Size;
    file=$destination;bytes=$bytes.Length;sha256=$expected;status='copied and readback verified; cold boot pending'}
$result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'build/sd_boot/card_write.json') -Encoding UTF8
Write-Output "SD_CARD_BOOT_FILE_VERIFIED $destination SHA256=$expected"
Write-Output 'Safely eject the card before removal. No formatting or Flash programming was performed.'
