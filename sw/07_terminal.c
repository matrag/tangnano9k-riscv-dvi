// Step 7 demo: a terminal. What you type on the PC appears on the HDMI screen.
//
// Open a serial terminal on the board's COM port at 115200 baud, 8N1.
// Every character typed there is:
//   - shown on the HDMI screen (in yellow)
//   - sent back to the PC ("echo"), so you see it in the terminal too
//   - shown on the LEDs as its character code
// Enter starts a new line, Backspace deletes. S2 sends a message to the PC.

#include "soc.h"
#include "console.h"

static void put_both(const char *s)      // print on the screen and on the PC
{
    con_puts(s);
    for (; *s; s++) {
        if (*s == '\n')
            uart_putc('\r');               // terminals want "\r\n" for a new line
        uart_putc(*s);
    }
}

int main(void)
{
    con_init(LIGHT_GRAY, BLACK);
    con_fill_row(0, ' ', WHITE, BLUE);
    con_color(WHITE, BLUE);
    con_goto(0, 2);
    con_puts("rv32i_core on Tang Nano 9K  -  UART terminal, 115200 8N1");
    con_color(LIGHT_GRAY, BLACK);
    con_goto(2, 0);

    put_both("Hello from the FPGA! Type in your serial terminal;\n"
             "the text appears here and on the HDMI screen.\n\n");

    con_color(YELLOW, BLACK);
    unsigned int was_pressed = 0;
    int prev = 0;

    for (;;) {
        int c = uart_getc();
        if (c >= 0) {
            LEDS = c;
            if (c == '\n' && prev == '\r') {
                // "\r\n": some terminals send both for Enter - already handled
            } else if (c == '\r' || c == '\n') {   // Enter
                con_putc('\n');
                uart_puts("\r\n");
            } else if (c == '\b' || c == 127) {    // Backspace (some terminals send 127)
                con_putc('\b');
                uart_puts("\b \b");                // back, overwrite with space, back
            } else if (c >= 32 && c < 127) {       // printable
                con_putc(c);
                uart_putc(c);
            }
            prev = c;
        }

        unsigned int pressed = BUTTONS & 1;
        if (pressed && !was_pressed) {
            con_color(LIGHT_GREEN, BLACK);
            put_both("\n[S2 pressed]\n");
            con_color(YELLOW, BLACK);
        }
        was_pressed = pressed;
    }
}
