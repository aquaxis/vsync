// =============================================================================
// VSync - RV32M Multiply/Divide Extension Test Bench
// =============================================================================
// Test IDs: MEXT-001 ~ MEXT-008
// - MEXT-001: MUL (lower 32-bit multiplication)
// - MEXT-002: MULH (signed x signed, upper 32 bits)
// - MEXT-003: MULHSU (signed x unsigned, upper 32 bits)
// - MEXT-004: MULHU (unsigned x unsigned, upper 32 bits)
// - MEXT-005: DIV (signed division)
// - MEXT-006: DIVU (unsigned division)
// - MEXT-007: REM (signed remainder)
// - MEXT-008: REMU (unsigned remainder)
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_rv32m;

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

    // DUT interface
    logic             start;
    mext_op_t         op;
    logic [31:0]      operand_a;
    logic [31:0]      operand_b;
    logic [31:0]      result;
    logic             done;
    logic             busy;

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
    multiplier_divider u_dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (start),
        .op        (op),
        .operand_a (operand_a),
        .operand_b (operand_b),
        .result    (result),
        .done      (done),
        .busy      (busy)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_rv32m.vcd");
        $dumpvars(0, tb_rv32m);
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 500000);  // Longer timeout for multi-cycle divide
        $display("ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded maximum time");
    end

    // =========================================================================
    // Helper: apply operands and start, wait for done
    // =========================================================================
    // For multiply ops (single-cycle): done is asserted combinationally when
    //   start=1 and op is a mul type. Result is valid while start is held.
    // For div-by-zero / overflow: same as multiply (immediate result).
    // For normal division: multi-cycle. Deassert start, then wait for done.
    // =========================================================================
    task automatic do_op(
        input mext_op_t    op_val,
        input logic [31:0] a,
        input logic [31:0] b
    );
        operand_a = a;
        operand_b = b;
        op        = op_val;
        start     = 1'b1;
        @(posedge clk);
        #1;
        // For mul/immediate-div: done is already 1 (combinational on start)
        // For normal division: done is 0, need to wait
        if (!done) begin
            start = 1'b0;
            begin : wait_div
                int cnt = 0;
                while (!done && cnt < 50) begin
                    @(posedge clk);
                    #1;
                    cnt++;
                end
                if (!done)
                    $display("  [ERROR] Operation timed out after %0d cycles", cnt);
            end
        end
        // Result is now valid:
        //   - mul: start still 1, result driven combinationally
        //   - div: div_state==DIV_DONE, result driven from quotient/remainder
    endtask

    // =========================================================================
    // Helper: clean up after checking result
    // =========================================================================
    task automatic cleanup();
        start     = 1'b0;
        @(posedge clk);
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        // Initialize signals
        start     = 1'b0;
        operand_a = '0;
        operand_b = '0;
        op        = MEXT_MUL;

        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("RV32M Multiply/Divide Extension Tests");

        // === MEXT-001: MUL ===
        test_mul();

        // === MEXT-002: MULH ===
        test_mulh();

        // === MEXT-003: MULHSU ===
        test_mulhsu();

        // === MEXT-004: MULHU ===
        test_mulhu();

        // === MEXT-005: DIV ===
        test_div();

        // === MEXT-006: DIVU ===
        test_divu();

        // === MEXT-007: REM ===
        test_rem();

        // === MEXT-008: REMU ===
        test_remu();

        // === Boundary Value Tests ===
        test_multiply_boundary();
        test_divide_boundary();

    endtask

    // =========================================================================
    // MEXT-001: MUL
    // =========================================================================

    task automatic test_mul();
        test_begin("MEXT-001: MUL (lower 32-bit product)");

        // 2 * 3 = 6
        do_op(MEXT_MUL, 32'd2, 32'd3);
        check_eq(result, 32'd6, "2 * 3 = 6");
        cleanup();

        // (-1) * 1 = -1 (0xFFFFFFFF)
        do_op(MEXT_MUL, 32'hFFFFFFFF, 32'd1);
        check_eq(result, 32'hFFFFFFFF, "(-1) * 1 = 0xFFFFFFFF");
        cleanup();

        // 0 * 5 = 0
        do_op(MEXT_MUL, 32'd0, 32'd5);
        check_eq(result, 32'd0, "0 * 5 = 0");
        cleanup();

        // 0x10000 * 0x10000 = 0x100000000 -> lower 32 = 0
        do_op(MEXT_MUL, 32'h00010000, 32'h00010000);
        check_eq(result, 32'h00000000, "0x10000 * 0x10000 = 0x00000000 (lower 32 bits)");
        cleanup();
    endtask

    // =========================================================================
    // MEXT-002: MULH
    // =========================================================================

    task automatic test_mulh();
        test_begin("MEXT-002: MULH (signed*signed upper 32 bits)");

        // 0x7FFFFFFF * 0x7FFFFFFF -> upper = 0x3FFFFFFF
        do_op(MEXT_MULH, 32'h7FFFFFFF, 32'h7FFFFFFF);
        check_eq(result, 32'h3FFFFFFF, "0x7FFFFFFF * 0x7FFFFFFF upper = 0x3FFFFFFF");
        cleanup();

        // (-1) * (-1) = 1 -> upper = 0
        do_op(MEXT_MULH, 32'hFFFFFFFF, 32'hFFFFFFFF);
        check_eq(result, 32'h00000000, "(-1) * (-1) upper = 0");
        cleanup();

        // 0x80000000 * 0x80000000: (-2^31)^2 = 2^62 -> upper = 0x40000000
        do_op(MEXT_MULH, 32'h80000000, 32'h80000000);
        check_eq(result, 32'h40000000, "0x80000000 * 0x80000000 upper = 0x40000000");
        cleanup();
    endtask

    // =========================================================================
    // MEXT-003: MULHSU
    // =========================================================================

    task automatic test_mulhsu();
        test_begin("MEXT-003: MULHSU (signed*unsigned upper 32 bits)");

        // (-1)(signed) * 1(unsigned) -> -1 full 64-bit -> upper = 0xFFFFFFFF
        do_op(MEXT_MULHSU, 32'hFFFFFFFF, 32'd1);
        check_eq(result, 32'hFFFFFFFF, "(-1) * 1u upper = 0xFFFFFFFF");
        cleanup();

        // 1(signed) * 1(unsigned) -> 1 -> upper = 0
        do_op(MEXT_MULHSU, 32'd1, 32'd1);
        check_eq(result, 32'h00000000, "1 * 1u upper = 0");
        cleanup();
    endtask

    // =========================================================================
    // MEXT-004: MULHU
    // =========================================================================

    task automatic test_mulhu();
        test_begin("MEXT-004: MULHU (unsigned*unsigned upper 32 bits)");

        // 0xFFFFFFFF * 0xFFFFFFFF -> upper = 0xFFFFFFFE
        do_op(MEXT_MULHU, 32'hFFFFFFFF, 32'hFFFFFFFF);
        check_eq(result, 32'hFFFFFFFE, "0xFFFFFFFF * 0xFFFFFFFF upper = 0xFFFFFFFE");
        cleanup();

        // small * small -> upper = 0
        do_op(MEXT_MULHU, 32'd100, 32'd100);
        check_eq(result, 32'h00000000, "100 * 100 upper = 0");
        cleanup();
    endtask

    // =========================================================================
    // MEXT-005: DIV
    // =========================================================================

    task automatic test_div();
        test_begin("MEXT-005: DIV (signed division)");

        // 6 / 3 = 2
        do_op(MEXT_DIV, 32'd6, 32'd3);
        check_eq(result, 32'd2, "6 / 3 = 2");
        cleanup();

        // (-6) / 3 = -2 = 0xFFFFFFFE
        do_op(MEXT_DIV, 32'hFFFFFFFA, 32'd3);
        check_eq(result, 32'hFFFFFFFE, "(-6) / 3 = -2");
        cleanup();

        // 6 / (-3) = -2 = 0xFFFFFFFE
        do_op(MEXT_DIV, 32'd6, 32'hFFFFFFFD);
        check_eq(result, 32'hFFFFFFFE, "6 / (-3) = -2");
        cleanup();

        // (-6) / (-3) = 2
        do_op(MEXT_DIV, 32'hFFFFFFFA, 32'hFFFFFFFD);
        check_eq(result, 32'd2, "(-6) / (-3) = 2");
        cleanup();

        // Division by zero: 7 / 0 -> 0xFFFFFFFF
        do_op(MEXT_DIV, 32'd7, 32'd0);
        check_eq(result, 32'hFFFFFFFF, "7 / 0 = 0xFFFFFFFF (div by zero)");
        cleanup();

        // Overflow: 0x80000000 / (-1) -> 0x80000000
        do_op(MEXT_DIV, 32'h80000000, 32'hFFFFFFFF);
        check_eq(result, 32'h80000000, "0x80000000 / (-1) = 0x80000000 (overflow)");
        cleanup();
    endtask

    // =========================================================================
    // MEXT-006: DIVU
    // =========================================================================

    task automatic test_divu();
        test_begin("MEXT-006: DIVU (unsigned division)");

        // 6 / 3 = 2
        do_op(MEXT_DIVU, 32'd6, 32'd3);
        check_eq(result, 32'd2, "6u / 3u = 2");
        cleanup();

        // 0xFFFFFFFF / 2 = 0x7FFFFFFF
        do_op(MEXT_DIVU, 32'hFFFFFFFF, 32'd2);
        check_eq(result, 32'h7FFFFFFF, "0xFFFFFFFF / 2 = 0x7FFFFFFF");
        cleanup();

        // Division by zero: 7 / 0 -> 0xFFFFFFFF
        do_op(MEXT_DIVU, 32'd7, 32'd0);
        check_eq(result, 32'hFFFFFFFF, "7u / 0 = 0xFFFFFFFF (div by zero)");
        cleanup();
    endtask

    // =========================================================================
    // MEXT-007: REM
    // =========================================================================

    task automatic test_rem();
        test_begin("MEXT-007: REM (signed remainder)");

        // 7 % 3 = 1
        do_op(MEXT_REM, 32'd7, 32'd3);
        check_eq(result, 32'd1, "7 %% 3 = 1");
        cleanup();

        // (-7) % 3 = -1 = 0xFFFFFFFF
        do_op(MEXT_REM, 32'hFFFFFFF9, 32'd3);
        check_eq(result, 32'hFFFFFFFF, "(-7) %% 3 = -1");
        cleanup();

        // 7 % (-3) = 1
        do_op(MEXT_REM, 32'd7, 32'hFFFFFFFD);
        check_eq(result, 32'd1, "7 %% (-3) = 1");
        cleanup();

        // Remainder by zero: 7 % 0 -> dividend (7)
        do_op(MEXT_REM, 32'd7, 32'd0);
        check_eq(result, 32'd7, "7 %% 0 = 7 (rem by zero)");
        cleanup();

        // Overflow: 0x80000000 % (-1) = 0
        do_op(MEXT_REM, 32'h80000000, 32'hFFFFFFFF);
        check_eq(result, 32'd0, "0x80000000 %% (-1) = 0 (overflow)");
        cleanup();
    endtask

    // =========================================================================
    // MEXT-008: REMU
    // =========================================================================

    task automatic test_remu();
        test_begin("MEXT-008: REMU (unsigned remainder)");

        // 7 % 3 = 1
        do_op(MEXT_REMU, 32'd7, 32'd3);
        check_eq(result, 32'd1, "7u %% 3u = 1");
        cleanup();

        // Remainder by zero: 7 % 0 -> dividend (7)
        do_op(MEXT_REMU, 32'd7, 32'd0);
        check_eq(result, 32'd7, "7u %% 0 = 7 (rem by zero)");
        cleanup();
    endtask

    // =========================================================================
    // Boundary Value Tests
    // =========================================================================

    task automatic test_multiply_boundary();
        test_begin("Multiply Boundary Values");

        // 0 * anything = 0
        do_op(MEXT_MUL, 32'd0, 32'hDEADBEEF);
        check_eq(result, 32'd0, "0 * anything = 0");
        cleanup();

        // 1 * anything = anything
        do_op(MEXT_MUL, 32'd1, 32'hCAFEBABE);
        check_eq(result, 32'hCAFEBABE, "1 * x = x");
        cleanup();

        // (-1) * x = -x (lower 32 bits)
        do_op(MEXT_MUL, 32'hFFFFFFFF, 32'd42);
        check_eq(result, 32'hFFFFFFD6, "(-1) * 42 = -42 (0xFFFFFFD6)");
        cleanup();
    endtask

    task automatic test_divide_boundary();
        test_begin("Divide Boundary Values");

        // x / 1 = x
        do_op(MEXT_DIV, 32'd42, 32'd1);
        check_eq(result, 32'd42, "42 / 1 = 42");
        cleanup();

        // x / (-1) = -x
        do_op(MEXT_DIV, 32'd42, 32'hFFFFFFFF);
        check_eq(result, 32'hFFFFFFD6, "42 / (-1) = -42 (0xFFFFFFD6)");
        cleanup();
    endtask

endmodule
