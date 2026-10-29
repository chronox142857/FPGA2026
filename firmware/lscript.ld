/* Cortex-A9 OCM low mapping, 192KiB. High 64KiB remains reserved.
 * No external DDR is required. ARM boot vectors/code begin at 0x00000000.
 */
_STACK_SIZE = 0x4000;
_HEAP_SIZE = 0x1000;
_ABORT_STACK_SIZE = 0x400;
_SUPERVISOR_STACK_SIZE = 0x800;
_IRQ_STACK_SIZE = 0x400;
_FIQ_STACK_SIZE = 0x400;
_UNDEF_STACK_SIZE = 0x400;
MEMORY { ps7_ram_0 (rwx) : ORIGIN = 0x00000000, LENGTH = 0x00030000 }
ENTRY(_vector_table)
SECTIONS
{
 .text : { KEEP(*(.vectors)) *(.boot) *(.text .text.* .gnu.linkonce.t.*) *(.plt) *(.gnu.warning) *(.gcc_execpt_table) *(.glue_7) *(.glue_7t) } > ps7_ram_0
 .init : { KEEP(*(.init)) } > ps7_ram_0
 .fini : { KEEP(*(.fini)) } > ps7_ram_0
 .rodata : { *(.rodata .rodata.* .gnu.linkonce.r.*) } > ps7_ram_0
 .sdata2 : { __sdata2_start = .; *(.sdata2 .sdata2.* .gnu.linkonce.s2.*) __sdata2_end = .; } > ps7_ram_0
 .sbss2 (NOLOAD) : { __sbss2_start = .; *(.sbss2 .sbss2.* .gnu.linkonce.sb2.*) __sbss2_end = .; } > ps7_ram_0
 .data : { __data_start = .; *(.data .data.* .gnu.linkonce.d.*) *(.jcr) *(.got .got.*) __data_end = .; } > ps7_ram_0
 .ctors : { __CTOR_LIST__ = .; KEEP(*crtbegin.o(.ctors)) KEEP(*(EXCLUDE_FILE(*crtend.o) .ctors)) KEEP(*(SORT(.ctors.*))) KEEP(*(.ctors)) __CTOR_END__ = .; } > ps7_ram_0
 .dtors : { __DTOR_LIST__ = .; KEEP(*crtbegin.o(.dtors)) KEEP(*(EXCLUDE_FILE(*crtend.o) .dtors)) KEEP(*(SORT(.dtors.*))) KEEP(*(.dtors)) __DTOR_END__ = .; } > ps7_ram_0
 .ARM.extab : { *(.ARM.extab* .gnu.linkonce.armextab.*) } > ps7_ram_0
 .ARM.exidx : { __exidx_start = .; *(.ARM.exidx* .gnu.linkonce.armexidx.*) __exidx_end = .; } > ps7_ram_0
 .preinit_array : { __preinit_array_start = .; KEEP(*(.preinit_array)) __preinit_array_end = .; } > ps7_ram_0
 .init_array : { __init_array_start = .; KEEP(*(SORT(.init_array.*))) KEEP(*(.init_array)) __init_array_end = .; } > ps7_ram_0
 .fini_array : { __fini_array_start = .; KEEP(*(SORT(.fini_array.*))) KEEP(*(.fini_array)) __fini_array_end = .; } > ps7_ram_0
 .mmu_tbl ALIGN(16384) : { __mmu_tbl_start = .; *(.mmu_tbl) __mmu_tbl_end = .; } > ps7_ram_0
 .sdata : { __sdata_start = .; *(.sdata .sdata.* .gnu.linkonce.s.*) __sdata_end = .; } > ps7_ram_0
 .sbss (NOLOAD) : { __sbss_start = .; *(.sbss .sbss.* .gnu.linkonce.sb.*) __sbss_end = .; } > ps7_ram_0
 .bss (NOLOAD) : { . = ALIGN(4); __bss_start = .; *(.bss .bss.* .gnu.linkonce.b.*) *(COMMON) . = ALIGN(4); __bss_end = .; } > ps7_ram_0
 _SDA_BASE_ = __sdata_start + ((__sbss_end - __sdata_start) / 2);
 _SDA2_BASE_ = __sdata2_start + ((__sbss2_end - __sdata2_start) / 2);
 .heap (NOLOAD) : { . = ALIGN(16); _heap = .; HeapBase = .; _heap_start = .; . += _HEAP_SIZE; _heap_end = .; HeapLimit = .; } > ps7_ram_0
 .stack (NOLOAD) : {
   . = ALIGN(16); _stack_end = .; . += _STACK_SIZE; _stack = .; __stack = .;
   . = ALIGN(16); _irq_stack_end = .; . += _IRQ_STACK_SIZE; __irq_stack = .;
   _supervisor_stack_end = .; . += _SUPERVISOR_STACK_SIZE; __supervisor_stack = .;
   _abort_stack_end = .; . += _ABORT_STACK_SIZE; __abort_stack = .;
   _fiq_stack_end = .; . += _FIQ_STACK_SIZE; __fiq_stack = .;
   _undef_stack_end = .; . += _UNDEF_STACK_SIZE; __undef_stack = .;
 } > ps7_ram_0
 _end = .; end = .;
}
