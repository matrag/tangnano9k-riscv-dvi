# Startup code for the bootloader (sw/08_boot.c), at the very start of the boot ROM.
#
# After reset the CPU starts here (RESET_PC = 0x3000_0000). The only thing C
# needs before boot_main() is a stack: the top 256 bytes of RAM (see 08_boot.ld).
# There is no .data/.bss to prepare - the linker script forbids them.

    .section .text.start
    .globl _start
_start:
    la   sp, __stack_top
    call boot_main          # never returns: it jumps to the program at address 0
1:  j    1b
