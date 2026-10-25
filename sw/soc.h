// Memory map of the SoC (lib/soc.v), for C programs.
//
// Every device is just an address: writing LEDS = 5 is a store instruction
// to 0x10000000, which the SoC's address decoder sends to the LED register
// instead of the RAM ("memory-mapped IO").

#ifndef SOC_H
#define SOC_H

#define REG32(addr) (*(volatile unsigned int *)(addr))
// `volatile` = every read/write in the source really happens, in order.
// Without it the compiler could e.g. read TIMER once and reuse the value.

#define LEDS     REG32(0x10000000)   // rw: bit n = 1 lights LED n (6 LEDs)
#define CONSOLE  REG32(0x10000004)   // w : print a character (simulation only)
#define EXIT     REG32(0x10000008)   // w : end the simulation (ignored on the board)
#define TIMER    REG32(0x1000000C)   // r : counts CPU clock cycles, wraps after 2^32
#define BUTTONS  REG32(0x10000010)   // r : bit 0 = S2 pressed

// Serial port (step 7): 115200 baud, 8N1, over the board's USB connector
#define UART_DATA    REG32(0x10000014) // w: send a byte; r: bit 8 = byte received, bits 7..0 = the byte
#define UART_STATUS  REG32(0x10000018) // r: bit 0 = ready to send, bit 1 = byte waiting

// Text screen (step 6, lib/soc_text.v): 80 x 30 cells, one 32-bit word each
#define TEXT_COLS   80
#define TEXT_ROWS   30
#define TEXT        ((volatile unsigned int *)0x20000000)  // TEXT[ram_row*80+col] = bg<<12 | fg<<8 | char
                                                           // (ram_row = (screen row + TEXT_SCROLL) mod TEXT_RING)
#define TEXT_SCROLL REG32(0x20010000)                      // char RAM row shown at the top
#define TEXT_RING   REG32(0x20010004)                      // r: rows in the char RAM ring (30, or 51 with scrollback)

#ifndef CPU_HZ
#define CPU_HZ 27000000u             // 27 MHz board clock (step 5); steps 6-7 build with 25200000
#endif

// Busy-wait for `ms` milliseconds using the cycle counter. The subtraction
// (now - start) gives the right answer even when TIMER wraps around.
static inline void delay_ms(unsigned int ms)
{
    unsigned int start = TIMER;
    unsigned int ticks = ms * (CPU_HZ / 1000u);
    while (TIMER - start < ticks)
        ;
}

// Send one byte: wait until the transmitter is free, then hand it over.
// One byte takes 10 bit times = 87 us at 115200 baud.
static inline void uart_putc(char c)
{
    while (!(UART_STATUS & 1))
        ;
    UART_DATA = (unsigned char)c;
}

static inline void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

// Received byte (0..255), or -1 if nothing has arrived. Doesn't wait.
static inline int uart_getc(void)
{
    unsigned int d = UART_DATA;      // one read: valid flag and byte together
    return (d & 0x100) ? (int)(d & 0xFF) : -1;
}

#endif
