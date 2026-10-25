# Startup code for C programs: runs before main().
#
# C expects three things the hardware doesn't give us by itself:
#   1. a stack pointer (sp) pointing at usable RAM - here the top of RAM,
#      the stack grows downwards from there
#   2. global variables without an initial value (.bss) set to zero
#   3. initialized globals (.data) holding their values - true at the first
#      start, because the whole program image, data included, is loaded into
#      RAM (by the bitstream or by an upload). After S1 they keep whatever
#      values the program gave them: nothing reloads them (a known limitation,
#      see notes/gotchas.md).
# Then it calls main() and reports main's return value through EXIT.

    .equ EXIT, 0x10000008

    .section .text.start
    .globl _start
_start:
    la   sp, __stack_top

    la   t0, __bss_start
    la   t1, __bss_end
clear_bss:
    bgeu t0, t1, bss_done
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    clear_bss
bss_done:

    call main

    li   t0, EXIT                # a0 = main's return value
    sw   a0, 0(t0)
1:  j    1b                      # on real hardware: stay here forever
