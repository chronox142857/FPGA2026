ENTRY(_start)
MEMORY { ddr (rwx) : ORIGIN = 0x00200000, LENGTH = 0x00100000 }
SECTIONS {
    .text : { KEEP(*(.text.boot)) *(.text*) } > ddr
    .payload ALIGN(16) : { *(.data) } > ddr
    /DISCARD/ : { *(.comment) *(.ARM.attributes) }
}
