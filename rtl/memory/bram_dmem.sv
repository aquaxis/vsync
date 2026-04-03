// =============================================================================
// VSync - Block RAM Data Memory
//
// File: bram_dmem.sv
// Description: 16KB data memory using Xilinx BRAM inference pattern.
//              Supports byte-enable writes and synchronous read/write.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

module bram_dmem
  import vsync_pkg::*;
#(
    parameter int DEPTH      = 4096,  // 4096 x 32bit = 16KB
    parameter int ADDR_WIDTH = 12,    // Word address width (log2(4096) = 12)
    parameter int DATA_WIDTH = 32,    // 32-bit data width
    parameter     INIT_FILE  = ""     // Optional hex initialization file
) (
    input  logic                    clk,    // System clock
    input  logic [  ADDR_WIDTH-1:0] addr,   // Word address
    input  logic [  DATA_WIDTH-1:0] wdata,  // Write data
    input  logic                    we,     // Write enable
    input  logic [DATA_WIDTH/8-1:0] be,     // Byte enable (4 bits for 32-bit data)
    input  logic                    re,     // Read enable
    output logic [  DATA_WIDTH-1:0] rdata   // Read data (1-cycle latency)
);

  // =========================================================================
  // Memory Array - Xilinx BRAM Inference Pattern
  // =========================================================================
  logic [DATA_WIDTH-1:0] mem[0:DEPTH-1];

  // =========================================================================
  // Optional Hex File Initialization
  // =========================================================================
  initial begin
    if (INIT_FILE != "") begin
      $display("Load dmem filename: %s", INIT_FILE);
      $readmemh(INIT_FILE, mem);
    end
  end

  // =========================================================================
  // Synchronous Read/Write with Byte Enable
  // =========================================================================
  // Xilinx BRAM inference: all operations inside a single always_ff block
  always_ff @(posedge clk) begin
    // Byte-enable write
    if (we) begin
      if (be[0]) mem[addr][7:0] <= wdata[7:0];
      if (be[1]) mem[addr][15:8] <= wdata[15:8];
      if (be[2]) mem[addr][23:16] <= wdata[23:16];
      if (be[3]) mem[addr][31:24] <= wdata[31:24];
    end

    // Synchronous read (1-cycle latency)
    if (re) begin
      rdata <= mem[addr];
    end
  end

endmodule : bram_dmem
