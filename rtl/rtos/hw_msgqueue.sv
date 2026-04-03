// =============================================================================
// VSync - Hardware Message Queue
// RISC-V RV32IM Processor with Hardware RTOS
//
// File: hw_msgqueue.sv
// Description: Hardware message queue with FIFO-based ring buffer.
//              Supports task blocking on full (send) or empty (recv).
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module hw_msgqueue #(
    parameter int NUM_QUEUES  = 4,
    parameter int QUEUE_DEPTH = 8,
    parameter int MSG_WIDTH   = 32,
    parameter int TASK_ID_W   = 4,
    parameter int MAX_TASKS   = 16
)(
    input  logic                                clk,
    input  logic                                rst_n,

    // Operation interface
    input  logic [1:0]                          msgq_op,        // 00=NOP, 01=SEND, 10=RECV
    input  logic [$clog2(NUM_QUEUES)-1:0]       queue_id,
    input  logic [MSG_WIDTH-1:0]                msg_data_in,
    input  logic [TASK_ID_W-1:0]                task_id,

    // Operation results
    output logic                                msgq_success,   // Operation succeeded
    output logic                                msgq_block,     // Task should be blocked
    output logic [MSG_WIDTH-1:0]                msg_data_out,   // Received message data

    // Wake-up interface
    output logic [TASK_ID_W-1:0]                wake_task_id,
    output logic                                wake_valid,

    // Queue status
    output logic [$clog2(QUEUE_DEPTH):0]        queue_counts [NUM_QUEUES]
);

    // =========================================================================
    // Message queue operation encoding
    // =========================================================================
    localparam logic [1:0] MSGQ_NOP  = 2'b00;
    localparam logic [1:0] MSGQ_SEND = 2'b01;
    localparam logic [1:0] MSGQ_RECV = 2'b10;

    // Pointer width
    localparam int PTR_W = $clog2(QUEUE_DEPTH);

    // =========================================================================
    // Per-queue state
    // =========================================================================
    logic [MSG_WIDTH-1:0]       fifo_mem   [NUM_QUEUES][QUEUE_DEPTH];
    logic [PTR_W-1:0]           wr_ptr_r   [NUM_QUEUES];
    logic [PTR_W-1:0]           rd_ptr_r   [NUM_QUEUES];
    logic [$clog2(QUEUE_DEPTH):0] count_r  [NUM_QUEUES];
    logic [MAX_TASKS-1:0]       send_wait_r[NUM_QUEUES];  // Tasks waiting to send (queue full)
    logic [MAX_TASKS-1:0]       recv_wait_r[NUM_QUEUES];  // Tasks waiting to receive (queue empty)

    // =========================================================================
    // Queue full/empty signals (combinational)
    // =========================================================================
    logic queue_full;
    logic queue_empty;

    assign queue_full  = (count_r[queue_id] == QUEUE_DEPTH[$clog2(QUEUE_DEPTH):0]);
    assign queue_empty = (count_r[queue_id] == '0);

    // =========================================================================
    // Find first waiting task for wakeup (lowest ID = simple priority)
    // For send: wake a recv-waiting task; For recv: wake a send-waiting task
    // =========================================================================
    logic [TASK_ID_W-1:0]   send_wake_id;
    logic                   send_wake_found;
    logic [TASK_ID_W-1:0]   recv_wake_id;
    logic                   recv_wake_found;

    always_comb begin
        // Find first recv-waiting task (to wake when sending)
        send_wake_id    = '0;
        send_wake_found = 1'b0;
        for (int i = 0; i < MAX_TASKS; i++) begin
            if (recv_wait_r[queue_id][i] && !send_wake_found) begin
                send_wake_id    = TASK_ID_W'(i);
                send_wake_found = 1'b1;
            end
        end

        // Find first send-waiting task (to wake when receiving)
        recv_wake_id    = '0;
        recv_wake_found = 1'b0;
        for (int i = 0; i < MAX_TASKS; i++) begin
            if (send_wait_r[queue_id][i] && !recv_wake_found) begin
                recv_wake_id    = TASK_ID_W'(i);
                recv_wake_found = 1'b1;
            end
        end
    end

    // =========================================================================
    // Atomic message queue operations (single always_ff block)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msgq_success <= 1'b0;
            msgq_block   <= 1'b0;
            msg_data_out <= '0;
            wake_task_id <= '0;
            wake_valid   <= 1'b0;

            for (int i = 0; i < NUM_QUEUES; i++) begin
                wr_ptr_r[i]    <= '0;
                rd_ptr_r[i]    <= '0;
                count_r[i]     <= '0;
                send_wait_r[i] <= '0;
                recv_wait_r[i] <= '0;
                for (int j = 0; j < QUEUE_DEPTH; j++) begin
                    fifo_mem[i][j] <= '0;
                end
            end
        end else begin
            // Default outputs: de-assert every cycle
            msgq_success <= 1'b0;
            msgq_block   <= 1'b0;
            msg_data_out <= '0;
            wake_task_id <= '0;
            wake_valid   <= 1'b0;

            case (msgq_op)
                // -------------------------------------------------------------
                // SEND: Enqueue message or block if full
                // -------------------------------------------------------------
                MSGQ_SEND: begin
                    if (!queue_full) begin
                        // Queue has space: write message
                        fifo_mem[queue_id][wr_ptr_r[queue_id]] <= msg_data_in;
                        wr_ptr_r[queue_id] <= (wr_ptr_r[queue_id] == PTR_W'(QUEUE_DEPTH - 1))
                                              ? '0
                                              : wr_ptr_r[queue_id] + 1'b1;
                        count_r[queue_id]  <= count_r[queue_id] + 1'b1;
                        msgq_success       <= 1'b1;

                        // If a task is waiting to receive, wake it
                        if (send_wake_found) begin
                            recv_wait_r[queue_id][send_wake_id] <= 1'b0;
                            wake_task_id                        <= send_wake_id;
                            wake_valid                          <= 1'b1;
                        end
                    end else begin
                        // Queue is full: block sender
                        send_wait_r[queue_id][task_id] <= 1'b1;
                        msgq_block                     <= 1'b1;
                    end
                end

                // -------------------------------------------------------------
                // RECV: Dequeue message or block if empty
                // -------------------------------------------------------------
                MSGQ_RECV: begin
                    if (!queue_empty) begin
                        // Queue has data: read message
                        msg_data_out       <= fifo_mem[queue_id][rd_ptr_r[queue_id]];
                        rd_ptr_r[queue_id] <= (rd_ptr_r[queue_id] == PTR_W'(QUEUE_DEPTH - 1))
                                              ? '0
                                              : rd_ptr_r[queue_id] + 1'b1;
                        count_r[queue_id]  <= count_r[queue_id] - 1'b1;
                        msgq_success       <= 1'b1;

                        // If a task is waiting to send, wake it
                        if (recv_wake_found) begin
                            send_wait_r[queue_id][recv_wake_id] <= 1'b0;
                            wake_task_id                        <= recv_wake_id;
                            wake_valid                          <= 1'b1;
                        end
                    end else begin
                        // Queue is empty: block receiver
                        recv_wait_r[queue_id][task_id] <= 1'b1;
                        msgq_block                     <= 1'b1;
                    end
                end

                default: ; // NOP
            endcase
        end
    end

    // =========================================================================
    // Output: current queue counts
    // =========================================================================
    always_comb begin
        for (int i = 0; i < NUM_QUEUES; i++) begin
            queue_counts[i] = count_r[i];
        end
    end

endmodule : hw_msgqueue
