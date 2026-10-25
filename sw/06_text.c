// Step 6 demo: the CPU writes to the HDMI text screen.
//
//   - a welcome screen: title bar, system info, color table, box drawing
//   - a small benchmark: counting primes, timed with the TIMER register
//   - then a log line every second (uptime), LEDs counting seconds
//   - S2 prints a burst of 40 colored lines (one every 50 ms), to watch the
//     hardware scrolling
//
// Runs on the 25.2 MHz pixel clock (the Makefile passes CPU_HZ).

#include "soc.h"
#include "console.h"

static const char *const color_names[16] = {
    "black", "blue", "green", "cyan", "red", "magenta", "brown", "light gray",
    "dark gray", "light blue", "light green", "light cyan", "light red",
    "light magenta", "yellow", "white"
};

static void title_bar(void)
{
    con_fill_row(0, ' ', WHITE, BLUE);
    con_color(WHITE, BLUE);
    con_goto(0, 2);
    con_puts("rv32i_core on Tang Nano 9K  -  text console over HDMI");
    con_color(LIGHT_GRAY, BLACK);
    con_goto(2, 0);
}

// Double-line box using the CP437 box-drawing characters of the font
static void box(int r0, int c0, int r1, int c1, int fg)
{
    con_put_at(r0, c0, 0xC9, fg, BLACK);
    con_put_at(r0, c1, 0xBB, fg, BLACK);
    con_put_at(r1, c0, 0xC8, fg, BLACK);
    con_put_at(r1, c1, 0xBC, fg, BLACK);
    for (int c = c0 + 1; c < c1; c++) {
        con_put_at(r0, c, 0xCD, fg, BLACK);
        con_put_at(r1, c, 0xCD, fg, BLACK);
    }
    for (int r = r0 + 1; r < r1; r++) {
        con_put_at(r, c0, 0xBA, fg, BLACK);
        con_put_at(r, c1, 0xBA, fg, BLACK);
    }
}

static int is_prime(unsigned int n)
{
    if (n < 2)
        return 0;
    for (unsigned int d = 2; d * d <= n; d++)
        if (n % d == 0)
            return 0;
    return 1;
}

static void put_2digits(unsigned int n)
{
    con_putc('0' + n / 10);
    con_putc('0' + n % 10);
}

static void burst(void)
{
    con_color(YELLOW, BLACK);
    con_puts("S2 pressed: 40 lines in a row...\n");
    for (int i = 1; i <= 40; i++) {
        con_color(LIGHT_BLUE + i % 7, BLACK);    // the 7 bright colors, 9..15
        con_puts("  line ");
        con_put_dec(i);
        con_puts(" - scrolling changes one register, not 2400 cells\n");
        delay_ms(50);        // slow enough to watch the screen scroll (2 s in total)
    }
    con_color(LIGHT_GRAY, BLACK);
}

int main(void)
{
    con_init(LIGHT_GRAY, BLACK);
    title_bar();

    con_puts("CPU    : rv32i_core, RV32I, multi-cycle, ");
    con_put_dec(CPU_HZ / 1000000);              // 25.2: integer part,
    con_putc('.');
    con_put_dec(CPU_HZ / 100000 % 10);          // then one decimal
    con_puts(" MHz\n");
    con_puts("Memory : 8 KB RAM at 0x00000000, IO at 0x10000000, text at 0x20000000\n");
    con_puts("Screen : 80 x 30 characters, 16 colors, 640 x 480 @ 60 Hz\n\n");

    // Color table inside a box: rows 6..15
    box(6, 1, 15, 76, LIGHT_CYAN);
    for (int i = 0; i < 16; i++) {
        int row = 7 + i % 8, col = 3 + (i / 8) * 37;
        con_goto(row, col);
        con_color(i == BLACK ? DARK_GRAY : i, BLACK);
        con_putc(0xDB); con_putc(0xDB); con_putc(' ');   // two solid blocks as a swatch
        con_put_dec(i);
        con_putc(' ');
        con_puts(color_names[i]);
    }
    con_color(LIGHT_GRAY, BLACK);
    con_goto(17, 0);

    // Benchmark
    con_puts("Counting primes below 5000... ");
    unsigned int t0 = TIMER, count = 0;
    for (unsigned int n = 0; n < 5000; n++)
        count += is_prime(n);
    unsigned int ms = (TIMER - t0) / (CPU_HZ / 1000);
    con_put_dec(count);
    con_puts(" found in ");
    con_put_dec(ms);
    con_puts(" ms\n\n");

    con_color(LIGHT_GREEN, BLACK);
    con_puts("Running. One line per second; press S2 for a burst of lines.\n");
    con_color(LIGHT_GRAY, BLACK);

    // Main loop
    unsigned int seconds = 0, next = TIMER + CPU_HZ, was_pressed = 0;
    for (;;) {
        unsigned int pressed = BUTTONS & 1;
        if (pressed && !was_pressed)
            burst();
        was_pressed = pressed;

        if ((int)(TIMER - next) >= 0) {        // wrap-safe "TIMER >= next"
            next += CPU_HZ;
            seconds++;
            LEDS = seconds;
            con_puts("uptime ");
            put_2digits(seconds / 3600);
            con_putc(':');
            put_2digits(seconds / 60 % 60);
            con_putc(':');
            put_2digits(seconds % 60);
            con_puts("   timer = 0x");
            con_put_hex(TIMER, 8);
            con_putc('\n');
        }
        delay_ms(10);
    }
}
