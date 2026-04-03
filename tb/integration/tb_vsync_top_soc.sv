// =============================================================================
// VSync - Full SoC Integration Testbench
// =============================================================================
// End-to-end verification of the entire VSync SoC using vsync_top:
//   CPU boot → instruction fetch from IMEM → execute → AXI4 bus →
//   APB bridge → UART TX serial output
//
// This is the most important test in the project - it proves the entire SoC
// works as an integrated system.
//
// Test firmware (test_soc_firmware.hex) writes 'O', 'K', '\n' to UART TX.
// Testbench captures UART TX serial output and verifies each byte.
//
// Simulation:
//   iverilog -g2012 -DIVERILOG -I rtl/core -I tb/common -o sim.vvp \
//       <all_rtl_files> tb/integration/tb_vsync_top_soc.sv
//   vvp sim.vvp
// =============================================================================

`timescale 1ns / 1ps

`include "test_utils.sv"

module tb_vsync_top_soc;

    import vsync_pkg::*;
    import test_utils::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    // Clock: 25 MHz to match vsync_top internal UART CLK_FREQ=25_000_000
    // (MMCM bypassed in iverilog: clk_sys = clk, so TB clock = system clock)
    localparam real CLK_PERIOD   = 40.0;            // 25 MHz = 40 ns period
    localparam int  RST_CYCLES   = 20;              // Reset hold cycles

    // UART timing (must match vsync_top uart_apb configuration)
    // CLK_FREQ=25MHz, BAUD=115200, BAUD_DIV = round(25M / 115200) = 217 (int=13, frac=9)
    localparam int  BAUD_DIV     = 217;
    localparam int  CLKS_PER_BIT = BAUD_DIV;         // 217 clocks per bit
    // One byte (8N1): start + 8 data + stop = 10 bits = 2170 clocks = 86800 ns

    // Timeout: 50 ms simulation time (plenty for 3 UART bytes)
    localparam int  TIMEOUT_NS   = 50_000_000;

    // Expected UART output
    localparam logic [7:0] EXPECTED_BYTE_0 = 8'h4F;  // 'O'
    localparam logic [7:0] EXPECTED_BYTE_1 = 8'h4B;  // 'K'
    localparam logic [7:0] EXPECTED_BYTE_2 = 8'h0A;  // '\n'

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst_n;

    // UART
    logic        uart_tx;
    logic        uart_rx;

    // GPIO (active tristate)
    wire  [15:0] gpio_io;

    // HyperRAM (active tristate)
    wire         hyper_rwds;
    wire  [7:0]  hyper_dq;

    // Captured UART bytes
    logic [7:0]  captured_bytes [0:2];
    int          byte_count;

    // =========================================================================
    // Clock Generation (25 MHz)
    // =========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_vsync_top_soc.vcd");
        $dumpvars(0, tb_vsync_top_soc);
    end

    // =========================================================================
    // Signal Tieoffs
    // =========================================================================
    assign uart_rx  = 1'b1;       // UART idle = high
    assign gpio_io  = 16'bz;      // Tri-state
    assign hyper_rwds = 1'bz;     // Tri-state
    assign hyper_dq   = 8'bz;     // Tri-state

    // =========================================================================
    // DUT Instantiation - vsync_top (Full SoC)
    // =========================================================================
    vsync_top #(
        .IMEM_INIT_FILE ("tb/integration/test_soc_firmware.hex")
    ) u_dut (
        .clk            (clk),
        .rst_n          (rst_n),

        // UART
        .uart_tx        (uart_tx),
        .uart_rx        (uart_rx),

        // GPIO
        .gpio_io        (gpio_io),

        // HyperRAM (active tristate, directly tied)
        .hyper_cs_n     (),
        .hyper_ck       (),
        .hyper_ck_n     (),
        .hyper_rwds     (hyper_rwds),
        .hyper_dq       (hyper_dq),
        .hyper_rst_n    (),

        // JTAG (disabled)
        .jtag_tck       (1'b0),
        .jtag_tms       (1'b0),
        .jtag_tdi       (1'b0),
        .jtag_tdo       (),
        .jtag_trst_n    (1'b0)
    );

    // =========================================================================
    // UART TX Capture Task
    // =========================================================================
    // Captures one byte from the UART TX line using 8N1 protocol (LSB first).
    // Waits for start bit (falling edge), then samples each bit at center.
    task automatic uart_capture_byte(output logic [7:0] data);
        // Wait for start bit (falling edge on uart_tx)
        @(negedge uart_tx);

        // Move to center of start bit
        #(CLKS_PER_BIT * CLK_PERIOD / 2);

        // Sample 8 data bits (LSB first)
        for (int i = 0; i < 8; i++) begin
            #(CLKS_PER_BIT * CLK_PERIOD);  // Move to center of next bit
            data[i] = uart_tx;
        end

        // Wait through stop bit
        #(CLKS_PER_BIT * CLK_PERIOD);
    endtask

    // =========================================================================
    // UART Capture Process (runs in background)
    // =========================================================================
    initial begin
        byte_count = 0;
        captured_bytes[0] = 8'h00;
        captured_bytes[1] = 8'h00;
        captured_bytes[2] = 8'h00;

        // Wait for reset to deassert
        @(posedge rst_n);
        #100;

        // Capture 3 bytes from UART TX
        for (int b = 0; b < 3; b++) begin
            logic [7:0] rx_byte;
            uart_capture_byte(rx_byte);
            captured_bytes[b] = rx_byte;
            byte_count++;
            $display("[TB] UART TX byte %0d captured: 0x%02h ('%c')",
                     b, rx_byte, (rx_byte >= 8'h20) ? rx_byte : 8'h2E);
        end
    end

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // -----------------------------------------------------------------
        // Reset (vsync_top uses active-high rst_n: 1=reset, 0=run)
        // -----------------------------------------------------------------
        rst_n = 1'b1;  // Assert reset (active high)
        repeat (RST_CYCLES) @(posedge clk);
        rst_n = 1'b0;  // Release reset
        $display("[TB] Reset released at %0t", $time);

        // -----------------------------------------------------------------
        // Wait for all 3 UART bytes or timeout
        // -----------------------------------------------------------------
        fork
            begin
                // Wait for capture to finish
                wait (byte_count >= 3);
                $display("[TB] All 3 UART bytes captured at %0t", $time);
            end
            begin
                // Timeout watchdog
                #(TIMEOUT_NS);
                $display("[TB] ERROR: Timeout after %0d ns, captured %0d bytes",
                         TIMEOUT_NS, byte_count);
            end
        join_any
        disable fork;

        // Small delay to settle
        #1000;

        // -----------------------------------------------------------------
        // Test Verification
        // -----------------------------------------------------------------
        test_suite_begin("VSync SoC Integration Test (vsync_top)");

        test_begin("UART TX Byte 0 = 'O' (0x4F)");
        check_eq({24'b0, captured_bytes[0]}, {24'b0, EXPECTED_BYTE_0},
                 "UART TX byte 0");

        test_begin("UART TX Byte 1 = 'K' (0x4B)");
        check_eq({24'b0, captured_bytes[1]}, {24'b0, EXPECTED_BYTE_1},
                 "UART TX byte 1");

        test_begin("UART TX Byte 2 = '\\n' (0x0A)");
        check_eq({24'b0, captured_bytes[2]}, {24'b0, EXPECTED_BYTE_2},
                 "UART TX byte 2");

        test_finish();
    end

    // =========================================================================
    // Absolute Timeout (safety net)
    // =========================================================================
    initial begin
        #(TIMEOUT_NS + 1_000_000);  // 51 ms absolute safety
        $display("[TB] FATAL: Absolute timeout reached");
        $finish(1);
    end

endmodule : tb_vsync_top_soc
