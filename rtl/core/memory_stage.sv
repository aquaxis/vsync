// =============================================================================
// VSync - Memory Stage
// RISC-V RV32IM Processor
//
// File: memory_stage.sv
// Description: Memory access stage for load/store operations with byte/half/word
//              selection, sign/zero extension, and MEM/WB pipeline register.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module memory_stage (
    input  logic                clk,
    input  logic                rst_n,

    // Pipeline input from EX/MEM
    input  ex_mem_reg_t         ex_mem_reg,

    // Data memory interface
    input  logic [XLEN-1:0]    dmem_rdata,
    output logic [XLEN-1:0]    dmem_addr,
    output logic [XLEN-1:0]    dmem_wdata,
    output logic                dmem_we,
    output logic [3:0]          dmem_be,
    output logic                dmem_re,

    // Pipeline control
    input  logic                stall,
    input  logic                flush,

    // Pipeline output to MEM/WB
    output mem_wb_reg_t         mem_wb_reg
);

    // =========================================================================
    // Internal signals
    // =========================================================================
    logic [XLEN-1:0]   load_data;
    logic [1:0]         byte_offset;
    logic [2:0]         mem_funct3;

    assign byte_offset = ex_mem_reg.alu_result[1:0];
    assign mem_funct3  = ex_mem_reg.mem_funct3;

    // =========================================================================
    // Memory address output
    // =========================================================================
    assign dmem_addr = ex_mem_reg.alu_result;

    // =========================================================================
    // Memory read enable
    // =========================================================================
    assign dmem_re = ex_mem_reg.mem_read & ex_mem_reg.valid;

    // =========================================================================
    // Memory write enable
    // =========================================================================
    assign dmem_we = ex_mem_reg.mem_write & ex_mem_reg.valid & ~flush;

    // =========================================================================
    // Store data and byte enable generation (shift-based, iverilog-safe)
    // =========================================================================
    logic [4:0] store_shift;
    assign store_shift = {byte_offset, 3'b000};  // byte_offset * 8

    always_comb begin
        dmem_wdata = '0;
        dmem_be    = 4'b0000;

        if (ex_mem_reg.mem_write && ex_mem_reg.valid) begin
            if (mem_funct3 == F3_SB) begin
                // SB: Store byte — shift data and byte-enable to correct lane
                dmem_wdata = {24'b0, ex_mem_reg.rs2_data[7:0]} << store_shift;
                dmem_be    = 4'b0001 << byte_offset;
            end else if (mem_funct3 == F3_SH) begin
                // SH: Store halfword
                dmem_wdata = byte_offset[1]
                    ? {ex_mem_reg.rs2_data[15:0], 16'b0}
                    : {16'b0, ex_mem_reg.rs2_data[15:0]};
                dmem_be    = byte_offset[1] ? 4'b1100 : 4'b0011;
            end else if (mem_funct3 == F3_SW) begin
                // SW: Store word
                dmem_wdata = ex_mem_reg.rs2_data;
                dmem_be    = 4'b1111;
            end
        end
    end

    // =========================================================================
    // Load data selection and sign/zero extension (shift-based, iverilog-safe)
    //
    // Uses right-shift to align the target byte/halfword to bits [7:0]/[15:0],
    // then applies sign or zero extension. This avoids the iverilog
    // "constant selects in always_*" limitation that corrupts case-based
    // byte-lane selection.
    // =========================================================================
    logic [4:0]  load_shift;
    logic [31:0] shifted_rdata;
    assign load_shift    = {byte_offset, 3'b000};  // byte_offset * 8
    assign shifted_rdata = dmem_rdata >> load_shift;

    always_comb begin
        load_data = '0;

        if (mem_funct3 == F3_LB) begin
            // LB: Load byte (sign-extended)
            load_data = {{24{shifted_rdata[7]}}, shifted_rdata[7:0]};
        end else if (mem_funct3 == F3_LH) begin
            // LH: Load halfword (sign-extended)
            if (byte_offset[1])
                load_data = {{16{dmem_rdata[31]}}, dmem_rdata[31:16]};
            else
                load_data = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
        end else if (mem_funct3 == F3_LW) begin
            // LW: Load word
            load_data = dmem_rdata;
        end else if (mem_funct3 == F3_LBU) begin
            // LBU: Load byte unsigned (zero-extended)
            load_data = {24'b0, shifted_rdata[7:0]};
        end else if (mem_funct3 == F3_LHU) begin
            // LHU: Load halfword unsigned (zero-extended)
            if (byte_offset[1])
                load_data = {16'b0, dmem_rdata[31:16]};
            else
                load_data = {16'b0, dmem_rdata[15:0]};
        end else begin
            load_data = dmem_rdata;
        end
    end

    // =========================================================================
    // MEM/WB Pipeline Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_reg <= '0;
        end else if (flush) begin
            mem_wb_reg <= '0;
        end else if (!stall) begin
            mem_wb_reg.pc         <= ex_mem_reg.pc;
            mem_wb_reg.alu_result <= ex_mem_reg.alu_result;
            mem_wb_reg.mem_rdata  <= load_data;
            mem_wb_reg.csr_rdata  <= ex_mem_reg.csr_rdata;
            mem_wb_reg.rd_addr    <= ex_mem_reg.rd_addr;
            mem_wb_reg.reg_write  <= ex_mem_reg.reg_write & ex_mem_reg.valid;
            mem_wb_reg.wb_sel     <= ex_mem_reg.wb_sel;
            mem_wb_reg.valid      <= ex_mem_reg.valid;
        end
    end

endmodule : memory_stage
