// rv32i_core - a small multi-cycle RISC-V CPU (RV32I base integer ISA)
//
// RISC-V in one paragraph: 32 registers x0..x31 of 32 bits (x0 always reads
// 0), a program counter (pc), and fixed 32-bit instructions. Every
// instruction either computes something into a register, reads/writes
// memory (loads/stores are the ONLY instructions that touch memory), or
// changes the pc (jumps and branches). RV32I has 37 such instructions plus
// FENCE/ECALL/EBREAK; that's the whole base ISA, and GCC can compile C to it.
//
// "Multi-cycle" means one instruction is handled at a time, in several
// clock cycles, by a small state machine:
//
//          +--------------------------------------------------+
//          v                                                  |
//      FETCH ---> DECODE ---> EXECUTE --(ALU / jump / branch)-+
//   wait for the   read the     compute; write rd; pick the   |
//   instruction    2 source     next pc and start fetching it |
//   word           registers       |                          |
//                                  +--(load / store)--> MEM --+
//                                                  wait for the data
//
//   ALU, jump, branch: 4 clocks per instruction (2 of them waiting for memory)
//   load, store      : 6 clocks
//   At 25.2 MHz that is roughly 5 million instructions per second.
//
// A pipelined CPU would overlap these steps (fetch the next instruction
// while executing this one) and get close to 1 clock per instruction, at
// the cost of hazard detection and forwarding logic. Multi-cycle keeps the
// design small and every step visible.
//
// Memory bus (same idea as PicoRV32's "native" interface):
//   The CPU raises mem_valid with mem_addr (and for a write: mem_wdata and
//   mem_wstrb != 0). It keeps them stable until the memory raises mem_ready
//   for one clock. For a read, mem_rdata is valid in that same clock.
//   mem_wstrb selects the bytes to write: bit 0 = bits 7..0, ..., bit 3 =
//   bits 31..24. mem_wstrb = 0 means read.
//   Addresses are byte addresses; the CPU always presents a word-aligned
//   address (mem_addr[1:0] = 0) and uses wstrb / shifting for bytes and
//   halfwords.
//
// Not implemented (on purpose, to stay small):
//   - misaligned loads/stores (e.g. a 32-bit load from address 2): the result
//     is undefined. GCC never generates them for normal C code.
//   - CSRs, interrupts, exceptions: ECALL, EBREAK and any unknown
//     instruction stop the CPU and raise `trap`.
//   - FENCE is accepted and does nothing (there are no caches).

module rv32i_core #(
    parameter [31:0] RESET_PC = 32'h0000_0000
) (
    input  wire        clk,
    input  wire        rst,          // synchronous, active high

    output reg         mem_valid = 0,
    output reg  [31:0] mem_addr  = 0,
    output reg  [31:0] mem_wdata = 0,
    output reg  [3:0]  mem_wstrb = 0,
    input  wire        mem_ready,
    input  wire [31:0] mem_rdata,

    output reg         trap = 0      // CPU stopped (ECALL/EBREAK/illegal instruction)
);

    // ---- Architectural state ----------------------------------------------
    reg [31:0] pc = RESET_PC;
    reg [31:0] regs [0:31];          // x0..x31; x0 is never written, so stays 0

    integer k;
    initial for (k = 0; k < 32; k = k + 1) regs[k] = 0;

    // ---- Internal state -----------------------------------------------------
    localparam S_FETCH  = 3'd0,
               S_DECODE = 3'd1,
               S_EXEC   = 3'd2,
               S_MEM    = 3'd3,
               S_TRAP   = 3'd4;

    reg [2:0]  state   = S_FETCH;
    reg [31:0] ir      = 0;          // instruction register: the current instruction
    reg [31:0] rs1_val = 0;          // source register values, read in DECODE
    reg [31:0] rs2_val = 0;

    // ---- Instruction fields -------------------------------------------------
    // All RISC-V instructions keep these fields in the same bit positions,
    // so decoding is mostly just wiring.
    //
    //   31        25 24   20 19   15 14  12 11    7 6      0
    //  |  funct7    |  rs2  |  rs1  |funct3|  rd   | opcode |   R-type (reg-reg)
    //  |     imm[11:0]      |  rs1  |funct3|  rd   | opcode |   I-type (imm, loads, jalr)
    //  | imm[11:5]  |  rs2  |  rs1  |funct3|imm[4:0]| opcode|   S-type (stores)
    //  |            imm[31:12]             |  rd   | opcode |   U-type (lui, auipc)
    //   B-type (branches) and J-type (jal) are S and U with the immediate
    //   bits shuffled, so that the sign bit is always ir[31].
    wire [6:0] opcode = ir[6:0];
    wire [4:0] rd     = ir[11:7];
    wire [2:0] funct3 = ir[14:12];
    wire [4:0] rs1    = ir[19:15];
    wire [4:0] rs2    = ir[24:20];
    wire       alt    = ir[30];      // funct7 bit 5: SUB instead of ADD, SRA instead of SRL

    // Immediates, sign-extended to 32 bits ({n{bit}} repeats the sign bit)
    wire [31:0] imm_i = {{20{ir[31]}}, ir[31:20]};
    wire [31:0] imm_s = {{20{ir[31]}}, ir[31:25], ir[11:7]};
    wire [31:0] imm_b = {{19{ir[31]}}, ir[31], ir[7], ir[30:25], ir[11:8], 1'b0};
    wire [31:0] imm_u = {ir[31:12], 12'b0};
    wire [31:0] imm_j = {{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0};

    localparam OP_LUI    = 7'b0110111,   // rd = imm << 12
               OP_AUIPC  = 7'b0010111,   // rd = pc + (imm << 12)
               OP_JAL    = 7'b1101111,   // rd = pc + 4; pc += imm
               OP_JALR   = 7'b1100111,   // rd = pc + 4; pc = rs1 + imm
               OP_BRANCH = 7'b1100011,   // if (rs1 ? rs2) pc += imm
               OP_LOAD   = 7'b0000011,   // rd = mem[rs1 + imm]
               OP_STORE  = 7'b0100011,   // mem[rs1 + imm] = rs2
               OP_IMM    = 7'b0010011,   // rd = rs1 (op) imm
               OP_REG    = 7'b0110011,   // rd = rs1 (op) rs2
               OP_FENCE  = 7'b0001111,   // memory ordering - nothing to do here
               OP_SYSTEM = 7'b1110011;   // ECALL / EBREAK / CSRs

    // ---- ALU ------------------------------------------------------------------
    // One ALU serves OP and OP-IMM; funct3 selects the operation. The second
    // operand is rs2 for register-register ops and the immediate otherwise.
    wire [31:0] alu_a = rs1_val;
    wire [31:0] alu_b = (opcode == OP_REG) ? rs2_val : imm_i;
    wire [4:0]  shamt = alu_b[4:0];          // shifts use only the low 5 bits

    // Arithmetic shift right gets its own signal on purpose. Written inline as
    // `alt ? $signed(a) >>> n : a >> n`, the unsigned second branch makes the
    // whole ?: expression unsigned, which silently turns >>> into a logical
    // shift (zeros instead of copies of the sign bit shifted in). The test
    // program caught exactly that (test 13).
    wire signed [31:0] alu_sra = $signed(alu_a) >>> shamt;

    reg [31:0] alu_out;
    always @(*) begin
        case (funct3)
            3'b000: alu_out = (opcode == OP_REG && alt) ? alu_a - alu_b : alu_a + alu_b;  // ADD/SUB
            3'b001: alu_out = alu_a << shamt;                                              // SLL
            3'b010: alu_out = {31'b0, $signed(alu_a) < $signed(alu_b)};                    // SLT
            3'b011: alu_out = {31'b0, alu_a < alu_b};                                      // SLTU
            3'b100: alu_out = alu_a ^ alu_b;                                               // XOR
            3'b101: alu_out = alt ? alu_sra : alu_a >> shamt;                              // SRA/SRL
            3'b110: alu_out = alu_a | alu_b;                                               // OR
            3'b111: alu_out = alu_a & alu_b;                                               // AND
        endcase
    end

    // Branch condition (funct3: 000 BEQ, 001 BNE, 100 BLT, 101 BGE, 110 BLTU, 111 BGEU)
    reg branch_taken;
    always @(*) begin
        case (funct3)
            3'b000:  branch_taken = rs1_val == rs2_val;
            3'b001:  branch_taken = rs1_val != rs2_val;
            3'b100:  branch_taken = $signed(rs1_val) <  $signed(rs2_val);
            3'b101:  branch_taken = $signed(rs1_val) >= $signed(rs2_val);
            3'b110:  branch_taken = rs1_val <  rs2_val;
            3'b111:  branch_taken = rs1_val >= rs2_val;
            default: branch_taken = 1'b0;
        endcase
    end

    // ---- Loads and stores -----------------------------------------------------
    // Address for loads uses the I-immediate, stores the S-immediate
    wire [31:0] ls_addr = rs1_val + ((opcode == OP_STORE) ? imm_s : imm_i);

    // Stores: the memory is 32 bits wide, so put the byte/halfword in every
    // lane it could go to and let wstrb pick the right one.
    //   funct3 000 SB: 1 byte, 001 SH: 2 bytes, 010 SW: 4 bytes
    wire [31:0] store_data  = (funct3[1:0] == 2'b00) ? {4{rs2_val[7:0]}}  :
                              (funct3[1:0] == 2'b01) ? {2{rs2_val[15:0]}} : rs2_val;
    wire [3:0]  store_wstrb = (funct3[1:0] == 2'b00) ? (4'b0001 << ls_addr[1:0]) :
                              (funct3[1:0] == 2'b01) ? (4'b0011 << ls_addr[1:0]) : 4'b1111;

    // Loads: shift the addressed byte/halfword down to bit 0, then extend.
    // The bus address is word aligned, so the low 2 bits of the load address
    // are kept in mem_addr_lo to know which byte lane to use.
    //   funct3 000 LB, 001 LH, 010 LW, 100 LBU, 101 LHU (U = zero-extend)
    reg  [1:0]  mem_addr_lo  = 0;        // low address bits of the pending load
    wire [31:0] load_shifted = mem_rdata >> {mem_addr_lo, 3'b000};
    reg  [31:0] load_value;
    always @(*) begin
        case (funct3)
            3'b000:  load_value = {{24{load_shifted[7]}},  load_shifted[7:0]};   // LB
            3'b001:  load_value = {{16{load_shifted[15]}}, load_shifted[15:0]};  // LH
            3'b100:  load_value = {24'b0, load_shifted[7:0]};                    // LBU
            3'b101:  load_value = {16'b0, load_shifted[15:0]};                   // LHU
            default: load_value = load_shifted;                                  // LW
        endcase
    end

    // ---- Register file write port -----------------------------------------
    reg        rd_we    = 0;
    reg [31:0] rd_wdata = 0;
    always @(posedge clk)
        if (rd_we && rd != 0)            // writes to x0 are discarded
            regs[rd] <= rd_wdata;

    // ---- The state machine ------------------------------------------------
    wire [31:0] pc_plus4 = pc + 4;

    // Start fetching the instruction at `addr` (used at the end of every instruction)
    task start_fetch(input [31:0] addr);
        begin
            pc        <= addr;
            mem_valid <= 1;
            mem_addr  <= addr;
            mem_wstrb <= 0;
            state     <= S_FETCH;
        end
    endtask

    always @(posedge clk) begin
        rd_we <= 0;

        if (rst) begin
            pc        <= RESET_PC;
            mem_valid <= 1;              // fetch the first instruction right away
            mem_addr  <= RESET_PC;
            mem_wstrb <= 0;
            trap      <= 0;
            state     <= S_FETCH;
        end else case (state)

            // Wait for the instruction word
            S_FETCH: if (mem_ready) begin
                mem_valid <= 0;
                ir        <= mem_rdata;
                state     <= S_DECODE;
            end

            // Read the two source registers. This is a clocked read (like a
            // block RAM), so the values are ready in EXEC. Every instruction
            // reads both, even if it doesn't use them - that's harmless and
            // keeps the decoder simple.
            S_DECODE: begin
                rs1_val <= regs[rs1];
                rs2_val <= regs[rs2];
                state   <= S_EXEC;
            end

            // Do the work and decide what comes next
            S_EXEC: case (opcode)
                OP_LUI: begin
                    rd_we <= 1; rd_wdata <= imm_u;
                    start_fetch(pc_plus4);
                end
                OP_AUIPC: begin
                    rd_we <= 1; rd_wdata <= pc + imm_u;
                    start_fetch(pc_plus4);
                end
                OP_JAL: begin
                    rd_we <= 1; rd_wdata <= pc_plus4;     // return address
                    start_fetch(pc + imm_j);
                end
                OP_JALR: begin
                    rd_we <= 1; rd_wdata <= pc_plus4;
                    start_fetch((rs1_val + imm_i) & ~32'd1);   // bit 0 cleared by the spec
                end
                OP_BRANCH:
                    start_fetch(branch_taken ? pc + imm_b : pc_plus4);
                OP_IMM, OP_REG: begin
                    rd_we <= 1; rd_wdata <= alu_out;
                    start_fetch(pc_plus4);
                end
                OP_LOAD: begin
                    mem_valid   <= 1;
                    mem_addr    <= {ls_addr[31:2], 2'b00};
                    mem_addr_lo <= ls_addr[1:0];
                    mem_wstrb   <= 0;
                    state       <= S_MEM;
                end
                OP_STORE: begin
                    mem_valid <= 1;
                    mem_addr  <= {ls_addr[31:2], 2'b00};
                    mem_wdata <= store_data;
                    mem_wstrb <= store_wstrb;
                    state     <= S_MEM;
                end
                OP_FENCE:
                    start_fetch(pc_plus4);
                default: begin                     // ECALL, EBREAK, CSRs, unknown
                    trap  <= 1;
                    state <= S_TRAP;
                end
            endcase

            // Wait for the load data / store completion
            S_MEM: if (mem_ready) begin
                if (opcode == OP_LOAD) begin
                    rd_we <= 1; rd_wdata <= load_value;
                end
                mem_wstrb <= 0;
                start_fetch(pc_plus4);
            end

            // Stopped. Only reset gets the CPU out of here.
            S_TRAP: mem_valid <= 0;

            default: state <= S_TRAP;
        endcase
    end

endmodule
