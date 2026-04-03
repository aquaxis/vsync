// =============================================================================
// VSync - Core-Local Interruptor (CLINT) Test Bench
// =============================================================================
// Test IDs: INT-010 through INT-015
// - INT-010: mtime auto-increment
// - INT-011: mtimecmp compare and timer_irq generation
// - INT-012: timer_irq assertion/deassertion timing
// - INT-013: msip write and sw_irq generation
// - INT-014: mtime read/write via APB
// - INT-015: 64-bit mtime/mtimecmp upper-half register access
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_clint;

    import test_utils::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD   = 10;    // 100MHz clock
    localparam RST_CYCLES   = 10;    // Reset duration
    localparam TIMER_WIDTH  = 64;

    // Address map constants (matching DUT)
    localparam logic [15:0] ADDR_MSIP        = 16'h0000;
    localparam logic [15:0] ADDR_MTIMECMP_LO = 16'h4000;
    localparam logic [15:0] ADDR_MTIMECMP_HI = 16'h4004;
    localparam logic [15:0] ADDR_MTIME_LO    = 16'hBFF8;
    localparam logic [15:0] ADDR_MTIME_HI    = 16'hBFFC;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // APB signals
    logic        apb_psel;
    logic        apb_penable;
    logic        apb_pwrite;
    logic [15:0] apb_paddr;
    logic [31:0] apb_pwdata;
    logic [31:0] apb_prdata;
    logic        apb_pready;
    logic        apb_pslverr;

    // Interrupt outputs
    logic        timer_irq;
    logic        sw_irq;

    // Read data capture
    logic [31:0] rd_data;

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
    clint #(
        .TIMER_WIDTH (TIMER_WIDTH)
    ) u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .apb_psel    (apb_psel),
        .apb_penable (apb_penable),
        .apb_pwrite  (apb_pwrite),
        .apb_paddr   (apb_paddr),
        .apb_pwdata  (apb_pwdata),
        .apb_prdata  (apb_prdata),
        .apb_pready  (apb_pready),
        .apb_pslverr (apb_pslverr),
        .timer_irq   (timer_irq),
        .sw_irq      (sw_irq)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_clint.vcd");
        $dumpvars(0, tb_clint);
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 100000);
        $display("ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded maximum time");
    end

    // =========================================================================
    // APB Helper Tasks
    // =========================================================================

    // APB write transaction
    task automatic apb_write(input logic [15:0] addr, input logic [31:0] data);
        // Setup phase
        @(posedge clk);
        apb_psel    <= 1'b1;
        apb_penable <= 1'b0;
        apb_pwrite  <= 1'b1;
        apb_paddr   <= addr;
        apb_pwdata  <= data;

        // Access phase
        @(posedge clk);
        apb_penable <= 1'b1;

        // Wait for ready
        while (!apb_pready) @(posedge clk);

        // Return to idle
        apb_psel    <= 1'b0;
        apb_penable <= 1'b0;
        apb_pwrite  <= 1'b0;
    endtask

    // APB read transaction
    task automatic apb_read(input logic [15:0] addr, output logic [31:0] data);
        // Setup phase
        @(posedge clk);
        apb_psel    <= 1'b1;
        apb_penable <= 1'b0;
        apb_pwrite  <= 1'b0;
        apb_paddr   <= addr;

        // Access phase
        @(posedge clk);
        apb_penable <= 1'b1;

        // Wait for ready
        while (!apb_pready) @(posedge clk);
        data = apb_prdata;

        // Return to idle
        apb_psel    <= 1'b0;
        apb_penable <= 1'b0;
    endtask

    // =========================================================================
    // Signal Initialization
    // =========================================================================
    initial begin
        apb_psel    = 1'b0;
        apb_penable = 1'b0;
        apb_pwrite  = 1'b0;
        apb_paddr   = 16'h0;
        apb_pwdata  = 32'h0;
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
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("CLINT Interrupt Controller Tests");

        // INT-010: mtime auto-increment
        test_mtime_increment();

        // INT-011: mtimecmp compare and timer_irq
        test_mtimecmp_timer_irq();

        // INT-012: timer_irq timing and deassertion
        test_timer_irq_timing();

        // INT-013: msip write and sw_irq
        test_msip_sw_irq();

        // INT-014: mtime read/write via APB
        test_mtime_read_write();

        // INT-015: 64-bit upper-half register access
        test_64bit_registers();

    endtask

    // =========================================================================
    // INT-010: mtime Auto-Increment
    // =========================================================================
    task automatic test_mtime_increment();
        logic [31:0] mtime_val1;
        logic [31:0] mtime_val2;

        test_begin("INT-010: mtime Auto-Increment");

        // Write mtime to a known value
        apb_write(ADDR_MTIME_LO, 32'h0000_0000);
        apb_write(ADDR_MTIME_HI, 32'h0000_0000);

        // Wait a few cycles for the counter to increment
        repeat (10) @(posedge clk);

        // Read mtime low
        apb_read(ADDR_MTIME_LO, mtime_val1);
        check(mtime_val1 > 32'h0, "mtime incremented from zero");

        // Wait more cycles and read again
        repeat (10) @(posedge clk);
        apb_read(ADDR_MTIME_LO, mtime_val2);
        check(mtime_val2 > mtime_val1, "mtime continues incrementing");

        // Verify the increment rate is approximately 1 per clock
        // (the exact value depends on APB transaction timing overhead)
        $display("  [INFO] mtime_val1 = %0d, mtime_val2 = %0d, diff = %0d",
                 mtime_val1, mtime_val2, mtime_val2 - mtime_val1);
        check(mtime_val2 - mtime_val1 >= 10,
              "mtime increments at least 10 in 10 cycles");
    endtask

    // =========================================================================
    // INT-011: mtimecmp Compare and timer_irq Generation
    // =========================================================================
    task automatic test_mtimecmp_timer_irq();
        test_begin("INT-011: mtimecmp Compare and timer_irq");

        // Reset mtime to 0
        apb_write(ADDR_MTIME_LO, 32'h0);
        apb_write(ADDR_MTIME_HI, 32'h0);

        // Set mtimecmp to a large value (no interrupt expected)
        apb_write(ADDR_MTIMECMP_HI, 32'hFFFF_FFFF);
        apb_write(ADDR_MTIMECMP_LO, 32'hFFFF_FFFF);
        repeat (2) @(posedge clk);
        check(timer_irq == 1'b0, "No timer_irq with max mtimecmp");

        // Read back mtimecmp
        apb_read(ADDR_MTIMECMP_LO, rd_data);
        check_eq(rd_data, 32'hFFFF_FFFF, "mtimecmp_lo readback");
        apb_read(ADDR_MTIMECMP_HI, rd_data);
        check_eq(rd_data, 32'hFFFF_FFFF, "mtimecmp_hi readback");

        // Set mtimecmp to a small value that mtime will reach soon
        apb_write(ADDR_MTIME_LO, 32'h0);
        apb_write(ADDR_MTIME_HI, 32'h0);
        apb_write(ADDR_MTIMECMP_HI, 32'h0);
        apb_write(ADDR_MTIMECMP_LO, 32'h0000_0020);  // Compare at 32

        // Wait until timer_irq asserts
        `WAIT_FOR(timer_irq == 1'b1, 200, "timer_irq asserted when mtime >= mtimecmp")

        check(timer_irq == 1'b1, "timer_irq is high after mtime >= mtimecmp");

        // Set mtimecmp far away to deassert timer_irq
        apb_write(ADDR_MTIMECMP_HI, 32'hFFFF_FFFF);
        apb_write(ADDR_MTIMECMP_LO, 32'hFFFF_FFFF);
        repeat (2) @(posedge clk);
        check(timer_irq == 1'b0, "timer_irq deasserted after raising mtimecmp");
    endtask

    // =========================================================================
    // INT-012: timer_irq Assertion/Deassertion Timing
    // =========================================================================
    task automatic test_timer_irq_timing();
        logic [31:0] mtime_at_irq;

        test_begin("INT-012: timer_irq Timing");

        // Reset mtime
        apb_write(ADDR_MTIME_LO, 32'h0);
        apb_write(ADDR_MTIME_HI, 32'h0);

        // Set mtimecmp to exact value
        apb_write(ADDR_MTIMECMP_HI, 32'h0);
        apb_write(ADDR_MTIMECMP_LO, 32'h0000_0040);  // Compare at 64

        // timer_irq should be low now (mtime < 64)
        repeat (2) @(posedge clk);
        check(timer_irq == 1'b0, "timer_irq low before mtime reaches mtimecmp");

        // Wait for timer_irq to assert
        `WAIT_FOR(timer_irq == 1'b1, 500, "Waiting for timer_irq")

        // Read mtime at the moment of interrupt
        apb_read(ADDR_MTIME_LO, mtime_at_irq);
        $display("  [INFO] mtime at timer_irq assertion: %0d (target: 64)", mtime_at_irq);
        check(mtime_at_irq >= 32'h40, "mtime >= mtimecmp when timer_irq asserts");

        // timer_irq should remain asserted as long as mtime >= mtimecmp
        repeat (10) @(posedge clk);
        check(timer_irq == 1'b1, "timer_irq remains asserted (level-sensitive)");

        // Writing a new (larger) mtimecmp should clear the interrupt
        apb_write(ADDR_MTIMECMP_LO, 32'hFFFF_FF00);
        apb_write(ADDR_MTIMECMP_HI, 32'hFFFF_FFFF);
        repeat (2) @(posedge clk);
        check(timer_irq == 1'b0, "timer_irq cleared by writing larger mtimecmp");

        // Setting mtimecmp to 0 should immediately trigger (mtime > 0)
        apb_write(ADDR_MTIMECMP_LO, 32'h0);
        apb_write(ADDR_MTIMECMP_HI, 32'h0);
        repeat (2) @(posedge clk);
        check(timer_irq == 1'b1, "timer_irq asserts immediately with mtimecmp=0");

        // Clean up
        apb_write(ADDR_MTIMECMP_HI, 32'hFFFF_FFFF);
        apb_write(ADDR_MTIMECMP_LO, 32'hFFFF_FFFF);
    endtask

    // =========================================================================
    // INT-013: msip Write and sw_irq Generation
    // =========================================================================
    task automatic test_msip_sw_irq();
        test_begin("INT-013: msip Write and sw_irq");

        // Initially sw_irq should be low (msip reset to 0)
        apb_read(ADDR_MSIP, rd_data);
        check_eq(rd_data, 32'h0, "msip register is 0 after reset");
        check(sw_irq == 1'b0, "sw_irq is low initially");

        // Write msip = 1
        apb_write(ADDR_MSIP, 32'h1);
        repeat (2) @(posedge clk);

        apb_read(ADDR_MSIP, rd_data);
        check_eq(rd_data, 32'h1, "msip readback after write 1");
        check(sw_irq == 1'b1, "sw_irq asserted when msip=1");

        // Write msip = 0
        apb_write(ADDR_MSIP, 32'h0);
        repeat (2) @(posedge clk);

        apb_read(ADDR_MSIP, rd_data);
        check_eq(rd_data, 32'h0, "msip readback after write 0");
        check(sw_irq == 1'b0, "sw_irq deasserted when msip=0");

        // Toggle msip rapidly
        apb_write(ADDR_MSIP, 32'h1);
        repeat (1) @(posedge clk);
        check(sw_irq == 1'b1, "sw_irq high after rapid set");

        apb_write(ADDR_MSIP, 32'h0);
        repeat (1) @(posedge clk);
        check(sw_irq == 1'b0, "sw_irq low after rapid clear");

        // Only bit 0 matters
        apb_write(ADDR_MSIP, 32'hFFFF_FFFE);  // Bit 0 = 0
        repeat (2) @(posedge clk);
        check(sw_irq == 1'b0, "sw_irq low when bit 0 is 0 (other bits ignored)");

        apb_write(ADDR_MSIP, 32'h0000_0001);  // Bit 0 = 1
        repeat (2) @(posedge clk);
        check(sw_irq == 1'b1, "sw_irq high when only bit 0 is 1");

        // Clean up
        apb_write(ADDR_MSIP, 32'h0);
    endtask

    // =========================================================================
    // INT-014: mtime Read/Write via APB
    // =========================================================================
    task automatic test_mtime_read_write();
        logic [31:0] val_lo, val_hi;

        test_begin("INT-014: mtime Read/Write via APB");

        // Write a known value to mtime
        apb_write(ADDR_MTIME_LO, 32'hDEAD_BEEF);
        // Read it back immediately (mtime will have incremented by the APB
        // transaction overhead, so check approximate range)
        apb_read(ADDR_MTIME_LO, val_lo);
        $display("  [INFO] Written 0xDEADBEEF, read back 0x%08h", val_lo);
        check(val_lo >= 32'hDEAD_BEEF, "mtime_lo retains written value (or incremented)");

        // Write mtime_hi
        apb_write(ADDR_MTIME_HI, 32'h0000_CAFE);
        apb_read(ADDR_MTIME_HI, val_hi);
        check_eq(val_hi, 32'h0000_CAFE, "mtime_hi readback matches written value");

        // Write both halves to zero and verify
        apb_write(ADDR_MTIME_LO, 32'h0);
        apb_write(ADDR_MTIME_HI, 32'h0);
        repeat (5) @(posedge clk);

        apb_read(ADDR_MTIME_LO, val_lo);
        apb_read(ADDR_MTIME_HI, val_hi);
        check(val_lo > 0, "mtime_lo non-zero after clearing and waiting");
        check_eq(val_hi, 32'h0, "mtime_hi still 0 (not enough cycles to overflow)");

        // Write mtime_lo close to overflow to verify mtime_hi increment
        // Note: This requires that mtime_lo overflow increments mtime_hi,
        // which happens naturally when the 64-bit counter wraps the low word.
        apb_write(ADDR_MTIME_HI, 32'h0);
        apb_write(ADDR_MTIME_LO, 32'hFFFF_FFF0);

        // Wait enough cycles for low word to overflow
        repeat (30) @(posedge clk);

        apb_read(ADDR_MTIME_HI, val_hi);
        apb_read(ADDR_MTIME_LO, val_lo);
        $display("  [INFO] After overflow: mtime_hi=0x%08h, mtime_lo=0x%08h", val_hi, val_lo);
        check(val_hi >= 32'h1, "mtime_hi incremented after mtime_lo overflow");
    endtask

    // =========================================================================
    // INT-015: 64-bit mtime/mtimecmp Upper-Half Register Access
    // =========================================================================
    task automatic test_64bit_registers();
        logic [31:0] lo_val, hi_val;

        test_begin("INT-015: 64-bit Register Access");

        // Test mtimecmp full 64-bit write/read
        apb_write(ADDR_MTIMECMP_LO, 32'h1234_5678);
        apb_write(ADDR_MTIMECMP_HI, 32'h9ABC_DEF0);

        apb_read(ADDR_MTIMECMP_LO, lo_val);
        check_eq(lo_val, 32'h1234_5678, "mtimecmp_lo full readback");

        apb_read(ADDR_MTIMECMP_HI, hi_val);
        check_eq(hi_val, 32'h9ABC_DEF0, "mtimecmp_hi full readback");

        // Write only upper half, verify lower half unchanged
        apb_write(ADDR_MTIMECMP_HI, 32'h0000_0042);
        apb_read(ADDR_MTIMECMP_LO, lo_val);
        check_eq(lo_val, 32'h1234_5678, "mtimecmp_lo unchanged after writing only hi");
        apb_read(ADDR_MTIMECMP_HI, hi_val);
        check_eq(hi_val, 32'h0000_0042, "mtimecmp_hi updated independently");

        // Write only lower half, verify upper half unchanged
        apb_write(ADDR_MTIMECMP_LO, 32'hAAAA_BBBB);
        apb_read(ADDR_MTIMECMP_HI, hi_val);
        check_eq(hi_val, 32'h0000_0042, "mtimecmp_hi unchanged after writing only lo");
        apb_read(ADDR_MTIMECMP_LO, lo_val);
        check_eq(lo_val, 32'hAAAA_BBBB, "mtimecmp_lo updated independently");

        // Test mtime 64-bit write/read
        apb_write(ADDR_MTIME_LO, 32'hFEDC_BA98);
        apb_write(ADDR_MTIME_HI, 32'h7654_3210);

        apb_read(ADDR_MTIME_HI, hi_val);
        check_eq(hi_val, 32'h7654_3210, "mtime_hi readback after 64-bit write");

        // mtime_lo will have incremented, just verify it is close
        apb_read(ADDR_MTIME_LO, lo_val);
        $display("  [INFO] mtime_lo after write 0xFEDCBA98: read 0x%08h", lo_val);
        check(lo_val >= 32'hFEDC_BA98, "mtime_lo approximately correct (auto-increment)");

        // Test timer_irq with 64-bit comparison
        // Set mtime to a value where only upper half matters
        apb_write(ADDR_MTIME_LO, 32'h0);
        apb_write(ADDR_MTIME_HI, 32'h0000_0010);

        // Set mtimecmp lower than mtime (in upper half)
        apb_write(ADDR_MTIMECMP_LO, 32'h0);
        apb_write(ADDR_MTIMECMP_HI, 32'h0000_0005);

        repeat (2) @(posedge clk);
        check(timer_irq == 1'b1, "timer_irq with 64-bit comparison (mtime_hi > mtimecmp_hi)");

        // Set mtimecmp higher than mtime
        apb_write(ADDR_MTIMECMP_HI, 32'hFFFF_FFFF);
        apb_write(ADDR_MTIMECMP_LO, 32'hFFFF_FFFF);
        repeat (2) @(posedge clk);
        check(timer_irq == 1'b0, "timer_irq cleared with large 64-bit mtimecmp");
    endtask

endmodule
