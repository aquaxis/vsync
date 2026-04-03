// =============================================================================
// VSync - Task Control Block (TCB) Array
// RISC-V RV32IM Processor with Hardware RTOS
//
// File: tcb_array.sv
// Description: Hardware TCB register array with read/write/create/delete
//              interfaces and automatic time-slice decrement.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

/**
 * @brief Task Control Block register array
 *
 * Stores per-task state: task_id, prio_level, state, pc, sp, time_slice, valid.
 * Provides multiple access interfaces:
 *   - Random read (single port)
 *   - Full TCB write (single port)
 *   - State-only update (single port)
 *   - Task create (initializes a new TCB entry)
 *   - Task delete (invalidates a TCB entry)
 * Automatically decrements time_slice for the RUNNING task each clock cycle.
 * Exports bulk arrays of prio/state/valid/time_slice for the scheduler.
 */
module tcb_array #(
    parameter int MAX_TASKS    = 16,
    parameter int XLEN         = 32,
    parameter int TASK_ID_W    = 4,
    parameter int PRIORITY_W   = 4,
    parameter int TIME_SLICE_W = 16
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // =====================================================================
    // Read interface
    // =====================================================================
    input  logic [TASK_ID_W-1:0]      tcb_rd_id,
    output tcb_t                      tcb_rd_data,

    // =====================================================================
    // Write interface (full TCB update)
    // =====================================================================
    input  logic [TASK_ID_W-1:0]      tcb_wr_id,
    input  tcb_t                      tcb_wr_data,
    input  logic                      tcb_wr_en,

    // =====================================================================
    // State-only update interface
    // =====================================================================
    input  logic [TASK_ID_W-1:0]      state_wr_id,
    input  task_state_t               state_wr_data,
    input  logic                      state_wr_en,

    // =====================================================================
    // Task create interface
    // =====================================================================
    input  logic [TASK_ID_W-1:0]      create_id,
    input  logic [XLEN-1:0]           create_pc,
    input  logic [XLEN-1:0]           create_sp,
    input  logic [PRIORITY_W-1:0]     create_prio,
    input  logic                      create_en,

    // =====================================================================
    // Task delete interface
    // =====================================================================
    input  logic [TASK_ID_W-1:0]      delete_id,
    input  logic                      delete_en,

    // =====================================================================
    // Time-slice reload (for newly scheduled tasks)
    // =====================================================================
    input  logic [TASK_ID_W-1:0]      ts_reload_id,
    input  logic [TIME_SLICE_W-1:0]   ts_reload_val,
    input  logic                      ts_reload_en,

    // =====================================================================
    // Bulk outputs (to scheduler)
    // =====================================================================
    output logic [MAX_TASKS*PRIORITY_W-1:0]  all_prio,
    output logic [MAX_TASKS*3-1:0]           all_state,
    output logic [MAX_TASKS-1:0]             all_valid,
    output logic [MAX_TASKS*TIME_SLICE_W-1:0] all_time_slice,
    output logic [TASK_ID_W-1:0]      running_task_id
);

    // =========================================================================
    // TCB register array - individual field arrays for iverilog compatibility
    // =========================================================================
    logic [TASK_ID_W-1:0]    tcb_task_id    [MAX_TASKS];
    logic [PRIORITY_W-1:0]   tcb_prio_level [MAX_TASKS];
    logic [2:0]              tcb_state_r    [MAX_TASKS];
    logic [XLEN-1:0]         tcb_pc         [MAX_TASKS];
    logic [XLEN-1:0]         tcb_sp         [MAX_TASKS];
    logic [TIME_SLICE_W-1:0] tcb_time_slice [MAX_TASKS];
    logic [MAX_TASKS-1:0]    tcb_valid_r;  // packed vector for iverilog compatibility

    // =========================================================================
    // Read interface (combinational) - pack into tcb_t struct
    // =========================================================================
    assign tcb_rd_data.task_id    = tcb_task_id[tcb_rd_id];
    assign tcb_rd_data.prio_level = tcb_prio_level[tcb_rd_id];
    assign tcb_rd_data.state      = task_state_t'(tcb_state_r[tcb_rd_id]);
    assign tcb_rd_data.pc         = tcb_pc[tcb_rd_id];
    assign tcb_rd_data.sp         = tcb_sp[tcb_rd_id];
    assign tcb_rd_data.time_slice = tcb_time_slice[tcb_rd_id];
    assign tcb_rd_data.valid      = tcb_valid_r[tcb_rd_id]; // packed vector bit select

    // =========================================================================
    // Bulk output generation (combinational)
    // =========================================================================
    logic [TASK_ID_W-1:0] running_id_comb;
    logic                 running_found;

    // Bulk output: packed vector assigns for IVerilog compatibility
    assign all_valid = tcb_valid_r;

    // Generate packed vector outputs from unpacked internal arrays
    genvar gi;
    generate
        for (gi = 0; gi < MAX_TASKS; gi++) begin : gen_bulk_pack
            assign all_prio[gi*PRIORITY_W +: PRIORITY_W] = tcb_prio_level[gi];
            assign all_state[gi*3 +: 3]                  = tcb_state_r[gi];
            assign all_time_slice[gi*TIME_SLICE_W +: TIME_SLICE_W] = tcb_time_slice[gi];
        end
    endgenerate

    always_comb begin
        running_id_comb = '0;
        running_found   = 1'b0;
        for (int i = 0; i < MAX_TASKS; i++) begin
            // Find running task (first match) - use tcb_valid_r directly
            if (tcb_valid_r[i] &&
                tcb_state_r[i] == TASK_RUNNING &&
                !running_found) begin
                running_id_comb = i[TASK_ID_W-1:0];
                running_found   = 1'b1;
            end
        end
    end

    assign running_task_id = running_id_comb;

    // =========================================================================
    // TCB register update logic
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset: invalidate all TCB entries
            tcb_valid_r <= '0;  // packed vector reset
            for (int i = 0; i < MAX_TASKS; i++) begin
                tcb_task_id[i]    <= i[TASK_ID_W-1:0];
                tcb_prio_level[i] <= '0;
                tcb_state_r[i]    <= TASK_DORMANT;
                tcb_pc[i]         <= '0;
                tcb_sp[i]         <= '0;
                tcb_time_slice[i] <= '0;
            end
        end else begin
            // ---------------------------------------------------------------
            // Auto-decrement time_slice for RUNNING task
            // ---------------------------------------------------------------
            for (int i = 0; i < MAX_TASKS; i++) begin
                if (tcb_valid_r[i] &&
                    tcb_state_r[i] == TASK_RUNNING &&
                    tcb_time_slice[i] > '0) begin
                    tcb_time_slice[i] <= tcb_time_slice[i] - 1'b1;
                end
            end

            // ---------------------------------------------------------------
            // Task create: initialize a new TCB entry
            // ---------------------------------------------------------------
            if (create_en) begin
                tcb_task_id[create_id]    <= create_id;
                tcb_prio_level[create_id] <= create_prio;
                tcb_state_r[create_id]    <= TASK_READY;
                tcb_pc[create_id]         <= create_pc;
                tcb_sp[create_id]         <= create_sp;
                tcb_time_slice[create_id] <= {TIME_SLICE_W{1'b1}};  // Max slice
                tcb_valid_r[create_id]    <= 1'b1;
            end

            // ---------------------------------------------------------------
            // Task delete: invalidate a TCB entry
            // ---------------------------------------------------------------
            if (delete_en) begin
                tcb_state_r[delete_id] <= TASK_DORMANT;
                tcb_valid_r[delete_id] <= 1'b0;
            end

            // ---------------------------------------------------------------
            // Full TCB write
            // ---------------------------------------------------------------
            if (tcb_wr_en) begin
                tcb_task_id[tcb_wr_id]    <= tcb_wr_data.task_id;
                tcb_prio_level[tcb_wr_id] <= tcb_wr_data.prio_level;
                tcb_state_r[tcb_wr_id]    <= tcb_wr_data.state;
                tcb_pc[tcb_wr_id]         <= tcb_wr_data.pc;
                tcb_sp[tcb_wr_id]         <= tcb_wr_data.sp;
                tcb_time_slice[tcb_wr_id] <= tcb_wr_data.time_slice;
                tcb_valid_r[tcb_wr_id]    <= tcb_wr_data.valid;
            end

            // ---------------------------------------------------------------
            // State-only update (higher priority than full write for state)
            // ---------------------------------------------------------------
            if (state_wr_en) begin
                tcb_state_r[state_wr_id] <= state_wr_data;
            end

            // ---------------------------------------------------------------
            // Time-slice reload
            // ---------------------------------------------------------------
            if (ts_reload_en) begin
                tcb_time_slice[ts_reload_id] <= ts_reload_val;
            end
        end
    end

endmodule : tcb_array
