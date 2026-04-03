// =============================================================================
// VSync - Arithmetic Logic Unit (ALU)
// RISC-V RV32IM Processor
//
// File: alu.sv
// Description: Combinational ALU supporting all RV32I arithmetic/logic ops
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

/**
 * @brief Arithmetic Logic Unit for RV32I base integer instructions
 *
 * Supports ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, LUI, AUIPC.
 * All operations are purely combinational (no clock needed).
 * SRA uses $signed() for arithmetic right shift.
 * SLT/SLTU produce 0 or 1 comparison result.
 */
module alu (
    // Operand inputs
    input  logic [XLEN-1:0] operand_a,   // Source operand A (rs1 or PC)
    input  logic [XLEN-1:0] operand_b,   // Source operand B (rs2 or immediate)
    input  alu_op_t         alu_op,       // ALU operation selector

    // Result outputs
    output logic [XLEN-1:0] result,       // ALU computation result
    output logic             zero          // Zero flag (result == 0)
);

    // =========================================================================
    // Shift amount (lower 5 bits of operand_b for RV32)
    // =========================================================================
    logic [4:0] shamt;
    assign shamt = operand_b[4:0];

    // =========================================================================
    // Main ALU operation select (combinational)
    // =========================================================================
    always_comb begin
        case (alu_op)
            ALU_ADD:   result = operand_a + operand_b;
            ALU_SUB:   result = operand_a - operand_b;
            ALU_SLL:   result = operand_a << shamt;
            ALU_SLT:   result = {31'b0, $signed(operand_a) < $signed(operand_b)};
            ALU_SLTU:  result = {31'b0, operand_a < operand_b};
            ALU_XOR:   result = operand_a ^ operand_b;
            ALU_SRL:   result = operand_a >> shamt;
            ALU_SRA:   result = $unsigned($signed(operand_a) >>> shamt);
            ALU_OR:    result = operand_a | operand_b;
            ALU_AND:   result = operand_a & operand_b;
            ALU_LUI:   result = operand_b;                   // Pass B (upper immediate)
            ALU_AUIPC: result = operand_a + operand_b;       // PC + immediate
            default:   result = '0;
        endcase
    end

    // =========================================================================
    // Zero flag generation
    // =========================================================================
    assign zero = (result == '0);

endmodule : alu
