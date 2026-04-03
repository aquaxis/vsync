// =============================================================================
// VSync - Execute Stage
// RISC-V RV32IM Processor
//
// File: execute_stage.sv
// Description: Execute pipeline stage - instantiates ALU, branch unit, and
//              multiplier/divider. Handles forwarding, operand selection,
//              and EX/MEM pipeline register output.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

/**
 * @brief Execute pipeline stage for the 5-stage RISC-V pipeline
 *
 * Responsibilities:
 *   - Forwarding MUX: selects operand source based on hazard unit signals
 *   - ALU operand selection: rs1/PC for A, rs2/immediate for B
 *   - ALU computation
 *   - Branch condition evaluation and target calculation
 *   - M-extension multiply/divide operations
 *   - EX/MEM pipeline register update
 */
module execute_stage (
    input  logic             clk,
    input  logic             rst_n,

    // Pipeline input (from ID/EX register)
    input  id_ex_reg_t       id_ex_reg,

    // Forwarding control (from hazard unit)
    input  logic [1:0]       forward_a,        // 00: reg, 01: EX/MEM, 10: MEM/WB
    input  logic [1:0]       forward_b,        // 00: reg, 01: EX/MEM, 10: MEM/WB

    // Forwarding data sources
    input  logic [XLEN-1:0]  ex_mem_alu_result, // EX/MEM stage forwarded result
    input  logic [XLEN-1:0]  wb_data,           // MEM/WB stage forwarded result

    // Pipeline control
    input  logic             stall,             // Stall this stage
    input  logic             flush,             // Flush this stage

    // Pipeline output (EX/MEM register)
    output ex_mem_reg_t      ex_mem_reg,

    // Branch/jump outputs (to IF stage and hazard unit)
    output logic             branch_taken,
    output logic [XLEN-1:0]  branch_target,

    // M-extension status
    output logic             mext_busy
);

    // =========================================================================
    // Packed struct field extraction (iverilog workaround)
    // =========================================================================
    // iverilog incorrectly passes the full 189-bit packed struct instead of
    // individual fields to module ports ("expects N bits, got 189") and has
    // issues with constant selects in always_* blocks. Extracting fields via
    // continuous assign wires works correctly on all simulators.
    // =========================================================================
`ifdef IVERILOG
    wire [3:0] iv_alu_op          = id_ex_reg.ctrl.alu_op;
    wire       iv_alu_src_a       = id_ex_reg.ctrl.alu_src_a;
    wire       iv_alu_src_b       = id_ex_reg.ctrl.alu_src_b;
    wire [2:0] iv_branch_funct3   = id_ex_reg.ctrl.branch_funct3;
    wire       iv_branch          = id_ex_reg.ctrl.branch;
    wire       iv_jal             = id_ex_reg.ctrl.jal;
    wire       iv_jalr            = id_ex_reg.ctrl.jalr;
    wire       iv_mext_en         = id_ex_reg.ctrl.mext_en;
    wire [2:0] iv_mext_op         = id_ex_reg.ctrl.mext_op;
    wire       iv_reg_write       = id_ex_reg.ctrl.reg_write;
    wire [1:0] iv_wb_sel          = id_ex_reg.ctrl.wb_sel;
    wire       iv_mem_read        = id_ex_reg.ctrl.mem_read;
    wire       iv_mem_write       = id_ex_reg.ctrl.mem_write;
    wire [2:0] iv_mem_funct3      = id_ex_reg.ctrl.mem_funct3;
`endif

    // =========================================================================
    // Forwarding MUX - select actual operand values
    // =========================================================================
    logic [XLEN-1:0] rs1_forwarded;
    logic [XLEN-1:0] rs2_forwarded;

    // Debug probe wires for testbench access
`ifdef IVERILOG
    wire [31:0] dbg_rs1_forwarded = rs1_forwarded;
    wire [31:0] dbg_rs2_forwarded = rs2_forwarded;
    wire [31:0] dbg_wb_data       = wb_data;
`endif

    /** @brief Forwarding MUX for rs1 operand */
    always_comb begin
        case (forward_a)
            2'b00:   rs1_forwarded = id_ex_reg.rs1_data;     // No forwarding
            2'b01:   rs1_forwarded = ex_mem_alu_result;       // Forward from EX/MEM
            2'b10:   rs1_forwarded = wb_data;                 // Forward from MEM/WB
            default: rs1_forwarded = id_ex_reg.rs1_data;
        endcase
    end

    /** @brief Forwarding MUX for rs2 operand */
    always_comb begin
        case (forward_b)
            2'b00:   rs2_forwarded = id_ex_reg.rs2_data;     // No forwarding
            2'b01:   rs2_forwarded = ex_mem_alu_result;       // Forward from EX/MEM
            2'b10:   rs2_forwarded = wb_data;                 // Forward from MEM/WB
            default: rs2_forwarded = id_ex_reg.rs2_data;
        endcase
    end

    // =========================================================================
    // ALU operand selection
    // =========================================================================
    logic [XLEN-1:0] alu_operand_a;
    logic [XLEN-1:0] alu_operand_b;

    // Operand A: rs1 (forwarded) or PC
`ifdef IVERILOG
    assign alu_operand_a = iv_alu_src_a ? id_ex_reg.pc : rs1_forwarded;
`else
    assign alu_operand_a = id_ex_reg.ctrl.alu_src_a ? id_ex_reg.pc : rs1_forwarded;
`endif

    // Operand B: rs2 (forwarded) or immediate
`ifdef IVERILOG
    assign alu_operand_b = iv_alu_src_b ? id_ex_reg.immediate : rs2_forwarded;
`else
    assign alu_operand_b = id_ex_reg.ctrl.alu_src_b ? id_ex_reg.immediate : rs2_forwarded;
`endif

    // =========================================================================
    // ALU instantiation
    // =========================================================================
    logic [XLEN-1:0] alu_result;
    logic             alu_zero;

    alu u_alu (
        .operand_a (alu_operand_a),
        .operand_b (alu_operand_b),
    `ifdef IVERILOG
        .alu_op    (iv_alu_op),
    `else
        .alu_op    (id_ex_reg.ctrl.alu_op),
    `endif
        .result    (alu_result),
        .zero      (alu_zero)
    );

    // =========================================================================
    // Branch unit instantiation
    // =========================================================================
    branch_unit u_branch_unit (
        .rs1_data      (rs1_forwarded),
        .rs2_data      (rs2_forwarded),
        .pc            (id_ex_reg.pc),
        .immediate     (id_ex_reg.immediate),
    `ifdef IVERILOG
        .branch_funct3 (iv_branch_funct3),
        .is_branch     (iv_branch && id_ex_reg.valid),
        .is_jal        (iv_jal    && id_ex_reg.valid),
        .is_jalr       (iv_jalr   && id_ex_reg.valid),
    `else
        .branch_funct3 (id_ex_reg.ctrl.branch_funct3),
        .is_branch     (id_ex_reg.ctrl.branch && id_ex_reg.valid),
        .is_jal        (id_ex_reg.ctrl.jal    && id_ex_reg.valid),
        .is_jalr       (id_ex_reg.ctrl.jalr   && id_ex_reg.valid),
    `endif
        .branch_taken  (branch_taken),
        .branch_target (branch_target)
    );

    // =========================================================================
    // Multiplier / Divider instantiation (M-extension)
    // =========================================================================
    logic [XLEN-1:0] mext_result;
    logic             mext_done;
    logic             mext_start;

    // Start M-extension operation when valid and enabled, not stalled
`ifdef IVERILOG
    assign mext_start = iv_mext_en && id_ex_reg.valid && !stall;
`else
    assign mext_start = id_ex_reg.ctrl.mext_en && id_ex_reg.valid && !stall;
`endif

    multiplier_divider u_muldiv (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (mext_start),
    `ifdef IVERILOG
        .op        (iv_mext_op),
    `else
        .op        (id_ex_reg.ctrl.mext_op),
    `endif
        .operand_a (rs1_forwarded),
        .operand_b (rs2_forwarded),
        .result    (mext_result),
        .done      (mext_done),
        .busy      (mext_busy)
    );

    // =========================================================================
    // Result selection: ALU or M-extension
    // =========================================================================
    logic [XLEN-1:0] exe_result;
`ifdef IVERILOG
    assign exe_result = (iv_mext_en && mext_done) ? mext_result : alu_result;
`else
    assign exe_result = (id_ex_reg.ctrl.mext_en && mext_done) ? mext_result : alu_result;
`endif

    // =========================================================================
    // EX/MEM Pipeline Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_reg.pc         <= '0;
            ex_mem_reg.alu_result <= '0;
            ex_mem_reg.rs2_data   <= '0;
            ex_mem_reg.csr_rdata  <= '0;
            ex_mem_reg.rd_addr    <= '0;
            ex_mem_reg.reg_write  <= 1'b0;
            ex_mem_reg.wb_sel     <= 2'b00;
            ex_mem_reg.mem_read   <= 1'b0;
            ex_mem_reg.mem_write  <= 1'b0;
            ex_mem_reg.mem_funct3 <= 3'b000;
            ex_mem_reg.valid      <= 1'b0;
        end else if (stall) begin
            // Stall: hold current values - takes priority over flush to
            // preserve in-flight memory operations in the EX/MEM register.
        end else if (flush) begin
            // Flush: invalidate the pipeline register (insert bubble)
            ex_mem_reg.pc         <= '0;
            ex_mem_reg.alu_result <= '0;
            ex_mem_reg.rs2_data   <= '0;
            ex_mem_reg.csr_rdata  <= '0;
            ex_mem_reg.rd_addr    <= '0;
            ex_mem_reg.reg_write  <= 1'b0;
            ex_mem_reg.wb_sel     <= 2'b00;
            ex_mem_reg.mem_read   <= 1'b0;
            ex_mem_reg.mem_write  <= 1'b0;
            ex_mem_reg.mem_funct3 <= 3'b000;
            ex_mem_reg.valid      <= 1'b0;
        end else begin
            ex_mem_reg.pc         <= id_ex_reg.pc;
            ex_mem_reg.alu_result <= exe_result;
            ex_mem_reg.rs2_data   <= rs2_forwarded;    // Store data (forwarded)
            ex_mem_reg.csr_rdata  <= '0;               // CSR data passed through later
            ex_mem_reg.rd_addr    <= id_ex_reg.rd_addr;
        `ifdef IVERILOG
            // Gate write-enable and memory-access signals with valid to prevent
            // suppress_valid bubbles (valid=0) from causing incorrect forwarding
            // or spurious memory operations in downstream pipeline stages.
            ex_mem_reg.reg_write  <= iv_reg_write & id_ex_reg.valid;
            ex_mem_reg.wb_sel     <= iv_wb_sel;
            ex_mem_reg.mem_read   <= iv_mem_read  & id_ex_reg.valid;
            ex_mem_reg.mem_write  <= iv_mem_write & id_ex_reg.valid;
            ex_mem_reg.mem_funct3 <= iv_mem_funct3;
        `else
            // Gate write-enable and memory-access signals with valid to prevent
            // suppress_valid bubbles (valid=0) from causing incorrect forwarding
            // or spurious memory operations in downstream pipeline stages.
            ex_mem_reg.reg_write  <= id_ex_reg.ctrl.reg_write & id_ex_reg.valid;
            ex_mem_reg.wb_sel     <= id_ex_reg.ctrl.wb_sel;
            ex_mem_reg.mem_read   <= id_ex_reg.ctrl.mem_read  & id_ex_reg.valid;
            ex_mem_reg.mem_write  <= id_ex_reg.ctrl.mem_write & id_ex_reg.valid;
            ex_mem_reg.mem_funct3 <= id_ex_reg.ctrl.mem_funct3;
        `endif
            ex_mem_reg.valid      <= id_ex_reg.valid;
        end
    end

endmodule : execute_stage
