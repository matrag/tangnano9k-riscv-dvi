/* Linker script for the bootloader (sw/08_boot.c), step 8.
 *
 * The bootloader's code and constants live in the 2 KB boot ROM, where the
 * CPU starts. It may not use the RAM it is loading a program into, except
 * the top 256 bytes for its stack - so uploaded programs can be at most
 * 8 KB - 256 B = 7936 bytes (tools/upload.py checks this).
 *
 *   0x3000_0000  ROM  .text, .rodata   (bootloader code, messages)
 *   0x0000_1F00  RAM  stack, growing down from 0x2000
 *
 * There is no .data or .bss: initialized writable variables would need their
 * starting values copied from ROM, and the bootloader doesn't need any -
 * it keeps everything in local variables (registers / stack).
 */

MEMORY
{
    ROM (rx) : ORIGIN = 0x30000000, LENGTH = 2K
    RAM (rw) : ORIGIN = 0x00001F00, LENGTH = 256
}

ENTRY(_start)

SECTIONS
{
    .text : {
        *(.text.start)
        *(.text .text.*)
        . = ALIGN(4);
        *(.rodata .rodata.* .srodata .srodata.*)
    } > ROM

    .data : { *(.data .data.* .sdata .sdata.*) } > RAM
    .bss (NOLOAD) : { *(.bss .bss.* .sbss .sbss.* COMMON) } > RAM

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);

    ASSERT(SIZEOF(.data) == 0, "bootloader: no initialized writable globals allowed (it runs from ROM)")
    ASSERT(SIZEOF(.bss)  == 0, "bootloader: no global variables allowed (use locals)")
}
