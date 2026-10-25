# Self-checking test of every RV32I instruction.
#
# Each test loads known inputs, runs one instruction, and compares the result
# with the value the RISC-V spec says it must produce. The test number is
# kept in x31; on the first mismatch the program writes that number to the
# EXIT register, so the simulation reports exactly which test failed.
# If everything passes it writes 0.
#
# Register use: x1, x2 = inputs, x3 = result, x4 = expected, x31 = test number

    .equ EXIT, 0x10000008

# rd = a <op> b, register-register
.macro TEST_RR n, inst, expected, a, b
    li   x31, \n
    li   x1, \a
    li   x2, \b
    \inst x3, x1, x2
    li   x4, \expected
    bne  x3, x4, fail
.endm

# rd = a <op> imm, register-immediate
.macro TEST_RI n, inst, expected, a, imm
    li   x31, \n
    li   x1, \a
    \inst x3, x1, \imm
    li   x4, \expected
    bne  x3, x4, fail
.endm

# branch must be taken
.macro TEST_BR_TAKEN n, inst, a, b
    li   x31, \n
    li   x1, \a
    li   x2, \b
    \inst x1, x2, 1f
    j    fail
1:
.endm

# branch must NOT be taken
.macro TEST_BR_NOT n, inst, a, b
    li   x31, \n
    li   x1, \a
    li   x2, \b
    \inst x1, x2, fail
.endm

# load from `data` + offset, compare
.macro TEST_LD n, inst, expected, offset
    li   x31, \n
    la   x1, data
    \inst x3, \offset(x1)
    li   x4, \expected
    bne  x3, x4, fail
.endm

    .section .text.start
    .globl _start
_start:

# ---- ALU, register-register ---------------------------------------------------
    TEST_RR  1, add,  0x00000003, 1, 2
    TEST_RR  2, add,  0x00000000, 0xFFFFFFFF, 1          # wraps around
    TEST_RR  3, sub,  0xFFFFFFFF, 1, 2
    TEST_RR  4, sub,  0x80000000, 0x7FFFFFFF, 0xFFFFFFFF
    TEST_RR  5, sll,  0x80000000, 1, 31
    TEST_RR  6, sll,  0x00000002, 1, 33                  # only low 5 bits of the shift count
    TEST_RR  7, slt,  1, -1, 1                           # signed: -1 < 1
    TEST_RR  8, slt,  0, 1, -1
    TEST_RR  9, sltu, 0, -1, 1                           # unsigned: 0xFFFFFFFF > 1
    TEST_RR 10, sltu, 1, 1, -1
    TEST_RR 11, xor,  0x0FF00FF0, 0xFF00FF00, 0xF0F0F0F0
    TEST_RR 12, srl,  0x01000000, 0x80000000, 7
    TEST_RR 13, sra,  0xFF000000, 0x80000000, 7          # sign bit copied in
    TEST_RR 14, or,   0xFFF0FFF0, 0xFF00FF00, 0xF0F0F0F0
    TEST_RR 15, and,  0xF000F000, 0xFF00FF00, 0xF0F0F0F0

# ---- ALU, register-immediate (12-bit sign-extended immediate) -------------
    TEST_RI 20, addi,  0x00000000, 1, -1
    TEST_RI 21, addi,  0x000007FF, 0, 2047               # largest positive immediate
    TEST_RI 22, addi,  0xFFFFF800, 0, -2048              # most negative immediate
    TEST_RI 23, slti,  1, -5, -4
    TEST_RI 24, sltiu, 1, 0, 1                           # "seqz"
    TEST_RI 25, sltiu, 0, 5, 1
    TEST_RI 26, xori,  0xFFFFFF00, 0xFF, -1              # "not"
    TEST_RI 27, ori,   0x123457FF, 0x12345678, 0x7FF
    TEST_RI 28, andi,  0x00000678, 0x12345678, 0x7FF
    TEST_RI 29, slli,  0x80000000, 1, 31
    TEST_RI 30, srli,  0x00000001, 0x80000000, 31
    TEST_RI 31, srai,  0xFFFFFFFF, 0x80000000, 31

# ---- x0 is hard-wired to zero ---------------------------------------------
    li   x31, 40
    addi x0, x0, 5
    bne  x0, zero, fail
    add  x3, x0, x0
    bne  x3, zero, fail

# ---- LUI and AUIPC ----------------------------------------------------------
    li   x31, 41
    lui  x3, 0xABCDE
    li   x4, 0xABCDE000
    bne  x3, x4, fail

    li   x31, 42
auipc_here:
    auipc x3, 1                                          # x3 = address of this instruction + 0x1000
    lui   x4, %hi(auipc_here + 0x1000)
    addi  x4, x4, %lo(auipc_here + 0x1000)
    bne   x3, x4, fail

# ---- Branches, taken and not taken ------------------------------------------
    TEST_BR_TAKEN 50, beq,  7, 7
    TEST_BR_NOT   51, beq,  7, 8
    TEST_BR_TAKEN 52, bne,  7, 8
    TEST_BR_NOT   53, bne,  7, 7
    TEST_BR_TAKEN 54, blt,  -1, 1
    TEST_BR_NOT   55, blt,  1, -1
    TEST_BR_TAKEN 56, bge,  1, -1
    TEST_BR_TAKEN 57, bge,  5, 5
    TEST_BR_NOT   58, bge,  -1, 1
    TEST_BR_TAKEN 59, bltu, 1, -1                        # unsigned: 1 < 0xFFFFFFFF
    TEST_BR_NOT   60, bltu, -1, 1
    TEST_BR_TAKEN 61, bgeu, -1, 1
    TEST_BR_NOT   62, bgeu, 1, -1

    # backward branch: a loop summing 1..10
    li   x31, 63
    li   x1, 10
    li   x3, 0
sum_loop:
    add  x3, x3, x1
    addi x1, x1, -1
    bnez x1, sum_loop
    li   x4, 55
    bne  x3, x4, fail

# ---- Jumps --------------------------------------------------------------------
    li   x31, 70                                         # JAL writes the return address
    la   x4, jal_ret
    jal  x3, jal_target
jal_ret:
    j    fail                                            # must be skipped
jal_target:
    bne  x3, x4, fail

    li   x31, 71                                         # JALR jumps to rs1 + imm, bit 0 cleared
    la   x5, jalr_target
    addi x5, x5, -1                                      # odd address on purpose
    la   x4, jalr_ret
    jalr x3, 2(x5)                                       # (target - 1 + 2) & ~1 = target
jalr_ret:
    j    fail
jalr_target:
    bne  x3, x4, fail

# ---- Stores and loads ---------------------------------------------------------
    # data is initialized to 0x80FF017F (bytes, from address 0 up: 7F 01 FF 80)
    TEST_LD 80, lw,  0x80FF017F, 0
    TEST_LD 81, lb,  0x0000007F, 0
    TEST_LD 82, lb,  0x00000001, 1
    TEST_LD 83, lb,  0xFFFFFFFF, 2                       # 0xFF sign-extended
    TEST_LD 84, lb,  0xFFFFFF80, 3
    TEST_LD 85, lbu, 0x000000FF, 2                       # zero-extended
    TEST_LD 86, lbu, 0x00000080, 3
    TEST_LD 87, lh,  0x0000017F, 0
    TEST_LD 88, lh,  0xFFFF80FF, 2
    TEST_LD 89, lhu, 0x000080FF, 2

    # byte stores into each lane, then read the whole word back
    li   x31, 90
    la   x1, scratch
    sw   zero, 0(x1)
    li   x2, 0x11
    sb   x2, 0(x1)
    li   x2, 0x22
    sb   x2, 1(x1)
    li   x2, 0x33
    sb   x2, 2(x1)
    li   x2, 0x44
    sb   x2, 3(x1)
    lw   x3, 0(x1)
    li   x4, 0x44332211
    bne  x3, x4, fail

    # halfword stores
    li   x31, 91
    li   x2, 0xBEEF
    sh   x2, 0(x1)
    li   x2, 0xDEAD
    sh   x2, 2(x1)
    lw   x3, 0(x1)
    li   x4, 0xDEADBEEF
    bne  x3, x4, fail

    # a word store with a negative offset
    li   x31, 92
    li   x2, 0x13579BDF
    sw   x2, -4(x1)
    lw   x3, -4(x1)
    bne  x3, x2, fail

# ---- FENCE is a no-op here --------------------------------------------------
    li   x31, 95
    fence

# ---- All passed --------------------------------------------------------------
    li   x31, 0
fail:
    li   x1, EXIT
    sw   x31, 0(x1)
1:  j    1b

    .data
    .align 2
data:
    .word 0x80FF017F
    .word 0                                              # target of the -4 offset store
scratch:
    .word 0
