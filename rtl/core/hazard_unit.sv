// =============================================================================
// VSync - Hazard Detection and Forwarding Unit
// RISC-V RV32IM Processor Pipeline - Hazard Control
//
// File: hazard_unit.sv
// Description: Data hazard detection (load-use stall), data forwarding
//              control (EX→EX, MEM→EX 2-stage forwarding), and control
//              hazard handling (branch/jump pipeline flush).
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module hazard_unit (
    // ID stage source register addresses (for load-use hazard detection)
    input  logic [REG_ADDR_W-1:0] id_rs1_addr,     // ID stage rs1 address
    input  logic [REG_ADDR_W-1:0] id_rs2_addr,     // ID stage rs2 address

    // EX stage source register addresses (for forwarding decisions)
    input  logic [REG_ADDR_W-1:0] ex_rs1_addr,     // EX stage rs1 address
    input  logic [REG_ADDR_W-1:0] ex_rs2_addr,     // EX stage rs2 address

    // EX/MEM stage information
    input  logic [REG_ADDR_W-1:0] ex_mem_rd_addr,  // EX/MEM stage rd address
    input  logic                   ex_mem_reg_write, // EX/MEM stage register write enable
    input  logic                   ex_mem_mem_read,  // EX/MEM stage memory read (load instr)

    // MEM/WB stage information
    input  logic [REG_ADDR_W-1:0] mem_wb_rd_addr,  // MEM/WB stage rd address
    input  logic                   mem_wb_reg_write, // MEM/WB stage register write enable

    // Branch/Jump control
    input  logic                   branch_taken,     // Branch or jump taken

    // Hazard control output
    output hazard_ctrl_t           hazard_ctrl       // Combined hazard control signals
);

    // =========================================================================
    // Internal Signals
    // =========================================================================

    /** Load-use hazard detected at the ID stage (classic detection) */
    logic load_use_hazard_id;

    /** Load-use hazard detected at the EX stage (for stall-delayed cases) */
    logic load_use_hazard_ex;

    /** Combined load-use hazard flag */
    logic load_use_hazard;

    /** Forwarding select for operand A (rs1) */
    logic [1:0] fwd_a;

    /** Forwarding select for operand B (rs2) */
    logic [1:0] fwd_b;

    // Debug probe wires for testbench access
`ifdef IVERILOG
    wire dbg_luh_id = load_use_hazard_id;
    wire dbg_luh_ex = load_use_hazard_ex;
    wire dbg_luh    = load_use_hazard;
`endif

    // =========================================================================
    // Load-Use Hazard Detection
    // =========================================================================
    // A load-use hazard occurs when a load instruction in the EX/MEM stage
    // writes to a register that is read by a following instruction. Two
    // detection points are needed:
    //
    // 1. ID-stage detection (classic): the consuming instruction is in the
    //    ID stage when the load is in MEM. This is the normal case.
    //
    // 2. EX-stage detection: the consuming instruction has already advanced
    //    to the EX stage (e.g., due to a preceding memory stall that delayed
    //    the load reaching MEM). In this case, the EX stage instruction
    //    cannot use EX/MEM forwarding for loads (the data is the memory
    //    address, not the loaded value), so we must stall EX for 1 cycle.
    //
    // Condition:
    //   EX/MEM is a load (mem_read=1) AND
    //   EX/MEM destination matches one of the source registers AND
    //   destination is not x0
    // =========================================================================
    always_comb begin
        load_use_hazard_id = 1'b0;
        load_use_hazard_ex = 1'b0;

        if (ex_mem_mem_read && (ex_mem_rd_addr != 5'b0)) begin
            // Classic load-use: consuming instruction in ID stage
            if ((ex_mem_rd_addr == id_rs1_addr) ||
                (ex_mem_rd_addr == id_rs2_addr)) begin
                load_use_hazard_id = 1'b1;
            end
            // Delayed load-use: consuming instruction already in EX stage
            if ((ex_mem_rd_addr == ex_rs1_addr) ||
                (ex_mem_rd_addr == ex_rs2_addr)) begin
                load_use_hazard_ex = 1'b1;
            end
        end
    end

    assign load_use_hazard = load_use_hazard_id || load_use_hazard_ex;

    // =========================================================================
    // Data Forwarding Logic
    // =========================================================================
    // Two-stage forwarding to resolve RAW (Read After Write) data hazards
    // without stalling (except for load-use which requires 1-cycle stall).
    //
    // Forward select encoding:
    //   2'b00 = No forwarding, use register file value
    //   2'b01 = Forward from EX/MEM stage (most recent result)
    //   2'b10 = Forward from MEM/WB stage (older result)
    //
    // Priority: EX/MEM forwarding takes precedence over MEM/WB forwarding
    //           when both stages write to the same register.
    // =========================================================================

    // --- Forwarding for Operand A (rs1) ---
    // Uses EX stage source addresses (ex_rs1_addr) since the forwarding MUX
    // is in the execute stage and operates on the EX-stage instruction.
    //
    // BUG FIX: Do NOT forward from EX/MEM when the instruction is a LOAD.
    // For loads, EX/MEM.alu_result contains the memory ADDRESS (not the loaded
    // data). The loaded data is only available in MEM/WB after memory responds.
    // Forwarding the address causes consumers (especially branches like BNEZ)
    // to operate on wrong data. The load_use_hazard stall ensures the consumer
    // waits until MEM/WB forwarding can provide the correct loaded data.
    always_comb begin
        fwd_a = 2'b00;  // Default: no forwarding

        // Priority 1: Forward from EX/MEM (most recent, non-load only)
        if (ex_mem_reg_write && !ex_mem_mem_read &&
            (ex_mem_rd_addr != 5'b0) &&
            (ex_mem_rd_addr == ex_rs1_addr)) begin
            fwd_a = 2'b01;
        end
        // Priority 2: Forward from MEM/WB (older, only if EX/MEM doesn't match)
        else if (mem_wb_reg_write &&
                 (mem_wb_rd_addr != 5'b0) &&
                 (mem_wb_rd_addr == ex_rs1_addr)) begin
            fwd_a = 2'b10;
        end
    end

    // --- Forwarding for Operand B (rs2) ---
    // Uses EX stage source addresses (ex_rs2_addr) since the forwarding MUX
    // is in the execute stage and operates on the EX-stage instruction.
    always_comb begin
        fwd_b = 2'b00;  // Default: no forwarding

        // Priority 1: Forward from EX/MEM (most recent, non-load only)
        if (ex_mem_reg_write && !ex_mem_mem_read &&
            (ex_mem_rd_addr != 5'b0) &&
            (ex_mem_rd_addr == ex_rs2_addr)) begin
            fwd_b = 2'b01;
        end
        // Priority 2: Forward from MEM/WB (older, only if EX/MEM doesn't match)
        else if (mem_wb_reg_write &&
                 (mem_wb_rd_addr != 5'b0) &&
                 (mem_wb_rd_addr == ex_rs2_addr)) begin
            fwd_b = 2'b10;
        end
    end

    // =========================================================================
    // Stall Signal Generation
    // =========================================================================
    // Load-use hazard: stall pipeline stages to allow load data to become
    // available from memory.
    //   - Both ID-stage and EX-stage detection: stall IF and ID to hold
    //     instructions behind the consuming instruction.
    //   - EX stage is NOT stalled by the hazard unit: the EX/MEM register
    //     is flushed instead (bubble insertion).
    // =========================================================================
    assign hazard_ctrl.stall_if = load_use_hazard;
    assign hazard_ctrl.stall_id = load_use_hazard;
    assign hazard_ctrl.stall_ex = 1'b0;

    // =========================================================================
    // Flush Signal Generation
    // =========================================================================
    // Control hazard (branch/jump taken):
    //   - Flush IF (IF/ID register) and ID (ID/EX register) to cancel
    //     incorrectly fetched/decoded instructions behind the branch.
    //   - The EX stage (EX/MEM register) is NOT flushed by a branch, because
    //     the branch/jump instruction itself is in EX and may need to write
    //     back a result (e.g., JAL writes PC+4 to the link register).
    //
    // Load-use hazard (ID or EX detection):
    //   - Flush EX output (EX/MEM register) to insert a bubble and replay
    //     the consuming instruction after the load data becomes available.
    //
    // BUG FIX: Suppress branch flush during load_use_hazard_ex.
    // When load_use_hazard_ex is active, the branch instruction in EX has
    // incorrect operands (stale register file value or wrongly-forwarded
    // memory address from EX/MEM). Its branch_taken result is UNRELIABLE.
    // By suppressing flush_if/flush_id, we prevent the stale branch from
    // corrupting the pipeline. The branch will be correctly re-evaluated
    // when it replays in EX with the correct load data forwarded from MEM/WB.
    // Note: Only load_use_hazard_ex is gated (not load_use_hazard_id),
    // because in the _id case the branch in EX is a different instruction
    // whose operands are not affected by the load.
    // =========================================================================
    assign hazard_ctrl.flush_if  = branch_taken && !load_use_hazard_ex;
    assign hazard_ctrl.flush_id  = branch_taken && !load_use_hazard_ex;
    assign hazard_ctrl.flush_ex  = load_use_hazard;
    assign hazard_ctrl.flush_mem = 1'b0;

    // =========================================================================
    // Forwarding Output
    // =========================================================================
    assign hazard_ctrl.forward_a = fwd_a;
    assign hazard_ctrl.forward_b = fwd_b;

endmodule : hazard_unit
