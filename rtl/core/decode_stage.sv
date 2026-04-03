// =============================================================================
// VSync - Decode Stage (ID Stage)
// RISC-V RV32IM Processor Pipeline - Instruction Decode
//
// File: decode_stage.sv
// Description: Full RV32IM instruction decoding, control signal generation,
//              immediate generation, register address extraction, M-extension
//              detection, CSR/ECALL/EBREAK/MRET detection.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module decode_stage (
    // Clock and Reset
    input  logic                clk,        // System clock
    input  logic                rst_n,      // Active-low asynchronous reset

    // Pipeline Input (from IF/ID register)
    input  if_id_reg_t          if_id_reg,  // IF/ID pipeline register

    // Pipeline Control
    input  logic                stall,      // Stall ID stage
    input  logic                flush,      // Flush ID/EX register

    // Register File Data (read from register file externally)
    input  logic [XLEN-1:0]    rs1_data,   // Source register 1 data
    input  logic [XLEN-1:0]    rs2_data,   // Source register 2 data

    // Register File Read Addresses
    output logic [REG_ADDR_W-1:0] rs1_addr,  // Source register 1 address
    output logic [REG_ADDR_W-1:0] rs2_addr,  // Source register 2 address

    // Pipeline Output (ID/EX register)
    output id_ex_reg_t          id_ex_reg   // ID/EX pipeline register output
);

    // =========================================================================
    // Instruction Field Extraction
    // =========================================================================

    /** Full instruction word */
    logic [ILEN-1:0] instr;
    assign instr = if_id_reg.instruction;

    /** Opcode field [6:0] */
    opcode_t opcode;
    assign opcode = opcode_t'(instr[6:0]);

    /** Destination register address [11:7] */
    logic [REG_ADDR_W-1:0] rd;
    assign rd = instr[11:7];

    /** Funct3 field [14:12] */
    logic [2:0] funct3;
    assign funct3 = instr[14:12];

    /** Source register 1 address [19:15] */
    logic [REG_ADDR_W-1:0] rs1;
    assign rs1 = instr[19:15];

    /** Source register 2 address [24:20] */
    logic [REG_ADDR_W-1:0] rs2;
    assign rs2 = instr[24:20];

    /** Funct7 field [31:25] */
    logic [6:0] funct7;
    assign funct7 = instr[31:25];

    // =========================================================================
    // Register Address Outputs
    // =========================================================================
    assign rs1_addr = rs1;
    assign rs2_addr = rs2;

    // =========================================================================
    // Immediate Generation Unit
    // =========================================================================
    // Generates sign-extended immediate values based on instruction type.
    // =========================================================================

    /** Decoded immediate type */
    imm_type_t imm_type;

    /** Generated immediate value */
    logic [XLEN-1:0] immediate;

    // Determine immediate type from opcode
    always_comb begin
        case (opcode)
            OP_LUI,
            OP_AUIPC:    imm_type = IMM_U;
            OP_JAL:      imm_type = IMM_J;
            OP_JALR,
            OP_LOAD,
            OP_OP_IMM,
            OP_FENCE,
            OP_SYSTEM:   imm_type = IMM_I;
            OP_BRANCH:   imm_type = IMM_B;
            OP_STORE:    imm_type = IMM_S;
            default:     imm_type = IMM_I;
        endcase
    end

    // Generate immediate value based on type
    always_comb begin
        case (imm_type)
            // I-type: instr[31:20] sign-extended
            IMM_I: begin
                immediate = {{20{instr[31]}}, instr[31:20]};
            end
            // S-type: {instr[31:25], instr[11:7]} sign-extended
            IMM_S: begin
                immediate = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end
            // B-type: {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0} sign-extended
            IMM_B: begin
                immediate = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            end
            // U-type: {instr[31:12], 12'b0}
            IMM_U: begin
                immediate = {instr[31:12], 12'b0};
            end
            // J-type: {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0} sign-extended
            IMM_J: begin
                immediate = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            end
            default: begin
                immediate = 32'b0;
            end
        endcase
    end

    // =========================================================================
    // Control Signal Decode Logic
    // =========================================================================

    /** Decoded control signals (combinational) */
    ctrl_signals_t ctrl;

    always_comb begin
        // Default: all signals inactive / safe defaults
        ctrl.alu_op        = ALU_ADD;
        ctrl.alu_src_a     = 1'b0;    // rs1
        ctrl.alu_src_b     = 1'b0;    // rs2
        ctrl.mext_en       = 1'b0;
        ctrl.mext_op       = MEXT_MUL;
        ctrl.reg_write     = 1'b0;
        ctrl.wb_sel        = 2'b00;   // ALU result
        ctrl.mem_read      = 1'b0;
        ctrl.mem_write     = 1'b0;
        ctrl.mem_funct3    = 3'b000;
        ctrl.branch        = 1'b0;
        ctrl.jal           = 1'b0;
        ctrl.jalr          = 1'b0;
        ctrl.branch_funct3 = 3'b000;
        ctrl.csr_en        = 1'b0;
        ctrl.csr_op        = 2'b00;
        ctrl.csr_imm       = 1'b0;
        ctrl.ecall         = 1'b0;
        ctrl.ebreak        = 1'b0;
        ctrl.mret          = 1'b0;
        ctrl.fence         = 1'b0;
        ctrl.illegal_instr = 1'b0;

        case (opcode)
            // -----------------------------------------------------------------
            // LUI - Load Upper Immediate
            // -----------------------------------------------------------------
            OP_LUI: begin
                ctrl.alu_op    = ALU_LUI;
                ctrl.alu_src_b = 1'b1;    // immediate
                ctrl.reg_write = 1'b1;
                ctrl.wb_sel    = 2'b00;   // ALU result
            end

            // -----------------------------------------------------------------
            // AUIPC - Add Upper Immediate to PC
            // -----------------------------------------------------------------
            OP_AUIPC: begin
                ctrl.alu_op    = ALU_AUIPC;
                ctrl.alu_src_a = 1'b1;    // PC
                ctrl.alu_src_b = 1'b1;    // immediate
                ctrl.reg_write = 1'b1;
                ctrl.wb_sel    = 2'b00;   // ALU result
            end

            // -----------------------------------------------------------------
            // JAL - Jump and Link
            // -----------------------------------------------------------------
            OP_JAL: begin
                ctrl.jal       = 1'b1;
                ctrl.reg_write = 1'b1;
                ctrl.wb_sel    = 2'b10;   // PC + 4
            end

            // -----------------------------------------------------------------
            // JALR - Jump and Link Register
            // -----------------------------------------------------------------
            OP_JALR: begin
                ctrl.jalr      = 1'b1;
                ctrl.alu_src_b = 1'b1;    // immediate
                ctrl.reg_write = 1'b1;
                ctrl.wb_sel    = 2'b10;   // PC + 4
            end

            // -----------------------------------------------------------------
            // BRANCH - Conditional Branch
            // -----------------------------------------------------------------
            OP_BRANCH: begin
                ctrl.branch        = 1'b1;
                ctrl.branch_funct3 = funct3;
            end

            // -----------------------------------------------------------------
            // LOAD - Memory Load
            // -----------------------------------------------------------------
            OP_LOAD: begin
                ctrl.alu_op    = ALU_ADD;
                ctrl.alu_src_b = 1'b1;    // immediate (offset)
                ctrl.mem_read  = 1'b1;
                ctrl.mem_funct3= funct3;
                ctrl.reg_write = 1'b1;
                ctrl.wb_sel    = 2'b01;   // Memory data
            end

            // -----------------------------------------------------------------
            // STORE - Memory Store
            // -----------------------------------------------------------------
            OP_STORE: begin
                ctrl.alu_op    = ALU_ADD;
                ctrl.alu_src_b = 1'b1;    // immediate (offset)
                ctrl.mem_write = 1'b1;
                ctrl.mem_funct3= funct3;
            end

            // -----------------------------------------------------------------
            // OP_IMM - Register-Immediate ALU Operations
            // -----------------------------------------------------------------
            OP_OP_IMM: begin
                ctrl.alu_src_b = 1'b1;    // immediate
                ctrl.reg_write = 1'b1;
                ctrl.wb_sel    = 2'b00;   // ALU result

                case (funct3)
                    3'b000: ctrl.alu_op = ALU_ADD;   // ADDI
                    3'b001: ctrl.alu_op = ALU_SLL;   // SLLI
                    3'b010: ctrl.alu_op = ALU_SLT;   // SLTI
                    3'b011: ctrl.alu_op = ALU_SLTU;  // SLTIU
                    3'b100: ctrl.alu_op = ALU_XOR;   // XORI
                    3'b101: begin
                        // SRLI (funct7[5]==0) or SRAI (funct7[5]==1)
                        ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    end
                    3'b110: ctrl.alu_op = ALU_OR;    // ORI
                    3'b111: ctrl.alu_op = ALU_AND;   // ANDI
                    default: ctrl.alu_op = ALU_ADD;
                endcase
            end

            // -----------------------------------------------------------------
            // OP - Register-Register ALU Operations (incl. M-extension)
            // -----------------------------------------------------------------
            OP_OP: begin
                ctrl.reg_write = 1'b1;
                ctrl.wb_sel    = 2'b00;   // ALU result

                if (funct7 == 7'b0000001) begin
                    // ---------------------------------------------------------
                    // M-extension: MUL/DIV operations
                    // ---------------------------------------------------------
                    ctrl.mext_en = 1'b1;
                    ctrl.mext_op = mext_op_t'(funct3);
                end else begin
                    // ---------------------------------------------------------
                    // Base integer ALU operations
                    // ---------------------------------------------------------
                    case (funct3)
                        3'b000: ctrl.alu_op = funct7[5] ? ALU_SUB : ALU_ADD; // ADD/SUB
                        3'b001: ctrl.alu_op = ALU_SLL;   // SLL
                        3'b010: ctrl.alu_op = ALU_SLT;   // SLT
                        3'b011: ctrl.alu_op = ALU_SLTU;  // SLTU
                        3'b100: ctrl.alu_op = ALU_XOR;   // XOR
                        3'b101: ctrl.alu_op = funct7[5] ? ALU_SRA : ALU_SRL; // SRL/SRA
                        3'b110: ctrl.alu_op = ALU_OR;    // OR
                        3'b111: ctrl.alu_op = ALU_AND;   // AND
                        default: ctrl.alu_op = ALU_ADD;
                    endcase
                end
            end

            // -----------------------------------------------------------------
            // FENCE - Memory Ordering
            // -----------------------------------------------------------------
            OP_FENCE: begin
                ctrl.fence = 1'b1;
            end

            // -----------------------------------------------------------------
            // SYSTEM - ECALL, EBREAK, MRET, CSR
            // -----------------------------------------------------------------
            OP_SYSTEM: begin
                if (funct3 == 3'b000) begin
                    // ECALL / EBREAK / MRET
                    if (funct7 == 7'b0011000 && rs2 == 5'b00010) begin
                        // MRET: funct7==0011000, rs2==00010
                        ctrl.mret = 1'b1;
                    end else if (instr[20] == 1'b0) begin
                        // ECALL: instruction[20] == 0
                        ctrl.ecall = 1'b1;
                    end else begin
                        // EBREAK: instruction[20] == 1
                        ctrl.ebreak = 1'b1;
                    end
                end else begin
                    // CSR instructions
                    ctrl.csr_en = 1'b1;
                    ctrl.reg_write = 1'b1;
                    ctrl.wb_sel = 2'b11;  // CSR read data

                    case (funct3)
                        3'b001: begin  // CSRRW
                            ctrl.csr_op  = 2'b01;
                            ctrl.csr_imm = 1'b0;
                        end
                        3'b010: begin  // CSRRS
                            ctrl.csr_op  = 2'b10;
                            ctrl.csr_imm = 1'b0;
                        end
                        3'b011: begin  // CSRRC
                            ctrl.csr_op  = 2'b11;
                            ctrl.csr_imm = 1'b0;
                        end
                        3'b101: begin  // CSRRWI
                            ctrl.csr_op  = 2'b01;
                            ctrl.csr_imm = 1'b1;
                        end
                        3'b110: begin  // CSRRSI
                            ctrl.csr_op  = 2'b10;
                            ctrl.csr_imm = 1'b1;
                        end
                        3'b111: begin  // CSRRCI
                            ctrl.csr_op  = 2'b11;
                            ctrl.csr_imm = 1'b1;
                        end
                        default: begin
                            ctrl.illegal_instr = 1'b1;
                        end
                    endcase
                end
            end

            // -----------------------------------------------------------------
            // Unknown opcode → Illegal instruction
            // -----------------------------------------------------------------
            default: begin
                ctrl.illegal_instr = 1'b1;
            end
        endcase
    end

    // =========================================================================
    // CSR Address Extraction
    // =========================================================================
    /** CSR address from instruction[31:20] */
    logic [11:0] csr_addr;
    assign csr_addr = instr[31:20];

    // =========================================================================
    // ID/EX Pipeline Register
    // =========================================================================
    // Captures decoded control signals, register data, immediate, and addresses.
    // Flush inserts a bubble (NOP) by invalidating the register and clearing
    // all write-enable signals to prevent side effects.
    // Stall holds the current values.
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_reg.pc        <= '0;
            id_ex_reg.rs1_data  <= '0;
            id_ex_reg.rs2_data  <= '0;
            id_ex_reg.immediate <= '0;
            id_ex_reg.rs1_addr  <= '0;
            id_ex_reg.rs2_addr  <= '0;
            id_ex_reg.rd_addr   <= '0;
            id_ex_reg.csr_addr  <= '0;
            id_ex_reg.ctrl      <= '0;
            id_ex_reg.valid     <= 1'b0;
        end else if (flush) begin
            // Flush: insert bubble - clear all control signals
            id_ex_reg.pc        <= '0;
            id_ex_reg.rs1_data  <= '0;
            id_ex_reg.rs2_data  <= '0;
            id_ex_reg.immediate <= '0;
            id_ex_reg.rs1_addr  <= '0;
            id_ex_reg.rs2_addr  <= '0;
            id_ex_reg.rd_addr   <= '0;
            id_ex_reg.csr_addr  <= '0;
            id_ex_reg.ctrl      <= '0;
            id_ex_reg.valid     <= 1'b0;
        end else if (!stall) begin
            // Normal operation: latch decoded values
            id_ex_reg.pc        <= if_id_reg.pc;
            id_ex_reg.rs1_data  <= rs1_data;
            id_ex_reg.rs2_data  <= rs2_data;
            id_ex_reg.immediate <= immediate;
            id_ex_reg.rs1_addr  <= rs1;
            id_ex_reg.rs2_addr  <= rs2;
            id_ex_reg.rd_addr   <= rd;
            id_ex_reg.csr_addr  <= csr_addr;
            id_ex_reg.ctrl      <= ctrl;
            id_ex_reg.valid     <= if_id_reg.valid;
        end
        // When stalled: hold current values (implicit)
    end

endmodule : decode_stage
