# SDK 2018.2 command line, Cortex-A9 standalone, OCM only (no DDR configuration).
set root [file normalize [file join [file dirname [info script]] ..]]
if {[info exists ::env(FPGA2026_ROOT)]} {set root $::env(FPGA2026_ROOT)}
set hdf [file join $root build export system.hdf]
if {![file exists $hdf]} {error "Build hardware first: missing $hdf"}
setws [file join $root build sdk]
if {![file exists [file join $root build sdk hw .project]]} {
    createhw -name hw -hwspec $hdf
} else {updatehw -hw hw -newhwspec $hdf}
if {![file exists [file join $root build sdk bsp .project]]} {
    createbsp -name bsp -hwproject hw -proc ps7_cortexa9_0 -os standalone
}
configbsp -bsp bsp stdin debug_uart
configbsp -bsp bsp stdout debug_uart
regenbsp -bsp bsp
if {![file exists [file join $root build sdk analyzer .project]]} {
    createapp -name analyzer -hwproject hw -bsp bsp -proc ps7_cortexa9_0 -os standalone -lang C -app {Empty Application}
}
set src [file join $root build sdk analyzer src]
file mkdir $src
foreach f [concat [glob [file join $root firmware src *.c]] [glob [file join $root firmware include *.h]]] {file copy -force $f $src}
file copy -force [file join $root firmware lscript.ld] [file join $src lscript.ld]
configapp -app analyzer build-config release
configapp -app analyzer compiler-optimization {Optimize for size (-Os)}
configapp -app analyzer -set compiler-misc {-c -fmessage-length=0 -MT"$@" -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -Wextra -Werror -std=c99}
configapp -app analyzer -set linker-misc {-mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -Wl,-build-id=none -specs=Xilinx.spec -Wl,-Map,analyzer.map}
projects -clean -type all
projects -build -type all
set elf [file join $root build sdk analyzer Release analyzer.elf]
if {![file exists $elf]} {error "ELF not generated: inspect SDK build output"}
file copy -force $elf [file join $root build export analyzer.elf]
file copy -force [file join $root build sdk analyzer Release analyzer.map] [file join $root build export analyzer.map]
puts "FIRMWARE_READY=$elf"
