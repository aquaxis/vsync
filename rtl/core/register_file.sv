// =============================================================================
// VSync - Register File
// RISC-V RV32IM Processor
//
// File: register_file.sv
// Description: 32x32-bit register file with 2 read ports, 1 write port.
//              x0 is hardwired to zero.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module register_file (
    input  logic                    clk,
    input  logic                    rst_n,

    // Read port 1
    input  logic [REG_ADDR_W-1:0]  rs1_addr,
    output logic [XLEN-1:0]        rs1_data,

    // Read port 2
    input  logic [REG_ADDR_W-1:0]  rs2_addr,
    output logic [XLEN-1:0]        rs2_data,

    // Write port
    input  logic [REG_ADDR_W-1:0]  rd_addr,
    input  logic [XLEN-1:0]        rd_data,
    input  logic                    reg_write
);

    // =========================================================================
    // Register array (x0 ~ x31)
    // =========================================================================
    logic [XLEN-1:0] regs [NUM_REGS];

    // =========================================================================
    // Write logic: synchronous write on rising edge of clk
    // x0 writes are ignored (hardwired zero)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_REGS; i++) begin
                regs[i] <= '0;
            end
        end else if (reg_write && (rd_addr != '0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

    // =========================================================================
    // Read logic: combinational (asynchronous) read with write bypass
    // x0 always returns zero.
    // When the write port writes to the same register being read in the
    // same cycle, the new (written) value is forwarded to the read port.
    // This write-first bypass ensures that the ID stage reads the most
    // recent value when WB writes and ID reads the same register
    // simultaneously.
    // =========================================================================
    assign rs1_data = (rs1_addr == '0)                                ? '0 :
                      (reg_write && (rd_addr != '0) && (rd_addr == rs1_addr)) ? rd_data :
                      regs[rs1_addr];
    assign rs2_data = (rs2_addr == '0)                                ? '0 :
                      (reg_write && (rd_addr != '0) && (rd_addr == rs2_addr)) ? rd_data :
                      regs[rs2_addr];

endmodule : register_file
