// =============================================================================
// VSync - RV32I Branch Instruction Test Bench
// =============================================================================
// Test IDs: CORE-001, CORE-002, CORE-003
// - CORE-001: LUI/AUIPC (upper immediate)
// - CORE-002: JAL/JALR (unconditional jump)
// - CORE-003: BEQ/BNE/BLT/BGE/BLTU/BGEU (conditional branch)
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_rv32i_branch;

    import test_utils::*;
    import vsync_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD = 10;
    localparam RST_CYCLES = 10;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // CPU core interface signals
    logic [31:0] pc;
    logic [31:0] next_pc;
    logic [31:0] instr;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] rd_data;
    logic        branch_taken;

    // Additional signals for branch_unit
    logic [31:0] immediate;
    logic [2:0]  branch_funct3;
    logic        is_branch;
    logic        is_jal;
    logic        is_jalr;
    logic [31:0] branch_target;

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
    // DUT Instantiation
    // =========================================================================
    branch_unit u_branch_unit (
        .rs1_data      (rs1_data),
        .rs2_data      (rs2_data),
        .pc            (pc),
        .immediate     (immediate),
        .branch_funct3 (branch_funct3),
        .is_branch     (is_branch),
        .is_jal        (is_jal),
        .is_jalr       (is_jalr),
        .branch_taken  (branch_taken),
        .branch_target (branch_target)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_rv32i_branch.vcd");
        $dumpvars(0, tb_rv32i_branch);
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
    // Main test sequence
    // =========================================================================
    initial begin
        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    // Test a branch condition: sets is_branch=1 and checks branch_taken
    task automatic test_branch_cond(
        input logic [31:0] rs1,
        input logic [31:0] rs2,
        input logic [2:0]  funct3,
        input logic        expect_taken,
        input string       msg
    );
        is_branch     = 1'b1;
        is_jal        = 1'b0;
        is_jalr       = 1'b0;
        rs1_data      = rs1;
        rs2_data      = rs2;
        branch_funct3 = funct3;
        pc            = 32'h0000_1000;
        immediate     = 32'h0000_0010;
        #1;
        check(branch_taken == expect_taken, msg);
    endtask

    // Test a jump/branch target address
    task automatic test_jump_target(
        input logic [31:0] pc_val,
        input logic [31:0] imm_val,
        input logic [31:0] rs1_val,
        input logic        is_jal_v,
        input logic        is_jalr_v,
        input logic [31:0] expect_target,
        input string       msg
    );
        pc            = pc_val;
        immediate     = imm_val;
        rs1_data      = rs1_val;
        rs2_data      = 32'h0;
        is_jal        = is_jal_v;
        is_jalr       = is_jalr_v;
        is_branch     = ~is_jal_v & ~is_jalr_v;
        branch_funct3 = 3'b000;
        #1;
        check_eq(branch_target, expect_target, msg);
    endtask

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("RV32I Branch & Jump Instruction Tests");

        // === CORE-001: Upper Immediate Tests ===
        test_lui();
        test_auipc();

        // === CORE-002: Unconditional Jump Tests ===
        test_jal();
        test_jalr();

        // === CORE-003: Conditional Branch Tests ===
        test_beq();
        test_bne();
        test_blt();
        test_bge();
        test_bltu();
        test_bgeu();

        // === Additional Tests ===
        test_branch_boundary();
        test_branch_target_alignment();

    endtask

    // =========================================================================
    // CORE-001: Upper Immediate Instructions
    // =========================================================================

    task automatic test_lui();
        test_begin("CORE-001: LUI");
        // LUI is handled by the ALU, not the branch_unit.
        // Verify that when no branch/jump is active, branch_taken is 0.
        is_branch     = 1'b0;
        is_jal        = 1'b0;
        is_jalr       = 1'b0;
        rs1_data      = 32'h1234_5000;
        rs2_data      = 32'h0000_0000;
        branch_funct3 = 3'b000;
        pc            = 32'h0000_0100;
        immediate     = 32'h1234_5000;
        #1;
        check(branch_taken == 1'b0, "LUI: branch_taken=0 when no branch/jump active");
    endtask

    task automatic test_auipc();
        test_begin("CORE-001: AUIPC");
        // AUIPC is handled by the ALU, not the branch_unit.
        // Verify that when no branch/jump is active, branch_taken is 0.
        is_branch     = 1'b0;
        is_jal        = 1'b0;
        is_jalr       = 1'b0;
        rs1_data      = 32'h0000_0000;
        rs2_data      = 32'h0000_0000;
        branch_funct3 = 3'b000;
        pc            = 32'h0000_0200;
        immediate     = 32'h0000_1000;
        #1;
        check(branch_taken == 1'b0, "AUIPC: branch_taken=0 when no branch/jump active");
        // branch_target still computes pc+imm even when not taken
        check_eq(branch_target, 32'h0000_1200, "AUIPC: target = pc + imm (computed but not taken)");
    endtask

    // =========================================================================
    // CORE-002: Unconditional Jump Instructions
    // =========================================================================

    task automatic test_jal();
        test_begin("CORE-002: JAL");

        // JAL: branch_taken=1, target = pc + immediate
        is_branch     = 1'b0;
        is_jal        = 1'b1;
        is_jalr       = 1'b0;
        rs1_data      = 32'h0000_0000;
        rs2_data      = 32'h0000_0000;
        branch_funct3 = 3'b000;
        pc            = 32'h0000_0100;
        immediate     = 32'h0000_0020;
        #1;
        check(branch_taken == 1'b1, "JAL: branch_taken=1");
        check_eq(branch_target, 32'h0000_0120, "JAL: target = 0x100 + 0x20 = 0x120");

        // JAL forward jump with larger offset
        pc        = 32'h0000_0200;
        immediate = 32'h0000_0400;
        #1;
        check(branch_taken == 1'b1, "JAL forward: branch_taken=1");
        check_eq(branch_target, 32'h0000_0600, "JAL forward: target = 0x200 + 0x400 = 0x600");

        // JAL backward jump (negative immediate)
        pc        = 32'h0000_0400;
        immediate = 32'hFFFF_FF00; // -256
        #1;
        check(branch_taken == 1'b1, "JAL backward: branch_taken=1");
        check_eq(branch_target, 32'h0000_0300, "JAL backward: target = 0x400 + (-0x100) = 0x300");
    endtask

    task automatic test_jalr();
        test_begin("CORE-002: JALR");

        // JALR: branch_taken=1, target = (rs1 + immediate) & ~1
        is_branch     = 1'b0;
        is_jal        = 1'b0;
        is_jalr       = 1'b1;
        rs2_data      = 32'h0000_0000;
        branch_funct3 = 3'b000;
        pc            = 32'h0000_0000;

        // Basic: rs1=0x100, imm=0x20 -> target=0x120
        rs1_data  = 32'h0000_0100;
        immediate = 32'h0000_0020;
        #1;
        check(branch_taken == 1'b1, "JALR: branch_taken=1");
        check_eq(branch_target, 32'h0000_0120, "JALR: target = (0x100+0x20)&~1 = 0x120");

        // JALR clears LSB: rs1=0x101, imm=0 -> target=0x100
        rs1_data  = 32'h0000_0101;
        immediate = 32'h0000_0000;
        #1;
        check(branch_taken == 1'b1, "JALR LSB clear: branch_taken=1");
        check_eq(branch_target, 32'h0000_0100, "JALR LSB clear: target = (0x101+0)&~1 = 0x100");

        // JALR with offset: rs1=0x200, imm=0x05 -> (0x205)&~1 = 0x204
        rs1_data  = 32'h0000_0200;
        immediate = 32'h0000_0005;
        #1;
        check_eq(branch_target, 32'h0000_0204, "JALR: target = (0x200+0x05)&~1 = 0x204");
    endtask

    // =========================================================================
    // CORE-003: Conditional Branch Instructions
    // =========================================================================

    task automatic test_beq();
        test_begin("CORE-003: BEQ");

        // Equal values -> taken
        test_branch_cond(32'd5, 32'd5, F3_BEQ, 1'b1, "BEQ: 5==5 -> taken");

        // Unequal values -> not taken
        test_branch_cond(32'd5, 32'd10, F3_BEQ, 1'b0, "BEQ: 5!=10 -> not taken");

        // Both zero -> taken
        test_branch_cond(32'd0, 32'd0, F3_BEQ, 1'b1, "BEQ: 0==0 -> taken");

        // Max unsigned equal -> taken
        test_branch_cond(32'hFFFF_FFFF, 32'hFFFF_FFFF, F3_BEQ, 1'b1, "BEQ: 0xFFFFFFFF==0xFFFFFFFF -> taken");
    endtask

    task automatic test_bne();
        test_begin("CORE-003: BNE");

        // Unequal values -> taken
        test_branch_cond(32'd5, 32'd10, F3_BNE, 1'b1, "BNE: 5!=10 -> taken");

        // Equal values -> not taken
        test_branch_cond(32'd5, 32'd5, F3_BNE, 1'b0, "BNE: 5==5 -> not taken");
    endtask

    task automatic test_blt();
        test_begin("CORE-003: BLT");

        // rs1 < rs2 (signed) -> taken
        test_branch_cond(32'd5, 32'd10, F3_BLT, 1'b1, "BLT: 5<10 -> taken");

        // rs1 > rs2 (signed) -> not taken
        test_branch_cond(32'd10, 32'd5, F3_BLT, 1'b0, "BLT: 10>5 -> not taken");

        // Negative < positive -> taken (-1 < 1)
        test_branch_cond(32'hFFFF_FFFF, 32'd1, F3_BLT, 1'b1, "BLT: -1<1 -> taken");

        // Positive > negative -> not taken (1 > -1)
        test_branch_cond(32'd1, 32'hFFFF_FFFF, F3_BLT, 1'b0, "BLT: 1>-1 -> not taken");

        // Negative < negative -> taken (-5 < -3)
        test_branch_cond(32'hFFFF_FFFB, 32'hFFFF_FFFD, F3_BLT, 1'b1, "BLT: -5<-3 -> taken");

        // Equal -> not taken
        test_branch_cond(32'd7, 32'd7, F3_BLT, 1'b0, "BLT: 7==7 -> not taken");
    endtask

    task automatic test_bge();
        test_begin("CORE-003: BGE");

        // rs1 > rs2 (signed) -> taken
        test_branch_cond(32'd10, 32'd5, F3_BGE, 1'b1, "BGE: 10>=5 -> taken");

        // Equal -> taken
        test_branch_cond(32'd5, 32'd5, F3_BGE, 1'b1, "BGE: 5==5 -> taken");

        // rs1 < rs2 (signed) -> not taken
        test_branch_cond(32'd5, 32'd10, F3_BGE, 1'b0, "BGE: 5<10 -> not taken");

        // Negative vs positive -> not taken (-1 < 1)
        test_branch_cond(32'hFFFF_FFFF, 32'd1, F3_BGE, 1'b0, "BGE: -1<1 -> not taken");
    endtask

    task automatic test_bltu();
        test_begin("CORE-003: BLTU");

        // rs1 < rs2 (unsigned) -> taken
        test_branch_cond(32'd5, 32'd10, F3_BLTU, 1'b1, "BLTU: 5<10 -> taken");

        // rs1 > rs2 (unsigned) -> not taken
        test_branch_cond(32'd10, 32'd5, F3_BLTU, 1'b0, "BLTU: 10>5 -> not taken");

        // 0xFFFFFFFF is large unsigned, NOT less than 1
        test_branch_cond(32'hFFFF_FFFF, 32'd1, F3_BLTU, 1'b0, "BLTU: 0xFFFFFFFF>1 -> not taken");

        // 1 < 0xFFFFFFFF unsigned -> taken
        test_branch_cond(32'd1, 32'hFFFF_FFFF, F3_BLTU, 1'b1, "BLTU: 1<0xFFFFFFFF -> taken");
    endtask

    task automatic test_bgeu();
        test_begin("CORE-003: BGEU");

        // rs1 > rs2 (unsigned) -> taken
        test_branch_cond(32'd10, 32'd5, F3_BGEU, 1'b1, "BGEU: 10>=5 -> taken");

        // Equal -> taken
        test_branch_cond(32'd5, 32'd5, F3_BGEU, 1'b1, "BGEU: 5==5 -> taken");

        // rs1 < rs2 (unsigned) -> not taken
        test_branch_cond(32'd5, 32'd10, F3_BGEU, 1'b0, "BGEU: 5<10 -> not taken");

        // 0xFFFFFFFF == 0xFFFFFFFF -> taken
        test_branch_cond(32'hFFFF_FFFF, 32'hFFFF_FFFF, F3_BGEU, 1'b1, "BGEU: 0xFFFFFFFF==0xFFFFFFFF -> taken");
    endtask

    // =========================================================================
    // Additional Tests
    // =========================================================================

    task automatic test_branch_boundary();
        test_begin("Branch Boundary Conditions");

        // Max positive offset: pc=0, imm=0x7FFFFFFF -> target=0x7FFFFFFF
        test_jump_target(
            32'h0000_0000, 32'h7FFF_FFFF, 32'h0000_0000,
            1'b1, 1'b0,
            32'h7FFF_FFFF, "JAL max offset: pc=0 + imm=0x7FFFFFFF"
        );

        // Address wrap: pc=0x80000000, imm=0x80000000 -> wraps to 0x00000000
        test_jump_target(
            32'h8000_0000, 32'h8000_0000, 32'h0000_0000,
            1'b1, 1'b0,
            32'h0000_0000, "JAL wrap: pc=0x80000000 + imm=0x80000000 = 0x0"
        );

        // Branch target with negative offset: pc=0x1000, imm=0xFFFFFFF0 (-16)
        test_jump_target(
            32'h0000_1000, 32'hFFFF_FFF0, 32'h0000_0000,
            1'b1, 1'b0,
            32'h0000_0FF0, "JAL negative offset: pc=0x1000 + (-16) = 0xFF0"
        );
    endtask

    task automatic test_branch_target_alignment();
        test_begin("Branch Target Alignment");

        // JALR clears bit 0: rs1=0x101, imm=1 -> (0x102) & ~1 = 0x102
        is_branch     = 1'b0;
        is_jal        = 1'b0;
        is_jalr       = 1'b1;
        rs2_data      = 32'h0000_0000;
        branch_funct3 = 3'b000;
        pc            = 32'h0000_0000;

        rs1_data  = 32'h0000_0101;
        immediate = 32'h0000_0001;
        #1;
        check_eq(branch_target, 32'h0000_0102, "JALR alignment: (0x101+0x1)&~1 = 0x102");

        // JALR clears bit 0: rs1=0x103, imm=0 -> (0x103) & ~1 = 0x102
        rs1_data  = 32'h0000_0103;
        immediate = 32'h0000_0000;
        #1;
        check_eq(branch_target, 32'h0000_0102, "JALR alignment: (0x103+0x0)&~1 = 0x102");

        // JALR with odd result: rs1=0xFFF, imm=0 -> (0xFFF) & ~1 = 0xFFE
        rs1_data  = 32'h0000_0FFF;
        immediate = 32'h0000_0000;
        #1;
        check_eq(branch_target, 32'h0000_0FFE, "JALR alignment: (0xFFF+0x0)&~1 = 0xFFE");
    endtask

endmodule
