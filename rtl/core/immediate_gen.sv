// =============================================================================
// VSync - Immediate Generator
// RISC-V RV32IM Processor
//
// File: immediate_gen.sv
// Description: Generates sign-extended 32-bit immediate values for all
//              RISC-V immediate formats (I, S, B, U, J).
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module immediate_gen (
    input  logic [ILEN-1:0]  instruction,
    input  imm_type_t        imm_type,
    output logic [XLEN-1:0]  immediate
);

    // =========================================================================
    // Combinational immediate generation
    // =========================================================================
    always_comb begin
        case (imm_type)
            // -----------------------------------------------------------------
            // I-type: inst[31:20] sign-extended
            // Used by: ADDI, SLTI, ANDI, ORI, XORI, LW, LH, LB, JALR, etc.
            // -----------------------------------------------------------------
            IMM_I: begin
                immediate = {{20{instruction[31]}}, instruction[31:20]};
            end

            // -----------------------------------------------------------------
            // S-type: {inst[31:25], inst[11:7]} sign-extended
            // Used by: SW, SH, SB
            // -----------------------------------------------------------------
            IMM_S: begin
                immediate = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            end

            // -----------------------------------------------------------------
            // B-type: {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0} sign-extended
            // Used by: BEQ, BNE, BLT, BGE, BLTU, BGEU
            // -----------------------------------------------------------------
            IMM_B: begin
                immediate = {{19{instruction[31]}}, instruction[31], instruction[7],
                             instruction[30:25], instruction[11:8], 1'b0};
            end

            // -----------------------------------------------------------------
            // U-type: {inst[31:12], 12'b0}
            // Used by: LUI, AUIPC
            // -----------------------------------------------------------------
            IMM_U: begin
                immediate = {instruction[31:12], 12'b0};
            end

            // -----------------------------------------------------------------
            // J-type: {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0} sign-extended
            // Used by: JAL
            // -----------------------------------------------------------------
            IMM_J: begin
                immediate = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                             instruction[20], instruction[30:21], 1'b0};
            end

            default: begin
                immediate = '0;
            end
        endcase
    end

endmodule : immediate_gen
