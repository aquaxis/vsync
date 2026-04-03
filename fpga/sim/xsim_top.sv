// =============================================================================
// xsim_top.sv - VSync Top-Level Simulation Testbench for Vivado xsim
// =============================================================================
// Description:
//   Simulation testbench for vsync_top using Vivado xsim.
//   Generates 100 MHz clock (MMCME2_BASE generates 25 MHz internally),
//   waits for MMCM lock before releasing reset, and runs a basic smoke test.
//   Unlike sim_top.sv (iverilog), this testbench does NOT define IVERILOG,
//   so MMCME2_BASE and BUFG primitives are active via unisim library.
//
// Usage:
//   cd fpga/scripts
//   make sim          # Batch simulation
//   make sim-gui      # GUI simulation with waveform viewer
// =============================================================================

`timescale 1ns / 1ps

module xsim_top;

  // =========================================================================
  // Parameters
  // =========================================================================
  localparam real CLK_PERIOD = 10.0;  // 100 MHz = 10 ns period
  localparam real HALF_PERIOD = CLK_PERIOD / 2.0;
  localparam integer TIMEOUT_NS = 500_000;  // 500 us timeout (MMCM lock ~few us)
  localparam integer RST_CYCLES = 10;  // Reset duration in clock cycles

  // =========================================================================
  // DUT Port Signals
  // =========================================================================

  // Clock & Reset
  logic        clk;
  logic        rst_n;

  // UART
  wire         uart_tx;
  wire         uart_rx;

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
  // Clock Generation - 100 MHz
  // =========================================================================
  // MMCME2_BASE inside vsync_top will convert this to 25 MHz system clock
  initial begin
    clk = 1'b0;
  end

  always #(HALF_PERIOD) clk = ~clk;

  // =========================================================================
  // Reset Sequence - Wait for MMCM Lock
  // =========================================================================
  // vsync_top uses active-high rst_n: 1=reset, 0=run
  // Must wait for MMCM to lock before releasing reset
  initial begin
    rst_n = 1'b1;  // Assert reset (active high)
    @(posedge u_dut.mmcm_locked);  // Wait for MMCM lock
    $display("[%0t] INFO: MMCM locked", $time);
    repeat (RST_CYCLES) @(posedge clk);
    #1;
    rst_n = 1'b0;  // Release reset
    $display("[%0t] INFO: Reset de-asserted", $time);
  end

  // =========================================================================
  // Input Tie-offs
  // =========================================================================
  /*
  // UART RX: idle high (UART idle state)
  initial begin
    uart_rx = 1'b1;
  end
*/
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

  // Release JTAG reset after system reset de-assertion
  initial begin
    @(negedge rst_n);  // Wait for reset release (active-high -> low = running)
    repeat (5) @(posedge clk);
    jtag_trst_n = 1'b1;
  end

  // =========================================================================
  // DUT Instantiation
  // =========================================================================
  vsync_top #(
      .IMEM_INIT_FILE("/home/hidemi/vsync/fpga/scripts/firmware_i.hex"),
      .DMEM_INIT_FILE("/home/hidemi/vsync/fpga/scripts/firmware_d.hex"),
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
    $dumpfile("xsim_top.vcd");
    $dumpvars(0, xsim_top);
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
/*
  // Pipeline activity monitor - print status every 500 cycles after reset
  integer cycle_count;
  initial begin
    cycle_count = 0;
    @(negedge rst_n);  // Wait for reset release (active-high -> low = running)
    $display("[%0t] INFO: Simulation started, monitoring pipeline...", $time);

    forever begin
      @(posedge clk);
      cycle_count = cycle_count + 1;

      // Print status every 500 cycles (more spaced out due to 100 MHz clock)
      if (cycle_count % 500 == 0) begin
        $display("[%0t] INFO: Cycle %0d", $time, cycle_count);
      end

      // Check for UART TX activity (start bit = low)
      if (uart_tx === 1'b0 && cycle_count > 20) begin
        $display("[%0t] INFO: UART TX activity detected at cycle %0d", $time, cycle_count);
      end
    end
  end
*/
  // Stop after a reasonable number of cycles if no timeout
  initial begin
    @(negedge rst_n);  // Wait for reset release
    repeat (10000) @(posedge clk);
    //$display("[%0t] INFO: Basic simulation completed after 10000 cycles", $time);
    //$display("[%0t] INFO: Simulation PASSED (no fatal errors)", $time);
    //$finish;
  end

  // =========================================================================
  // Assertion Checks (basic sanity)
  // =========================================================================

  // Check that MMCM locks
  initial begin
    @(posedge u_dut.mmcm_locked);
    $display("[%0t] INFO: MMCM lock verified", $time);
  end

  // Check that reset is properly applied and released after MMCM lock
  initial begin
    // Wait for reset release (rst_n goes low = running)
    @(negedge rst_n);
    assert (rst_n == 1'b0)
    else $error("Reset not properly de-asserted");
    $display("[%0t] INFO: Reset sequence verified", $time);
  end

  // Check HyperRAM reset mirrors system reset
  always @(posedge clk) begin
    if (rst_n === 1'b0) begin
      // After reset release, hyper_rst_n should eventually go high
      // (it's directly connected to sys_rst_n in vsync_top)
    end
  end

  task_uart u_task_uart (
      .tx(uart_rx),
      .rx(uart_tx)
  );

endmodule
