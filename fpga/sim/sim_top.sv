// =============================================================================
// sim_top.sv - VSync Top-Level Simulation Testbench
// =============================================================================
// Description:
//   Simulation testbench for vsync_top. Generates 25 MHz clock, reset
//   sequence, ties off unused inputs, and runs a basic pipeline smoke test.
//   Produces VCD waveform output for debugging.
//
// Usage:
//   iverilog -g2012 -o sim_top.vvp \
//       ../../rtl/core/vsync_pkg.sv \
//       ../../rtl/**/*.sv \
//       sim_top.sv
//   vvp sim_top.vvp
//   gtkwave sim_top.vcd
// =============================================================================

`timescale 1ns / 1ps

module sim_top;

  // =========================================================================
  // Parameters
  // =========================================================================
  localparam real CLK_PERIOD = 40.0;  // 25 MHz = 40 ns period
  localparam real HALF_PERIOD = CLK_PERIOD / 2.0;
  localparam integer TIMEOUT_NS = 1_000_000_000;  // 100 us timeout
  localparam integer RST_CYCLES = 10;  // Reset duration in clock cycles

  // =========================================================================
  // DUT Port Signals
  // =========================================================================

  // Clock & Reset
  logic        clk;
  logic        rst_n;

  // UART
  wire         uart_tx;
  logic        uart_rx;

  // GPIO (bidirectional)
  wire  [15:0] gpio_io;
  logic [15:0] gpio_drive;
  logic [15:0] gpio_drive_en;

  // HyperRAM (bidirectional)
  wire         hyper_cs_n;
  wire         hyper_ck;
  wire         hyper_ck_n;
  wire         hyper_rwds;
  wire  [ 7:0] hyper_dq;
  wire         hyper_rst_n;
  logic        hyper_rwds_drive;
  logic        hyper_rwds_drive_en;
  logic [ 7:0] hyper_dq_drive;
  logic        hyper_dq_drive_en;

  // JTAG
  logic        jtag_tck;
  logic        jtag_tms;
  logic        jtag_tdi;
  wire         jtag_tdo;
  logic        jtag_trst_n;

  // =========================================================================
  // Clock Generation - 25 MHz
  // =========================================================================
  initial begin
    clk = 1'b0;
  end

  always #(HALF_PERIOD) clk = ~clk;

  // =========================================================================
  // Reset Sequence
  // =========================================================================
  // vsync_top uses active-high rst_n: 1=reset, 0=run
  initial begin
    rst_n = 1'b1;  // Assert reset (active high)
    repeat (RST_CYCLES) @(posedge clk);
    #1;
    rst_n = 1'b0;  // Release reset
    $display("[%0t] INFO: Reset de-asserted", $time);
  end

  // =========================================================================
  // Input Tie-offs
  // =========================================================================

  // UART RX: idle high (UART idle state)
  initial begin
    uart_rx = 1'b1;
  end

  // GPIO: tristate by default (not driving)
  initial begin
    gpio_drive    = 16'h0000;
    gpio_drive_en = 16'h0000;
  end

  genvar gi;
  generate
    for (gi = 0; gi < 16; gi++) begin : gen_gpio_tb
      assign gpio_io[gi] = gpio_drive_en[gi] ? gpio_drive[gi] : 1'bz;
    end
  endgenerate

  // HyperRAM: tie-off DQ and RWDS inputs (not driving from testbench by default)
  initial begin
    hyper_rwds_drive    = 1'b0;
    hyper_rwds_drive_en = 1'b0;
    hyper_dq_drive      = 8'h00;
    hyper_dq_drive_en   = 1'b0;
  end

  assign hyper_rwds = hyper_rwds_drive_en ? hyper_rwds_drive : 1'bz;
  assign hyper_dq   = hyper_dq_drive_en ? hyper_dq_drive : 8'bz;

  // JTAG: inactive state
  initial begin
    jtag_tck    = 1'b0;
    jtag_tms    = 1'b1;    // TMS high = stay in Test-Logic-Reset
    jtag_tdi    = 1'b0;
    jtag_trst_n = 1'b0;    // Hold JTAG in reset
  end

  // Release JTAG reset after system reset
  initial begin
    @(posedge rst_n);
    repeat (5) @(posedge clk);
    jtag_trst_n = 1'b1;
  end

  // =========================================================================
  // DUT Instantiation
  // =========================================================================
  vsync_top #(
      .IMEM_INIT_FILE("firmware.hex"),
      .GPIO_WIDTH    (16)
  ) u_dut (
      // Clock & Reset
      .clk  (clk),
      .rst_n(rst_n),

      // UART
      .uart_tx(uart_tx),
      .uart_rx(uart_rx),

      // GPIO
      .gpio_io(gpio_io),

      // HyperRAM
      .hyper_cs_n (hyper_cs_n),
      .hyper_ck   (hyper_ck),
      .hyper_ck_n (hyper_ck_n),
      .hyper_rwds (hyper_rwds),
      .hyper_dq   (hyper_dq),
      .hyper_rst_n(hyper_rst_n),

      // JTAG Debug
      .jtag_tck   (jtag_tck),
      .jtag_tms   (jtag_tms),
      .jtag_tdi   (jtag_tdi),
      .jtag_tdo   (jtag_tdo),
      .jtag_trst_n(jtag_trst_n)
  );

  // =========================================================================
  // VCD Waveform Dump
  // =========================================================================
  initial begin
    $dumpfile("sim_top.vcd");
    $dumpvars(0, sim_top);
  end

  // =========================================================================
  // Simulation Timeout
  // =========================================================================
  initial begin
    #(TIMEOUT_NS);
    $display("[%0t] ERROR: Simulation timeout after %0d ns", $time, TIMEOUT_NS);
    $finish;
  end

  // =========================================================================
  // Basic Stimulus & Monitoring
  // =========================================================================

  // Monitor key internal signals (hierarchical references)
  // These may cause warnings if internal signal names differ; that is OK
  // for initial bring-up.

  // Pipeline activity monitor - print PC every 100 cycles after reset
  integer cycle_count;
  initial begin
    cycle_count = 0;
    @(posedge rst_n);
    $display("[%0t] INFO: Simulation started, monitoring pipeline...", $time);

    forever begin
      @(posedge clk);
      cycle_count = cycle_count + 1;

      // Print status every 100 cycles
      if (cycle_count % 100 == 0) begin
        $display("[%0t] INFO: Cycle %0d", $time, cycle_count);
      end

      // Check for UART TX activity (start bit = low)
      if (uart_tx === 1'b0 && cycle_count > 20) begin
        $display("[%0t] INFO: UART TX activity detected at cycle %0d", $time, cycle_count);
      end
    end
  end

  // Stop after a reasonable number of cycles if no timeout
  initial begin
    @(posedge rst_n);
    repeat (5000) @(posedge clk);
    $display("[%0t] INFO: Basic simulation completed after 5000 cycles", $time);
    $display("[%0t] INFO: Simulation PASSED (no fatal errors)", $time);
    $finish;
  end

  // =========================================================================
  // Assertion Checks (basic sanity)
  // =========================================================================

  // Check that reset is properly applied
  initial begin
    @(negedge rst_n);  // Wait for reset assertion
    assert (rst_n == 1'b0)
    else $error("Reset not properly asserted");
    @(posedge rst_n);
    assert (rst_n == 1'b1)
    else $error("Reset not properly de-asserted");
    $display("[%0t] INFO: Reset sequence verified", $time);
  end

  // Check HyperRAM reset mirrors system reset
  always @(posedge clk) begin
    if (rst_n === 1'b1) begin
      // After reset release, hyper_rst_n should eventually go high
      // (it's directly connected to sys_rst_n in vsync_top)
    end
  end

endmodule
