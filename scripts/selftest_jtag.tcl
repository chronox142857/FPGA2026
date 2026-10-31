# Physical pin loopback test. It only configures the production application's
# normal settings and repeat flag; the running C main loop performs acquisition,
# BRAM readout and decoding. No software-generated capture data is injected.
if {[catch {
    source [lindex $argv 0]
    proc word {address} {return [mrd -force -value $address]}
    proc save_words {path address count} {
        set handle [open $path w]
        foreach value [mrd -force -value $address $count] {puts $handle [format %08x $value]}
        close $handle
    }
    proc halt_cpu {} {
        targets -set -filter {name =~ "ARM*#0"}
        if {[catch {stop} message] && ![string match "*Already stopped*" $message]} {error $message}
        after 100
        targets -set -filter {name == "APU"}
        configparams force-mem-access 1
    }
    proc resume_cpu {} {targets -set -filter {name =~ "ARM*#0"};con}
    connect
    halt_cpu
    if {[word 0x43c00000]!=0x4c410101 || [word 0x44a00000]!=0x4c440101} {error "Wrong FPGA image"}
    mrd -force -bin -file [file join $out running_text.bin] 0 $text_words
    proc binary_file {path} {
        set file [open $path rb]
        set bytes [read $file]
        close $file
        return $bytes
    }
    if {[binary_file [file join $out running_text.bin]] ne [binary_file [file join $out expected_text.bin]]} {
        error "Running ARM executable differs from test ELF; no test settings applied"
    }
    if {[word $screen_ok]!=1} {error "Application display initialization failed"}
    # Stop any old capture before changing the next-capture configuration.
    mwr -force 0x43c00004 2
    mwr -force $config $config_words
    mwr -force $awaiting 0
    mwr -force $record_count 0
    mwr -force $repeat_at {0 0}
    mwr -force $last_paint {0 0}
    resume_cpu
    targets -set -filter {name == "APU"}
    configparams force-mem-access 1
    set complete 0
    for {set attempt 0} {$attempt<100} {incr attempt} {
        after 100
        if {[word $record_count]==32768 && [word $awaiting]==0 && [word 0x43c00008]==3} {
            set complete 1;break
        }
    }
    halt_cpu
    # Disable loop mode while leaving the generator running, preserving the
    # completed record. The production app will show the decoded page on resume.
    set packed [word $repeat_word_address]
    mwr -force $repeat_word_address [expr {$packed & ~$repeat_word_mask}]
    if {!$complete || [word $awaiting]!=0 || [word 0x43c00008]!=3} {error "Capture timeout or no stable completed record; check the physical loopback"}
    save_words [file join $out capture_registers.hex] 0x43c00000 27
    save_words [file join $out record.hex] $record $record_words
    save_words [file join $out result.hex] $result $result_words
    save_words [file join $out decoded.hex] $decoded $decoded_words
    save_words [file join $out arm_samples.hex] $samples 8192
    save_words [file join $out bram_samples.hex] 0x42000000 8192
    set ui_word [word $ui]
    mwr -force $ui [expr {($ui_word & ~0xffff) | 2}]
    # Force a full frame for hardware test results. Partial-refresh robustness
    # is a separate display acceptance item; do not change LCD timing here.
    mwr -force $first_frame 1
    mwr -force $last_paint {0 0}
    resume_cpu
    disconnect
    puts "PHYSICAL_CAPTURE_EXPORTED_CPU_RESUMED"
} message options]} {
    # On failure, stop repeat mode if possible and always restore CPU execution.
    if {[info exists repeat_word_address]} {
        catch {
            halt_cpu
            mwr -force $repeat_word_address [expr {[word $repeat_word_address] & ~$repeat_word_mask}]
            mwr -force 0x43c00004 2
            mwr -force $awaiting 0
        }
    }
    catch {resume_cpu}
    puts stderr "PHYSICAL_SELFTEST_FAILED: $message"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit
