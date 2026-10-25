// Text console on the 80x30 HDMI screen - see console.h
//
// The character RAM is a ring of `ring` rows (30, or up to 51 with
// scrollback - the hardware tells us in TEXT_RING). `top` is the RAM row
// shown at the top of the screen (the value in TEXT_SCROLL), so logical row
// r lives in RAM row (top + r) mod ring.
//
//   Scrolling up   = top + 1, then clear the row that appears at the bottom.
//   Scrolling back = top - 1: with a ring bigger than the screen, the row
//                    that reappears at the top still holds its old text.
//
// `back` counts how many lines above the screen still hold valid text
// (at most ring - 30). The screen doesn't remember where a line ended, so
// line_len[] keeps that for every RAM row - needed to put the cursor at the
// end of the previous line when a row is deleted.

#include "soc.h"
#include "console.h"

#define MAX_RING 51

static int ring = TEXT_ROWS;     // rows in the RAM ring
static int top;                  // RAM row shown at the top of the screen
static int back;                 // valid lines kept above the screen
static int cur_row, cur_col;     // cursor, logical
static unsigned int attr;        // current colors, already shifted: bg<<12 | fg<<8
static unsigned char line_len[MAX_RING];   // per RAM row: where its line ended

static int ram_row(int row)
{
    int r = top + row;
    if (r >= ring)
        r -= ring;
    return r;
}

// Address of the cell at a logical row/col
static volatile unsigned int *cell(int row, int col)
{
    return &TEXT[ram_row(row) * TEXT_COLS + col];
}

void con_put_at(int row, int col, unsigned char c, int fg, int bg)
{
    *cell(row, col) = (bg << 12) | (fg << 8) | c;
}

void con_fill_row(int row, unsigned char c, int fg, int bg)
{
    volatile unsigned int *p = cell(row, 0);
    unsigned int v = (bg << 12) | (fg << 8) | c;
    for (int i = 0; i < TEXT_COLS; i++)
        p[i] = v;
}

void con_color(int fg, int bg)
{
    attr = (bg << 12) | (fg << 8);
}

void con_init(int fg, int bg)
{
    ring = TEXT_RING;                // 30 on hardware without scrollback
    if (ring < TEXT_ROWS || ring > MAX_RING)
        ring = TEXT_ROWS;
    top = back = 0;
    TEXT_SCROLL = 0;
    // Clear the whole ring, not just the visible rows, so no old text can
    // come back when scrolling back
    for (int r = 0; r < ring; r++) {
        con_fill_row(r, ' ', fg, bg);
        line_len[r] = 0;
    }
    con_color(fg, bg);
    cur_row = cur_col = 0;
}

void con_goto(int row, int col)
{
    cur_row = row;
    cur_col = col;
}

static void new_line(void)
{
    line_len[ram_row(cur_row)] = cur_col;      // remember where this line ended
    cur_col = 0;
    if (cur_row < TEXT_ROWS - 1) {
        cur_row++;
        return;
    }
    // Bottom reached: scroll everything up one line in hardware
    top = (top == ring - 1) ? 0 : top + 1;
    TEXT_SCROLL = top;
    if (back < ring - TEXT_ROWS)
        back++;                                 // one more line kept above the screen
    // The row now at the bottom held the oldest kept line (or nothing): blank it
    con_fill_row(TEXT_ROWS - 1, ' ', (attr >> 8) & 15, attr >> 12);
    line_len[ram_row(TEXT_ROWS - 1)] = 0;
}

void con_putc(char c)
{
    if (c == '\n') {
        new_line();
        return;
    }
    if (c == '\r') {
        cur_col = 0;
        return;
    }
    if (c == '\b') {                // backspace: step back and erase (not past the line start)
        if (cur_col > 0) {
            cur_col--;
            *cell(cur_row, cur_col) = attr | ' ';
        }
        return;
    }
    if (cur_col >= TEXT_COLS)       // cursor parked after a full line (see con_delete_row)
        new_line();
    *cell(cur_row, cur_col) = attr | (unsigned char)c;
    if (++cur_col == TEXT_COLS)     // automatic wrap at the right edge
        new_line();
}

void con_clear_line(void)
{
    con_fill_row(cur_row, ' ', (attr >> 8) & 15, attr >> 12);
    cur_col = 0;
}

int con_delete_row(void)
{
    if (cur_row == 0 && back == 0)
        return 0;                               // nothing above to go back to

    con_fill_row(cur_row, ' ', (attr >> 8) & 15, attr >> 12);
    line_len[ram_row(cur_row)] = 0;

    if (back > 0) {
        // Scroll back: everything moves down one row, the most recent line
        // that had scrolled off comes back at the top. The cursor row now
        // shows the line that was above it.
        top = (top == 0) ? ring - 1 : top - 1;
        TEXT_SCROLL = top;
        back--;
    } else {
        cur_row--;                              // nothing kept above: just move up
    }
    cur_col = line_len[ram_row(cur_row)];       // to the end of that line
    return 1;
}

int con_cursor_col(void)
{
    return cur_col;
}

void con_puts(const char *s)
{
    while (*s)
        con_putc(*s++);
}

void con_put_dec(unsigned int n)
{
    char buf[10];
    int i = 0;
    do {
        buf[i++] = '0' + n % 10;
        n /= 10;
    } while (n);
    while (i)
        con_putc(buf[--i]);
}

void con_put_hex(unsigned int n, int digits)
{
    while (digits--)
        con_putc("0123456789ABCDEF"[(n >> (4 * digits)) & 15]);
}
