// =============================================================================
// VSync - Hardware Semaphore
// RISC-V RV32IM Processor with Hardware RTOS
//
// File: hw_semaphore.sv
// Description: Hardware counting semaphore with atomic P/V operations.
//              Supports task blocking and priority-based wakeup.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module hw_semaphore #(
    parameter int NUM_SEMS    = 8,
    parameter int SEM_COUNT_W = 8,
    parameter int TASK_ID_W   = 4,
    parameter int MAX_TASKS   = 16
)(
    input  logic                                clk,
    input  logic                                rst_n,

    // Operation interface
    input  logic [1:0]                          sem_op,         // 00=NOP, 01=INIT, 10=WAIT, 11=POST
    input  logic [$clog2(NUM_SEMS)-1:0]         sem_id,
    input  logic [TASK_ID_W-1:0]                task_id,
    input  logic [SEM_COUNT_W-1:0]              init_count,
    input  logic [SEM_COUNT_W-1:0]              max_count,

    // Task priorities for wakeup selection
    input  logic [TASK_PRIORITY_W-1:0]          task_priorities [MAX_TASKS],

    // Outputs
    output logic                                sem_success,    // Operation succeeded
    output logic                                sem_block,      // Task should be blocked
    output logic [TASK_ID_W-1:0]                wake_task_id,   // Task to wake up
    output logic                                wake_valid,     // Wake signal valid
    output logic [SEM_COUNT_W-1:0]              sem_counts [NUM_SEMS]
);

    // =========================================================================
    // Semaphore operation encoding
    // =========================================================================
    localparam logic [1:0] SEM_NOP  = 2'b00;
    localparam logic [1:0] SEM_INIT = 2'b01;
    localparam logic [1:0] SEM_WAIT = 2'b10;
    localparam logic [1:0] SEM_POST = 2'b11;

    // =========================================================================
    // Per-semaphore state
    // =========================================================================
    logic [SEM_COUNT_W-1:0]  count_r     [NUM_SEMS];
    logic [SEM_COUNT_W-1:0]  max_count_r [NUM_SEMS];
    logic [MAX_TASKS-1:0]    wait_mask_r [NUM_SEMS];

    // =========================================================================
    // Highest-priority waiting task selection (combinational)
    // =========================================================================
    logic [TASK_ID_W-1:0]           best_wake_id;
    logic                           best_wake_found;
    logic [TASK_PRIORITY_W-1:0]     best_prio;

    always_comb begin
        best_wake_id    = '0;
        best_wake_found = 1'b0;
        best_prio       = '0;  // Lowest priority (higher number = higher priority)

        for (int i = 0; i < MAX_TASKS; i++) begin
            if (wait_mask_r[sem_id][i]) begin
                if (!best_wake_found || (task_priorities[i] > best_prio)) begin
                    best_wake_id    = TASK_ID_W'(i);
                    best_prio       = task_priorities[i];
                    best_wake_found = 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // Atomic semaphore operations (single always_ff block)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sem_success <= 1'b0;
            sem_block   <= 1'b0;
            wake_task_id <= '0;
            wake_valid  <= 1'b0;

            for (int i = 0; i < NUM_SEMS; i++) begin
                count_r[i]     <= '0;
                max_count_r[i] <= '0;
                wait_mask_r[i] <= '0;
            end
        end else begin
            // Default outputs: de-assert every cycle
            sem_success  <= 1'b0;
            sem_block    <= 1'b0;
            wake_task_id <= '0;
            wake_valid   <= 1'b0;

            case (sem_op)
                // -------------------------------------------------------------
                // INIT: Initialize semaphore count and max
                // -------------------------------------------------------------
                SEM_INIT: begin
                    count_r[sem_id]     <= init_count;
                    max_count_r[sem_id] <= max_count;
                    wait_mask_r[sem_id] <= '0;
                    sem_success         <= 1'b1;
                end

                // -------------------------------------------------------------
                // WAIT (P operation): Decrement or block
                // -------------------------------------------------------------
                SEM_WAIT: begin
                    if (count_r[sem_id] > '0) begin
                        // Resource available: decrement and succeed
                        count_r[sem_id] <= count_r[sem_id] - 1'b1;
                        sem_success     <= 1'b1;
                    end else begin
                        // No resource: add task to wait mask, signal block
                        wait_mask_r[sem_id][task_id] <= 1'b1;
                        sem_block                    <= 1'b1;
                    end
                end

                // -------------------------------------------------------------
                // POST (V operation): Increment or wake highest-priority waiter
                // -------------------------------------------------------------
                SEM_POST: begin
                    if (best_wake_found) begin
                        // Waiting tasks exist: wake highest-priority waiter
                        // Count stays the same (resource immediately consumed by woken task)
                        wait_mask_r[sem_id][best_wake_id] <= 1'b0;
                        wake_task_id                      <= best_wake_id;
                        wake_valid                        <= 1'b1;
                        sem_success                       <= 1'b1;
                    end else if (count_r[sem_id] < max_count_r[sem_id]) begin
                        // No waiters, below max: increment count
                        count_r[sem_id] <= count_r[sem_id] + 1'b1;
                        sem_success     <= 1'b1;
                    end else begin
                        // Already at max count: fail silently
                        sem_success <= 1'b0;
                    end
                end

                default: ; // NOP
            endcase
        end
    end

    // =========================================================================
    // Output: current semaphore counts
    // =========================================================================
    always_comb begin
        for (int i = 0; i < NUM_SEMS; i++) begin
            sem_counts[i] = count_r[i];
        end
    end

endmodule : hw_semaphore
