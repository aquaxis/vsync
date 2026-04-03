// =============================================================================
// VSync - Hardware Mutex with Priority Inheritance Protocol
// RISC-V RV32IM Processor with Hardware RTOS
//
// File: hw_mutex.sv
// Description: Hardware mutex with atomic lock/unlock operations and
//              priority inheritance protocol to prevent priority inversion.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module hw_mutex #(
    parameter int NUM_MUTEXES = 8,
    parameter int TASK_ID_W   = 4,
    parameter int PRIORITY_W  = 4,
    parameter int MAX_TASKS   = 16
)(
    input  logic                                clk,
    input  logic                                rst_n,

    // Operation interface
    input  logic [1:0]                          mutex_op,       // 00=NOP, 01=LOCK, 10=UNLOCK
    input  logic [$clog2(NUM_MUTEXES)-1:0]      mutex_id,
    input  logic [TASK_ID_W-1:0]                task_id,

    // Task priorities for wakeup and inheritance
    input  logic [PRIORITY_W-1:0]               task_priorities [MAX_TASKS],

    // Operation results
    output logic                                mutex_success,  // Operation succeeded
    output logic                                mutex_block,    // Task should be blocked

    // Wake-up interface
    output logic [TASK_ID_W-1:0]                wake_task_id,
    output logic                                wake_valid,

    // Priority inheritance interface
    output logic [TASK_ID_W-1:0]                prio_boost_id,  // Task whose priority is boosted
    output logic [PRIORITY_W-1:0]               prio_boost_val, // New (boosted) priority value
    output logic                                prio_boost_valid
);

    // =========================================================================
    // Mutex operation encoding
    // =========================================================================
    localparam logic [1:0] MUTEX_NOP    = 2'b00;
    localparam logic [1:0] MUTEX_LOCK   = 2'b01;
    localparam logic [1:0] MUTEX_UNLOCK = 2'b10;

    // =========================================================================
    // Per-mutex state
    // =========================================================================
    logic                       locked_r       [NUM_MUTEXES];
    logic [TASK_ID_W-1:0]       owner_id_r     [NUM_MUTEXES];
    logic [PRIORITY_W-1:0]      original_prio_r[NUM_MUTEXES];
    logic [MAX_TASKS-1:0]       wait_mask_r    [NUM_MUTEXES];

    // =========================================================================
    // Highest-priority waiting task selection (combinational)
    // =========================================================================
    logic [TASK_ID_W-1:0]       best_wake_id;
    logic                       best_wake_found;
    logic [PRIORITY_W-1:0]      best_prio;

    always_comb begin
        best_wake_id    = '0;
        best_wake_found = 1'b0;
        best_prio       = '0;

        for (int i = 0; i < MAX_TASKS; i++) begin
            if (wait_mask_r[mutex_id][i]) begin
                if (!best_wake_found || (task_priorities[i] > best_prio)) begin
                    best_wake_id    = TASK_ID_W'(i);
                    best_prio       = task_priorities[i];
                    best_wake_found = 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // Highest priority among all waiters (for priority inheritance boost)
    // =========================================================================
    logic [PRIORITY_W-1:0] max_waiter_prio;
    logic                  any_waiter;

    always_comb begin
        max_waiter_prio = '0;
        any_waiter      = 1'b0;

        for (int i = 0; i < MAX_TASKS; i++) begin
            if (wait_mask_r[mutex_id][i] || (i == int'(task_id) && mutex_op == MUTEX_LOCK)) begin
                if (i == int'(task_id) && mutex_op == MUTEX_LOCK) begin
                    // Include the requesting task's priority
                    if (!any_waiter || (task_priorities[i] > max_waiter_prio)) begin
                        max_waiter_prio = task_priorities[i];
                        any_waiter      = 1'b1;
                    end
                end else if (wait_mask_r[mutex_id][i]) begin
                    if (!any_waiter || (task_priorities[i] > max_waiter_prio)) begin
                        max_waiter_prio = task_priorities[i];
                        any_waiter      = 1'b1;
                    end
                end
            end
        end
    end

    // =========================================================================
    // Atomic mutex operations (single always_ff block)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mutex_success    <= 1'b0;
            mutex_block      <= 1'b0;
            wake_task_id     <= '0;
            wake_valid       <= 1'b0;
            prio_boost_id    <= '0;
            prio_boost_val   <= '0;
            prio_boost_valid <= 1'b0;

            for (int i = 0; i < NUM_MUTEXES; i++) begin
                locked_r[i]        <= 1'b0;
                owner_id_r[i]      <= '0;
                original_prio_r[i] <= '0;
                wait_mask_r[i]     <= '0;
            end
        end else begin
            // Default outputs: de-assert every cycle
            mutex_success    <= 1'b0;
            mutex_block      <= 1'b0;
            wake_task_id     <= '0;
            wake_valid       <= 1'b0;
            prio_boost_id    <= '0;
            prio_boost_val   <= '0;
            prio_boost_valid <= 1'b0;

            case (mutex_op)
                // -------------------------------------------------------------
                // LOCK: Acquire mutex or block with priority inheritance
                // -------------------------------------------------------------
                MUTEX_LOCK: begin
                    if (!locked_r[mutex_id]) begin
                        // Mutex is free: acquire it
                        locked_r[mutex_id]        <= 1'b1;
                        owner_id_r[mutex_id]      <= task_id;
                        original_prio_r[mutex_id] <= task_priorities[task_id];
                        mutex_success             <= 1'b1;
                    end else begin
                        // Mutex is locked: block requesting task
                        wait_mask_r[mutex_id][task_id] <= 1'b1;
                        mutex_block                    <= 1'b1;

                        // Priority inheritance check:
                        // If requesting task has higher priority than current owner,
                        // boost owner's priority to prevent priority inversion
                        if (task_priorities[task_id] > task_priorities[owner_id_r[mutex_id]]) begin
                            prio_boost_id    <= owner_id_r[mutex_id];
                            prio_boost_val   <= task_priorities[task_id];
                            prio_boost_valid <= 1'b1;
                        end
                    end
                end

                // -------------------------------------------------------------
                // UNLOCK: Release mutex, restore priority, wake waiter
                // -------------------------------------------------------------
                MUTEX_UNLOCK: begin
                    // Only the owner can unlock
                    if (locked_r[mutex_id] && (owner_id_r[mutex_id] == task_id)) begin
                        // Restore owner's original priority
                        prio_boost_id    <= task_id;
                        prio_boost_val   <= original_prio_r[mutex_id];
                        prio_boost_valid <= 1'b1;

                        if (best_wake_found) begin
                            // Hand off mutex to highest-priority waiter
                            owner_id_r[mutex_id]              <= best_wake_id;
                            original_prio_r[mutex_id]         <= task_priorities[best_wake_id];
                            wait_mask_r[mutex_id][best_wake_id] <= 1'b0;
                            wake_task_id                      <= best_wake_id;
                            wake_valid                        <= 1'b1;
                            // Mutex stays locked (ownership transfer)
                        end else begin
                            // No waiters: fully release mutex
                            locked_r[mutex_id] <= 1'b0;
                            owner_id_r[mutex_id] <= '0;
                        end

                        mutex_success <= 1'b1;
                    end else begin
                        // Non-owner or unlocked mutex: signal completion
                        // so the FSM does not stall waiting for a response
                        mutex_success <= 1'b1;
                    end
                end

                default: ; // NOP
            endcase
        end
    end

endmodule : hw_mutex
