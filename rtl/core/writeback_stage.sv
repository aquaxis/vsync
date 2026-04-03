// =============================================================================
// VSync - Writeback Stage
// RISC-V RV32IM Processor
//
// File: writeback_stage.sv
// Description: Writeback data selection based on wb_sel control signal.
//              Selects from ALU result, memory data, PC+4, or CSR data.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module writeback_stage (
    // Pipeline input from MEM/WB
    input  mem_wb_reg_t             mem_wb_reg,

    // Writeback outputs to register file
    output logic [REG_ADDR_W-1:0]   rd_addr,
    output logic [XLEN-1:0]         rd_data,
    output logic                     reg_write
);

    // =========================================================================
    // Writeback data selection (combinational)
    // =========================================================================
    always_comb begin
        case (mem_wb_reg.wb_sel)
            2'b00:   rd_data = mem_wb_reg.alu_result;                  // ALU result
            2'b01:   rd_data = mem_wb_reg.mem_rdata;                   // Memory read data
            2'b10:   rd_data = mem_wb_reg.pc + 32'd4;                  // PC+4 (JAL/JALR link)
            2'b11:   rd_data = mem_wb_reg.csr_rdata;                   // CSR read data
            default: rd_data = mem_wb_reg.alu_result;
        endcase
    end

    // =========================================================================
    // Pass through register address and write enable
    // =========================================================================
    assign rd_addr   = mem_wb_reg.rd_addr;
    assign reg_write = mem_wb_reg.reg_write & mem_wb_reg.valid;

endmodule : writeback_stage
