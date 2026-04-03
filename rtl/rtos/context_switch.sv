// =============================================================================
// VSync - Context Switch Unit (Register Bank Method)
// RISC-V RV32IM Processor with Hardware RTOS
//
// File: context_switch.sv
// Description: Hardware context switch using per-task register banks.
//              Saves/restores x1-x31 + PC via FSM-driven sequential copy.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

/**
 * @brief Context switch unit with register bank approach
 *
 * Each task has a dedicated register bank (32 x 32-bit registers + PC).
 * On context switch:
 *   1. SAVE phase: sequentially reads x1-x31 from CPU register file and
 *      stores them in the old task's register bank (31 cycles).
 *   2. LOAD phase: sequentially writes x1-x31 from the new task's register
 *      bank into the CPU register file (31 cycles).
 * During both phases, the pipeline is stalled.
 *
 * x0 is hardwired to zero in RISC-V and is not saved/restored.
 * SP is managed via x2 as part of the general register set.
 * PC is saved/restored separately via dedicated ports.
 */
module context_switch #(
    parameter int XLEN       = 32,
    parameter int NUM_REGS   = 32,
    parameter int TASK_ID_W  = 4,
    parameter int MAX_TASKS  = 16
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // =====================================================================
    // Scheduler interface
    // =====================================================================
    input  logic                      switch_req,         // Context switch request
    input  logic [TASK_ID_W-1:0]      old_task_id,        // Task to save
    input  logic [TASK_ID_W-1:0]      new_task_id,        // Task to restore

    // =====================================================================
    // CPU register file interface
    // =====================================================================
    input  logic [XLEN-1:0]           cpu_reg_rdata,      // Data read from CPU reg file
    output logic [4:0]                cpu_reg_addr,        // Register address to CPU
    output logic [XLEN-1:0]           cpu_reg_wdata,      // Data to write to CPU reg file
    output logic                      cpu_reg_we,          // Write enable to CPU reg file

    // =====================================================================
    // CPU PC interface
    // =====================================================================
    input  logic [XLEN-1:0]           cpu_pc,             // Current PC from CPU

    // =====================================================================
    // Outputs
    // =====================================================================
    output logic                      switch_done,        // Switch complete pulse
    output logic [XLEN-1:0]           restore_pc,         // PC to restore after switch
    output logic                      stall_pipeline,     // Stall CPU pipeline during switch
    output logic                      busy                // Unit is busy
);

    // =========================================================================
    // Context switch FSM states
    // =========================================================================
    typedef enum logic [2:0] {
        CTX_IDLE = 3'b000,
        CTX_SAVE = 3'b001,
        CTX_LOAD = 3'b010,
        CTX_DONE = 3'b011
    } ctx_state_t;

    ctx_state_t                    state;

    // =========================================================================
    // Register banks: MAX_TASKS x NUM_REGS x XLEN
    // =========================================================================
    // Note: reg_banks[task][0] is unused (x0 is always zero)
    logic [XLEN-1:0]              reg_banks [MAX_TASKS][NUM_REGS];

    // Per-task saved PC
    logic [XLEN-1:0]              saved_pc [MAX_TASKS];

    // =========================================================================
    // Internal registers
    // =========================================================================
    logic [4:0]                    reg_idx;           // Current register index (1-31)
    logic [TASK_ID_W-1:0]          old_id_latched;    // Latched old task ID
    logic [TASK_ID_W-1:0]          new_id_latched;    // Latched new task ID
    logic [XLEN-1:0]              restore_pc_reg;

    // =========================================================================
    // Output assignments
    // =========================================================================
    assign busy           = (state != CTX_IDLE);
    assign stall_pipeline = (state == CTX_SAVE) || (state == CTX_LOAD);
    assign switch_done    = (state == CTX_DONE);
    assign restore_pc     = restore_pc_reg;

    // =========================================================================
    // CPU register file access control (combinational)
    // =========================================================================
    always_comb begin
        cpu_reg_addr  = '0;
        cpu_reg_wdata = '0;
        cpu_reg_we    = 1'b0;

        case (state)
            CTX_SAVE: begin
                // Read from CPU register file: set address for current reg_idx
                cpu_reg_addr  = reg_idx;
                cpu_reg_wdata = '0;
                cpu_reg_we    = 1'b0;
            end

            CTX_LOAD: begin
                // Write to CPU register file: load from new task's bank
                cpu_reg_addr  = reg_idx;
                cpu_reg_wdata = reg_banks[new_id_latched][reg_idx];
                cpu_reg_we    = 1'b1;
            end

            default: begin
                cpu_reg_addr  = '0;
                cpu_reg_wdata = '0;
                cpu_reg_we    = 1'b0;
            end
        endcase
    end

    // =========================================================================
    // Context switch FSM
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= CTX_IDLE;
            reg_idx        <= 5'd1;
            old_id_latched <= '0;
            new_id_latched <= '0;
            restore_pc_reg <= '0;

            // Reset register banks and saved PCs
            for (int t = 0; t < MAX_TASKS; t++) begin
                saved_pc[t] <= '0;
                for (int r = 0; r < NUM_REGS; r++) begin
                    reg_banks[t][r] <= '0;
                end
            end
        end else begin
            case (state)
                // ---------------------------------------------------------
                // IDLE: Wait for switch request
                // ---------------------------------------------------------
                CTX_IDLE: begin
                    if (switch_req) begin
                        state          <= CTX_SAVE;
                        reg_idx        <= 5'd1;      // Start from x1 (skip x0)
                        old_id_latched <= old_task_id;
                        new_id_latched <= new_task_id;
                        // Save PC immediately
                        saved_pc[old_task_id] <= cpu_pc;
                    end
                end

                // ---------------------------------------------------------
                // SAVE: Read CPU registers and store in old task's bank
                // ---------------------------------------------------------
                CTX_SAVE: begin
                    // Store the value read from CPU (available this cycle for reg_idx)
                    reg_banks[old_id_latched][reg_idx] <= cpu_reg_rdata;

                    if (reg_idx == 5'd31) begin
                        // All registers saved, move to LOAD phase
                        state   <= CTX_LOAD;
                        reg_idx <= 5'd1;  // Reset for load phase
                    end else begin
                        reg_idx <= reg_idx + 5'd1;
                    end
                end

                // ---------------------------------------------------------
                // LOAD: Write new task's register bank to CPU
                // ---------------------------------------------------------
                CTX_LOAD: begin
                    if (reg_idx == 5'd31) begin
                        // All registers restored, finalize
                        state          <= CTX_DONE;
                        restore_pc_reg <= saved_pc[new_id_latched];
                    end else begin
                        reg_idx <= reg_idx + 5'd1;
                    end
                end

                // ---------------------------------------------------------
                // DONE: Signal completion, return to IDLE
                // ---------------------------------------------------------
                CTX_DONE: begin
                    state <= CTX_IDLE;
                end

                default: begin
                    state <= CTX_IDLE;
                end
            endcase
        end
    end

endmodule : context_switch
