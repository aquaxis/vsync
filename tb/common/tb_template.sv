// =============================================================================
// VSync - Testbench Template
// =============================================================================
// Template for creating new testbenches. Copy this file and modify for your
// specific DUT (Device Under Test).
//
// Usage:
//   1. Copy this file to the appropriate tb/ subdirectory
//   2. Replace MODULE_NAME with your DUT module name
//   3. Add DUT-specific ports and connections
//   4. Implement test cases in the test_main task
//
// Simulation:
//   iverilog -g2012 -o sim.vvp tb_MODULE_NAME.sv ../common/*.sv ../../rtl/MODULE_NAME.sv
//   vvp sim.vvp
//   gtkwave dump.vcd  (optional, for waveform viewing)
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_template;

    import test_utils::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD = 10;    // 100MHz clock
    localparam RST_CYCLES = 10;    // Reset duration

    // =========================================================================
    // Signals
    // =========================================================================
    logic clk;
    logic rst;
    logic rst_n;
    logic init_done;

    // TODO: Add DUT-specific signals here
    // Example:
    // logic [31:0] data_in;
    // logic [31:0] data_out;
    // logic        valid;
    // logic        ready;

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
    // TODO: Instantiate your DUT here
    // Example:
    // module_name #(
    //     .PARAM1 (VALUE1),
    //     .PARAM2 (VALUE2)
    // ) u_dut (
    //     .clk     (clk),
    //     .rst_n   (rst_n),
    //     .data_in (data_in),
    //     .data_out(data_out),
    //     .valid   (valid),
    //     .ready   (ready)
    // );

    // =========================================================================
    // VCD Dump (for waveform viewing)
    // =========================================================================
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_template);
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 100000);  // 100K cycles timeout
        $display("ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded maximum time");
    end

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        // Wait for reset to complete
        @(posedge init_done);
        repeat (5) @(posedge clk);  // Additional settle time

        // Run tests
        test_main();

        // Finish
        test_finish();
    end

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("Template Test Suite");

        // ----- Test Case 1 -----
        test_case_1();

        // ----- Test Case 2 -----
        test_case_2();

        // Add more test cases as needed...

    endtask

    // -------------------------------------------------------------------------
    // Test Case 1: Basic functionality
    // -------------------------------------------------------------------------
    task automatic test_case_1();
        test_begin("Basic Functionality Test");

        // TODO: Implement test stimulus
        // Example:
        // data_in = 32'hDEAD_BEEF;
        // @(posedge clk);
        // valid = 1'b1;
        // @(posedge clk iff ready);
        // valid = 1'b0;

        // TODO: Check results
        // Example:
        // check_eq(data_out, 32'hDEAD_BEEF, "Data passthrough");

        test_pass("Basic functionality verified");
    endtask

    // -------------------------------------------------------------------------
    // Test Case 2: Edge cases
    // -------------------------------------------------------------------------
    task automatic test_case_2();
        test_begin("Edge Case Test");

        // TODO: Implement edge case tests

        test_pass("Edge cases verified");
    endtask

endmodule
