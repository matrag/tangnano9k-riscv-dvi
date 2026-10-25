// Text console on the 80x30 HDMI screen (step 6).
//
// Works like a terminal: characters appear at the cursor, '\n' moves to the
// next line, and when the cursor goes past the bottom line the whole screen
// scrolls up by one line (using the hardware SCROLL register).
//
// Rows in this API are "logical": row 0 is always the top line currently
// on the screen, whatever the scroll position is.
//
// On hardware with scrollback (TEXT_RING > 30, step 7) the last lines that
// scrolled off the top are kept, and con_delete_row() can bring them back.

#ifndef CONSOLE_H
#define CONSOLE_H

// The 16 CGA colors, same order as the palette in lib/text_mode.v
enum {
    BLACK, BLUE, GREEN, CYAN, RED, MAGENTA, BROWN, LIGHT_GRAY,
    DARK_GRAY, LIGHT_BLUE, LIGHT_GREEN, LIGHT_CYAN, LIGHT_RED, LIGHT_MAGENTA, YELLOW, WHITE
};

void con_init(int fg, int bg);                  // clear the screen, cursor to 0,0
void con_color(int fg, int bg);                 // color for the following text
void con_goto(int row, int col);                // move the cursor
void con_putc(char c);                          // print one character ('\n' new line, '\b' backspace)
void con_puts(const char *s);                   // print a string
void con_put_dec(unsigned int n);               // print a number in decimal
void con_put_hex(unsigned int n, int digits);   // print a number in hex, fixed width
void con_put_at(int row, int col, unsigned char c, int fg, int bg);  // one cell, cursor unchanged
void con_fill_row(int row, unsigned char c, int fg, int bg);         // a whole line
void con_clear_line(void);                      // blank the cursor's line, cursor to its start
int  con_delete_row(void);                      // remove the cursor's line, go to the end of the
                                                // previous one (scrolling back if possible);
                                                // returns 0 if there is nothing to go back to
int  con_cursor_col(void);                      // cursor column (0..80)

#endif
