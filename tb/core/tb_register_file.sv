// =============================================================================
// VSync - Register File Test Bench
// =============================================================================
// Test IDs: CORE-REG-001 through CORE-REG-009
// - CORE-REG-001: Reset clears all registers to zero
// - CORE-REG-002: x0 hardwired to zero (writes to x0 ignored)
// - CORE-REG-003: Write and read each register x1 through x31
// - CORE-REG-004: Simultaneous read of two different registers
// - CORE-REG-005: Write-then-read in same cycle behavior
// - CORE-REG-006: Write with reg_write=0 (should not modify register)
// - CORE-REG-007: Full word patterns (0xFFFFFFFF and 0x00000000)
// - CORE-REG-008: Rapid successive writes to same register
// - CORE-REG-009: Read forwarding (read from register being written)
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

import vsync_pkg::*;

module tb_register_file;

    import test_utils::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD = 10;    // 100MHz clock
    localparam RST_CYCLES = 10;    // Reset duration

    // =========================================================================
    // Signals
    // =========================================================================
    logic                   clk;
    logic                   rst;
    logic                   rst_n;
    logic                   init_done;

    // Register file interface
    logic [REG_ADDR_W-1:0]  rs1_addr;
    logic [XLEN-1:0]        rs1_data;
    logic [REG_ADDR_W-1:0]  rs2_addr;
    logic [XLEN-1:0]        rs2_data;
    logic [REG_ADDR_W-1:0]  rd_addr;
    logic [XLEN-1:0]        rd_data;
    logic                    reg_write;

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
    register_file u_dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .rs1_addr  (rs1_addr),
        .rs1_data  (rs1_data),
        .rs2_addr  (rs2_addr),
        .rs2_data  (rs2_data),
        .rd_addr   (rd_addr),
        .rd_data   (rd_data),
        .reg_write (reg_write)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_register_file.vcd");
        $dumpvars(0, tb_register_file);
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
    // Helper tasks
    // =========================================================================

    // Initialize all inputs to idle state
    task automatic idle_inputs();
        rs1_addr  = '0;
        rs2_addr  = '0;
        rd_addr   = '0;
        rd_data   = '0;
        reg_write = 1'b0;
    endtask

    // Write a value to a register (takes effect at next rising edge)
    task automatic write_reg(
        input logic [REG_ADDR_W-1:0] addr,
        input logic [XLEN-1:0]       data
    );
        @(posedge clk);
        rd_addr   = addr;
        rd_data   = data;
        reg_write = 1'b1;
        @(posedge clk);
        reg_write = 1'b0;
    endtask

    // Read a value from rs1 port (combinational, result available after #1)
    task automatic read_rs1(
        input  logic [REG_ADDR_W-1:0] addr,
        output logic [XLEN-1:0]       data
    );
        rs1_addr = addr;
        #1;
        data = rs1_data;
    endtask

    // Read a value from rs2 port (combinational, result available after #1)
    task automatic read_rs2(
        input  logic [REG_ADDR_W-1:0] addr,
        output logic [XLEN-1:0]       data
    );
        rs2_addr = addr;
        #1;
        data = rs2_data;
    endtask

    // Read both ports simultaneously (combinational)
    task automatic read_both(
        input  logic [REG_ADDR_W-1:0] addr1,
        output logic [XLEN-1:0]       data1,
        input  logic [REG_ADDR_W-1:0] addr2,
        output logic [XLEN-1:0]       data2
    );
        rs1_addr = addr1;
        rs2_addr = addr2;
        #1;
        data1 = rs1_data;
        data2 = rs2_data;
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        idle_inputs();

        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("Register File Tests");

        // CORE-REG-001
        test_reset();

        // CORE-REG-002
        test_x0_hardwired_zero();

        // CORE-REG-003
        test_write_read_all_registers();

        // CORE-REG-004
        test_simultaneous_dual_read();

        // CORE-REG-005
        test_write_then_read_same_cycle();

        // CORE-REG-006
        test_write_disabled();

        // CORE-REG-007
        test_full_word_patterns();

        // CORE-REG-008
        test_rapid_successive_writes();

        // CORE-REG-009
        test_read_forwarding();

    endtask

    // =========================================================================
    // CORE-REG-001: Reset clears all registers to zero
    // =========================================================================
    task automatic test_reset();
        logic [XLEN-1:0] val;

        test_begin("CORE-REG-001: Reset clears all registers to zero");

        // First write some non-zero data into a few registers so that a
        // subsequent reset has something to clear.
        write_reg(5'd1,  32'hDEAD_BEEF);
        write_reg(5'd15, 32'hCAFE_BABE);
        write_reg(5'd31, 32'h1234_5678);

        // Verify the writes took effect before resetting
        read_rs1(5'd1, val);
        check_eq(val, 32'hDEAD_BEEF, "Pre-reset: x1 written");

        // Apply reset: drive rst_n low for a few cycles, then release
        // We manipulate the DUT reset directly (rst_n is driven by clk_rst_gen
        // but the DUT has an asynchronous reset, so we can force it).
        force u_dut.rst_n = 1'b0;
        repeat (3) @(posedge clk);
        release u_dut.rst_n;
        repeat (2) @(posedge clk);

        // Now read every register via rs1 port and verify zero
        for (int i = 0; i < NUM_REGS; i++) begin
            read_rs1(i[REG_ADDR_W-1:0], val);
            check_eq(val, 32'h0, $sformatf("After reset: x%0d == 0", i));
        end

    endtask

    // =========================================================================
    // CORE-REG-002: x0 hardwired to zero (writes ignored)
    // =========================================================================
    task automatic test_x0_hardwired_zero();
        logic [XLEN-1:0] val;

        test_begin("CORE-REG-002: x0 hardwired to zero");

        // Attempt to write various non-zero values to x0
        write_reg(5'd0, 32'hFFFF_FFFF);
        read_rs1(5'd0, val);
        check_eq(val, 32'h0, "x0 == 0 after write 0xFFFFFFFF");

        write_reg(5'd0, 32'hDEAD_BEEF);
        read_rs1(5'd0, val);
        check_eq(val, 32'h0, "x0 == 0 after write 0xDEADBEEF");

        write_reg(5'd0, 32'h0000_0001);
        read_rs1(5'd0, val);
        check_eq(val, 32'h0, "x0 == 0 after write 0x00000001");

        // Also check via rs2 port
        read_rs2(5'd0, val);
        check_eq(val, 32'h0, "x0 == 0 via rs2 port");

    endtask

    // =========================================================================
    // CORE-REG-003: Write and read each register x1 through x31
    // =========================================================================
    task automatic test_write_read_all_registers();
        logic [XLEN-1:0] val;
        logic [XLEN-1:0] expected;

        test_begin("CORE-REG-003: Write and read x1..x31");

        // Write a unique value to each register x1..x31
        for (int i = 1; i < NUM_REGS; i++) begin
            expected = 32'hA000_0000 | i[31:0];
            write_reg(i[REG_ADDR_W-1:0], expected);
        end

        // Read back via rs1 and verify
        for (int i = 1; i < NUM_REGS; i++) begin
            expected = 32'hA000_0000 | i[31:0];
            read_rs1(i[REG_ADDR_W-1:0], val);
            check_eq(val, expected, $sformatf("x%0d read-back via rs1", i));
        end

        // Read back via rs2 and verify
        for (int i = 1; i < NUM_REGS; i++) begin
            expected = 32'hA000_0000 | i[31:0];
            read_rs2(i[REG_ADDR_W-1:0], val);
            check_eq(val, expected, $sformatf("x%0d read-back via rs2", i));
        end

    endtask

    // =========================================================================
    // CORE-REG-004: Simultaneous read of two different registers
    // =========================================================================
    task automatic test_simultaneous_dual_read();
        logic [XLEN-1:0] val1, val2;

        test_begin("CORE-REG-004: Simultaneous dual read");

        // Load known values
        write_reg(5'd3,  32'h1111_1111);
        write_reg(5'd7,  32'h2222_2222);
        write_reg(5'd10, 32'h3333_3333);
        write_reg(5'd25, 32'h4444_4444);

        // Read x3 and x7 simultaneously
        read_both(5'd3, val1, 5'd7, val2);
        check_eq(val1, 32'h1111_1111, "Dual read: rs1=x3");
        check_eq(val2, 32'h2222_2222, "Dual read: rs2=x7");

        // Read x10 and x25 simultaneously
        read_both(5'd10, val1, 5'd25, val2);
        check_eq(val1, 32'h3333_3333, "Dual read: rs1=x10");
        check_eq(val2, 32'h4444_4444, "Dual read: rs2=x25");

        // Read same register on both ports
        read_both(5'd3, val1, 5'd3, val2);
        check_eq(val1, 32'h1111_1111, "Dual read same reg: rs1=x3");
        check_eq(val2, 32'h1111_1111, "Dual read same reg: rs2=x3");

        // Read x0 on one port and a valid register on the other
        read_both(5'd0, val1, 5'd10, val2);
        check_eq(val1, 32'h0, "Dual read: rs1=x0 (zero)");
        check_eq(val2, 32'h3333_3333, "Dual read: rs2=x10");

    endtask

    // =========================================================================
    // CORE-REG-005: Write-then-read in same cycle behavior
    // =========================================================================
    task automatic test_write_then_read_same_cycle();
        logic [XLEN-1:0] val_at_edge;
        logic [XLEN-1:0] val_after_edge;

        test_begin("CORE-REG-005: Write-then-read same cycle");

        // Write a known initial value to x5
        write_reg(5'd5, 32'hAAAA_AAAA);

        // Now set up a new write to x5 and simultaneously read x5.
        // The DUT uses synchronous write with combinational write-first
        // bypass. When a write and read target the same register in the
        // same cycle, the read port returns the NEW value being written
        // (bypass path: rd_data forwarded to rs1_data/rs2_data).
        @(posedge clk);
        rd_addr   = 5'd5;
        rd_data   = 32'hBBBB_BBBB;
        reg_write = 1'b1;
        rs1_addr  = 5'd5;

        // The read is combinational with write-first bypass, so it should
        // immediately reflect the new value (0xBBBBBBBB) being written.
        #1;
        val_at_edge = rs1_data;

        // Let the write commit
        @(posedge clk);
        reg_write = 1'b0;
        #1;
        val_after_edge = rs1_data;

        // Write-first bypass: read during write cycle shows NEW value
        check_eq(val_at_edge, 32'hBBBB_BBBB,
                 "Read during write cycle shows new value (write-first bypass)");

        // After the write commits, the new value should be visible
        check_eq(val_after_edge, 32'hBBBB_BBBB,
                 "Read after write edge shows new value (0xBBBBBBBB)");

    endtask

    // =========================================================================
    // CORE-REG-006: Write with reg_write=0 (no modification)
    // =========================================================================
    task automatic test_write_disabled();
        logic [XLEN-1:0] val;

        test_begin("CORE-REG-006: Write disabled (reg_write=0)");

        // Write a known value to x8
        write_reg(5'd8, 32'h5555_5555);
        read_rs1(5'd8, val);
        check_eq(val, 32'h5555_5555, "x8 initial value written");

        // Attempt to write a different value with reg_write=0
        @(posedge clk);
        rd_addr   = 5'd8;
        rd_data   = 32'hBAAD_F00D;
        reg_write = 1'b0;
        @(posedge clk);
        reg_write = 1'b0;

        // Read back - should still be the original value
        read_rs1(5'd8, val);
        check_eq(val, 32'h5555_5555,
                 "x8 unchanged after write with reg_write=0");

        // Try multiple cycles with reg_write=0
        @(posedge clk);
        rd_addr   = 5'd8;
        rd_data   = 32'hFFFF_0000;
        reg_write = 1'b0;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);

        read_rs1(5'd8, val);
        check_eq(val, 32'h5555_5555,
                 "x8 still unchanged after multiple disabled writes");

        // Also verify that a different register is not accidentally modified
        read_rs1(5'd9, val);
        // x9 should still hold whatever was there (from earlier tests, or 0
        // if not written). Primarily, it should NOT be 0xBAADF00D or 0xFFFF0000.
        check(val != 32'hBAAD_F00D,
              "x9 not corrupted to 0xBAADF00D by disabled write to x8");

    endtask

    // =========================================================================
    // CORE-REG-007: Full word patterns (0xFFFFFFFF and 0x00000000)
    // =========================================================================
    task automatic test_full_word_patterns();
        logic [XLEN-1:0] val;

        test_begin("CORE-REG-007: Full word patterns");

        // --- Write 0xFFFFFFFF to x12 and verify ---
        write_reg(5'd12, 32'hFFFF_FFFF);
        read_rs1(5'd12, val);
        check_eq(val, 32'hFFFF_FFFF, "x12 == 0xFFFFFFFF (all ones)");

        // Also verify via rs2 port
        read_rs2(5'd12, val);
        check_eq(val, 32'hFFFF_FFFF, "x12 == 0xFFFFFFFF via rs2 (all ones)");

        // --- Overwrite with 0x00000000 and verify ---
        write_reg(5'd12, 32'h0000_0000);
        read_rs1(5'd12, val);
        check_eq(val, 32'h0000_0000, "x12 == 0x00000000 (all zeros)");

        read_rs2(5'd12, val);
        check_eq(val, 32'h0000_0000, "x12 == 0x00000000 via rs2 (all zeros)");

        // --- Alternating bit patterns ---
        write_reg(5'd13, 32'hAAAA_AAAA);
        read_rs1(5'd13, val);
        check_eq(val, 32'hAAAA_AAAA, "x13 == 0xAAAAAAAA (alternating 10)");

        write_reg(5'd13, 32'h5555_5555);
        read_rs1(5'd13, val);
        check_eq(val, 32'h5555_5555, "x13 == 0x55555555 (alternating 01)");

        // --- Walking ones: bit 0 and bit 31 ---
        write_reg(5'd14, 32'h0000_0001);
        read_rs1(5'd14, val);
        check_eq(val, 32'h0000_0001, "x14 == 0x00000001 (bit 0 set)");

        write_reg(5'd14, 32'h8000_0000);
        read_rs1(5'd14, val);
        check_eq(val, 32'h8000_0000, "x14 == 0x80000000 (bit 31 set)");

        // --- Verify 0xFFFFFFFF written to x0 is still zero ---
        write_reg(5'd0, 32'hFFFF_FFFF);
        read_rs1(5'd0, val);
        check_eq(val, 32'h0, "x0 == 0 after writing 0xFFFFFFFF");

    endtask

    // =========================================================================
    // CORE-REG-008: Rapid successive writes to same register
    // =========================================================================
    task automatic test_rapid_successive_writes();
        logic [XLEN-1:0] val;

        test_begin("CORE-REG-008: Rapid successive writes to same register");

        // Write three values to x20 on consecutive clock edges
        @(posedge clk);
        rd_addr   = 5'd20;
        rd_data   = 32'h0000_0001;
        reg_write = 1'b1;

        @(posedge clk);
        rd_data   = 32'h0000_0002;

        @(posedge clk);
        rd_data   = 32'h0000_0003;

        @(posedge clk);
        reg_write = 1'b0;

        // After three consecutive writes, the register should hold the
        // last written value (0x00000003).
        read_rs1(5'd20, val);
        check_eq(val, 32'h0000_0003,
                 "x20 holds last value after 3 rapid writes");

        // Write a burst of 8 values to x21
        for (int i = 0; i < 8; i++) begin
            @(posedge clk);
            rd_addr   = 5'd21;
            rd_data   = i[31:0] * 32'h1111_1111;
            reg_write = 1'b1;
        end
        @(posedge clk);
        reg_write = 1'b0;

        // x21 should hold 7 * 0x11111111 = 0x77777777
        read_rs1(5'd21, val);
        check_eq(val, 32'h7777_7777,
                 "x21 holds last value after 8 rapid writes");

        // Interleave writes to two registers rapidly
        @(posedge clk);
        rd_addr = 5'd22; rd_data = 32'hAAAA_0001; reg_write = 1'b1;
        @(posedge clk);
        rd_addr = 5'd23; rd_data = 32'hBBBB_0002; reg_write = 1'b1;
        @(posedge clk);
        rd_addr = 5'd22; rd_data = 32'hAAAA_0003; reg_write = 1'b1;
        @(posedge clk);
        rd_addr = 5'd23; rd_data = 32'hBBBB_0004; reg_write = 1'b1;
        @(posedge clk);
        reg_write = 1'b0;

        read_rs1(5'd22, val);
        check_eq(val, 32'hAAAA_0003,
                 "x22 holds correct value after interleaved writes");
        read_rs1(5'd23, val);
        check_eq(val, 32'hBBBB_0004,
                 "x23 holds correct value after interleaved writes");

    endtask

    // =========================================================================
    // CORE-REG-009: Read forwarding (read same register being written)
    // =========================================================================
    task automatic test_read_forwarding();
        logic [XLEN-1:0] val_rs1, val_rs2;

        test_begin("CORE-REG-009: Read from register being written");

        // Write an initial value to x16
        write_reg(5'd16, 32'h01D0_DEAD);

        // Set up a simultaneous write and read on the same register.
        // This tests whether the design does write-first or read-first
        // (also known as "read-during-write" behavior).
        //
        // For this DUT, write-first bypass is implemented: when reg_write=1
        // and rd_addr matches rs1_addr/rs2_addr, the new rd_data is
        // combinationally forwarded to the read ports. This ensures the
        // WB→ID path in the pipeline sees the latest value without
        // requiring an extra forwarding stage.

        @(posedge clk);
        rd_addr   = 5'd16;
        rd_data   = 32'h0E10_CAFE;
        reg_write = 1'b1;
        rs1_addr  = 5'd16;
        rs2_addr  = 5'd16;
        #1;  // Let combinational logic settle
        val_rs1 = rs1_data;
        val_rs2 = rs2_data;

        check_eq(val_rs1, 32'h0E10_CAFE,
                 "rs1 reads new value during concurrent write (write-first bypass)");
        check_eq(val_rs2, 32'h0E10_CAFE,
                 "rs2 reads new value during concurrent write (write-first bypass)");

        // After the clock edge, the new value should be visible
        @(posedge clk);
        reg_write = 1'b0;
        #1;
        val_rs1 = rs1_data;
        val_rs2 = rs2_data;

        check_eq(val_rs1, 32'h0E10_CAFE,
                 "rs1 reads new value after write commits");
        check_eq(val_rs2, 32'h0E10_CAFE,
                 "rs2 reads new value after write commits");

        // Test with x0 as the target: both read ports should see zero even
        // while a write to x0 is pending.
        @(posedge clk);
        rd_addr   = 5'd0;
        rd_data   = 32'hFFFF_FFFF;
        reg_write = 1'b1;
        rs1_addr  = 5'd0;
        rs2_addr  = 5'd0;
        #1;
        val_rs1 = rs1_data;
        val_rs2 = rs2_data;

        check_eq(val_rs1, 32'h0,
                 "rs1=x0 reads zero during write attempt to x0");
        check_eq(val_rs2, 32'h0,
                 "rs2=x0 reads zero during write attempt to x0");

        @(posedge clk);
        reg_write = 1'b0;

    endtask

endmodule : tb_register_file
