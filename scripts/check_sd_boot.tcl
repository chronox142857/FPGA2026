# Read-only cold-boot audit. Never resets, downloads, initializes PS, or writes
# a target register: otherwise it could hide a failing autonomous boot.
if {[catch {
    source [lindex $argv 0]
    proc file_bytes {path} {set f [open $path rb];set b [read $f];close $f;return $b}
    connect
    targets -set -filter {name == "APU"}
    configparams force-mem-access 1
    set mode [mrd -force -value 0xf800025c]
    puts "BOOT_MODE=[format 0x%08x $mode]"
    # Read boot diagnostics before any application/PL access. A missing card or
    # early BootROM failure can leave DDR and the PL entirely uninitialized.
    puts "REBOOT_STATUS=[mrd -force 0xf8000258]"
    puts "OCM_CONFIG=[mrd -force 0xf8000910]"
    if {($mode & 7)!=5} {error "Board did not select SD boot; no automatic download will be attempted"}
    mrd -force -bin -file [file join $out running_text.bin] 0 $text_words
    if {[file_bytes [file join $out running_text.bin]] ne [file_bytes [file join $out expected_text.bin]]} {
        error "OCM executable differs from the packaged analyzer"
    }
    set capture [mrd -force -value 0x43c00000]
    set display [mrd -force -value 0x44a00000]
    set status [mrd -force -value 0x44a00004]
    set frames [mrd -force -value 0x44a0000c]
    set screen [mrd -force -value $screen_ok]
    puts "CAPTURE_ID=[format 0x%08x $capture] DISPLAY_ID=[format 0x%08x $display] STATUS=$status FRAMES=$frames SCREEN_OK=$screen"
    if {$capture!=0x4c410101 || $display!=0x4c440101 || !($status&1) || ($status&4) || $frames<1 || $screen!=1} {
        error "Autonomous application/display state is not ready"
    }
    set before [mrd -force -value $last_paint]
    after 500
    set later [mrd -force -value $last_paint]
    puts "PAINT_BEFORE=$before PAINT_AFTER=$later"
    if {$before==$later} {error "Application paint scheduler did not advance"}
    disconnect
    puts "SD_AUTONOMOUS_BOOT_VERIFIED_WITHOUT_TARGET_WRITES"
} message options]} {
    puts stderr "SD_BOOT_CHECK_FAILED: $message"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit
