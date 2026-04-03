// =============================================================================
// VSync - Multiplier/Divider Unit Testbench
// =============================================================================
// Comprehensive testbench for the M-Extension multiplier_divider module.
// Tests all 8 operations (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU),
// corner cases (division by zero, signed overflow), boundary values,
// and timing/control signals (done, busy).
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_multiplier_divider;

    import vsync_pkg::*;
    import test_utils::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD = 10;    // 100MHz clock
    localparam RST_CYCLES = 10;    // Reset duration
    localparam DIV_TIMEOUT = 100;  // Max cycles to wait for division done

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
    logic [XLEN-1:0]  operand_a;
    logic [XLEN-1:0]  operand_b;
    logic [XLEN-1:0]  result;
    logic              done;
    logic              busy;

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
        $dumpfile("tb_multiplier_divider.vcd");
        $dumpvars(0, tb_multiplier_divider);
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 500000);
        $display("ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded maximum time");
    end

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    // Apply a single-cycle start pulse for a multiplication operation and
    // check the result on the same cycle (combinational done).
    task automatic apply_mul_op(
        input mext_op_t    t_op,
        input logic [31:0] t_a,
        input logic [31:0] t_b,
        input logic [31:0] t_expected,
        input string       t_msg
    );
        @(posedge clk);
        start     <= 1'b1;
        op        <= t_op;
        operand_a <= t_a;
        operand_b <= t_b;

        // done is combinational with start for mul ops, so check in same cycle
        // after signals propagate
        #1;
        if (done !== 1'b1) begin
            $display("  [FAIL] %s: done not asserted", t_msg);
            test_fail("done not asserted");
        end else begin
            test_pass("done asserted");
        end
        if (busy !== 1'b0) begin
            $display("  [FAIL] %s: busy not deasserted", t_msg);
            test_fail("busy not deasserted");
        end else begin
            test_pass("busy deasserted");
        end
        `ASSERT_EQ(result, t_expected, t_msg);

        @(posedge clk);
        start <= 1'b0;
        @(posedge clk);
    endtask

    // Apply a start pulse for a division operation, wait for done, and
    // check the result. Also returns the number of cycles taken.
    task automatic apply_div_op(
        input  mext_op_t    t_op,
        input  logic [31:0] t_a,
        input  logic [31:0] t_b,
        input  logic [31:0] t_expected,
        input  string       t_msg,
        output int          cycles_taken
    );
        int cnt;
        @(posedge clk);
        start     <= 1'b1;
        op        <= t_op;
        operand_a <= t_a;
        operand_b <= t_b;
        #1;

        // Check if this is an immediate-result case (div-by-zero or overflow)
        if (done === 1'b1) begin
            `ASSERT_EQ(result, t_expected, t_msg);
            cycles_taken = 0;
            @(posedge clk);
            start <= 1'b0;
            @(posedge clk);
        end else begin
            @(posedge clk);
            start <= 1'b0;

            // Wait for done
            cnt = 0;
            while (done !== 1'b1 && cnt < DIV_TIMEOUT) begin
                @(posedge clk);
                cnt++;
            end

            if (cnt >= DIV_TIMEOUT) begin
                $display("  [FAIL] %s: Timeout waiting for done after %0d cycles", t_msg, DIV_TIMEOUT);
                test_fail("Timeout waiting for done");
                cycles_taken = cnt;
            end else begin
                #1;
                `ASSERT_EQ(result, t_expected, t_msg);
                cycles_taken = cnt;

                @(posedge clk);
            end
        end
    endtask

    // Apply a start pulse for a division and only check immediate done
    // (for corner-case tests that complete in one cycle).
    task automatic apply_div_immediate(
        input mext_op_t    t_op,
        input logic [31:0] t_a,
        input logic [31:0] t_b,
        input logic [31:0] t_expected,
        input string       t_msg
    );
        @(posedge clk);
        start     <= 1'b1;
        op        <= t_op;
        operand_a <= t_a;
        operand_b <= t_b;
        #1;

        if (done !== 1'b1) begin
            $display("  [FAIL] %s: done not immediate", t_msg);
            test_fail("done not immediate");
        end else begin
            test_pass("done immediate");
        end
        if (busy !== 1'b0) begin
            $display("  [FAIL] %s: busy not deasserted", t_msg);
            test_fail("busy not deasserted");
        end else begin
            test_pass("busy deasserted");
        end
        `ASSERT_EQ(result, t_expected, t_msg);

        @(posedge clk);
        start <= 1'b0;
        @(posedge clk);
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        // Initialize inputs
        start     = 1'b0;
        op        = MEXT_MUL;
        operand_a = '0;
        operand_b = '0;

        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Test Entry Point
    // =========================================================================
    task automatic test_main();
        test_suite_begin("Multiplier/Divider Unit Tests");

        // Multiplication tests
        test_mul();
        test_mulh();
        test_mulhsu();
        test_mulhu();

        // Division tests
        test_div();
        test_divu();
        test_rem();
        test_remu();

        // Corner cases
        test_div_by_zero();
        test_signed_overflow();

        // Boundary values
        test_boundary_values();

        // Timing and control signals
        test_mul_done_timing();
        test_div_done_timing();
        test_busy_signal();
    endtask

    // =========================================================================
    // MEXT-001: MUL - Lower 32-bit multiplication
    // =========================================================================
    task automatic test_mul();
        test_begin("MUL: basic multiplication");

        // 0 * 0 = 0
        apply_mul_op(MEXT_MUL, 32'h0, 32'h0, 32'h0, "MUL 0*0");

        // 0 * 12345 = 0
        apply_mul_op(MEXT_MUL, 32'h0, 32'd12345, 32'h0, "MUL 0*12345");

        // 12345 * 0 = 0
        apply_mul_op(MEXT_MUL, 32'd12345, 32'h0, 32'h0, "MUL 12345*0");

        // 1 * 0xDEADBEEF = 0xDEADBEEF
        apply_mul_op(MEXT_MUL, 32'h1, 32'hDEADBEEF, 32'hDEADBEEF, "MUL 1*0xDEADBEEF");

        // 0xDEADBEEF * 1 = 0xDEADBEEF
        apply_mul_op(MEXT_MUL, 32'hDEADBEEF, 32'h1, 32'hDEADBEEF, "MUL 0xDEADBEEF*1");

        // 2 * 3 = 6
        apply_mul_op(MEXT_MUL, 32'd2, 32'd3, 32'd6, "MUL 2*3");

        // 7 * 13 = 91
        apply_mul_op(MEXT_MUL, 32'd7, 32'd13, 32'd91, "MUL 7*13");

        // (-1) * 1 = -1 (0xFFFFFFFF)
        apply_mul_op(MEXT_MUL, 32'hFFFFFFFF, 32'h1, 32'hFFFFFFFF, "MUL (-1)*1");

        // (-1) * (-1) = 1 (lower 32 bits)
        apply_mul_op(MEXT_MUL, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'h00000001, "MUL (-1)*(-1)");

        // Large: 0x10000 * 0x10000 = 0x00000000 (overflow, lower 32 bits)
        apply_mul_op(MEXT_MUL, 32'h00010000, 32'h00010000, 32'h00000000, "MUL 0x10000*0x10000 lower");

        // 0x12345678 * 0x2 = 0x2468ACF0
        apply_mul_op(MEXT_MUL, 32'h12345678, 32'h2, 32'h2468ACF0, "MUL 0x12345678*2");
    endtask

    // =========================================================================
    // MEXT-002: MULH - Signed * Signed upper 32 bits
    // =========================================================================
    task automatic test_mulh();
        test_begin("MULH: signed*signed upper 32 bits");

        // Small positive * small positive -> upper = 0
        apply_mul_op(MEXT_MULH, 32'd2, 32'd3, 32'h0, "MULH 2*3 upper");

        // (-1) * (-1) = 1 -> upper = 0
        apply_mul_op(MEXT_MULH, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'h0, "MULH (-1)*(-1) upper");

        // (-1) * 1 = -1 -> upper = 0xFFFFFFFF
        apply_mul_op(MEXT_MULH, 32'hFFFFFFFF, 32'h1, 32'hFFFFFFFF, "MULH (-1)*1 upper");

        // 0x7FFFFFFF * 0x7FFFFFFF = 0x3FFFFFFF_00000001 -> upper = 0x3FFFFFFF
        apply_mul_op(MEXT_MULH, 32'h7FFFFFFF, 32'h7FFFFFFF, 32'h3FFFFFFF, "MULH maxpos*maxpos upper");

        // 0x80000000 * 0x80000000 = signed: (-2^31)*(-2^31) = 2^62 = 0x40000000_00000000
        apply_mul_op(MEXT_MULH, 32'h80000000, 32'h80000000, 32'h40000000, "MULH minint*minint upper");

        // 0x80000000 * 0x7FFFFFFF = (-2^31)*(2^31-1) = -2^62 + 2^31
        // = 0xC0000000_80000000 -> upper = 0xC0000000
        apply_mul_op(MEXT_MULH, 32'h80000000, 32'h7FFFFFFF, 32'hC0000000, "MULH minint*maxpos upper");

        // 0 * anything -> upper = 0
        apply_mul_op(MEXT_MULH, 32'h0, 32'hDEADBEEF, 32'h0, "MULH 0*x upper");
    endtask

    // =========================================================================
    // MEXT-003: MULHSU - Signed * Unsigned upper 32 bits
    // =========================================================================
    task automatic test_mulhsu();
        test_begin("MULHSU: signed*unsigned upper 32 bits");

        // Small positive * small positive -> upper = 0
        apply_mul_op(MEXT_MULHSU, 32'd5, 32'd7, 32'h0, "MULHSU 5*7 upper");

        // (-1) * 1 = signed(-1) * unsigned(1) = -1 -> upper = 0xFFFFFFFF
        apply_mul_op(MEXT_MULHSU, 32'hFFFFFFFF, 32'h1, 32'hFFFFFFFF, "MULHSU (-1)*1 upper");

        // (-1) * 0xFFFFFFFF = signed(-1) * unsigned(0xFFFFFFFF) = -0xFFFFFFFF
        // = 0xFFFFFFFF_00000001 -> upper = 0xFFFFFFFF
        apply_mul_op(MEXT_MULHSU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFF, "MULHSU (-1)*0xFFFFFFFF upper");

        // 1 * 0xFFFFFFFF = 0xFFFFFFFF -> upper = 0
        apply_mul_op(MEXT_MULHSU, 32'h1, 32'hFFFFFFFF, 32'h0, "MULHSU 1*0xFFFFFFFF upper");

        // 0x7FFFFFFF * 0xFFFFFFFF = (2^31-1)*(2^32-1) = 0x7FFFFFFE_80000001
        apply_mul_op(MEXT_MULHSU, 32'h7FFFFFFF, 32'hFFFFFFFF, 32'h7FFFFFFE, "MULHSU maxpos*0xFFFFFFFF upper");

        // 0x80000000 * 0x1 = (-2^31) * 1 = -2^31 -> upper = 0xFFFFFFFF
        apply_mul_op(MEXT_MULHSU, 32'h80000000, 32'h1, 32'hFFFFFFFF, "MULHSU minint*1 upper");

        // 0x80000000 * 0x2 = (-2^31) * 2 = -2^32 -> 0xFFFFFFFF_00000000 -> upper = 0xFFFFFFFF
        apply_mul_op(MEXT_MULHSU, 32'h80000000, 32'h2, 32'hFFFFFFFF, "MULHSU minint*2 upper");

        // 0 * anything -> upper = 0
        apply_mul_op(MEXT_MULHSU, 32'h0, 32'hFFFFFFFF, 32'h0, "MULHSU 0*0xFFFFFFFF upper");
    endtask

    // =========================================================================
    // MEXT-004: MULHU - Unsigned * Unsigned upper 32 bits
    // =========================================================================
    task automatic test_mulhu();
        test_begin("MULHU: unsigned*unsigned upper 32 bits");

        // Small * small -> upper = 0
        apply_mul_op(MEXT_MULHU, 32'd2, 32'd3, 32'h0, "MULHU 2*3 upper");

        // 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE_00000001 -> upper = 0xFFFFFFFE
        apply_mul_op(MEXT_MULHU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'hFFFFFFFE, "MULHU 0xFFFFFFFF*0xFFFFFFFF upper");

        // 0xFFFFFFFF * 1 -> upper = 0
        apply_mul_op(MEXT_MULHU, 32'hFFFFFFFF, 32'h1, 32'h0, "MULHU 0xFFFFFFFF*1 upper");

        // 0x80000000 * 0x2 = 0x1_00000000 -> upper = 1
        apply_mul_op(MEXT_MULHU, 32'h80000000, 32'h2, 32'h1, "MULHU 0x80000000*2 upper");

        // 0x80000000 * 0x80000000 = 0x40000000_00000000 -> upper = 0x40000000
        apply_mul_op(MEXT_MULHU, 32'h80000000, 32'h80000000, 32'h40000000, "MULHU 0x80000000*0x80000000 upper");

        // 0 * anything -> upper = 0
        apply_mul_op(MEXT_MULHU, 32'h0, 32'hFFFFFFFF, 32'h0, "MULHU 0*0xFFFFFFFF upper");

        // 0x10000 * 0x10000 = 0x1_00000000 -> upper = 1
        apply_mul_op(MEXT_MULHU, 32'h00010000, 32'h00010000, 32'h1, "MULHU 0x10000*0x10000 upper");
    endtask

    // =========================================================================
    // MEXT-005: DIV - Signed division
    // =========================================================================
    task automatic test_div();
        int cyc;
        test_begin("DIV: signed division");

        // 6 / 3 = 2
        apply_div_op(MEXT_DIV, 32'd6, 32'd3, 32'd2, "DIV 6/3", cyc);

        // 7 / 2 = 3 (truncates toward zero)
        apply_div_op(MEXT_DIV, 32'd7, 32'd2, 32'd3, "DIV 7/2", cyc);

        // (-6) / 3 = -2
        apply_div_op(MEXT_DIV, -32'sd6, 32'd3, -32'sd2, "DIV (-6)/3", cyc);

        // 6 / (-3) = -2
        apply_div_op(MEXT_DIV, 32'd6, -32'sd3, -32'sd2, "DIV 6/(-3)", cyc);

        // (-6) / (-3) = 2
        apply_div_op(MEXT_DIV, -32'sd6, -32'sd3, 32'd2, "DIV (-6)/(-3)", cyc);

        // (-7) / 2 = -3 (truncates toward zero)
        apply_div_op(MEXT_DIV, -32'sd7, 32'd2, -32'sd3, "DIV (-7)/2", cyc);

        // 1 / 1 = 1
        apply_div_op(MEXT_DIV, 32'd1, 32'd1, 32'd1, "DIV 1/1", cyc);

        // 0 / 5 = 0
        apply_div_op(MEXT_DIV, 32'd0, 32'd5, 32'd0, "DIV 0/5", cyc);

        // 100 / 1 = 100
        apply_div_op(MEXT_DIV, 32'd100, 32'd1, 32'd100, "DIV 100/1", cyc);

        // Large dividend: 0x7FFFFFFF / 1 = 0x7FFFFFFF
        apply_div_op(MEXT_DIV, 32'h7FFFFFFF, 32'd1, 32'h7FFFFFFF, "DIV maxpos/1", cyc);
    endtask

    // =========================================================================
    // MEXT-006: DIVU - Unsigned division
    // =========================================================================
    task automatic test_divu();
        int cyc;
        test_begin("DIVU: unsigned division");

        // 6 / 3 = 2
        apply_div_op(MEXT_DIVU, 32'd6, 32'd3, 32'd2, "DIVU 6/3", cyc);

        // 7 / 2 = 3
        apply_div_op(MEXT_DIVU, 32'd7, 32'd2, 32'd3, "DIVU 7/2", cyc);

        // 0xFFFFFFFF / 1 = 0xFFFFFFFF
        apply_div_op(MEXT_DIVU, 32'hFFFFFFFF, 32'd1, 32'hFFFFFFFF, "DIVU 0xFFFFFFFF/1", cyc);

        // 0xFFFFFFFF / 2 = 0x7FFFFFFF
        apply_div_op(MEXT_DIVU, 32'hFFFFFFFF, 32'd2, 32'h7FFFFFFF, "DIVU 0xFFFFFFFF/2", cyc);

        // 0x80000000 / 2 = 0x40000000
        apply_div_op(MEXT_DIVU, 32'h80000000, 32'd2, 32'h40000000, "DIVU 0x80000000/2", cyc);

        // 0 / 5 = 0
        apply_div_op(MEXT_DIVU, 32'd0, 32'd5, 32'd0, "DIVU 0/5", cyc);

        // 1 / 0xFFFFFFFF = 0 (unsigned: 1 / 4294967295)
        apply_div_op(MEXT_DIVU, 32'd1, 32'hFFFFFFFF, 32'd0, "DIVU 1/0xFFFFFFFF", cyc);
    endtask

    // =========================================================================
    // MEXT-007: REM - Signed remainder
    // =========================================================================
    task automatic test_rem();
        int cyc;
        test_begin("REM: signed remainder");

        // 7 % 3 = 1
        apply_div_op(MEXT_REM, 32'd7, 32'd3, 32'd1, "REM 7%3", cyc);

        // 6 % 3 = 0
        apply_div_op(MEXT_REM, 32'd6, 32'd3, 32'd0, "REM 6%3", cyc);

        // (-7) % 3 = -1 (remainder has sign of dividend)
        apply_div_op(MEXT_REM, -32'sd7, 32'd3, -32'sd1, "REM (-7)%3", cyc);

        // 7 % (-3) = 1 (remainder has sign of dividend)
        apply_div_op(MEXT_REM, 32'd7, -32'sd3, 32'd1, "REM 7%(-3)", cyc);

        // (-7) % (-3) = -1
        apply_div_op(MEXT_REM, -32'sd7, -32'sd3, -32'sd1, "REM (-7)%(-3)", cyc);

        // 0 % 5 = 0
        apply_div_op(MEXT_REM, 32'd0, 32'd5, 32'd0, "REM 0%5", cyc);

        // 5 % 1 = 0
        apply_div_op(MEXT_REM, 32'd5, 32'd1, 32'd0, "REM 5%1", cyc);

        // 1 % 7 = 1
        apply_div_op(MEXT_REM, 32'd1, 32'd7, 32'd1, "REM 1%7", cyc);
    endtask

    // =========================================================================
    // MEXT-008: REMU - Unsigned remainder
    // =========================================================================
    task automatic test_remu();
        int cyc;
        test_begin("REMU: unsigned remainder");

        // 7 % 3 = 1
        apply_div_op(MEXT_REMU, 32'd7, 32'd3, 32'd1, "REMU 7%3", cyc);

        // 6 % 3 = 0
        apply_div_op(MEXT_REMU, 32'd6, 32'd3, 32'd0, "REMU 6%3", cyc);

        // 0xFFFFFFFF % 0x80000000 = 0x7FFFFFFF
        apply_div_op(MEXT_REMU, 32'hFFFFFFFF, 32'h80000000, 32'h7FFFFFFF, "REMU 0xFFFFFFFF%0x80000000", cyc);

        // 0 % 5 = 0
        apply_div_op(MEXT_REMU, 32'd0, 32'd5, 32'd0, "REMU 0%5", cyc);

        // 5 % 1 = 0
        apply_div_op(MEXT_REMU, 32'd5, 32'd1, 32'd0, "REMU 5%1", cyc);

        // 0x80000000 % 3 = 0x80000000 mod 3 = 2147483648 mod 3 = 2
        apply_div_op(MEXT_REMU, 32'h80000000, 32'd3, 32'd2, "REMU 0x80000000%3", cyc);

        // 1 % 0xFFFFFFFF = 1
        apply_div_op(MEXT_REMU, 32'd1, 32'hFFFFFFFF, 32'd1, "REMU 1%0xFFFFFFFF", cyc);
    endtask

    // =========================================================================
    // Division by zero (all 4 div/rem ops)
    // =========================================================================
    task automatic test_div_by_zero();
        test_begin("Division by zero corner cases");

        // DIV x / 0 = 0xFFFFFFFF (all ones)
        apply_div_immediate(MEXT_DIV, 32'd42, 32'd0, 32'hFFFFFFFF, "DIV 42/0");
        apply_div_immediate(MEXT_DIV, 32'h0, 32'd0, 32'hFFFFFFFF, "DIV 0/0");
        apply_div_immediate(MEXT_DIV, 32'h80000000, 32'd0, 32'hFFFFFFFF, "DIV minint/0");
        apply_div_immediate(MEXT_DIV, 32'hFFFFFFFF, 32'd0, 32'hFFFFFFFF, "DIV (-1)/0");

        // DIVU x / 0 = 0xFFFFFFFF (all ones)
        apply_div_immediate(MEXT_DIVU, 32'd42, 32'd0, 32'hFFFFFFFF, "DIVU 42/0");
        apply_div_immediate(MEXT_DIVU, 32'hFFFFFFFF, 32'd0, 32'hFFFFFFFF, "DIVU 0xFFFFFFFF/0");

        // REM x % 0 = x (dividend)
        apply_div_immediate(MEXT_REM, 32'd42, 32'd0, 32'd42, "REM 42%0");
        apply_div_immediate(MEXT_REM, 32'h80000000, 32'd0, 32'h80000000, "REM minint%0");
        apply_div_immediate(MEXT_REM, 32'h0, 32'd0, 32'h0, "REM 0%0");
        apply_div_immediate(MEXT_REM, 32'hFFFFFFFF, 32'd0, 32'hFFFFFFFF, "REM (-1)%0");

        // REMU x % 0 = x (dividend)
        apply_div_immediate(MEXT_REMU, 32'd42, 32'd0, 32'd42, "REMU 42%0");
        apply_div_immediate(MEXT_REMU, 32'hFFFFFFFF, 32'd0, 32'hFFFFFFFF, "REMU 0xFFFFFFFF%0");
    endtask

    // =========================================================================
    // Signed overflow (0x80000000 / -1) for DIV and REM
    // =========================================================================
    task automatic test_signed_overflow();
        test_begin("Signed overflow: 0x80000000 / -1");

        // DIV: 0x80000000 / 0xFFFFFFFF = 0x80000000 (MIN_INT, per RISC-V spec)
        apply_div_immediate(MEXT_DIV, 32'h80000000, 32'hFFFFFFFF, 32'h80000000, "DIV overflow: minint/(-1)");

        // REM: 0x80000000 % 0xFFFFFFFF = 0 (per RISC-V spec)
        apply_div_immediate(MEXT_REM, 32'h80000000, 32'hFFFFFFFF, 32'h0, "REM overflow: minint%(-1)");
    endtask

    // =========================================================================
    // Boundary values
    // =========================================================================
    task automatic test_boundary_values();
        int cyc;
        test_begin("Boundary value tests");

        // --- MUL boundary ---
        // 0x7FFFFFFF * 0x7FFFFFFF lower = 0x00000001
        apply_mul_op(MEXT_MUL, 32'h7FFFFFFF, 32'h7FFFFFFF, 32'h00000001, "MUL maxpos*maxpos lower");

        // 0x80000000 * 0x80000000 lower = 0x00000000
        apply_mul_op(MEXT_MUL, 32'h80000000, 32'h80000000, 32'h00000000, "MUL minint*minint lower");

        // 0xFFFFFFFF * 0xFFFFFFFF lower = 0x00000001
        apply_mul_op(MEXT_MUL, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'h00000001, "MUL allones*allones lower");

        // 0x7FFFFFFF * 2 lower = 0xFFFFFFFE
        apply_mul_op(MEXT_MUL, 32'h7FFFFFFF, 32'h2, 32'hFFFFFFFE, "MUL maxpos*2 lower");

        // --- DIV boundary ---
        // 0x7FFFFFFF / 0x7FFFFFFF = 1
        apply_div_op(MEXT_DIV, 32'h7FFFFFFF, 32'h7FFFFFFF, 32'd1, "DIV maxpos/maxpos", cyc);

        // 0x7FFFFFFF / 1 = 0x7FFFFFFF
        apply_div_op(MEXT_DIV, 32'h7FFFFFFF, 32'd1, 32'h7FFFFFFF, "DIV maxpos/1", cyc);

        // 0x7FFFFFFF / (-1) = 0x80000001 (-MAX_POS)
        apply_div_op(MEXT_DIV, 32'h7FFFFFFF, 32'hFFFFFFFF, 32'h80000001, "DIV maxpos/(-1)", cyc);

        // 1 / 0x7FFFFFFF = 0
        apply_div_op(MEXT_DIV, 32'd1, 32'h7FFFFFFF, 32'd0, "DIV 1/maxpos", cyc);

        // --- DIVU boundary ---
        // 0xFFFFFFFF / 0xFFFFFFFF = 1
        apply_div_op(MEXT_DIVU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd1, "DIVU allones/allones", cyc);

        // 0xFFFFFFFF / 1 = 0xFFFFFFFF
        apply_div_op(MEXT_DIVU, 32'hFFFFFFFF, 32'd1, 32'hFFFFFFFF, "DIVU allones/1", cyc);

        // --- REM boundary ---
        // 0x7FFFFFFF % 0x7FFFFFFF = 0
        apply_div_op(MEXT_REM, 32'h7FFFFFFF, 32'h7FFFFFFF, 32'd0, "REM maxpos%maxpos", cyc);

        // 1 % 0x7FFFFFFF = 1
        apply_div_op(MEXT_REM, 32'd1, 32'h7FFFFFFF, 32'd1, "REM 1%maxpos", cyc);

        // --- REMU boundary ---
        // 0xFFFFFFFF % 0xFFFFFFFF = 0
        apply_div_op(MEXT_REMU, 32'hFFFFFFFF, 32'hFFFFFFFF, 32'd0, "REMU allones%allones", cyc);

        // 0xFFFFFFFE % 0xFFFFFFFF = 0xFFFFFFFE
        apply_div_op(MEXT_REMU, 32'hFFFFFFFE, 32'hFFFFFFFF, 32'hFFFFFFFE, "REMU (allones-1)%allones", cyc);
    endtask

    // =========================================================================
    // Verify MUL done timing: done must be high on the same cycle as start
    // =========================================================================
    task automatic test_mul_done_timing();
        test_begin("MUL done timing: single-cycle");

        // Drive start and check done in the same delta
        @(posedge clk);
        start     <= 1'b1;
        op        <= MEXT_MUL;
        operand_a <= 32'd5;
        operand_b <= 32'd7;

        #1;
        `ASSERT_TRUE(done === 1'b1, "MUL done high same cycle as start");
        `ASSERT_TRUE(busy === 1'b0, "MUL busy low during mul");
        `ASSERT_EQ(result, 32'd35, "MUL 5*7=35 timing check");

        @(posedge clk);
        start <= 1'b0;
        #1;
        // After deasserting start, done should go low
        `ASSERT_TRUE(done === 1'b0, "MUL done low after start deasserted");
        @(posedge clk);
    endtask

    // =========================================================================
    // Verify DIV done timing: done after ~32+ cycles (multi-cycle)
    // =========================================================================
    task automatic test_div_done_timing();
        int cycle_count;
        test_begin("DIV done timing: multi-cycle");

        // Issue a normal division (not corner case)
        @(posedge clk);
        start     <= 1'b1;
        op        <= MEXT_DIV;
        operand_a <= 32'd100;
        operand_b <= 32'd7;

        // done should NOT be asserted immediately for a normal division
        #1;
        `ASSERT_TRUE(done === 1'b0, "DIV done not immediate for normal op");

        @(posedge clk);
        start <= 1'b0;

        // Count cycles until done
        cycle_count = 0;
        while (done !== 1'b1 && cycle_count < DIV_TIMEOUT) begin
            @(posedge clk);
            cycle_count++;
        end

        `ASSERT_TRUE(done === 1'b1, "DIV done eventually asserts");
        if (cycle_count > 1) begin
            $display("  [PASS] DIV takes multiple cycles (%0d)", cycle_count);
            test_pass("DIV takes multiple cycles");
        end else begin
            $display("  [FAIL] DIV took only %0d cycles", cycle_count);
            test_fail("DIV should take multiple cycles");
        end

        // Verify result: 100 / 7 = 14
        #1;
        `ASSERT_EQ(result, 32'd14, "DIV 100/7=14 timing check");

        // done should be a single-cycle pulse (high during DIV_DONE state)
        @(posedge clk);
        #1;
        `ASSERT_TRUE(done === 1'b0, "DIV done deasserts after one cycle");

        @(posedge clk);
    endtask

    // =========================================================================
    // Verify busy signal: high during DIV_CALC, low otherwise
    // =========================================================================
    task automatic test_busy_signal();
        int busy_count;
        test_begin("Busy signal during division");

        // --- Verify busy is LOW for multiplication ---
        @(posedge clk);
        start     <= 1'b1;
        op        <= MEXT_MUL;
        operand_a <= 32'd3;
        operand_b <= 32'd4;
        #1;
        `ASSERT_TRUE(busy === 1'b0, "busy low during MUL");
        @(posedge clk);
        start <= 1'b0;
        @(posedge clk);

        // --- Verify busy is LOW for div-by-zero (immediate) ---
        @(posedge clk);
        start     <= 1'b1;
        op        <= MEXT_DIV;
        operand_a <= 32'd10;
        operand_b <= 32'd0;
        #1;
        `ASSERT_TRUE(busy === 1'b0, "busy low during div-by-zero");
        @(posedge clk);
        start <= 1'b0;
        @(posedge clk);

        // --- Verify busy is LOW for signed overflow (immediate) ---
        @(posedge clk);
        start     <= 1'b1;
        op        <= MEXT_DIV;
        operand_a <= 32'h80000000;
        operand_b <= 32'hFFFFFFFF;
        #1;
        `ASSERT_TRUE(busy === 1'b0, "busy low during signed overflow");
        @(posedge clk);
        start <= 1'b0;
        @(posedge clk);

        // --- Verify busy goes HIGH during normal division ---
        @(posedge clk);
        start     <= 1'b1;
        op        <= MEXT_DIVU;
        operand_a <= 32'd1000;
        operand_b <= 32'd7;

        #1;
        // On start cycle, busy should not be high yet (state is IDLE, start is
        // driving the transition to CALC on next clock edge)
        `ASSERT_TRUE(done === 1'b0, "DIVU normal: done low on start");

        @(posedge clk);
        start <= 1'b0;

        // Now the divider should be in CALC state and busy should be HIGH
        #1;
        `ASSERT_TRUE(busy === 1'b1, "busy HIGH during DIV_CALC");

        // Count busy cycles
        busy_count = 0;
        while (busy === 1'b1 && busy_count < DIV_TIMEOUT) begin
            @(posedge clk);
            busy_count++;
        end

        $display("  [INFO] Divider was busy for %0d cycles", busy_count);
        `ASSERT_TRUE(busy_count > 0, "busy was high for at least 1 cycle");

        // After busy goes low, done should be or become high
        // (we may land on DIV_DONE or just past it)
        #1;
        if (done === 1'b1) begin
            `ASSERT_EQ(result, 32'd142, "DIVU 1000/7=142 busy check");
        end else begin
            // busy went low because we transitioned to DONE; wait for done
            @(posedge clk);
            #1;
            if (done === 1'b1)
                `ASSERT_EQ(result, 32'd142, "DIVU 1000/7=142 busy check (delayed)");
            else
                test_fail("done never asserted after busy went low");
        end

        // Wait for done to deassert
        @(posedge clk);
        @(posedge clk);
    endtask

endmodule
