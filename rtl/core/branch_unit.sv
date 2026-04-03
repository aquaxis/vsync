// =============================================================================
// VSync - Branch Unit
// RISC-V RV32IM Processor
//
// File: branch_unit.sv
// Description: Branch condition evaluation and target address calculation
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

/**
 * @brief Branch condition evaluator and target address calculator
 *
 * Evaluates 6 branch conditions: BEQ, BNE, BLT, BGE, BLTU, BGEU.
 * Computes branch/jump target addresses:
 *   - Branch: PC + immediate (B-type)
 *   - JAL:    PC + immediate (J-type)
 *   - JALR:   (rs1 + immediate) & ~1
 * All logic is purely combinational.
 */
module branch_unit (
    // Data inputs
    input  logic [XLEN-1:0] rs1_data,        // Source register 1 data
    input  logic [XLEN-1:0] rs2_data,        // Source register 2 data
    input  logic [XLEN-1:0] pc,              // Current program counter
    input  logic [XLEN-1:0] immediate,       // Sign-extended immediate value

    // Control inputs
    input  logic [2:0]      branch_funct3,   // Branch condition type (funct3)
    input  logic             is_branch,       // Instruction is a branch
    input  logic             is_jal,          // Instruction is JAL
    input  logic             is_jalr,         // Instruction is JALR

    // Outputs
    output logic             branch_taken,    // Branch/jump is taken
    output logic [XLEN-1:0]  branch_target    // Computed target address
);

    // =========================================================================
    // Branch condition evaluation (combinational)
    // =========================================================================
    logic cond_result;

    always_comb begin
        cond_result = 1'b0;

        if (is_branch) begin
            case (branch_funct3)
                F3_BEQ:  cond_result = (rs1_data == rs2_data);
                F3_BNE:  cond_result = (rs1_data != rs2_data);
                F3_BLT:  cond_result = ($signed(rs1_data) < $signed(rs2_data));
                F3_BGE:  cond_result = ($signed(rs1_data) >= $signed(rs2_data));
                F3_BLTU: cond_result = (rs1_data < rs2_data);
                F3_BGEU: cond_result = (rs1_data >= rs2_data);
                default: cond_result = 1'b0;
            endcase
        end
    end

    // =========================================================================
    // Branch taken decision
    // =========================================================================
    // JAL/JALR are unconditional jumps, always taken
    assign branch_taken = (is_branch && cond_result) || is_jal || is_jalr;

    // =========================================================================
    // Target address calculation (combinational)
    // =========================================================================
    always_comb begin
        if (is_jalr) begin
            // JALR: (rs1 + immediate) with bit[0] cleared
            branch_target = (rs1_data + immediate) & {{(XLEN-1){1'b1}}, 1'b0};
        end else begin
            // Branch and JAL: PC + immediate
            branch_target = pc + immediate;
        end
    end

endmodule : branch_unit
