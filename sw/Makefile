# Software for the rv32i_core, shared by all steps.
#
#   make                            builds every program below
#   make upload PROG=07_terminal    builds PROG and sends it to the board's bootloader
#                                   (step 8 hardware). One board connected: found
#                                   automatically; several: add PORT=COM8
#   make ports                      lists the connected Tang Nano boards
#   make gui                        opens the upload window (tools/upload_gui.py)
#   make clean                      removes the build outputs
#
# File names: a program that belongs to one step starts with that step's
# number (04_hello.c is step 4's). Files without a number are shared by
# several steps: start.S, link.ld, soc.h, console.c/.h.
#
# Each program ends up as a memory init file (.hex) in the step folder that
# uses it, because Lushay runs yosys/iverilog from the project folder:
#   04_rv32i_test.S -> ../04_cpu_sim/rv32i_test.hex   (simulation)
#   04_hello.c      -> ../04_cpu_sim/hello.hex        (simulation; also uploaded in step 8's test)
#   05_leds.c       -> ../05_cpu_leds/leds.hex        (board)
#   06_text.c       -> ../06_cpu_text/text.hex        (board)
#   07_terminal.c   -> ../07_uart/terminal.hex        (board; also preloaded in step 8)
#   08_boot.c       -> ../08_bootloader/boot.hex      (the bootloader, in the boot ROM)
#
# Per program, build/ also gets:
#   .elf  the linked program, with symbols
#   .lst  disassembly: every instruction with its address and machine code -
#         keep it open next to a waveform
#   .bin  raw memory image (this is what `make upload` sends)

# Where the tools are: ../local_paths.mk, written by framework_initialise.py and
# not part of the repository (it holds paths of your own PC). Without it, the
# compiler (riscv-none-elf-gcc) and python must be on the PATH.
-include ../local_paths.mk

GCC_BIN ?=
PREFIX  := $(if $(GCC_BIN),$(GCC_BIN)/)riscv-none-elf-
CC      := $(PREFIX)gcc
OBJCOPY := $(PREFIX)objcopy
OBJDUMP := $(PREFIX)objdump
PYTHON  ?= python
# Serial port for uploads; empty = the only Tang Nano board connected.
# (The comment is on its own line: in make, spaces before a # would be part of the value.)
PORT    ?=

RAM_WORDS  := 2048      # 8 KB, must match RAM_ADDR_BITS (11) in the SoC
BOOT_WORDS := 512       # 2 KB boot ROM, must match the boot ROM size in lib/soc.v

# -march=rv32i     only the base integer instructions (no M, A, F, C extensions)
# -mabi=ilp32      int/long/pointer are 32 bit, no floating point registers
# -ffreestanding   no operating system / C library behind us
# -nostdlib        don't link the C library or its startup code (we have start.S)
# -Wl,--no-relax   don't let the linker rewrite address loads relative to the
#                  "global pointer" register, which start.S doesn't set up
# -Wl,--no-warn-rwx-segments
#                  code and data share one RAM, which the linker would
#                  otherwise warn about (a security concern on a PC, not here)
# -ffunction-sections + --gc-sections: put every function in its own section
#                  and let the linker drop the ones nobody calls, so programs
#                  that don't use the console don't carry its code
COMMON  := -march=rv32i -mabi=ilp32 -Os -ffreestanding -nostdlib -Wall \
           -Wl,--no-relax -Wl,--no-warn-rwx-segments \
           -ffunction-sections -Wl,--gc-sections
CFLAGS  := $(COMMON) -T link.ld         # programs that run from RAM at address 0

# Extra flags per program: from step 6 on, the CPU runs on the 25.2 MHz pixel clock
CFLAGS_06_text     := -DCPU_HZ=25200000u
CFLAGS_07_terminal := -DCPU_HZ=25200000u

HEXES := ../04_cpu_sim/rv32i_test.hex ../04_cpu_sim/hello.hex ../05_cpu_leds/leds.hex \
         ../06_cpu_text/text.hex ../07_uart/terminal.hex ../08_bootloader/boot.hex

all: $(HEXES)

# Folders are made and removed with Python, not mkdir/rm: on Windows, make may
# run commands through cmd.exe, where "mkdir -p build" creates a folder named -p.
build:
	$(PYTHON) -c "import os; os.makedirs('build', exist_ok=True)"

# The instruction test is self-contained assembly with its own _start
build/04_rv32i_test.elf: 04_rv32i_test.S link.ld | build
	$(CC) $(CFLAGS) -o $@ 04_rv32i_test.S

# The bootloader: runs from the boot ROM at 0x3000_0000 with its own linker
# script and startup code. -fno-delete-null-pointer-checks: it really writes
# to address 0 (the start of RAM), which C would otherwise treat as a null pointer.
build/08_boot.elf: 08_boot.c 08_boot_start.S 08_boot.ld soc.h | build
	$(CC) $(COMMON) -T 08_boot.ld -DCPU_HZ=25200000u -fno-delete-null-pointer-checks \
	      -o $@ 08_boot_start.S 08_boot.c -lgcc

# Only .text (code + constants) goes into the ROM image. Without -j, objcopy
# would fill the gap between the RAM (0x1F00) and the ROM (0x3000_0000) with zeros.
build/08_boot.bin: build/08_boot.elf
	$(OBJCOPY) -O binary -j .text $< $@
	$(OBJDUMP) -d $< > build/08_boot.lst

# C programs: start.S first, then the C file and the console library;
# libgcc supplies the multiply/divide helpers
build/%.elf: %.c start.S link.ld soc.h console.c console.h | build
	$(CC) $(CFLAGS) $(CFLAGS_$*) -o $@ start.S $< console.c -lgcc

build/%.bin: build/%.elf
	$(OBJCOPY) -O binary $< $@
	$(OBJDUMP) -d $< > build/$*.lst

# Program image -> .hex in its step folder (the hex keeps the short name the
# Verilog files load)
TO_HEX = $(PYTHON) -I ../tools/bin2hex.py $< $@

../04_cpu_sim/rv32i_test.hex: build/04_rv32i_test.bin ; $(TO_HEX) $(RAM_WORDS)
../04_cpu_sim/hello.hex:      build/04_hello.bin      ; $(TO_HEX) $(RAM_WORDS)
../05_cpu_leds/leds.hex:      build/05_leds.bin       ; $(TO_HEX) $(RAM_WORDS)
../06_cpu_text/text.hex:      build/06_text.bin       ; $(TO_HEX) $(RAM_WORDS)
../07_uart/terminal.hex:      build/07_terminal.bin   ; $(TO_HEX) $(RAM_WORDS)
../08_bootloader/boot.hex:    build/08_boot.bin       ; $(TO_HEX) $(BOOT_WORDS)

# Send a program to the step 8 bootloader: make upload PROG=07_terminal [PORT=COM8]
# The program must be built for 25.2 MHz (see CFLAGS_<name> above).
PROG ?= 07_terminal
upload: build/$(PROG).bin
	$(PYTHON) -I ../tools/upload.py $< $(if $(PORT),--port $(PORT))

ports:
	$(PYTHON) -I ../tools/upload.py --list

gui: all
	$(PYTHON) -I ../tools/upload_gui.py

clean:
	$(PYTHON) -c "import os, shutil, sys; shutil.rmtree('build', ignore_errors=True); [os.remove(f) for f in sys.argv[1:] if os.path.exists(f)]" $(HEXES)

.PHONY: all clean upload ports gui
.SECONDARY:
