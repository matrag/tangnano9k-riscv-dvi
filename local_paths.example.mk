# Paths of the tools on your PC, for sw/Makefile.
#
# framework_initialise.py writes the real file, local_paths.mk, next to this
# one. local_paths.mk is not part of the repository (see .gitignore), because
# it contains paths of your own PC. To write it by hand instead: copy this
# file to local_paths.mk and adjust the paths. Use forward slashes, also on
# Windows, and no spaces before a # comment on the same line.

# The bin folder of the xPack RISC-V GCC (contains riscv-none-elf-gcc)
GCC_BIN := C:/path/to/tangnano9k-riscv-dvi/toolchain/riscv-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin

# OSS CAD Suite (contains bin/ with yosys, nextpnr-himbaechel, iverilog, ...).
# Not used by sw/Makefile; it is the folder to enter in Lushay Code's setting
# lushay.OssCadSuite.path (see SETUP.md).
OSS_CAD := C:/path/to/tangnano9k-riscv-dvi/toolchain/oss-cad-suite

# The Python that has pyserial (used for bin2hex and the upload tools)
PYTHON := python
