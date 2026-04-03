// =============================================================================
// VSync - Task Scheduler (Priority-Based Preemptive)
// RISC-V RV32IM Processor with Hardware RTOS
//
// File: task_scheduler.sv
// Description: Priority-based preemptive task scheduler with linear TCB scan,
//              time-slice management, and context switch request generation.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

/**
 * @brief Priority-based preemptive task scheduler
 *
 * Scans all TCB entries to find the highest-priority READY task.
 * Issues context switch requests when a higher-priority task is found
 * or the current task's time-slice expires.
 *
 * Scheduling triggers:
 *   - Time-slice expiration
 *   - Task state change (e.g., BLOCKED -> READY)
 *   - Explicit yield (SYS_TASK_YIELD)
 *   - Higher-priority task becomes READY
 *
 * Tie-breaking: lowest task_id wins (for same priority).
 */
module task_scheduler #(
    parameter int MAX_TASKS  = 16,
    parameter int TASK_ID_W  = 4,
    parameter int PRIORITY_W = 4
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // Scheduling trigger
    input  logic                      sched_trigger,      // Request scheduling

    // Current running task
    input  logic [TASK_ID_W-1:0]      current_task_id,

    // TCB bulk status from tcb_array (packed vectors for IVerilog compatibility)
    input  logic [MAX_TASKS*PRIORITY_W-1:0] tcb_prio,          // Priority levels (packed)
    input  logic [MAX_TASKS*3-1:0]          tcb_state,         // Task states (packed)
    input  logic [MAX_TASKS-1:0]            tcb_valid,         // Valid flags (packed)

    // Scheduler outputs
    output logic [TASK_ID_W-1:0]      next_task_id,       // Selected next task
    output logic                      switch_request,     // Context switch needed
    output logic                      sched_busy,         // Scheduler is working
    output logic                      sched_done          // Scheduling complete pulse
);

    // =========================================================================
    // Scheduler FSM states
    // =========================================================================
    typedef enum logic [2:0] {
        SCHED_IDLE    = 3'b000,
        SCHED_SCAN    = 3'b001,
        SCHED_PREEMPT = 3'b010,
        SCHED_SWITCH  = 3'b011,
        SCHED_DONE    = 3'b100
    } sched_state_t;

    sched_state_t                  state, state_next;

    // =========================================================================
    // Internal registers
    // =========================================================================
    logic [$clog2(MAX_TASKS)-1:0]  scan_idx;             // Current scan index
    logic [TASK_ID_W-1:0]          best_task_id;          // Best candidate task ID
    logic [PRIORITY_W-1:0]         best_prio;             // Best candidate priority
    logic                          found_ready;           // At least one READY task found

    logic [TASK_ID_W-1:0]          next_task_id_reg;
    logic                          switch_request_reg;

    // =========================================================================
    // Output assignments
    // =========================================================================
    assign next_task_id   = next_task_id_reg;
    assign switch_request = switch_request_reg;
    assign sched_busy     = (state != SCHED_IDLE);
    assign sched_done     = (state == SCHED_DONE);

    // =========================================================================
    // Scheduler FSM
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= SCHED_IDLE;
            scan_idx           <= '0;
            best_task_id       <= '0;
            best_prio          <= '0;
            found_ready        <= 1'b0;
            next_task_id_reg   <= '0;
            switch_request_reg <= 1'b0;
        end else begin
            case (state)
                // ---------------------------------------------------------
                // IDLE: Wait for scheduling trigger
                // ---------------------------------------------------------
                SCHED_IDLE: begin
                    switch_request_reg <= 1'b0;
                    if (sched_trigger) begin
                        state       <= SCHED_SCAN;
                        scan_idx    <= '0;
                        best_task_id <= '0;
                        best_prio   <= '0;
                        found_ready <= 1'b0;
                    end
                end

                // ---------------------------------------------------------
                // SCAN: Linear scan all TCBs for highest-priority READY task
                // ---------------------------------------------------------
                SCHED_SCAN: begin
                    // Check current entry (packed vector indexing)
                    if (tcb_valid[scan_idx] &&
                        tcb_state[scan_idx*3 +: 3] == TASK_READY) begin
                        // Found a READY task - compare priority
                        // Higher numerical value = higher priority
                        if (!found_ready ||
                            tcb_prio[scan_idx*PRIORITY_W +: PRIORITY_W] > best_prio ||
                            (tcb_prio[scan_idx*PRIORITY_W +: PRIORITY_W] == best_prio &&
                             scan_idx[TASK_ID_W-1:0] < best_task_id)) begin
                            best_task_id <= scan_idx[TASK_ID_W-1:0];
                            best_prio    <= tcb_prio[scan_idx*PRIORITY_W +: PRIORITY_W];
                            found_ready  <= 1'b1;
                        end
                    end

                    // Advance or finish scan
                    if (scan_idx == MAX_TASKS - 1) begin
                        state <= SCHED_PREEMPT;
                    end else begin
                        scan_idx <= scan_idx + 1'b1;
                    end
                end

                // ---------------------------------------------------------
                // PREEMPT: Compare best candidate with current running task
                // ---------------------------------------------------------
                SCHED_PREEMPT: begin
                    if (found_ready) begin
                        // Check if preemption is needed (packed vector indexing)
                        if (best_task_id != current_task_id &&
                            (best_prio > tcb_prio[current_task_id*PRIORITY_W +: PRIORITY_W] ||
                             tcb_state[current_task_id*3 +: 3] != TASK_RUNNING)) begin
                            // Preemption needed
                            next_task_id_reg <= best_task_id;
                            state            <= SCHED_SWITCH;
                        end else begin
                            // No preemption - current task continues
                            next_task_id_reg <= current_task_id;
                            state            <= SCHED_DONE;
                        end
                    end else begin
                        // No READY task found - keep current (or idle)
                        next_task_id_reg <= current_task_id;
                        state            <= SCHED_DONE;
                    end
                end

                // ---------------------------------------------------------
                // SWITCH: Issue context switch request
                // ---------------------------------------------------------
                SCHED_SWITCH: begin
                    switch_request_reg <= 1'b1;
                    state              <= SCHED_DONE;
                end

                // ---------------------------------------------------------
                // DONE: Signal completion, return to IDLE
                // ---------------------------------------------------------
                SCHED_DONE: begin
                    state <= SCHED_IDLE;
                end

                default: begin
                    state <= SCHED_IDLE;
                end
            endcase
        end
    end

endmodule : task_scheduler
