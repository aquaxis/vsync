// =============================================================================
// VSync - Block RAM Instruction Memory (True Dual-Port)
//
// File: bram_imem.sv
// Description: 64KB instruction memory using Xilinx TDP BRAM inference pattern.
//              Port A: Fetch port (read-only, 1-cycle latency)
//              Port B: Data bus port (read/write with byte-enable)
//              Optional hex file initialization.
// Standard: IEEE 1800-2017 (SystemVerilog)
// Reference: Xilinx UG901 - Vivado Synthesis Guide (TDP BRAM)
// =============================================================================

module bram_imem
  import vsync_pkg::*;
#(
    parameter int DEPTH      = 16384,  // 16384 x 32bit = 64KB
    parameter int ADDR_WIDTH = 16,     // Word address width
    parameter int DATA_WIDTH = 32,     // 32-bit instruction width
    parameter     INIT_FILE  = ""      // Optional hex initialization file
) (
    input logic clk,  // System clock

    // Port A - Instruction Fetch (read-only)
    input  logic                  a_en,    // Read enable
    input  logic [ADDR_WIDTH-1:0] a_addr,  // Word address
    output logic [DATA_WIDTH-1:0] a_rdata, // Read data (1-cycle latency)

    // Port B - Data Bus Access (read/write with byte-enable)
    input  logic                  b_en,     // Port enable
    input  logic                  b_we,     // Write enable
    input  logic [           3:0] b_be,     // Byte enables
    input  logic [ADDR_WIDTH-1:0] b_addr,   // Word address
    input  logic [DATA_WIDTH-1:0] b_wdata,  // Write data
    output logic [DATA_WIDTH-1:0] b_rdata   // Read data (1-cycle latency)
);

  // =========================================================================
  // Memory Array - Xilinx TDP BRAM Inference Pattern
  // =========================================================================
  logic [DATA_WIDTH-1:0] mem[0:DEPTH-1];

  // =========================================================================
  // Optional Hex File Initialization
  // =========================================================================
  initial begin
    if (INIT_FILE != "") begin
      $display("Load imem filename: %s", INIT_FILE);
      $readmemh(INIT_FILE, mem);
    end
  end

  // =========================================================================
  // Port A: Synchronous Read (Instruction Fetch, read-only)
  // =========================================================================
  always_ff @(posedge clk) begin
    if (a_en) begin
      a_rdata <= mem[a_addr];
    end
  end

  // =========================================================================
  // Port B: Synchronous Read/Write with Byte-Enable (Data Bus Access)
  // =========================================================================
  always_ff @(posedge clk) begin
    if (b_en) begin
      if (b_we) begin
        // Byte-enable write
        if (b_be[0]) mem[b_addr][7:0] <= b_wdata[7:0];
        if (b_be[1]) mem[b_addr][15:8] <= b_wdata[15:8];
        if (b_be[2]) mem[b_addr][23:16] <= b_wdata[23:16];
        if (b_be[3]) mem[b_addr][31:24] <= b_wdata[31:24];
      end
      b_rdata <= mem[b_addr];
    end
  end

endmodule : bram_imem
