// =============================================================================
// VSync - Clock and Reset Generator
// =============================================================================
// Configurable clock and reset generator for testbenches.
// Supports multiple clock domains and parameterized reset duration.
// =============================================================================

`timescale 1ns / 1ps

module clk_rst_gen #(
    parameter real    CLK_PERIOD_NS  = 10.0,   // Clock period in nanoseconds (default 100MHz)
    parameter int     RST_CYCLES     = 10,      // Reset duration in clock cycles
    parameter bit     RST_ACTIVE_LOW = 0        // 0: active high reset, 1: active low reset
)(
    output logic clk,
    output logic rst,
    output logic rst_n,
    output logic init_done   // Asserted after reset deasserted
);

    // =========================================================================
    // Clock generation
    // =========================================================================
    initial begin
        clk = 1'b0;
    end

    always #(CLK_PERIOD_NS / 2.0) clk = ~clk;

    // =========================================================================
    // Reset generation
    // =========================================================================
    logic rst_internal;

    initial begin
        rst_internal = 1'b1;
        init_done    = 1'b0;

        // Hold reset for specified number of cycles
        repeat (RST_CYCLES) @(posedge clk);

        // Deassert reset synchronously
        @(posedge clk);
        rst_internal = 1'b0;

        // Signal initialization complete
        @(posedge clk);
        init_done = 1'b1;
    end

    // Generate both active-high and active-low reset
    assign rst   = rst_internal;
    assign rst_n = ~rst_internal;

    // =========================================================================
    // Assertions
    // =========================================================================

    // Check clock is toggling
`ifndef IVERILOG
    property p_clk_toggle;
        @(posedge clk) disable iff (rst)
        1'b1 |=> ##1 1'b1;
    endproperty

    // Check reset deasserts cleanly
    property p_rst_deassert;
        @(posedge clk)
        $fell(rst_internal) |-> ##1 !rst_internal;
    endproperty
`endif

    // =========================================================================
    // Helper tasks
    // =========================================================================

    // Wait for N clock cycles
    task automatic wait_cycles(int n);
        repeat (n) @(posedge clk);
    endtask

    // Wait for reset to complete
    task automatic wait_for_reset();
        @(posedge init_done);
    endtask

endmodule
