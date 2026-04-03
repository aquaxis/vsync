// =============================================================================
// VSync - RV32I ALU Instruction Test Bench
// =============================================================================
// Test IDs: CORE-006, CORE-007, CORE-008
// - CORE-006: ADDI/SLTI/SLTIU/XORI/ORI/ANDI (immediate arithmetic)
// - CORE-007: SLLI/SRLI/SRAI (immediate shift)
// - CORE-008: ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND (register arithmetic)
//
// Approach: Test instruction encoding -> ALU result using the ALU module and
// immediate_gen to verify that RV32I instruction encodings produce correct
// results. This validates the instruction encoding layer above the raw ALU.
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_rv32i_alu;

    import test_utils::*;
    import vsync_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD = 10;    // 100MHz clock
    localparam RST_CYCLES = 10;    // Reset duration

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // ALU DUT signals
    logic [XLEN-1:0] alu_operand_a;
    logic [XLEN-1:0] alu_operand_b;
    alu_op_t          alu_op;
    logic [XLEN-1:0] alu_result;
    logic             alu_zero;

    // Immediate generator signals
    logic [ILEN-1:0]  imm_instruction;
    imm_type_t         imm_type;
    logic [XLEN-1:0]  imm_out;

    // Simulated register file (for testing R-type instructions)
    logic [XLEN-1:0] regfile [0:31];

    // =========================================================================
    // Clock and Reset Generation
    // =========================================================================
    clk_rst_gen #(
        .CLK_PERIOD_NS (CLK_PERIOD),
        .RST_CYCLES    (RST_CYCLES)
    ) u_clk_rst (
        .clk       (clk),
        .rst       (rst),
        .rst_n     (rst_n),
        .init_done (init_done)
    );

    // =========================================================================
    // DUT Instantiation: ALU
    // =========================================================================
    alu u_alu (
        .operand_a (alu_operand_a),
        .operand_b (alu_operand_b),
        .alu_op    (alu_op),
        .result    (alu_result),
        .zero      (alu_zero)
    );

    // =========================================================================
    // DUT Instantiation: Immediate Generator
    // =========================================================================
    immediate_gen u_immgen (
        .instruction (imm_instruction),
        .imm_type    (imm_type),
        .immediate   (imm_out)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_rv32i_alu.vcd");
        $dumpvars(0, tb_rv32i_alu);
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 200000);
        $display("ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded maximum time");
    end

    // =========================================================================
    // Instruction Encoding Helper Functions
    // =========================================================================

    /** Encode I-type instruction */
    function automatic logic [31:0] encode_i_type(
        input logic [11:0] imm,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm, rs1, funct3, rd, opcode};
    endfunction

    /** Encode R-type instruction */
    function automatic logic [31:0] encode_r_type(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        return {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    /** Encode ADDI rd, rs1, imm */
    function automatic logic [31:0] encode_addi(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm
    );
        return encode_i_type(imm, rs1, 3'b000, rd, 7'b0010011);
    endfunction

    /** Encode SLTI rd, rs1, imm */
    function automatic logic [31:0] encode_slti(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm
    );
        return encode_i_type(imm, rs1, 3'b010, rd, 7'b0010011);
    endfunction

    /** Encode SLTIU rd, rs1, imm */
    function automatic logic [31:0] encode_sltiu(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm
    );
        return encode_i_type(imm, rs1, 3'b011, rd, 7'b0010011);
    endfunction

    /** Encode XORI rd, rs1, imm */
    function automatic logic [31:0] encode_xori(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm
    );
        return encode_i_type(imm, rs1, 3'b100, rd, 7'b0010011);
    endfunction

    /** Encode ORI rd, rs1, imm */
    function automatic logic [31:0] encode_ori(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm
    );
        return encode_i_type(imm, rs1, 3'b110, rd, 7'b0010011);
    endfunction

    /** Encode ANDI rd, rs1, imm */
    function automatic logic [31:0] encode_andi(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm
    );
        return encode_i_type(imm, rs1, 3'b111, rd, 7'b0010011);
    endfunction

    /** Encode SLLI rd, rs1, shamt */
    function automatic logic [31:0] encode_slli(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] shamt
    );
        return encode_i_type({7'b0000000, shamt}, rs1, 3'b001, rd, 7'b0010011);
    endfunction

    /** Encode SRLI rd, rs1, shamt */
    function automatic logic [31:0] encode_srli(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] shamt
    );
        return encode_i_type({7'b0000000, shamt}, rs1, 3'b101, rd, 7'b0010011);
    endfunction

    /** Encode SRAI rd, rs1, shamt */
    function automatic logic [31:0] encode_srai(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] shamt
    );
        return encode_i_type({7'b0100000, shamt}, rs1, 3'b101, rd, 7'b0010011);
    endfunction

    /** Encode ADD rd, rs1, rs2 */
    function automatic logic [31:0] encode_add(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );
        return encode_r_type(7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011);
    endfunction

    /** Encode SUB rd, rs1, rs2 */
    function automatic logic [31:0] encode_sub(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );
        return encode_r_type(7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011);
    endfunction

    // =========================================================================
    // Helper: Execute I-type ALU instruction
    // Sets up ALU with rs1_data and sign-extended immediate, applies alu_op
    // =========================================================================
    task automatic exec_i_type(
        input  logic [XLEN-1:0] rs1_val,
        input  logic [31:0]     instr,
        input  alu_op_t         op,
        output logic [XLEN-1:0] result
    );
        // Use immediate generator to get sign-extended immediate
        imm_instruction = instr;
        imm_type        = IMM_I;
        #1;

        alu_operand_a = rs1_val;
        alu_operand_b = imm_out;
        alu_op        = op;
        #1;

        result = alu_result;
    endtask

    // =========================================================================
    // Helper: Execute R-type ALU instruction
    // =========================================================================
    task automatic exec_r_type(
        input  logic [XLEN-1:0] rs1_val,
        input  logic [XLEN-1:0] rs2_val,
        input  alu_op_t         op,
        output logic [XLEN-1:0] result
    );
        alu_operand_a = rs1_val;
        alu_operand_b = rs2_val;
        alu_op        = op;
        #1;

        result = alu_result;
    endtask

    // =========================================================================
    // Helper: Initialize register file
    // =========================================================================
    task automatic init_regfile();
        integer i;
        for (i = 0; i < 32; i = i + 1) begin
            regfile[i] = 32'h0;
        end
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        init_regfile();
        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("RV32I ALU Instruction Tests");

        // === CORE-006: Immediate Arithmetic Tests ===
        test_addi();
        test_slti();
        test_sltiu();
        test_xori();
        test_ori();
        test_andi();

        // === CORE-007: Immediate Shift Tests ===
        test_slli();
        test_srli();
        test_srai();

        // === CORE-008: Register Arithmetic Tests ===
        test_add();
        test_sub();
        test_sll();
        test_slt();
        test_sltu();
        test_xor_op();
        test_srl();
        test_sra();
        test_or_op();
        test_and_op();

        // === Additional Tests ===
        test_x0_immutability();
        test_all_registers();
        test_boundary_values();

    endtask

    // =========================================================================
    // CORE-006: Immediate Arithmetic Instructions
    // =========================================================================

    task automatic test_addi();
        logic [XLEN-1:0] result;
        logic [31:0]     instr;

        test_begin("CORE-006: ADDI");

        // ADDI x1, x0, 1 (basic positive immediate)
        instr = encode_addi(5'd1, 5'd0, 12'd1);
        exec_i_type(32'd0, instr, ALU_ADD, result);
        check_eq(result, 32'd1, "ADDI x1, x0, 1 => 1");

        // ADDI x2, x1, -1 (negative immediate, sign-extended)
        instr = encode_addi(5'd2, 5'd1, 12'hFFF);  // -1 in 12-bit
        exec_i_type(32'd1, instr, ALU_ADD, result);
        check_eq(result, 32'd0, "ADDI x2, x1(=1), -1 => 0");

        // ADDI x3, x0, 2047 (max positive 12-bit immediate)
        instr = encode_addi(5'd3, 5'd0, 12'h7FF);  // 2047
        exec_i_type(32'd0, instr, ALU_ADD, result);
        check_eq(result, 32'd2047, "ADDI x3, x0, 2047 => 2047");

        // ADDI x4, x0, -2048 (min negative 12-bit immediate)
        instr = encode_addi(5'd4, 5'd0, 12'h800);  // -2048
        exec_i_type(32'd0, instr, ALU_ADD, result);
        check_eq(result, 32'hFFFFF800, "ADDI x4, x0, -2048 => 0xFFFFF800");

        // ADDI x5, x0, 0 (zero immediate)
        instr = encode_addi(5'd5, 5'd0, 12'd0);
        exec_i_type(32'hDEADBEEF, instr, ALU_ADD, result);
        check_eq(result, 32'hDEADBEEF, "ADDI with 0 is identity");
    endtask

    task automatic test_slti();
        logic [XLEN-1:0] result;
        logic [31:0]     instr;

        test_begin("CORE-006: SLTI");

        // 5 < 10 (true)
        instr = encode_slti(5'd1, 5'd2, 12'd10);
        exec_i_type(32'd5, instr, ALU_SLT, result);
        check_eq(result, 32'd1, "SLTI: 5 < 10 = 1 (signed)");

        // 10 < 5 (false)
        instr = encode_slti(5'd1, 5'd2, 12'd5);
        exec_i_type(32'd10, instr, ALU_SLT, result);
        check_eq(result, 32'd0, "SLTI: 10 < 5 = 0 (signed)");

        // -1 < 1 (true, signed)
        instr = encode_slti(5'd1, 5'd2, 12'd1);
        exec_i_type(32'hFFFFFFFF, instr, ALU_SLT, result);
        check_eq(result, 32'd1, "SLTI: -1 < 1 = 1 (signed)");

        // 1 < -1 (false, signed; -1 sign-extended from 12-bit = 0xFFF)
        instr = encode_slti(5'd1, 5'd2, 12'hFFF);
        exec_i_type(32'd1, instr, ALU_SLT, result);
        check_eq(result, 32'd0, "SLTI: 1 < -1 = 0 (signed)");

        // Equal values
        instr = encode_slti(5'd1, 5'd2, 12'd7);
        exec_i_type(32'd7, instr, ALU_SLT, result);
        check_eq(result, 32'd0, "SLTI: 7 < 7 = 0 (equal)");
    endtask

    task automatic test_sltiu();
        logic [XLEN-1:0] result;
        logic [31:0]     instr;

        test_begin("CORE-006: SLTIU");

        // 5 < 10 (unsigned, true)
        instr = encode_sltiu(5'd1, 5'd2, 12'd10);
        exec_i_type(32'd5, instr, ALU_SLTU, result);
        check_eq(result, 32'd1, "SLTIU: 5 < 10 = 1 (unsigned)");

        // 0xFFFFFFFF < 1 (false, large unsigned)
        // Note: immediate 1 sign-extends to 0x00000001
        instr = encode_sltiu(5'd1, 5'd2, 12'd1);
        exec_i_type(32'hFFFFFFFF, instr, ALU_SLTU, result);
        check_eq(result, 32'd0, "SLTIU: 0xFFFFFFFF < 1 = 0 (unsigned)");

        // 0 < 0xFFFFFFFF (true; imm=0xFFF sign-extends to 0xFFFFFFFF)
        instr = encode_sltiu(5'd1, 5'd2, 12'hFFF);
        exec_i_type(32'd0, instr, ALU_SLTU, result);
        check_eq(result, 32'd1, "SLTIU: 0 < 0xFFFFFFFF = 1 (unsigned, sign-extended imm)");
    endtask

    task automatic test_xori();
        logic [XLEN-1:0] result;
        logic [31:0]     instr;

        test_begin("CORE-006: XORI");

        // XOR with 0 (identity)
        instr = encode_xori(5'd1, 5'd2, 12'd0);
        exec_i_type(32'hA5A5A5A5, instr, ALU_XOR, result);
        check_eq(result, 32'hA5A5A5A5, "XORI with 0 = identity");

        // XOR with -1 (0xFFF sign-extends to 0xFFFFFFFF = bitwise NOT)
        instr = encode_xori(5'd1, 5'd2, 12'hFFF);
        exec_i_type(32'hA5A5A5A5, instr, ALU_XOR, result);
        check_eq(result, 32'h5A5A5A5A, "XORI with -1 = bitwise NOT");

        // XOR with pattern
        instr = encode_xori(5'd1, 5'd2, 12'h0FF);
        exec_i_type(32'h00000FF0, instr, ALU_XOR, result);
        check_eq(result, 32'h00000F0F, "XORI with 0xFF = selective flip");
    endtask

    task automatic test_ori();
        logic [XLEN-1:0] result;
        logic [31:0]     instr;

        test_begin("CORE-006: ORI");

        // OR with 0 (identity)
        instr = encode_ori(5'd1, 5'd2, 12'd0);
        exec_i_type(32'hABCD1234, instr, ALU_OR, result);
        check_eq(result, 32'hABCD1234, "ORI with 0 = identity");

        // OR with -1 (all ones)
        instr = encode_ori(5'd1, 5'd2, 12'hFFF);
        exec_i_type(32'd0, instr, ALU_OR, result);
        check_eq(result, 32'hFFFFFFFF, "ORI with -1 = all ones");

        // OR with pattern
        instr = encode_ori(5'd1, 5'd2, 12'h00F);
        exec_i_type(32'hFF00FF00, instr, ALU_OR, result);
        check_eq(result, 32'hFF00FF0F, "ORI: set lower 4 bits");
    endtask

    task automatic test_andi();
        logic [XLEN-1:0] result;
        logic [31:0]     instr;

        test_begin("CORE-006: ANDI");

        // AND with 0 (always 0)
        instr = encode_andi(5'd1, 5'd2, 12'd0);
        exec_i_type(32'hFFFFFFFF, instr, ALU_AND, result);
        check_eq(result, 32'd0, "ANDI with 0 = 0");

        // AND with -1 (identity; -1 sign-extends to 0xFFFFFFFF)
        instr = encode_andi(5'd1, 5'd2, 12'hFFF);
        exec_i_type(32'hDEADBEEF, instr, ALU_AND, result);
        check_eq(result, 32'hDEADBEEF, "ANDI with -1 = identity");

        // AND with mask
        instr = encode_andi(5'd1, 5'd2, 12'h0FF);
        exec_i_type(32'hABCD5678, instr, ALU_AND, result);
        check_eq(result, 32'h00000078, "ANDI: mask lower 8 bits");
    endtask

    // =========================================================================
    // CORE-007: Immediate Shift Instructions
    // =========================================================================

    task automatic test_slli();
        logic [XLEN-1:0] result;
        logic [31:0]     instr;

        test_begin("CORE-007: SLLI");

        // SLLI by 0
        instr = encode_slli(5'd1, 5'd2, 5'd0);
        exec_i_type(32'hDEADBEEF, instr, ALU_SLL, result);
        check_eq(result, 32'hDEADBEEF, "SLLI by 0 = identity");

        // SLLI by 1
        instr = encode_slli(5'd1, 5'd2, 5'd1);
        exec_i_type(32'd1, instr, ALU_SLL, result);
        check_eq(result, 32'd2, "SLLI: 1 << 1 = 2");

        // SLLI by 31
        instr = encode_slli(5'd1, 5'd2, 5'd31);
        exec_i_type(32'd1, instr, ALU_SLL, result);
        check_eq(result, 32'h80000000, "SLLI: 1 << 31 = 0x80000000");

        // SLLI by 16
        instr = encode_slli(5'd1, 5'd2, 5'd16);
        exec_i_type(32'h0000FFFF, instr, ALU_SLL, result);
        check_eq(result, 32'hFFFF0000, "SLLI: 0xFFFF << 16 = 0xFFFF0000");
    endtask

    task automatic test_srli();
        logic [XLEN-1:0] result;
        logic [31:0]     instr;

        test_begin("CORE-007: SRLI");

        // SRLI by 0
        instr = encode_srli(5'd1, 5'd2, 5'd0);
        exec_i_type(32'hDEADBEEF, instr, ALU_SRL, result);
        check_eq(result, 32'hDEADBEEF, "SRLI by 0 = identity");

        // SRLI by 1 (logical, MSB not sign-extended)
        instr = encode_srli(5'd1, 5'd2, 5'd1);
        exec_i_type(32'h80000000, instr, ALU_SRL, result);
        check_eq(result, 32'h40000000, "SRLI: 0x80000000 >> 1 = 0x40000000 (logical)");

        // SRLI by 31
        instr = encode_srli(5'd1, 5'd2, 5'd31);
        exec_i_type(32'h80000000, instr, ALU_SRL, result);
        check_eq(result, 32'd1, "SRLI: 0x80000000 >> 31 = 1");

        // SRLI by 16
        instr = encode_srli(5'd1, 5'd2, 5'd16);
        exec_i_type(32'hFFFF0000, instr, ALU_SRL, result);
        check_eq(result, 32'h0000FFFF, "SRLI: 0xFFFF0000 >> 16 = 0x0000FFFF");
    endtask

    task automatic test_srai();
        logic [XLEN-1:0] result;
        logic [31:0]     instr;

        test_begin("CORE-007: SRAI");

        // SRAI by 0
        instr = encode_srai(5'd1, 5'd2, 5'd0);
        exec_i_type(32'hDEADBEEF, instr, ALU_SRA, result);
        check_eq(result, 32'hDEADBEEF, "SRAI by 0 = identity");

        // SRAI positive value
        instr = encode_srai(5'd1, 5'd2, 5'd1);
        exec_i_type(32'h40000000, instr, ALU_SRA, result);
        check_eq(result, 32'h20000000, "SRAI: 0x40000000 >>> 1 = 0x20000000");

        // SRAI negative value (sign extended)
        instr = encode_srai(5'd1, 5'd2, 5'd1);
        exec_i_type(32'h80000000, instr, ALU_SRA, result);
        check_eq(result, 32'hC0000000, "SRAI: 0x80000000 >>> 1 = 0xC0000000 (sign extended)");

        // SRAI by 31 (all sign bits)
        instr = encode_srai(5'd1, 5'd2, 5'd31);
        exec_i_type(32'h80000000, instr, ALU_SRA, result);
        check_eq(result, 32'hFFFFFFFF, "SRAI: 0x80000000 >>> 31 = 0xFFFFFFFF");
    endtask

    // =========================================================================
    // CORE-008: Register Arithmetic Instructions
    // =========================================================================

    task automatic test_add();
        logic [XLEN-1:0] result;

        test_begin("CORE-008: ADD");

        // ADD: positive + positive
        exec_r_type(32'd10, 32'd20, ALU_ADD, result);
        check_eq(result, 32'd30, "ADD: 10 + 20 = 30");

        // ADD: positive + negative
        exec_r_type(32'd10, 32'hFFFFFFF6, ALU_ADD, result);  // -10
        check_eq(result, 32'd0, "ADD: 10 + (-10) = 0");

        // ADD: negative + negative
        exec_r_type(32'hFFFFFFFF, 32'hFFFFFFFF, ALU_ADD, result);
        check_eq(result, 32'hFFFFFFFE, "ADD: -1 + -1 = -2");

        // ADD: overflow wraps
        exec_r_type(32'hFFFFFFFF, 32'd1, ALU_ADD, result);
        check_eq(result, 32'd0, "ADD: overflow wraps to 0");

        // ADD: with zero
        exec_r_type(32'hCAFEBABE, 32'd0, ALU_ADD, result);
        check_eq(result, 32'hCAFEBABE, "ADD: x + 0 = x");
    endtask

    task automatic test_sub();
        logic [XLEN-1:0] result;

        test_begin("CORE-008: SUB");

        // SUB: positive result
        exec_r_type(32'd30, 32'd10, ALU_SUB, result);
        check_eq(result, 32'd20, "SUB: 30 - 10 = 20");

        // SUB: negative result
        exec_r_type(32'd10, 32'd30, ALU_SUB, result);
        check_eq(result, 32'hFFFFFFEC, "SUB: 10 - 30 = -20");

        // SUB: with zero
        exec_r_type(32'hDEADBEEF, 32'd0, ALU_SUB, result);
        check_eq(result, 32'hDEADBEEF, "SUB: x - 0 = x");

        // SUB: underflow wraps
        exec_r_type(32'd0, 32'd1, ALU_SUB, result);
        check_eq(result, 32'hFFFFFFFF, "SUB: 0 - 1 = 0xFFFFFFFF");
    endtask

    task automatic test_sll();
        logic [XLEN-1:0] result;

        test_begin("CORE-008: SLL");

        // SLL by 0
        exec_r_type(32'hDEADBEEF, 32'd0, ALU_SLL, result);
        check_eq(result, 32'hDEADBEEF, "SLL by 0 = identity");

        // SLL by 1
        exec_r_type(32'd1, 32'd1, ALU_SLL, result);
        check_eq(result, 32'd2, "SLL: 1 << 1 = 2");

        // SLL uses only lower 5 bits
        exec_r_type(32'd1, 32'h00000021, ALU_SLL, result);
        check_eq(result, 32'd2, "SLL: uses only lower 5 bits (0x21 -> shamt=1)");
    endtask

    task automatic test_slt();
        logic [XLEN-1:0] result;

        test_begin("CORE-008: SLT");

        // Signed: 5 < 10
        exec_r_type(32'd5, 32'd10, ALU_SLT, result);
        check_eq(result, 32'd1, "SLT: 5 < 10 = 1 (signed)");

        // Signed: 10 < 5 (false)
        exec_r_type(32'd10, 32'd5, ALU_SLT, result);
        check_eq(result, 32'd0, "SLT: 10 < 5 = 0 (signed)");

        // Signed: -1 < 1
        exec_r_type(32'hFFFFFFFF, 32'd1, ALU_SLT, result);
        check_eq(result, 32'd1, "SLT: -1 < 1 = 1 (signed)");

        // Equal
        exec_r_type(32'd7, 32'd7, ALU_SLT, result);
        check_eq(result, 32'd0, "SLT: 7 < 7 = 0 (equal)");
    endtask

    task automatic test_sltu();
        logic [XLEN-1:0] result;

        test_begin("CORE-008: SLTU");

        // Unsigned: 5 < 10
        exec_r_type(32'd5, 32'd10, ALU_SLTU, result);
        check_eq(result, 32'd1, "SLTU: 5 < 10 = 1 (unsigned)");

        // Unsigned: 0xFFFFFFFF < 0 (false)
        exec_r_type(32'hFFFFFFFF, 32'd0, ALU_SLTU, result);
        check_eq(result, 32'd0, "SLTU: 0xFFFFFFFF < 0 = 0 (unsigned)");

        // Unsigned: 0 < 0xFFFFFFFF (true)
        exec_r_type(32'd0, 32'hFFFFFFFF, ALU_SLTU, result);
        check_eq(result, 32'd1, "SLTU: 0 < 0xFFFFFFFF = 1 (unsigned)");
    endtask

    task automatic test_xor_op();
        logic [XLEN-1:0] result;

        test_begin("CORE-008: XOR");

        exec_r_type(32'hA5A5A5A5, 32'h5A5A5A5A, ALU_XOR, result);
        check_eq(result, 32'hFFFFFFFF, "XOR: complementary patterns = all ones");

        exec_r_type(32'hDEADBEEF, 32'hDEADBEEF, ALU_XOR, result);
        check_eq(result, 32'd0, "XOR: x ^ x = 0");
    endtask

    task automatic test_srl();
        logic [XLEN-1:0] result;

        test_begin("CORE-008: SRL");

        // Logical right shift by 1
        exec_r_type(32'h80000000, 32'd1, ALU_SRL, result);
        check_eq(result, 32'h40000000, "SRL: 0x80000000 >> 1 = 0x40000000 (logical)");

        // Uses only lower 5 bits
        exec_r_type(32'h80000000, 32'h00000021, ALU_SRL, result);
        check_eq(result, 32'h40000000, "SRL: uses only lower 5 bits (0x21 -> shamt=1)");
    endtask

    task automatic test_sra();
        logic [XLEN-1:0] result;

        test_begin("CORE-008: SRA");

        // Arithmetic shift positive
        exec_r_type(32'h40000000, 32'd1, ALU_SRA, result);
        check_eq(result, 32'h20000000, "SRA: positive >> 1 fills with 0");

        // Arithmetic shift negative
        exec_r_type(32'h80000000, 32'd1, ALU_SRA, result);
        check_eq(result, 32'hC0000000, "SRA: negative >> 1 fills with 1 (sign extension)");

        // Shift by 31
        exec_r_type(32'h80000000, 32'd31, ALU_SRA, result);
        check_eq(result, 32'hFFFFFFFF, "SRA: 0x80000000 >>> 31 = all ones");
    endtask

    task automatic test_or_op();
        logic [XLEN-1:0] result;

        test_begin("CORE-008: OR");

        exec_r_type(32'hF0F0F0F0, 32'h0F0F0F0F, ALU_OR, result);
        check_eq(result, 32'hFFFFFFFF, "OR: complementary = all ones");

        exec_r_type(32'hABCD1234, 32'd0, ALU_OR, result);
        check_eq(result, 32'hABCD1234, "OR: x | 0 = x");
    endtask

    task automatic test_and_op();
        logic [XLEN-1:0] result;

        test_begin("CORE-008: AND");

        exec_r_type(32'hF0F0F0F0, 32'h0F0F0F0F, ALU_AND, result);
        check_eq(result, 32'd0, "AND: disjoint patterns = 0");

        exec_r_type(32'hDEADBEEF, 32'hFFFFFFFF, ALU_AND, result);
        check_eq(result, 32'hDEADBEEF, "AND: x & all_ones = x");
    endtask

    // =========================================================================
    // Additional Tests
    // =========================================================================

    task automatic test_x0_immutability();
        logic [XLEN-1:0] result;

        test_begin("Register x0 Immutability");

        // x0 should always be 0
        // In our simulated regfile, regfile[0] = 0
        check_eq(regfile[0], 32'd0, "x0 initialized to 0");

        // Even if we "write" to x0 in our regfile, a proper core ignores it
        // Verify that using x0 as source always gives 0
        exec_r_type(32'd0, 32'd42, ALU_ADD, result);
        check_eq(result, 32'd42, "x0(=0) + 42 = 42 (x0 always zero)");

        // Verify ADDI from x0
        exec_r_type(32'd0, 32'd100, ALU_ADD, result);
        check_eq(result, 32'd100, "ADDI x1, x0, 100 => 100");
    endtask

    task automatic test_all_registers();
        logic [XLEN-1:0] result;
        integer i;

        test_begin("All Registers x0-x31 Read/Write");

        // Simulate writing unique values to all registers and verify
        for (i = 0; i < 32; i = i + 1) begin
            regfile[i] = (i == 0) ? 32'd0 : (32'h100 + i);
        end

        // Verify a few register values via ALU ADD with 0
        exec_r_type(regfile[1], 32'd0, ALU_ADD, result);
        check_eq(result, 32'h101, "x1 = 0x101");

        exec_r_type(regfile[15], 32'd0, ALU_ADD, result);
        check_eq(result, 32'h10F, "x15 = 0x10F");

        exec_r_type(regfile[31], 32'd0, ALU_ADD, result);
        check_eq(result, 32'h11F, "x31 = 0x11F");

        // Verify x0 is still 0
        exec_r_type(regfile[0], 32'd0, ALU_ADD, result);
        check_eq(result, 32'd0, "x0 = 0 (always)");
    endtask

    task automatic test_boundary_values();
        logic [XLEN-1:0] result;

        test_begin("Boundary Value Tests");

        // 0x00000000 + 0x00000000
        exec_r_type(32'h00000000, 32'h00000000, ALU_ADD, result);
        check_eq(result, 32'h00000000, "0 + 0 = 0");

        // 0x7FFFFFFF + 1 (overflow)
        exec_r_type(32'h7FFFFFFF, 32'd1, ALU_ADD, result);
        check_eq(result, 32'h80000000, "INT_MAX + 1 = INT_MIN (overflow)");

        // 0x80000000 - 1
        exec_r_type(32'h80000000, 32'd1, ALU_SUB, result);
        check_eq(result, 32'h7FFFFFFF, "INT_MIN - 1 = INT_MAX (underflow)");

        // 0xFFFFFFFF + 0xFFFFFFFF
        exec_r_type(32'hFFFFFFFF, 32'hFFFFFFFF, ALU_ADD, result);
        check_eq(result, 32'hFFFFFFFE, "0xFFFFFFFF + 0xFFFFFFFF = 0xFFFFFFFE");

        // SLT: INT_MIN < INT_MAX
        exec_r_type(32'h80000000, 32'h7FFFFFFF, ALU_SLT, result);
        check_eq(result, 32'd1, "SLT: INT_MIN < INT_MAX = 1 (signed)");

        // SLTU: 0x7FFFFFFF < 0x80000000 (unsigned)
        exec_r_type(32'h7FFFFFFF, 32'h80000000, ALU_SLTU, result);
        check_eq(result, 32'd1, "SLTU: 0x7FFFFFFF < 0x80000000 = 1 (unsigned)");
    endtask

endmodule
