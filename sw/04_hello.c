// First C program for the rv32i_core.
//
// Prints through the simulator's CONSOLE register and checks a few
// computations whose answers are known. The return value of main() becomes
// the simulation's exit code: 0 = everything correct.
//
// There is no C library here (no printf): the CPU has no operating system,
// so we write the few output routines we need ourselves. Multiplication and
// division still work although RV32I has no multiply/divide instructions:
// GCC calls small helper functions from libgcc (__mulsi3, __udivsi3, ...)
// that do them with shifts and adds.

#include "soc.h"     // LEDS, CONSOLE, ... register addresses

static void putc(char c) { CONSOLE = c; }

static void puts(const char *s)
{
    while (*s)
        putc(*s++);
}

static void put_dec(unsigned int n)
{
    char buf[10];
    int i = 0;
    do {
        buf[i++] = '0' + n % 10;      // division -> libgcc helper
        n /= 10;
    } while (n);
    while (i)
        putc(buf[--i]);
}

static unsigned int fib(unsigned int n)
{
    unsigned int a = 0, b = 1;
    while (n--) {
        unsigned int t = a + b;
        a = b;
        b = t;
    }
    return a;
}

static int is_prime(unsigned int n)
{
    if (n < 2)
        return 0;
    for (unsigned int d = 2; d * d <= n; d++)    // multiplication -> libgcc helper
        if (n % d == 0)
            return 0;
    return 1;
}

static unsigned int factorial(unsigned int n)
{
    return n <= 1 ? 1 : n * factorial(n - 1);    // recursion uses the stack
}

int counter;            // in .bss: start.S must have cleared it

int main(void)
{
    int errors = 0;

    puts("Hello from rv32i_core!\n");

    puts("fib(0..15): ");
    for (unsigned int i = 0; i <= 15; i++) {
        put_dec(fib(i));
        putc(i < 15 ? ' ' : '\n');
    }
    if (fib(30) != 832040) errors++;

    puts("primes < 100: ");
    unsigned int primes = 0;
    for (unsigned int n = 0; n < 100; n++)
        if (is_prime(n)) {
            put_dec(n);
            putc(' ');
            primes++;
        }
    puts("\ncount = ");
    put_dec(primes);
    putc('\n');
    if (primes != 25) errors++;

    puts("10! = ");
    put_dec(factorial(10));
    putc('\n');
    if (factorial(10) != 3628800) errors++;

    if (counter != 0) errors++;
    for (int i = 0; i < 8; i++) {
        counter++;
        LEDS = counter;
    }
    if (counter != 8) errors++;

    puts(errors ? "SOME CHECKS FAILED\n" : "all checks passed\n");
    return errors;
}
