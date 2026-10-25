// LED patterns on the Tang Nano 9K, driven by the rv32i_core.
//
// Two patterns, S2 switches between them:
//   0: "Knight Rider" - one light bouncing left and right
//   1: binary counter
// S1 resets the CPU (handled in hardware), which restarts this program.
//
// Timing uses the TIMER register (a cycle counter), so the speed doesn't
// depend on how fast the CPU executes the loop.

#include "soc.h"

#define NUM_LEDS  6
#define STEP_MS   80         // one pattern step
#define POLL_MS   10         // how often the button is checked

static unsigned int knight_rider(unsigned int step)
{
    // positions 0,1,2,3,4,5,4,3,2,1, 0,1,... : a period of 2*(6-1) = 10 steps
    unsigned int period = 2 * (NUM_LEDS - 1);
    unsigned int pos = step % period;
    if (pos >= NUM_LEDS)
        pos = period - pos;
    return 1u << pos;
}

int main(void)
{
    unsigned int mode = 0;
    unsigned int step = 0;
    unsigned int was_pressed = 0;

    // Short "all on" flash at start-up, to see that the program is running
    LEDS = (1u << NUM_LEDS) - 1;
    delay_ms(300);

    for (;;) {
        LEDS = (mode == 0) ? knight_rider(step) : step;
        step++;

        // Wait STEP_MS, checking the button every POLL_MS. Acting only on the
        // change from "not pressed" to "pressed" (an edge) means holding the
        // button switches once, not every step. Polling every 10 ms also
        // ignores contact bounce, which lasts only a few ms.
        for (unsigned int t = 0; t < STEP_MS; t += POLL_MS) {
            unsigned int pressed = BUTTONS & 1;
            if (pressed && !was_pressed) {
                mode ^= 1;
                step = 0;
            }
            was_pressed = pressed;
            delay_ms(POLL_MS);
        }
    }
}
