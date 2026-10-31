/* FSBL loads this small trampoline at 2 MiB in DDR. The released analyzer is
 * linked at OCM address zero, which must not overwrite the running FSBL.
 * After FSBL handoff (MMU/caches disabled), copy its unchanged flat image to
 * OCM and enter its original reset vector. No C runtime or stack is required.
 */
.syntax unified
.cpu cortex-a9
.arm
.section .text.boot,"ax",%progbits
.global _start
.type _start,%function
_start:
    cpsid if
    ldr r0, =_binary_analyzer_bin_start
    ldr r2, =_binary_analyzer_bin_end
    mov r1, #0
1:
    cmp r0, r2
    bhs 2f
    ldrb r3, [r0], #1
    strb r3, [r1], #1
    b 1b
2:
    dsb sy
    mov r0, #0
    mcr p15, 0, r0, c7, c5, 0
    mcr p15, 0, r0, c7, c5, 6
    dsb sy
    isb sy
    bx r0
.size _start, .-_start
