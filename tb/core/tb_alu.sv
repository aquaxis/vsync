// =============================================================================
// VSync - ALU Unit Testbench
// =============================================================================
// Comprehensive testbench for the combinational ALU module.
// Tests all 12 ALU operations with boundary values and zero flag verification.
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_alu;

    import test_utils::*;
    import vsync_pkg::*;

    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic [XLEN-1:0] operand_a;
    logic [XLEN-1:0] operand_b;
    alu_op_t         alu_op;
    logic [XLEN-1:0] result;
    logic             zero;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    alu u_alu (
        .operand_a (operand_a),
        .operand_b (operand_b),
        .alu_op    (alu_op),
        .result    (result),
        .zero      (zero)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_alu.vcd");
        $dumpvars(0, tb_alu);
    end

    // =========================================================================
    // Helper task: apply inputs and wait for combinational propagation
    // =========================================================================
    task automatic apply(
        input logic [XLEN-1:0] a,
        input logic [XLEN-1:0] b,
        input alu_op_t         op
    );
        operand_a = a;
        operand_b = b;
        alu_op    = op;
        #1;
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        test_suite_begin("ALU Unit Tests");

        // =====================================================================
        // ALU_ADD Tests
        // =====================================================================
        test_begin("ALU_ADD: basic addition");
        apply(32'd10, 32'd20, ALU_ADD);
        check_eq(result, 32'd30, "10 + 20 = 30");

        test_begin("ALU_ADD: add with zero");
        apply(32'd42, 32'd0, ALU_ADD);
        check_eq(result, 32'd42, "42 + 0 = 42");

        test_begin("ALU_ADD: overflow wraps around");
        apply(32'hFFFFFFFF, 32'd1, ALU_ADD);
        check_eq(result, 32'h00000000, "0xFFFFFFFF + 1 = 0x00000000");
        check(zero === 1'b1, "zero flag set on overflow to 0");

        test_begin("ALU_ADD: large values");
        apply(32'h80000000, 32'h80000000, ALU_ADD);
        check_eq(result, 32'h00000000, "0x80000000 + 0x80000000 = 0x00000000");

        test_begin("ALU_ADD: 0x7FFFFFFF + 1");
        apply(32'h7FFFFFFF, 32'd1, ALU_ADD);
        check_eq(result, 32'h80000000, "0x7FFFFFFF + 1 = 0x80000000");

        // =====================================================================
        // ALU_SUB Tests
        // =====================================================================
        test_begin("ALU_SUB: basic subtraction");
        apply(32'd30, 32'd10, ALU_SUB);
        check_eq(result, 32'd20, "30 - 10 = 20");

        test_begin("ALU_SUB: result is zero");
        apply(32'd100, 32'd100, ALU_SUB);
        check_eq(result, 32'd0, "100 - 100 = 0");
        check(zero === 1'b1, "zero flag set when a == b");

        test_begin("ALU_SUB: underflow wraps around");
        apply(32'd0, 32'd1, ALU_SUB);
        check_eq(result, 32'hFFFFFFFF, "0 - 1 = 0xFFFFFFFF");

        test_begin("ALU_SUB: large minus small");
        apply(32'hFFFFFFFF, 32'h7FFFFFFF, ALU_SUB);
        check_eq(result, 32'h80000000, "0xFFFFFFFF - 0x7FFFFFFF = 0x80000000");

        // =====================================================================
        // ALU_SLL Tests
        // =====================================================================
        test_begin("ALU_SLL: shift left by 0");
        apply(32'hDEADBEEF, 32'd0, ALU_SLL);
        check_eq(result, 32'hDEADBEEF, "shift by 0 is identity");

        test_begin("ALU_SLL: shift left by 1");
        apply(32'd1, 32'd1, ALU_SLL);
        check_eq(result, 32'd2, "1 << 1 = 2");

        test_begin("ALU_SLL: shift left by 16");
        apply(32'h0000FFFF, 32'd16, ALU_SLL);
        check_eq(result, 32'hFFFF0000, "0x0000FFFF << 16 = 0xFFFF0000");

        test_begin("ALU_SLL: shift left by 31");
        apply(32'd1, 32'd31, ALU_SLL);
        check_eq(result, 32'h80000000, "1 << 31 = 0x80000000");

        test_begin("ALU_SLL: only lower 5 bits of shamt used");
        apply(32'd1, 32'h00000021, ALU_SLL);  // shamt = 1 (bit[4:0] of 0x21 = 1)
        check_eq(result, 32'd2, "shamt uses only bits [4:0], 0x21 -> shift by 1");

        // =====================================================================
        // ALU_SLT Tests (signed less-than)
        // =====================================================================
        test_begin("ALU_SLT: positive < positive (true)");
        apply(32'd5, 32'd10, ALU_SLT);
        check_eq(result, 32'd1, "5 < 10 = 1 (signed)");

        test_begin("ALU_SLT: positive < positive (false)");
        apply(32'd10, 32'd5, ALU_SLT);
        check_eq(result, 32'd0, "10 < 5 = 0 (signed)");

        test_begin("ALU_SLT: equal values");
        apply(32'd7, 32'd7, ALU_SLT);
        check_eq(result, 32'd0, "7 < 7 = 0 (signed, equal)");

        test_begin("ALU_SLT: negative < positive");
        apply(32'hFFFFFFFF, 32'd1, ALU_SLT);  // -1 < 1
        check_eq(result, 32'd1, "-1 < 1 = 1 (signed)");

        test_begin("ALU_SLT: positive < negative (false)");
        apply(32'd1, 32'hFFFFFFFF, ALU_SLT);  // 1 < -1
        check_eq(result, 32'd0, "1 < -1 = 0 (signed)");

        test_begin("ALU_SLT: most negative < most positive");
        apply(32'h80000000, 32'h7FFFFFFF, ALU_SLT);  // INT_MIN < INT_MAX
        check_eq(result, 32'd1, "INT_MIN < INT_MAX = 1 (signed)");

        // =====================================================================
        // ALU_SLTU Tests (unsigned less-than)
        // =====================================================================
        test_begin("ALU_SLTU: small < large (true)");
        apply(32'd5, 32'd10, ALU_SLTU);
        check_eq(result, 32'd1, "5 < 10 = 1 (unsigned)");

        test_begin("ALU_SLTU: large < small (false)");
        apply(32'd10, 32'd5, ALU_SLTU);
        check_eq(result, 32'd0, "10 < 5 = 0 (unsigned)");

        test_begin("ALU_SLTU: 0 < 0xFFFFFFFF (true)");
        apply(32'd0, 32'hFFFFFFFF, ALU_SLTU);
        check_eq(result, 32'd1, "0 < 0xFFFFFFFF = 1 (unsigned)");

        test_begin("ALU_SLTU: 0xFFFFFFFF < 0 (false)");
        apply(32'hFFFFFFFF, 32'd0, ALU_SLTU);
        check_eq(result, 32'd0, "0xFFFFFFFF < 0 = 0 (unsigned)");

        test_begin("ALU_SLTU: equal values");
        apply(32'hABCD1234, 32'hABCD1234, ALU_SLTU);
        check_eq(result, 32'd0, "equal values -> 0 (unsigned)");

        // =====================================================================
        // ALU_XOR Tests
        // =====================================================================
        test_begin("ALU_XOR: XOR with all ones (bitwise NOT)");
        apply(32'hA5A5A5A5, 32'hFFFFFFFF, ALU_XOR);
        check_eq(result, 32'h5A5A5A5A, "0xA5A5A5A5 ^ 0xFFFFFFFF = 0x5A5A5A5A");

        test_begin("ALU_XOR: XOR with same value (zero result)");
        apply(32'hDEADBEEF, 32'hDEADBEEF, ALU_XOR);
        check_eq(result, 32'd0, "x ^ x = 0");
        check(zero === 1'b1, "zero flag set on x ^ x");

        test_begin("ALU_XOR: XOR with zero (identity)");
        apply(32'h12345678, 32'd0, ALU_XOR);
        check_eq(result, 32'h12345678, "x ^ 0 = x");

        test_begin("ALU_XOR: different values");
        apply(32'hFF00FF00, 32'h0F0F0F0F, ALU_XOR);
        check_eq(result, 32'hF00FF00F, "0xFF00FF00 ^ 0x0F0F0F0F = 0xF00FF00F");

        // =====================================================================
        // ALU_SRL Tests (logical right shift)
        // =====================================================================
        test_begin("ALU_SRL: shift right by 0");
        apply(32'hDEADBEEF, 32'd0, ALU_SRL);
        check_eq(result, 32'hDEADBEEF, "shift by 0 is identity");

        test_begin("ALU_SRL: shift right by 1");
        apply(32'h80000000, 32'd1, ALU_SRL);
        check_eq(result, 32'h40000000, "0x80000000 >> 1 = 0x40000000 (logical)");

        test_begin("ALU_SRL: shift right by 16");
        apply(32'hFFFF0000, 32'd16, ALU_SRL);
        check_eq(result, 32'h0000FFFF, "0xFFFF0000 >> 16 = 0x0000FFFF");

        test_begin("ALU_SRL: shift right by 31");
        apply(32'h80000000, 32'd31, ALU_SRL);
        check_eq(result, 32'd1, "0x80000000 >> 31 = 1 (logical)");

        test_begin("ALU_SRL: shift all bits out");
        apply(32'h7FFFFFFF, 32'd31, ALU_SRL);
        check_eq(result, 32'd0, "0x7FFFFFFF >> 31 = 0");
        check(zero === 1'b1, "zero flag set when shifted out");

        // =====================================================================
        // ALU_SRA Tests (arithmetic right shift, preserves sign bit)
        // =====================================================================
        test_begin("ALU_SRA: positive value shift right by 1");
        apply(32'h40000000, 32'd1, ALU_SRA);
        check_eq(result, 32'h20000000, "0x40000000 >>> 1 = 0x20000000");

        test_begin("ALU_SRA: negative value shift right by 1");
        apply(32'h80000000, 32'd1, ALU_SRA);
        check_eq(result, 32'hC0000000, "0x80000000 >>> 1 = 0xC0000000 (sign extended)");

        test_begin("ALU_SRA: negative value shift right by 4");
        apply(32'hF0000000, 32'd4, ALU_SRA);
        check_eq(result, 32'hFF000000, "0xF0000000 >>> 4 = 0xFF000000 (sign extended)");

        test_begin("ALU_SRA: negative value shift right by 31");
        apply(32'h80000000, 32'd31, ALU_SRA);
        check_eq(result, 32'hFFFFFFFF, "0x80000000 >>> 31 = 0xFFFFFFFF (all sign bits)");

        test_begin("ALU_SRA: shift right by 0");
        apply(32'hDEADBEEF, 32'd0, ALU_SRA);
        check_eq(result, 32'hDEADBEEF, "shift by 0 is identity");

        test_begin("ALU_SRA: all ones shift right");
        apply(32'hFFFFFFFF, 32'd16, ALU_SRA);
        check_eq(result, 32'hFFFFFFFF, "0xFFFFFFFF >>> 16 = 0xFFFFFFFF (all ones stay)");

        // =====================================================================
        // ALU_OR Tests
        // =====================================================================
        test_begin("ALU_OR: basic OR");
        apply(32'hF0F0F0F0, 32'h0F0F0F0F, ALU_OR);
        check_eq(result, 32'hFFFFFFFF, "0xF0F0F0F0 | 0x0F0F0F0F = 0xFFFFFFFF");

        test_begin("ALU_OR: OR with zero (identity)");
        apply(32'hABCD1234, 32'd0, ALU_OR);
        check_eq(result, 32'hABCD1234, "x | 0 = x");

        test_begin("ALU_OR: OR with all ones");
        apply(32'd0, 32'hFFFFFFFF, ALU_OR);
        check_eq(result, 32'hFFFFFFFF, "0 | 0xFFFFFFFF = 0xFFFFFFFF");

        test_begin("ALU_OR: OR of two zero values");
        apply(32'd0, 32'd0, ALU_OR);
        check_eq(result, 32'd0, "0 | 0 = 0");
        check(zero === 1'b1, "zero flag set on 0 | 0");

        // =====================================================================
        // ALU_AND Tests
        // =====================================================================
        test_begin("ALU_AND: basic AND");
        apply(32'hF0F0F0F0, 32'h0F0F0F0F, ALU_AND);
        check_eq(result, 32'h00000000, "0xF0F0F0F0 & 0x0F0F0F0F = 0x00000000");
        check(zero === 1'b1, "zero flag set on disjoint AND");

        test_begin("ALU_AND: AND with all ones (identity)");
        apply(32'hDEADBEEF, 32'hFFFFFFFF, ALU_AND);
        check_eq(result, 32'hDEADBEEF, "x & 0xFFFFFFFF = x");

        test_begin("ALU_AND: AND with zero");
        apply(32'hFFFFFFFF, 32'd0, ALU_AND);
        check_eq(result, 32'd0, "x & 0 = 0");

        test_begin("ALU_AND: partial overlap");
        apply(32'hFF00FF00, 32'h0FF00FF0, ALU_AND);
        check_eq(result, 32'h0F000F00, "0xFF00FF00 & 0x0FF00FF0 = 0x0F000F00");

        // =====================================================================
        // ALU_LUI Tests (pass operand_b)
        // =====================================================================
        test_begin("ALU_LUI: pass through operand_b");
        apply(32'hDEADBEEF, 32'h12345000, ALU_LUI);
        check_eq(result, 32'h12345000, "LUI passes operand_b = 0x12345000");

        test_begin("ALU_LUI: pass zero");
        apply(32'hFFFFFFFF, 32'd0, ALU_LUI);
        check_eq(result, 32'd0, "LUI passes operand_b = 0");
        check(zero === 1'b1, "zero flag set when LUI result is 0");

        test_begin("ALU_LUI: pass 0xFFFFF000 (upper immediate)");
        apply(32'd0, 32'hFFFFF000, ALU_LUI);
        check_eq(result, 32'hFFFFF000, "LUI passes operand_b = 0xFFFFF000");

        test_begin("ALU_LUI: operand_a is ignored");
        apply(32'h00000000, 32'hABCDE000, ALU_LUI);
        check_eq(result, 32'hABCDE000, "LUI ignores operand_a");
        apply(32'hFFFFFFFF, 32'hABCDE000, ALU_LUI);
        check_eq(result, 32'hABCDE000, "LUI ignores operand_a (changed a, same result)");

        // =====================================================================
        // ALU_AUIPC Tests (operand_a + operand_b = PC + imm)
        // =====================================================================
        test_begin("ALU_AUIPC: PC + immediate");
        apply(32'h0000_1000, 32'h0010_0000, ALU_AUIPC);
        check_eq(result, 32'h0010_1000, "PC(0x1000) + imm(0x100000) = 0x101000");

        test_begin("ALU_AUIPC: PC = 0");
        apply(32'd0, 32'h12345000, ALU_AUIPC);
        check_eq(result, 32'h12345000, "PC(0) + imm = imm");

        test_begin("ALU_AUIPC: large PC + large immediate");
        apply(32'h7FFFFFFF, 32'h80000001, ALU_AUIPC);
        check_eq(result, 32'h00000000, "0x7FFFFFFF + 0x80000001 = 0x00000000 (wraps)");
        check(zero === 1'b1, "zero flag set on AUIPC wrap to 0");

        // =====================================================================
        // Zero Flag Tests
        // =====================================================================
        test_begin("Zero flag: non-zero result");
        apply(32'd1, 32'd0, ALU_ADD);
        check(zero === 1'b0, "zero flag clear when result = 1");

        test_begin("Zero flag: zero result from ADD");
        apply(32'd0, 32'd0, ALU_ADD);
        check_eq(result, 32'd0, "0 + 0 = 0");
        check(zero === 1'b1, "zero flag set when result = 0 (ADD)");

        test_begin("Zero flag: zero result from SUB");
        apply(32'hCAFEBABE, 32'hCAFEBABE, ALU_SUB);
        check_eq(result, 32'd0, "x - x = 0");
        check(zero === 1'b1, "zero flag set when result = 0 (SUB)");

        test_begin("Zero flag: zero result from AND");
        apply(32'hAAAAAAAA, 32'h55555555, ALU_AND);
        check_eq(result, 32'd0, "0xAAAAAAAA & 0x55555555 = 0");
        check(zero === 1'b1, "zero flag set when result = 0 (AND)");

        test_begin("Zero flag: non-zero from SLT");
        apply(32'd0, 32'd1, ALU_SLT);
        check_eq(result, 32'd1, "0 < 1 = 1 (signed)");
        check(zero === 1'b0, "zero flag clear when SLT result = 1");

        test_begin("Zero flag: zero from SLT");
        apply(32'd1, 32'd0, ALU_SLT);
        check_eq(result, 32'd0, "1 < 0 = 0 (signed)");
        check(zero === 1'b1, "zero flag set when SLT result = 0");

        // =====================================================================
        // Boundary Value Tests
        // =====================================================================
        test_begin("Boundary: 0x00000000 + 0x00000000");
        apply(32'h00000000, 32'h00000000, ALU_ADD);
        check_eq(result, 32'h00000000, "0 + 0 = 0");

        test_begin("Boundary: 0xFFFFFFFF + 0xFFFFFFFF");
        apply(32'hFFFFFFFF, 32'hFFFFFFFF, ALU_ADD);
        check_eq(result, 32'hFFFFFFFE, "0xFFFFFFFF + 0xFFFFFFFF = 0xFFFFFFFE");

        test_begin("Boundary: 0x80000000 - 0x00000001");
        apply(32'h80000000, 32'h00000001, ALU_SUB);
        check_eq(result, 32'h7FFFFFFF, "0x80000000 - 1 = 0x7FFFFFFF");

        test_begin("Boundary: 0x7FFFFFFF + 0x7FFFFFFF");
        apply(32'h7FFFFFFF, 32'h7FFFFFFF, ALU_ADD);
        check_eq(result, 32'hFFFFFFFE, "0x7FFFFFFF + 0x7FFFFFFF = 0xFFFFFFFE");

        test_begin("Boundary: SRL 0xFFFFFFFF by 31");
        apply(32'hFFFFFFFF, 32'd31, ALU_SRL);
        check_eq(result, 32'd1, "0xFFFFFFFF >> 31 = 1 (logical)");

        test_begin("Boundary: SRA 0xFFFFFFFF by 31");
        apply(32'hFFFFFFFF, 32'd31, ALU_SRA);
        check_eq(result, 32'hFFFFFFFF, "0xFFFFFFFF >>> 31 = 0xFFFFFFFF (arithmetic)");

        test_begin("Boundary: SLL 0x80000000 by 1");
        apply(32'h80000000, 32'd1, ALU_SLL);
        check_eq(result, 32'h00000000, "0x80000000 << 1 = 0 (MSB shifted out)");
        check(zero === 1'b1, "zero flag set when MSB shifted out");

        test_begin("Boundary: XOR 0x80000000 ^ 0x7FFFFFFF");
        apply(32'h80000000, 32'h7FFFFFFF, ALU_XOR);
        check_eq(result, 32'hFFFFFFFF, "0x80000000 ^ 0x7FFFFFFF = 0xFFFFFFFF");

        test_begin("Boundary: OR 0x80000000 | 0x7FFFFFFF");
        apply(32'h80000000, 32'h7FFFFFFF, ALU_OR);
        check_eq(result, 32'hFFFFFFFF, "0x80000000 | 0x7FFFFFFF = 0xFFFFFFFF");

        test_begin("Boundary: AND 0x80000000 & 0x7FFFFFFF");
        apply(32'h80000000, 32'h7FFFFFFF, ALU_AND);
        check_eq(result, 32'h00000000, "0x80000000 & 0x7FFFFFFF = 0x00000000");
        check(zero === 1'b1, "zero flag set on MSB/rest disjoint AND");

        test_begin("Boundary: SLTU 0x7FFFFFFF vs 0x80000000");
        apply(32'h7FFFFFFF, 32'h80000000, ALU_SLTU);
        check_eq(result, 32'd1, "0x7FFFFFFF < 0x80000000 = 1 (unsigned)");

        test_begin("Boundary: SLT 0x7FFFFFFF vs 0x80000000");
        apply(32'h7FFFFFFF, 32'h80000000, ALU_SLT);
        check_eq(result, 32'd0, "INT_MAX < INT_MIN = 0 (signed, opposite of unsigned)");

        // =====================================================================
        // Finish
        // =====================================================================
        test_finish();
    end

endmodule : tb_alu
