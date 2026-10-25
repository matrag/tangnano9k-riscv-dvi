// Serial bootloader (step 8). Lives in the boot ROM; the CPU starts here.
//
// After reset it announces itself on the serial port and waits 1 second for
// an upload. Then:
//   - upload received and correct -> start it
//   - nothing within 1 s          -> start whatever program is already in RAM
//                                    (the one built into the bitstream, or the
//                                    last one uploaded)
//   - upload broken (bad size, CRC mismatch, data stopped) -> report it and
//                                    wait for a new upload (without a time
//                                    limit: RAM may hold half a program now)
//
// Upload protocol (tools/upload.py is the other side), little-endian:
//
//   board -> PC   "[boot] ..." line       the PC waits for this after you press S1
//   PC -> board   'U' 'P' 'L' 'D'         magic: "an upload follows"
//   PC -> board   length (4 bytes)        program size in bytes, 1..MAX_PROGRAM
//   PC -> board   program (length bytes)  written to RAM from address 0
//   PC -> board   CRC-32 (4 bytes)        of the program bytes (same as Python's zlib.crc32)
//   board -> PC   "[boot] OK ..."         or "[boot] ERROR ..."
//
// The PC must wait for the END of a "[boot]" line (its \n) before sending:
// while the bootloader prints it isn't reading, and more than 16 bytes
// arriving then would overflow the receive FIFO.
//
// A byte has 2190 clock cycles (87 us at 115200 baud) to be handled before the
// next one arrives; receiving, storing and the CRC step take a few hundred, so
// the bootloader keeps up with a continuous stream. The 16-byte receive FIFO
// covers any short delays.

#include "soc.h"

#define MAX_PROGRAM      0x1F00u            // RAM above this is the bootloader's stack
#define WAIT_MS          1000u              // how long to wait for an upload after reset
#define BYTE_TIMEOUT_MS  100u               // max gap between bytes of an upload

#define MS(n)  ((n) * (CPU_HZ / 1000u))     // milliseconds -> TIMER ticks

// Next received byte, or -1 if none arrives within `ticks` TIMER ticks
static int get_byte(unsigned int ticks)
{
    unsigned int start = TIMER;
    do {
        int c = uart_getc();
        if (c >= 0)
            return c;
    } while (TIMER - start < ticks);
    return -1;
}

// 4 bytes, least significant first. Returns 0 on timeout.
static int get_u32(unsigned int *value)
{
    unsigned int v = 0;
    for (int i = 0; i < 4; i++) {
        int c = get_byte(MS(BYTE_TIMEOUT_MS));
        if (c < 0)
            return 0;
        v |= (unsigned int)c << (8 * i);
    }
    *value = v;
    return 1;
}

// CRC-32 (IEEE 802.3, the one used by zip and Python's zlib.crc32), one byte
// at a time, without a table: for each bit, shift right and, if the bit
// shifted out was 1, XOR in the polynomial (bit-reversed form 0xEDB88320).
static unsigned int crc32_update(unsigned int crc, unsigned char b)
{
    crc ^= b;
    for (int i = 0; i < 8; i++)
        crc = (crc >> 1) ^ (0xEDB88320u & -(crc & 1u));    // -(1) = all ones, -(0) = 0
    return crc;
}

// Wait for the magic "UPLD". With limit_ticks = 0, wait forever.
// Other bytes are ignored, so line noise or a stray key press doesn't matter.
static int wait_magic(unsigned int limit_ticks)
{
    static const char magic[4] = { 'U', 'P', 'L', 'D' };   // in ROM (const)
    unsigned int start = TIMER;
    int matched = 0;
    while (limit_ticks == 0 || TIMER - start < limit_ticks) {
        int c = uart_getc();
        if (c < 0)
            continue;
        if (c == magic[matched])
            matched++;
        else
            matched = (c == magic[0]) ? 1 : 0;
        if (matched == 4)
            return 1;
    }
    return 0;
}

// After an error: let the rest of a broken upload pass (until 100 ms of silence)
static void drain(void)
{
    while (get_byte(MS(BYTE_TIMEOUT_MS)) >= 0)
        ;
}

// Start the program at address 0. Written as a jump in assembly, because
// calling a function pointer with the value 0 counts as a "null pointer"
// in C, which the compiler may assume never happens.
static void __attribute__((noreturn)) run_program(void)
{
    LEDS = 0;
    __asm__ volatile ("jr zero");          // zero = register x0 = address 0
    __builtin_unreachable();
}

// Receive length, program and CRC. Returns an error message, or 0 if all is well.
static const char *receive(void)
{
    unsigned int length, crc_sent;
    if (!get_u32(&length))
        return "timeout in the length";
    if (length == 0 || length > MAX_PROGRAM)
        return "program size out of range (1..7936 bytes)";

    // The RAM, written byte by byte from address 0. `volatile` keeps every
    // store; the pointer starts at 0, which is allowed by -fno-delete-null-pointer-checks.
    volatile unsigned char *ram = (volatile unsigned char *)0;
    unsigned int crc = 0xFFFFFFFFu;
    for (unsigned int i = 0; i < length; i++) {
        int c = get_byte(MS(BYTE_TIMEOUT_MS));
        if (c < 0)
            return "timeout in the program data";
        ram[i] = (unsigned char)c;
        crc = crc32_update(crc, (unsigned char)c);
        if ((i & 255) == 0)
            LEDS ^= 2;                     // LED 1 flickers while loading
    }
    crc = ~crc;

    if (!get_u32(&crc_sent))
        return "timeout in the CRC";
    if (crc != crc_sent)
        return "CRC mismatch, the data was damaged";
    return 0;
}

void __attribute__((noreturn)) boot_main(void)
{
    LEDS = 1;                              // LED 0: the bootloader is running
    uart_puts("\r\n[boot] rv32i_core bootloader - waiting 1 s for an upload\r\n");

    unsigned int limit = MS(WAIT_MS);
    for (;;) {
        if (!wait_magic(limit)) {
            uart_puts("[boot] no upload - starting the program in RAM\r\n");
            run_program();
        }
        const char *error = receive();
        if (!error) {
            uart_puts("[boot] OK - starting the uploaded program\r\n");
            run_program();
        }
        drain();
        uart_puts("[boot] ERROR: ");
        uart_puts(error);
        uart_puts(" - waiting for a new upload\r\n");
        limit = 0;                         // RAM may hold half a program: never run it
    }
}
