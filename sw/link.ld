/* Linker script: where each part of the program goes in memory.
 *
 * Everything lives in the 8 KB RAM at address 0, where the CPU starts.
 * The order matters: the startup code (.text.start) must be first, so it
 * is at address 0.
 *
 *   0x0000  .text    code
 *           .rodata  constants, string literals
 *           .data    initialized global variables
 *           .bss     zero-initialized globals (cleared by start.S)
 *     ...   free
 *   0x2000  top of RAM = initial stack pointer (stack grows down)
 */

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 8K
}

ENTRY(_start)

SECTIONS
{
    .text : {
        *(.text.start)
        *(.text .text.*)
    } > RAM

    .rodata : {
        . = ALIGN(4);
        *(.rodata .rodata.* .srodata .srodata.*)
    } > RAM

    .data : {
        . = ALIGN(4);
        *(.data .data.* .sdata .sdata.*)
    } > RAM

    .bss (NOLOAD) : {
        . = ALIGN(4);
        __bss_start = .;
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
