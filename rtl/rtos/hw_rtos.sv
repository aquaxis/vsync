// =============================================================================
// VSync - Hardware RTOS Engine (Top Module)
// RISC-V RV32IM Processor with Hardware RTOS
//
// File: hw_rtos.sv
// Description: Top-level Hardware RTOS integrating task_scheduler, tcb_array,
//              context_switch, hw_semaphore, hw_mutex, hw_msgqueue, and pmp_unit.
//              Implements scheduler FSM with priority-based preemptive scheduling,
//              context switch coordination, POSIX layer interface, AXI4-Lite
//              slave for configuration registers, and timer tick time-slicing.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

module hw_rtos
    import vsync_pkg::*;
(
    input  logic                     clk,
    input  logic                     rst_n,

    // Task Scheduler Control
    input  logic                     scheduler_en,
    input  logic [1:0]               schedule_policy,
    output logic [TASK_ID_W-1:0]     current_task_id,
    output logic [TASK_ID_W-1:0]     next_task_id,
    output logic                     task_active,

    // Context Switch Control (to/from rv32im_core)
    output logic                     ctx_switch_req,
    input  logic                     ctx_switch_ack,
    input  logic                     ctx_save_en,
    input  logic [REG_ADDR_W-1:0]    ctx_save_reg_idx,
    input  logic [XLEN-1:0]         ctx_save_reg_data,
    input  logic [XLEN-1:0]         ctx_save_pc,
    output logic                     ctx_restore_en,
    output logic [REG_ADDR_W-1:0]    ctx_restore_reg_idx,
    output logic [XLEN-1:0]         ctx_restore_reg_data,
    output logic [XLEN-1:0]         ctx_restore_pc,

    // Timer Input (from CLINT)
    input  logic                     timer_tick,

    // POSIX Layer Control Input
    input  logic                     rtos_task_create,
    input  logic [XLEN-1:0]         rtos_task_create_pc,
    input  logic [XLEN-1:0]         rtos_task_create_sp,
    input  logic [TASK_PRIORITY_W-1:0] rtos_task_create_prio,
    output logic                     rtos_task_create_done,
    output logic [TASK_ID_W-1:0]     rtos_task_create_id,
    input  logic                     rtos_task_exit,
    input  logic                     rtos_task_join,
    input  logic [TASK_ID_W-1:0]     rtos_task_target_id,
    output logic                     rtos_task_join_done,
    input  logic                     rtos_task_yield,
    input  logic [1:0]               rtos_sem_op,
    input  logic [2:0]               rtos_sem_id,
    input  logic [7:0]               rtos_sem_value,
    output logic                     rtos_sem_done,
    output logic                     rtos_sem_result,
    input  logic [1:0]               rtos_mutex_op,
    input  logic [2:0]               rtos_mutex_id,
    output logic                     rtos_mutex_done,
    output logic                     rtos_mutex_result,
    input  logic [1:0]               rtos_msgq_op,
    input  logic [1:0]               rtos_msgq_id,
    input  logic [XLEN-1:0]         rtos_msgq_data,
    output logic                     rtos_msgq_done,
    output logic [XLEN-1:0]         rtos_msgq_result,
    output logic                     rtos_msgq_success,

    // AXI4 Slave Interface (AXI4-Lite subset for config registers)
    input  logic [AXI_ADDR_W-1:0]   s_axi_awaddr,
    input  logic [2:0]               s_axi_awprot,
    input  logic                     s_axi_awvalid,
    output logic                     s_axi_awready,
    input  logic [AXI_DATA_W-1:0]   s_axi_wdata,
    input  logic [AXI_STRB_W-1:0]   s_axi_wstrb,
    input  logic                     s_axi_wvalid,
    output logic                     s_axi_wready,
    output logic [1:0]               s_axi_bresp,
    output logic                     s_axi_bvalid,
    input  logic                     s_axi_bready,
    input  logic [AXI_ADDR_W-1:0]   s_axi_araddr,
    input  logic [2:0]               s_axi_arprot,
    input  logic                     s_axi_arvalid,
    output logic                     s_axi_arready,
    output logic [AXI_DATA_W-1:0]   s_axi_rdata,
    output logic [1:0]               s_axi_rresp,
    output logic                     s_axi_rvalid,
    input  logic                     s_axi_rready
);

    // =========================================================================
    // Local Parameters
    // =========================================================================
    localparam int NUM_SEMS         = 8;
    localparam int SEM_COUNT_W      = 8;
    localparam int NUM_MUTEXES      = 8;
    localparam int NUM_QUEUES       = 4;
    localparam int QUEUE_DEPTH      = 8;
    localparam int MSG_WIDTH        = XLEN;
    localparam int NUM_PMP_REGIONS  = 8;
    localparam int DEFAULT_TIME_SLICE = 16'd1000;

    // AXI4-Lite register offsets (relative to ADDR_RTOS_BASE)
    localparam logic [7:0] REG_SCHEDULER_EN   = 8'h00;
    localparam logic [7:0] REG_SCHED_POLICY   = 8'h04;
    localparam logic [7:0] REG_CURRENT_TASK   = 8'h08;
    localparam logic [7:0] REG_NEXT_TASK      = 8'h0C;
    localparam logic [7:0] REG_TASK_ACTIVE    = 8'h10;
    localparam logic [7:0] REG_TASK_COUNT     = 8'h14;
    localparam logic [7:0] REG_TIME_SLICE_CFG = 8'h18;
    localparam logic [7:0] REG_FSM_STATE      = 8'h1C;
    localparam logic [7:0] REG_IRQ_STATUS     = 8'h20;
    localparam logic [7:0] REG_SCHED_TRIGGER  = 8'h24;

    // =========================================================================
    // Scheduler FSM State Definitions
    // =========================================================================
    typedef enum logic [3:0] {
        S_IDLE             = 4'b0000,
        S_SCAN_READY       = 4'b0001,
        S_COMPARE_PRIORITY = 4'b0010,
        S_PREEMPT_CHECK    = 4'b0011,
        S_CONTEXT_SAVE     = 4'b0100,
        S_CONTEXT_LOAD     = 4'b0101,
        S_DISPATCH         = 4'b0110,
        S_TIMER_UPDATE     = 4'b0111,
        S_TASK_CREATE      = 4'b1000,
        S_TASK_EXIT        = 4'b1001,
        S_BLOCK_TASK       = 4'b1010,
        S_UNBLOCK_TASK     = 4'b1011,
        S_WAIT_CTX_ACK     = 4'b1100,
        S_TASK_JOIN        = 4'b1101,
        S_EXIT_SETTLE      = 4'b1110
    } sched_fsm_t;

    sched_fsm_t fsm_state, fsm_next;

    // =========================================================================
    // Internal Signals - TCB Array
    // =========================================================================
    logic [TASK_ID_W-1:0]           tcb_rd_id;
    tcb_t                           tcb_rd_data;
    logic [TASK_ID_W-1:0]           tcb_wr_id;
    tcb_t                           tcb_wr_data;
    logic                           tcb_wr_en;
    logic [TASK_ID_W-1:0]           state_wr_id;
    task_state_t                    state_wr_data;
    logic                           state_wr_en;
    logic [TASK_ID_W-1:0]           create_id;
    logic [XLEN-1:0]               create_pc;
    logic [XLEN-1:0]               create_sp;
    logic [TASK_PRIORITY_W-1:0]    create_prio;
    logic                           create_en;
    logic [TASK_ID_W-1:0]           delete_id;
    logic                           delete_en;
    logic [TASK_ID_W-1:0]           ts_reload_id;
    logic [TIME_SLICE_W-1:0]       ts_reload_val;
    logic                           ts_reload_en;
    logic [MAX_TASKS*TASK_PRIORITY_W-1:0] all_prio;
    logic [MAX_TASKS*3-1:0]               all_state;
    logic [MAX_TASKS-1:0]                 all_valid;
    logic [MAX_TASKS*TIME_SLICE_W-1:0]    all_time_slice;
    logic [TASK_ID_W-1:0]           running_task_id;

    // Unpacked priority array for hw_semaphore/hw_mutex (unpack from packed vector)
    logic [TASK_PRIORITY_W-1:0]    all_prio_unpacked [MAX_TASKS];
    genvar gk;
    generate
        for (gk = 0; gk < MAX_TASKS; gk++) begin : gen_prio_unpack
            assign all_prio_unpacked[gk] = all_prio[gk*TASK_PRIORITY_W +: TASK_PRIORITY_W];
        end
    endgenerate

    // =========================================================================
    // Internal Signals - Task Scheduler
    // =========================================================================
    logic                           sched_trigger;
    logic [TASK_ID_W-1:0]           sched_next_task_id;
    logic                           sched_switch_request;
    logic                           sched_busy;
    logic                           sched_done;

    // =========================================================================
    // Internal Signals - Context Switch
    // =========================================================================
    logic                           cs_switch_req;
    logic [TASK_ID_W-1:0]           cs_old_task_id;
    logic [TASK_ID_W-1:0]           cs_new_task_id;
    logic [XLEN-1:0]               cs_cpu_reg_rdata;
    logic [4:0]                     cs_cpu_reg_addr;
    logic [XLEN-1:0]               cs_cpu_reg_wdata;
    logic                           cs_cpu_reg_we;
    logic [XLEN-1:0]               cs_cpu_pc;
    logic                           cs_switch_done;
    logic [XLEN-1:0]               cs_restore_pc;
    logic                           cs_stall_pipeline;
    logic                           cs_busy;

    // =========================================================================
    // Internal Signals - Semaphore
    // =========================================================================
    logic [1:0]                     sem_op_int;
    logic [$clog2(NUM_SEMS)-1:0]   sem_id_int;
    logic [TASK_ID_W-1:0]           sem_task_id;
    logic [SEM_COUNT_W-1:0]        sem_init_count;
    logic [SEM_COUNT_W-1:0]        sem_max_count;
    logic                           sem_success;
    logic                           sem_block;
    logic [TASK_ID_W-1:0]           sem_wake_task_id;
    logic                           sem_wake_valid;
    logic [SEM_COUNT_W-1:0]        sem_counts [NUM_SEMS];

    // =========================================================================
    // Internal Signals - Mutex
    // =========================================================================
    logic [1:0]                     mutex_op_int;
    logic [$clog2(NUM_MUTEXES)-1:0] mutex_id_int;
    logic [TASK_ID_W-1:0]           mutex_task_id;
    logic                           mutex_success;
    logic                           mutex_block;
    logic [TASK_ID_W-1:0]           mutex_wake_task_id;
    logic                           mutex_wake_valid;
    logic [TASK_ID_W-1:0]           mutex_prio_boost_id;
    logic [TASK_PRIORITY_W-1:0]    mutex_prio_boost_val;
    logic                           mutex_prio_boost_valid;

    // =========================================================================
    // Internal Signals - Message Queue
    // =========================================================================
    logic [1:0]                     msgq_op_int;
    logic [$clog2(NUM_QUEUES)-1:0] msgq_queue_id;
    logic [MSG_WIDTH-1:0]          msgq_data_in;
    logic [TASK_ID_W-1:0]           msgq_task_id;
    logic                           msgq_success_int;
    logic                           msgq_block;
    logic [MSG_WIDTH-1:0]          msgq_data_out;
    logic [TASK_ID_W-1:0]           msgq_wake_task_id;
    logic                           msgq_wake_valid;
    logic [$clog2(QUEUE_DEPTH):0]  queue_counts [NUM_QUEUES];

    // =========================================================================
    // Internal Signals - PMP
    // =========================================================================
    logic                           pmp_pmpcfg_wr;
    logic [$clog2((NUM_PMP_REGIONS+3)/4)-1:0] pmp_pmpcfg_idx;
    logic [XLEN-1:0]               pmp_pmpcfg_wdata;
    logic                           pmp_pmpaddr_wr;
    logic [$clog2(NUM_PMP_REGIONS)-1:0] pmp_pmpaddr_idx;
    logic [XLEN-1:0]               pmp_pmpaddr_wdata;
    logic [XLEN-1:0]               pmp_check_addr;
    logic [2:0]                     pmp_check_type;
    logic                           pmp_access_fault;
    logic [XLEN-1:0]               pmp_pmpcfg_out  [((NUM_PMP_REGIONS + 3) / 4)];
    logic [XLEN-1:0]               pmp_pmpaddr_out [NUM_PMP_REGIONS];

    // =========================================================================
    // Internal Registers
    // =========================================================================
    logic [TASK_ID_W-1:0]           current_task_id_r;
    logic [TASK_ID_W-1:0]           next_task_id_r;
    logic                           task_active_r;
    logic [TASK_ID_W-1:0]           free_task_id;         // Next free TCB slot
    logic                           free_task_found;
    logic [TIME_SLICE_W-1:0]       time_slice_config;    // Configurable time slice
    logic [3:0]                     task_count;           // Active task count
    logic                           need_reschedule;      // Reschedule flag
    logic                           timer_tick_pending;   // Latched timer tick

    // Context switch coordination
    logic                           ctx_switch_active;
    logic                           ctx_save_phase;       // 1=saving, 0=restoring
    logic [XLEN-1:0]               saved_pc;

    // Task create pending latch (captures create request when FSM is busy)
    logic                           task_create_pending;
    logic [XLEN-1:0]               task_create_pc_r;
    logic [XLEN-1:0]               task_create_sp_r;
    logic [TASK_PRIORITY_W-1:0]    task_create_prio_r;

    // POSIX operation pending registers
    logic                           sem_op_pending;
    logic                           mutex_op_pending;
    logic                           msgq_op_pending;

    // Wake task registers (for unblock)
    logic [TASK_ID_W-1:0]           wake_target_id;
    logic                           wake_pending;

    // Join tracking registers (per-task)
    logic [TASK_ID_W-1:0]           join_target [MAX_TASKS]; // Target task each task is joining
    logic                           join_valid  [MAX_TASKS]; // Whether task has pending join

    // Priority boost delayed write enable (F002 fix)
    logic                           prio_boost_wr_pending;
    logic [TASK_ID_W-1:0]           prio_boost_id_r;
    logic [TASK_PRIORITY_W-1:0]    prio_boost_val_r;

    // AXI4-Lite internal signals
    logic                           axi_aw_ready_r;
    logic                           axi_w_ready_r;
    logic                           axi_b_valid_r;
    logic [1:0]                     axi_b_resp_r;
    logic                           axi_ar_ready_r;
    logic                           axi_r_valid_r;
    logic [AXI_DATA_W-1:0]         axi_r_data_r;
    logic [1:0]                     axi_r_resp_r;
    logic [AXI_ADDR_W-1:0]         axi_aw_addr_r;
    logic [AXI_ADDR_W-1:0]         axi_ar_addr_r;
    logic                           axi_aw_done;
    logic                           axi_w_done;

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign current_task_id = current_task_id_r;
    assign next_task_id    = next_task_id_r;
    assign task_active     = task_active_r;

    // =========================================================================
    // Submodule Instantiation: task_scheduler
    // =========================================================================
    task_scheduler #(
        .MAX_TASKS  (MAX_TASKS),
        .TASK_ID_W  (TASK_ID_W),
        .PRIORITY_W (TASK_PRIORITY_W)
    ) u_task_scheduler (
        .clk             (clk),
        .rst_n           (rst_n),
        .sched_trigger   (sched_trigger),
        .current_task_id (current_task_id_r),
        .tcb_prio        (all_prio),
        .tcb_state       (all_state),
        .tcb_valid       (all_valid),
        .next_task_id    (sched_next_task_id),
        .switch_request  (sched_switch_request),
        .sched_busy      (sched_busy),
        .sched_done      (sched_done)
    );

    // =========================================================================
    // Submodule Instantiation: tcb_array
    // =========================================================================
    tcb_array #(
        .MAX_TASKS    (MAX_TASKS),
        .XLEN         (XLEN),
        .TASK_ID_W    (TASK_ID_W),
        .PRIORITY_W   (TASK_PRIORITY_W),
        .TIME_SLICE_W (TIME_SLICE_W)
    ) u_tcb_array (
        .clk            (clk),
        .rst_n          (rst_n),
        .tcb_rd_id      (tcb_rd_id),
        .tcb_rd_data    (tcb_rd_data),
        .tcb_wr_id      (tcb_wr_id),
        .tcb_wr_data    (tcb_wr_data),
        .tcb_wr_en      (tcb_wr_en),
        .state_wr_id    (state_wr_id),
        .state_wr_data  (state_wr_data),
        .state_wr_en    (state_wr_en),
        .create_id      (create_id),
        .create_pc      (create_pc),
        .create_sp      (create_sp),
        .create_prio    (create_prio),
        .create_en      (create_en),
        .delete_id      (delete_id),
        .delete_en      (delete_en),
        .ts_reload_id   (ts_reload_id),
        .ts_reload_val  (ts_reload_val),
        .ts_reload_en   (ts_reload_en),
        .all_prio       (all_prio),
        .all_state      (all_state),
        .all_valid       (all_valid),
        .all_time_slice (all_time_slice),
        .running_task_id(running_task_id)
    );

    // =========================================================================
    // Submodule Instantiation: context_switch
    // =========================================================================
    context_switch #(
        .XLEN      (XLEN),
        .NUM_REGS  (NUM_REGS),
        .TASK_ID_W (TASK_ID_W),
        .MAX_TASKS (MAX_TASKS)
    ) u_context_switch (
        .clk            (clk),
        .rst_n          (rst_n),
        .switch_req     (cs_switch_req),
        .old_task_id    (cs_old_task_id),
        .new_task_id    (cs_new_task_id),
        .cpu_reg_rdata  (cs_cpu_reg_rdata),
        .cpu_reg_addr   (cs_cpu_reg_addr),
        .cpu_reg_wdata  (cs_cpu_reg_wdata),
        .cpu_reg_we     (cs_cpu_reg_we),
        .cpu_pc         (cs_cpu_pc),
        .switch_done    (cs_switch_done),
        .restore_pc     (cs_restore_pc),
        .stall_pipeline (cs_stall_pipeline),
        .busy           (cs_busy)
    );

    // =========================================================================
    // Submodule Instantiation: hw_semaphore
    // =========================================================================
    hw_semaphore #(
        .NUM_SEMS    (NUM_SEMS),
        .SEM_COUNT_W (SEM_COUNT_W),
        .TASK_ID_W   (TASK_ID_W),
        .MAX_TASKS   (MAX_TASKS)
    ) u_hw_semaphore (
        .clk             (clk),
        .rst_n           (rst_n),
        .sem_op          (sem_op_int),
        .sem_id          (sem_id_int),
        .task_id         (sem_task_id),
        .init_count      (sem_init_count),
        .max_count       (sem_max_count),
        .task_priorities (all_prio_unpacked),
        .sem_success     (sem_success),
        .sem_block       (sem_block),
        .wake_task_id    (sem_wake_task_id),
        .wake_valid      (sem_wake_valid),
        .sem_counts      (sem_counts)
    );

    // =========================================================================
    // Submodule Instantiation: hw_mutex
    // =========================================================================
    hw_mutex #(
        .NUM_MUTEXES (NUM_MUTEXES),
        .TASK_ID_W   (TASK_ID_W),
        .PRIORITY_W  (TASK_PRIORITY_W),
        .MAX_TASKS   (MAX_TASKS)
    ) u_hw_mutex (
        .clk              (clk),
        .rst_n            (rst_n),
        .mutex_op         (mutex_op_int),
        .mutex_id         (mutex_id_int),
        .task_id          (mutex_task_id),
        .task_priorities  (all_prio_unpacked),
        .mutex_success    (mutex_success),
        .mutex_block      (mutex_block),
        .wake_task_id     (mutex_wake_task_id),
        .wake_valid       (mutex_wake_valid),
        .prio_boost_id    (mutex_prio_boost_id),
        .prio_boost_val   (mutex_prio_boost_val),
        .prio_boost_valid (mutex_prio_boost_valid)
    );

    // =========================================================================
    // Submodule Instantiation: hw_msgqueue
    // =========================================================================
    hw_msgqueue #(
        .NUM_QUEUES  (NUM_QUEUES),
        .QUEUE_DEPTH (QUEUE_DEPTH),
        .MSG_WIDTH   (MSG_WIDTH),
        .TASK_ID_W   (TASK_ID_W),
        .MAX_TASKS   (MAX_TASKS)
    ) u_hw_msgqueue (
        .clk          (clk),
        .rst_n        (rst_n),
        .msgq_op      (msgq_op_int),
        .queue_id     (msgq_queue_id),
        .msg_data_in  (msgq_data_in),
        .task_id      (msgq_task_id),
        .msgq_success (msgq_success_int),
        .msgq_block   (msgq_block),
        .msg_data_out (msgq_data_out),
        .wake_task_id (msgq_wake_task_id),
        .wake_valid   (msgq_wake_valid),
        .queue_counts (queue_counts)
    );

    // =========================================================================
    // Submodule Instantiation: pmp_unit
    // =========================================================================
    pmp_unit #(
        .NUM_REGIONS (NUM_PMP_REGIONS),
        .XLEN        (XLEN)
    ) u_pmp_unit (
        .clk               (clk),
        .rst_n             (rst_n),
        .csr_pmpcfg_wr     (pmp_pmpcfg_wr),
        .csr_pmpcfg_idx    (pmp_pmpcfg_idx),
        .csr_pmpcfg_wdata  (pmp_pmpcfg_wdata),
        .csr_pmpaddr_wr    (pmp_pmpaddr_wr),
        .csr_pmpaddr_idx   (pmp_pmpaddr_idx),
        .csr_pmpaddr_wdata (pmp_pmpaddr_wdata),
        .check_addr        (pmp_check_addr),
        .check_type        (pmp_check_type),
        .access_fault      (pmp_access_fault),
        .pmpcfg_out        (pmp_pmpcfg_out),
        .pmpaddr_out       (pmp_pmpaddr_out)
    );

    // =========================================================================
    // Context Switch <-> CPU Interface Mapping
    // =========================================================================
    // The context_switch submodule drives cpu_reg_addr/cpu_reg_wdata/cpu_reg_we
    // which maps to the top-level ctx_restore_* signals (RTOS -> CPU).
    // The CPU provides ctx_save_* signals which map to cpu_reg_rdata/cpu_pc.
    // =========================================================================

    // During save phase: CPU sends register data to context_switch
    assign cs_cpu_reg_rdata = ctx_save_reg_data;
    assign cs_cpu_pc        = ctx_save_pc;

    // Context switch request to CPU
    assign ctx_switch_req = cs_stall_pipeline;

    // During restore phase: context_switch sends register data to CPU
    assign ctx_restore_en       = cs_cpu_reg_we;
    assign ctx_restore_reg_idx  = cs_cpu_reg_addr;
    assign ctx_restore_reg_data = cs_cpu_reg_wdata;
    assign ctx_restore_pc       = cs_restore_pc;

    // =========================================================================
    // Free Task ID Finder (combinational priority encoder)
    // =========================================================================
    always_comb begin
        free_task_id    = '0;
        free_task_found = 1'b0;
        for (int i = 1; i < MAX_TASKS; i++) begin
            if (!all_valid[i] && !free_task_found) begin
                free_task_id    = TASK_ID_W'(i);
                free_task_found = 1'b1;
            end
        end
    end

    // =========================================================================
    // Active Task Counter (combinational)
    // =========================================================================
    always_comb begin
        task_count = '0;
        for (int i = 0; i < MAX_TASKS; i++) begin
            if (all_valid[i]) begin
                task_count = task_count + 4'd1;
            end
        end
    end

    // =========================================================================
    // Semaphore Interface Routing
    // =========================================================================
    assign sem_task_id   = current_task_id_r;
    assign sem_init_count = rtos_sem_value;
    assign sem_max_count  = 8'hFF; // Max count default

    // =========================================================================
    // Mutex Interface Routing
    // =========================================================================
    assign mutex_task_id = current_task_id_r;

    // =========================================================================
    // Message Queue Interface Routing
    // =========================================================================
    assign msgq_task_id = current_task_id_r;

    // =========================================================================
    // PMP Default Connections (access check disabled in idle)
    // =========================================================================
    assign pmp_check_addr = '0;
    assign pmp_check_type = 3'b000;

    // =========================================================================
    // Scheduler FSM - State Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fsm_state <= S_IDLE;
        end else begin
            fsm_state <= fsm_next;
        end
    end

    // =========================================================================
    // Scheduler FSM - Next State Logic & Output Logic
    // =========================================================================
    always_comb begin
        // Default assignments - hold previous values
        fsm_next = fsm_state;

        case (fsm_state)
            // -----------------------------------------------------------------
            // S_IDLE: Wait for scheduling trigger
            // -----------------------------------------------------------------
            S_IDLE: begin
                if (!scheduler_en) begin
                    fsm_next = S_IDLE;
                end else if (rtos_task_create || task_create_pending) begin
                    fsm_next = S_TASK_CREATE;
                end else if (rtos_task_exit) begin
                    fsm_next = S_TASK_EXIT;
                end else if (rtos_task_join) begin
                    fsm_next = S_TASK_JOIN;
                end else if (rtos_task_yield) begin
                    fsm_next = S_SCAN_READY;
                end else if (rtos_sem_op != 2'b00) begin
                    fsm_next = S_BLOCK_TASK;  // Handle sem op, may block
                end else if (rtos_mutex_op != 2'b00) begin
                    fsm_next = S_BLOCK_TASK;  // Handle mutex op, may block
                end else if (rtos_msgq_op != 2'b00) begin
                    fsm_next = S_BLOCK_TASK;  // Handle msgq op, may block
                end else if (timer_tick_pending) begin
                    fsm_next = S_TIMER_UPDATE;
                end else if (need_reschedule) begin
                    fsm_next = S_SCAN_READY;
                end
            end

            // -----------------------------------------------------------------
            // S_TIMER_UPDATE: Decrement time slice, check for expiry
            // -----------------------------------------------------------------
            S_TIMER_UPDATE: begin
                fsm_next = S_SCAN_READY;
            end

            // -----------------------------------------------------------------
            // S_SCAN_READY: Trigger scheduler to find highest priority task
            // -----------------------------------------------------------------
            S_SCAN_READY: begin
                if (sched_done) begin
                    fsm_next = S_COMPARE_PRIORITY;
                end
            end

            // -----------------------------------------------------------------
            // S_COMPARE_PRIORITY: Compare scheduler result with current task
            // -----------------------------------------------------------------
            S_COMPARE_PRIORITY: begin
                if (!task_active_r && sched_next_task_id != '0) begin
                    // No current active task, dispatch the new one directly
                    // Skip context save/switch entirely
                    fsm_next = S_DISPATCH;
                end else if (sched_next_task_id == current_task_id_r && task_active_r) begin
                    // Same task continues
                    fsm_next = S_DISPATCH;
                end else if (!task_active_r) begin
                    // No active task and no ready task found - stay idle
                    fsm_next = S_IDLE;
                end else begin
                    fsm_next = S_PREEMPT_CHECK;
                end
            end

            // -----------------------------------------------------------------
            // S_PREEMPT_CHECK: Determine if context switch is needed
            // F003 fix: Wait for CPU pipeline flush via ctx_switch_ack
            // -----------------------------------------------------------------
            S_PREEMPT_CHECK: begin
                // Both paths go through S_WAIT_CTX_ACK to wait for CPU ack
                fsm_next = S_WAIT_CTX_ACK;
            end

            // -----------------------------------------------------------------
            // S_WAIT_CTX_ACK: Wait for CPU pipeline flush completion
            // F003 fix: Ensure ctx_switch_ack before context save/restore
            // -----------------------------------------------------------------
            S_WAIT_CTX_ACK: begin
                if (ctx_switch_ack) begin
                    if (!task_active_r) begin
                        // No current task, just load new
                        fsm_next = S_CONTEXT_LOAD;
                    end else begin
                        // Need to save current before loading new
                        fsm_next = S_CONTEXT_SAVE;
                    end
                end
            end

            // -----------------------------------------------------------------
            // S_CONTEXT_SAVE: Save current task context via context_switch
            // -----------------------------------------------------------------
            S_CONTEXT_SAVE: begin
                if (cs_switch_done) begin
                    fsm_next = S_CONTEXT_LOAD;
                end
            end

            // -----------------------------------------------------------------
            // S_CONTEXT_LOAD: Load next task context
            // -----------------------------------------------------------------
            S_CONTEXT_LOAD: begin
                if (cs_switch_done) begin
                    fsm_next = S_DISPATCH;
                end
            end

            // -----------------------------------------------------------------
            // S_DISPATCH: Finalize task switch, resume CPU
            // -----------------------------------------------------------------
            S_DISPATCH: begin
                fsm_next = S_IDLE;
            end

            // -----------------------------------------------------------------
            // S_TASK_CREATE: Create a new task
            // -----------------------------------------------------------------
            S_TASK_CREATE: begin
                // Go directly to SCAN_READY to schedule the new task
                fsm_next = S_SCAN_READY;
            end

            // -----------------------------------------------------------------
            // S_TASK_EXIT: Terminate current task
            // -----------------------------------------------------------------
            S_TASK_EXIT: begin
                fsm_next = S_EXIT_SETTLE;
            end

            // -----------------------------------------------------------------
            // S_EXIT_SETTLE: Wait one cycle for TCB array to process
            //                delete_en and state_wr_en before scanning
            // -----------------------------------------------------------------
            S_EXIT_SETTLE: begin
                fsm_next = S_SCAN_READY;
            end

            // -----------------------------------------------------------------
            // S_BLOCK_TASK: Handle blocking operations (sem/mutex/msgq)
            // F001 fix: Transition to S_UNBLOCK_TASK when wake signals present
            // -----------------------------------------------------------------
            S_BLOCK_TASK: begin
                if (rtos_task_exit) begin
                    // Task exit takes priority over pending blocking operations
                    fsm_next = S_TASK_EXIT;
                end else if (sem_op_pending || mutex_op_pending || msgq_op_pending) begin
                    // Wait for operation to complete
                    if (sem_op_pending && (sem_success || sem_block)) begin
                        if (sem_block) begin
                            fsm_next = S_SCAN_READY;
                        end else begin
                            // F001: Check if blocked task needs waking after sem_post
                            if (wake_pending || sem_wake_valid || mutex_wake_valid || msgq_wake_valid)
                                fsm_next = S_UNBLOCK_TASK;
                            else
                                fsm_next = S_IDLE;
                        end
                    end else if (mutex_op_pending && (mutex_success || mutex_block)) begin
                        if (mutex_block) begin
                            fsm_next = S_SCAN_READY;
                        end else begin
                            // F001: Check if blocked task needs waking after mutex_unlock
                            if (wake_pending || sem_wake_valid || mutex_wake_valid || msgq_wake_valid)
                                fsm_next = S_UNBLOCK_TASK;
                            else
                                fsm_next = S_IDLE;
                        end
                    end else if (msgq_op_pending && (msgq_success_int || msgq_block)) begin
                        if (msgq_block) begin
                            fsm_next = S_SCAN_READY;
                        end else begin
                            // F001: Check if blocked task needs waking after msgq op
                            if (wake_pending || sem_wake_valid || mutex_wake_valid || msgq_wake_valid)
                                fsm_next = S_UNBLOCK_TASK;
                            else
                                fsm_next = S_IDLE;
                        end
                    end
                end else begin
                    fsm_next = S_IDLE;
                end
            end

            // -----------------------------------------------------------------
            // S_UNBLOCK_TASK: Handle wake-up from sem/mutex/msgq
            // -----------------------------------------------------------------
            S_UNBLOCK_TASK: begin
                fsm_next = S_SCAN_READY;
            end

            // -----------------------------------------------------------------
            // S_TASK_JOIN: Block current task until target task exits
            // -----------------------------------------------------------------
            S_TASK_JOIN: begin
                // Join always blocks current task and triggers reschedule
                fsm_next = S_SCAN_READY;
            end

            default: begin
                fsm_next = S_IDLE;
            end
        endcase
    end

    // =========================================================================
    // Scheduler FSM - Registered Output Logic
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_task_id_r  <= '0;
            next_task_id_r     <= '0;
            task_active_r      <= 1'b0;
            sched_trigger      <= 1'b0;
            cs_switch_req      <= 1'b0;
            cs_old_task_id     <= '0;
            cs_new_task_id     <= '0;
            create_en          <= 1'b0;
            create_id          <= '0;
            create_pc          <= '0;
            create_sp          <= '0;
            create_prio        <= '0;
            delete_en          <= 1'b0;
            delete_id          <= '0;
            state_wr_en        <= 1'b0;
            state_wr_id        <= '0;
            state_wr_data      <= TASK_READY;
            tcb_wr_en          <= 1'b0;
            // tcb_wr_id removed: driven by always_comb block (L1191-1199), multi-driver violation fix
            tcb_rd_id          <= '0;
            ts_reload_en       <= 1'b0;
            ts_reload_id       <= '0;
            ts_reload_val      <= '0;
            timer_tick_pending <= 1'b0;
            need_reschedule    <= 1'b0;
            time_slice_config  <= DEFAULT_TIME_SLICE;
            rtos_task_create_done <= 1'b0;
            rtos_task_create_id   <= '0;
            rtos_sem_done      <= 1'b0;
            rtos_sem_result    <= 1'b0;
            rtos_mutex_done    <= 1'b0;
            rtos_mutex_result  <= 1'b0;
            rtos_msgq_done     <= 1'b0;
            rtos_msgq_result   <= '0;
            rtos_msgq_success  <= 1'b0;
            sem_op_int         <= 2'b00;
            sem_id_int         <= '0;
            mutex_op_int       <= 2'b00;
            mutex_id_int       <= '0;
            msgq_op_int        <= 2'b00;
            msgq_queue_id      <= '0;
            msgq_data_in       <= '0;
            sem_op_pending     <= 1'b0;
            mutex_op_pending   <= 1'b0;
            msgq_op_pending    <= 1'b0;
            ctx_switch_active  <= 1'b0;
            ctx_save_phase     <= 1'b0;
            saved_pc           <= '0;
            wake_target_id     <= '0;
            wake_pending       <= 1'b0;
            rtos_task_join_done <= 1'b0;
            prio_boost_wr_pending <= 1'b0;
            prio_boost_id_r       <= '0;
            prio_boost_val_r      <= '0;
            for (int i = 0; i < MAX_TASKS; i++) begin
                join_target[i] <= '0;
                join_valid[i]  <= 1'b0;
            end
            task_create_pending <= 1'b0;
            task_create_pc_r   <= '0;
            task_create_sp_r   <= '0;
            task_create_prio_r <= '0;
            pmp_pmpcfg_wr      <= 1'b0;
            pmp_pmpcfg_idx     <= '0;
            pmp_pmpcfg_wdata   <= '0;
            pmp_pmpaddr_wr     <= 1'b0;
            pmp_pmpaddr_idx    <= '0;
            pmp_pmpaddr_wdata  <= '0;
        end else begin
            // Pulse signals default to 0
            sched_trigger         <= 1'b0;
            cs_switch_req         <= 1'b0;
            create_en             <= 1'b0;
            delete_en             <= 1'b0;
            state_wr_en           <= 1'b0;
            tcb_wr_en             <= 1'b0;
            ts_reload_en          <= 1'b0;
            rtos_task_create_done <= 1'b0;
            rtos_task_join_done   <= 1'b0;
            rtos_sem_done         <= 1'b0;
            rtos_mutex_done       <= 1'b0;
            rtos_msgq_done        <= 1'b0;
            pmp_pmpcfg_wr         <= 1'b0;
            pmp_pmpaddr_wr        <= 1'b0;

            // F002 fix: Delayed priority boost write enable
            if (prio_boost_wr_pending) begin
                tcb_wr_en             <= 1'b1;
                prio_boost_wr_pending <= 1'b0;
            end

            // Latch task_create request when FSM is busy
            if (rtos_task_create && fsm_state != S_IDLE) begin
                task_create_pending <= 1'b1;
                task_create_pc_r    <= rtos_task_create_pc;
                task_create_sp_r    <= rtos_task_create_sp;
                task_create_prio_r  <= rtos_task_create_prio;
            end

            // Latch timer tick
            if (timer_tick && scheduler_en) begin
                timer_tick_pending <= 1'b1;
            end

            // Latch wake-up signals from semaphore/mutex/msgqueue
            if (sem_wake_valid) begin
                wake_target_id <= sem_wake_task_id;
                wake_pending   <= 1'b1;
            end else if (mutex_wake_valid) begin
                wake_target_id <= mutex_wake_task_id;
                wake_pending   <= 1'b1;
            end else if (msgq_wake_valid) begin
                wake_target_id <= msgq_wake_task_id;
                wake_pending   <= 1'b1;
            end

            // Clear sem/mutex/msgq operation codes after issuing
            if (sem_op_int != 2'b00 && (sem_success || sem_block)) begin
                sem_op_int <= 2'b00;
            end
            if (mutex_op_int != 2'b00 && (mutex_success || mutex_block)) begin
                mutex_op_int <= 2'b00;
            end
            if (msgq_op_int != 2'b00 && (msgq_success_int || msgq_block)) begin
                msgq_op_int <= 2'b00;
            end

            case (fsm_state)
                // -------------------------------------------------------------
                // S_IDLE
                // -------------------------------------------------------------
                S_IDLE: begin
                    if (scheduler_en) begin
                        if (rtos_task_create) begin
                            // Prepare for task creation
                        end else if (rtos_task_exit) begin
                            // Prepare for task exit
                        end else if (rtos_task_join) begin
                            // Prepare for task join (target_id latched from input)
                        end else if (rtos_task_yield) begin
                            // Yield: move current task to back of ready queue
                            if (task_active_r) begin
                                state_wr_en   <= 1'b1;
                                state_wr_id   <= current_task_id_r;
                                state_wr_data <= TASK_READY;
                            end
                        end else if (rtos_sem_op != 2'b00) begin
                            sem_op_int     <= rtos_sem_op;
                            sem_id_int     <= rtos_sem_id[$clog2(NUM_SEMS)-1:0];
                            sem_op_pending <= 1'b1;
                        end else if (rtos_mutex_op != 2'b00) begin
                            mutex_op_int     <= rtos_mutex_op;
                            mutex_id_int     <= rtos_mutex_id[$clog2(NUM_MUTEXES)-1:0];
                            mutex_op_pending <= 1'b1;
                        end else if (rtos_msgq_op != 2'b00) begin
                            msgq_op_int     <= rtos_msgq_op;
                            msgq_queue_id   <= rtos_msgq_id[$clog2(NUM_QUEUES)-1:0];
                            msgq_data_in    <= rtos_msgq_data;
                            msgq_op_pending <= 1'b1;
                        end
                    end
                end

                // -------------------------------------------------------------
                // S_TIMER_UPDATE: Decrement time slice, trigger reschedule if 0
                // -------------------------------------------------------------
                S_TIMER_UPDATE: begin
                    timer_tick_pending <= 1'b0;
                    if (task_active_r && all_time_slice[current_task_id_r*TIME_SLICE_W +: TIME_SLICE_W] == '0) begin
                        // Time slice expired: reload and mark for round-robin
                        ts_reload_en  <= 1'b1;
                        ts_reload_id  <= current_task_id_r;
                        ts_reload_val <= time_slice_config;
                        // Move current to READY for round-robin rescheduling
                        state_wr_en   <= 1'b1;
                        state_wr_id   <= current_task_id_r;
                        state_wr_data <= TASK_READY;
                    end
                    // Always trigger scheduler scan after timer update
                    sched_trigger <= 1'b1;
                end

                // -------------------------------------------------------------
                // S_SCAN_READY: Trigger the task_scheduler submodule
                // -------------------------------------------------------------
                S_SCAN_READY: begin
                    `ifdef IVERILOG
                    $display("[DBG] S_SCAN_READY: sched_busy=%b sched_done=%b sched_trigger=%b next=%0d",
                             sched_busy, sched_done, sched_trigger, sched_next_task_id);
                    `endif
                    if (!sched_busy && !sched_done) begin
                        sched_trigger <= 1'b1;
                    end
                    if (sched_done) begin
                        next_task_id_r <= sched_next_task_id;
                    end
                end

                // -------------------------------------------------------------
                // S_COMPARE_PRIORITY: Decide on preemption
                // -------------------------------------------------------------
                S_COMPARE_PRIORITY: begin
                    `ifdef IVERILOG
                    $display("[DBG] S_COMPARE_PRIORITY: next_task_id_r=%0d current_task_id_r=%0d task_active_r=%b sched_next=%0d",
                             next_task_id_r, current_task_id_r, task_active_r, sched_next_task_id);
                    `endif
                    // Result stored in next_task_id_r, transition logic in comb
                end

                // -------------------------------------------------------------
                // S_PREEMPT_CHECK: Check if preemption is needed
                // -------------------------------------------------------------
                S_PREEMPT_CHECK: begin
                    if (task_active_r) begin
                        // Need to save current task first
                        cs_switch_req  <= 1'b1;
                        cs_old_task_id <= current_task_id_r;
                        cs_new_task_id <= next_task_id_r;
                        // Mark current task as READY (preempted)
                        state_wr_en    <= 1'b1;
                        state_wr_id    <= current_task_id_r;
                        state_wr_data  <= TASK_READY;
                        ctx_switch_active <= 1'b1;
                    end else begin
                        // No current task; load new directly
                        cs_switch_req  <= 1'b1;
                        cs_old_task_id <= '0;
                        cs_new_task_id <= next_task_id_r;
                        ctx_switch_active <= 1'b1;
                    end
                end

                // -------------------------------------------------------------
                // S_CONTEXT_SAVE: Wait for context_switch save phase
                // -------------------------------------------------------------
                S_CONTEXT_SAVE: begin
                    // context_switch submodule handles the save sequence
                    // stall_pipeline is asserted to CPU
                    if (cs_switch_done) begin
                        // Save done, prepare for load
                        cs_switch_req  <= 1'b1;
                        cs_old_task_id <= current_task_id_r;
                        cs_new_task_id <= next_task_id_r;
                    end
                end

                // -------------------------------------------------------------
                // S_CONTEXT_LOAD: Wait for context_switch load phase
                // -------------------------------------------------------------
                S_CONTEXT_LOAD: begin
                    if (cs_switch_done) begin
                        ctx_switch_active <= 1'b0;
                    end
                end

                // -------------------------------------------------------------
                // S_DISPATCH: Update current task, resume execution
                // -------------------------------------------------------------
                S_DISPATCH: begin
                    `ifdef IVERILOG
                    $display("[DBG] S_DISPATCH: next_task_id_r=%0d current_task_id_r=%0d task_active_r=%b",
                             next_task_id_r, current_task_id_r, task_active_r);
                    `endif
                    current_task_id_r <= next_task_id_r;
                    task_active_r     <= 1'b1;
                    need_reschedule   <= 1'b0;
                    // Mark new task as RUNNING
                    state_wr_en   <= 1'b1;
                    state_wr_id   <= next_task_id_r;
                    state_wr_data <= TASK_RUNNING;
                    // Reload time slice for new task
                    ts_reload_en  <= 1'b1;
                    ts_reload_id  <= next_task_id_r;
                    ts_reload_val <= time_slice_config;

                    // Handle pending wake-ups
                    if (wake_pending) begin
                        wake_pending    <= 1'b0;
                        need_reschedule <= 1'b1;
                    end
                end

                // -------------------------------------------------------------
                // S_TASK_CREATE: Allocate TCB for new task
                // -------------------------------------------------------------
                S_TASK_CREATE: begin
                    `ifdef IVERILOG
                    $display("[DBG] S_TASK_CREATE: free_task_found=%b free_task_id=%0d all_valid=%b pending=%b",
                             free_task_found, free_task_id, all_valid, task_create_pending);
                    `endif
                    if (free_task_found) begin
                        create_en   <= 1'b1;
                        create_id   <= free_task_id;
                        create_pc   <= task_create_pending ? task_create_pc_r   : rtos_task_create_pc;
                        create_sp   <= task_create_pending ? task_create_sp_r   : rtos_task_create_sp;
                        create_prio <= task_create_pending ? task_create_prio_r : rtos_task_create_prio;
                        // Reload time slice for new task
                        ts_reload_en  <= 1'b1;
                        ts_reload_id  <= free_task_id;
                        ts_reload_val <= time_slice_config;
                        // Signal completion
                        rtos_task_create_done <= 1'b1;
                        rtos_task_create_id   <= free_task_id;
                        // Trigger scheduler scan (we go directly to S_SCAN_READY)
                        sched_trigger <= 1'b1;
                        // Clear pending flag
                        task_create_pending <= 1'b0;
                    end else begin
                        // No free slot - signal done with ID=0 (error)
                        rtos_task_create_done <= 1'b1;
                        rtos_task_create_id   <= '0;
                        task_create_pending   <= 1'b0;
                    end
                end

                // -------------------------------------------------------------
                // S_TASK_EXIT: Terminate current task
                // Also wake any task that was joining on this task
                // -------------------------------------------------------------
                S_TASK_EXIT: begin
                    `ifdef IVERILOG
                    $display("[DBG] S_TASK_EXIT: current_task_id_r=%0d task_active_r=%b all_valid=%b",
                             current_task_id_r, task_active_r, all_valid);
                    `endif
                    if (task_active_r) begin
                        // Mark task as DORMANT
                        state_wr_en   <= 1'b1;
                        state_wr_id   <= current_task_id_r;
                        state_wr_data <= TASK_DORMANT;
                        // Delete the task
                        delete_en <= 1'b1;
                        delete_id <= current_task_id_r;
                        task_active_r <= 1'b0;
                        // Do NOT trigger scheduler here - wait for S_EXIT_SETTLE
                        // so that TCB array processes delete_en/state_wr_en first
                        // Check if any task was joining on the exiting task
                        for (int i = 0; i < MAX_TASKS; i++) begin
                            if (join_valid[i] && join_target[i] == current_task_id_r) begin
                                // Wake the joining task
                                wake_target_id <= TASK_ID_W'(i);
                                wake_pending   <= 1'b1;
                                join_valid[i]  <= 1'b0;
                            end
                        end
                    end
                end

                // -------------------------------------------------------------
                // S_EXIT_SETTLE: TCB updates propagate this cycle
                // Now trigger scheduler with updated TCB data
                // -------------------------------------------------------------
                S_EXIT_SETTLE: begin
                    sched_trigger <= 1'b1;
                end

                // -------------------------------------------------------------
                // S_BLOCK_TASK: Process blocking operations
                // -------------------------------------------------------------
                S_BLOCK_TASK: begin
                    // Task exit takes priority: clear any pending operations
                    if (rtos_task_exit) begin
                        sem_op_pending   <= 1'b0;
                        mutex_op_pending <= 1'b0;
                        msgq_op_pending  <= 1'b0;
                        sem_op_int       <= 2'b00;
                        mutex_op_int     <= 2'b00;
                        msgq_op_int      <= 2'b00;
                    end else if (sem_op_pending) begin
                        if (sem_success) begin
                            rtos_sem_done   <= 1'b1;
                            rtos_sem_result <= 1'b1;
                            sem_op_pending  <= 1'b0;
                        end else if (sem_block) begin
                            // Block current task
                            state_wr_en   <= 1'b1;
                            state_wr_id   <= current_task_id_r;
                            state_wr_data <= TASK_BLOCKED;
                            rtos_sem_done   <= 1'b1;
                            rtos_sem_result <= 1'b0;
                            sem_op_pending  <= 1'b0;
                            task_active_r   <= 1'b0;
                            sched_trigger   <= 1'b1;
                        end
                    end else if (mutex_op_pending) begin
                        if (mutex_success) begin
                            rtos_mutex_done   <= 1'b1;
                            rtos_mutex_result <= 1'b1;
                            mutex_op_pending  <= 1'b0;
                        end else if (mutex_block) begin
                            state_wr_en   <= 1'b1;
                            state_wr_id   <= current_task_id_r;
                            state_wr_data <= TASK_BLOCKED;
                            rtos_mutex_done   <= 1'b1;
                            rtos_mutex_result <= 1'b0;
                            mutex_op_pending  <= 1'b0;
                            task_active_r     <= 1'b0;
                            sched_trigger     <= 1'b1;
                        end
                    end else if (msgq_op_pending) begin
                        if (msgq_success_int) begin
                            rtos_msgq_done    <= 1'b1;
                            rtos_msgq_result  <= msgq_data_out;
                            rtos_msgq_success <= 1'b1;
                            msgq_op_pending   <= 1'b0;
                        end else if (msgq_block) begin
                            state_wr_en   <= 1'b1;
                            state_wr_id   <= current_task_id_r;
                            state_wr_data <= TASK_BLOCKED;
                            rtos_msgq_done    <= 1'b1;
                            rtos_msgq_result  <= '0;
                            rtos_msgq_success <= 1'b0;
                            msgq_op_pending   <= 1'b0;
                            task_active_r     <= 1'b0;
                            sched_trigger     <= 1'b1;
                        end
                    end

                    // Handle wake-up signals (unblock waiting tasks)
                    if (sem_wake_valid || mutex_wake_valid || msgq_wake_valid) begin
                        need_reschedule <= 1'b1;
                    end
                end

                // -------------------------------------------------------------
                // S_UNBLOCK_TASK: Move a blocked task to READY
                // -------------------------------------------------------------
                S_UNBLOCK_TASK: begin
                    if (wake_pending) begin
                        state_wr_en   <= 1'b1;
                        state_wr_id   <= wake_target_id;
                        state_wr_data <= TASK_READY;
                        wake_pending  <= 1'b0;
                        sched_trigger <= 1'b1;
                    end
                end

                // -------------------------------------------------------------
                // S_TASK_JOIN: Block current task until target exits
                // Record join dependency and block current task
                // -------------------------------------------------------------
                S_TASK_JOIN: begin
                    if (task_active_r) begin
                        // Check if target task is valid
                        if (all_valid[rtos_task_target_id]) begin
                            // Record join dependency
                            join_target[current_task_id_r] <= rtos_task_target_id;
                            join_valid[current_task_id_r]  <= 1'b1;
                            // Block current task
                            state_wr_en   <= 1'b1;
                            state_wr_id   <= current_task_id_r;
                            state_wr_data <= TASK_BLOCKED;
                            task_active_r <= 1'b0;
                            // Signal join completion to POSIX layer
                            rtos_task_join_done <= 1'b1;
                            // Trigger rescheduling
                            sched_trigger <= 1'b1;
                        end else begin
                            // Target task already exited/invalid, return immediately
                            rtos_task_join_done <= 1'b1;
                        end
                    end else begin
                        // No active task, signal done with error
                        rtos_task_join_done <= 1'b1;
                    end
                end

                default: begin
                    // Safety: do nothing
                end
            endcase

            // Handle priority boost from mutex (always active)
            // F002 fix: Latch boost id/val and assert write via delayed pending
            if (mutex_prio_boost_valid) begin
                // Read TCB this cycle; write will happen next cycle via prio_boost_wr_pending
                tcb_rd_id             <= mutex_prio_boost_id;
                prio_boost_wr_pending <= 1'b1;
                prio_boost_id_r       <= mutex_prio_boost_id;
                prio_boost_val_r      <= mutex_prio_boost_val;
            end

            // Handle AXI register write requests (merged to avoid multi-driven nets)
            // These override FSM-driven values when AXI write occurs on same cycle.
            if (axi_wr_time_slice_req) time_slice_config <= axi_wr_time_slice_val;
            if (axi_wr_reschedule_req) need_reschedule   <= 1'b1;
        end
    end

    // =========================================================================
    // TCB Write Data Mux (for priority boost)
    // F002 data path fix: Use latched prio_boost_id_r/val_r and
    // prio_boost_wr_pending (available on write cycle) instead of
    // mutex_prio_boost_valid (1-cycle pulse, already deasserted on write cycle)
    // =========================================================================
    always_comb begin
        tcb_wr_data = tcb_rd_data;
        if (prio_boost_wr_pending) begin
            tcb_wr_data.prio_level = prio_boost_val_r;
            tcb_wr_id = prio_boost_id_r;
        end else begin
            tcb_wr_id = '0;
        end
    end

    // =========================================================================
    // AXI4-Lite Slave Interface
    // =========================================================================

    // Write address channel
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_aw_ready_r <= 1'b0;
            axi_aw_addr_r  <= '0;
            axi_aw_done    <= 1'b0;
        end else begin
            if (s_axi_awvalid && !axi_aw_done) begin
                axi_aw_ready_r <= 1'b1;
                axi_aw_addr_r  <= s_axi_awaddr;
                axi_aw_done    <= 1'b1;
            end else begin
                axi_aw_ready_r <= 1'b0;
            end
            // Clear done when response is accepted
            if (s_axi_bready && axi_b_valid_r) begin
                axi_aw_done <= 1'b0;
            end
        end
    end

    // Write data channel
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_w_ready_r <= 1'b0;
            axi_w_done    <= 1'b0;
        end else begin
            if (s_axi_wvalid && !axi_w_done) begin
                axi_w_ready_r <= 1'b1;
                axi_w_done    <= 1'b1;
            end else begin
                axi_w_ready_r <= 1'b0;
            end
            if (s_axi_bready && axi_b_valid_r) begin
                axi_w_done <= 1'b0;
            end
        end
    end

    // Write response channel
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_b_valid_r <= 1'b0;
            axi_b_resp_r  <= 2'b00;
        end else begin
            if (axi_aw_done && axi_w_done && !axi_b_valid_r) begin
                axi_b_valid_r <= 1'b1;
                axi_b_resp_r  <= 2'b00; // OKAY
            end else if (s_axi_bready && axi_b_valid_r) begin
                axi_b_valid_r <= 1'b0;
            end
        end
    end

    // AXI write request signals (merged into main FSM to avoid multi-driven nets)
    logic                       axi_wr_time_slice_req;
    logic [TIME_SLICE_W-1:0]    axi_wr_time_slice_val;
    logic                       axi_wr_reschedule_req;

    // Write register logic - generates request pulses consumed by main FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_wr_time_slice_req <= 1'b0;
            axi_wr_time_slice_val <= '0;
            axi_wr_reschedule_req <= 1'b0;
        end else begin
            axi_wr_time_slice_req <= 1'b0;  // Default: pulse off
            axi_wr_reschedule_req <= 1'b0;  // Default: pulse off
            if (axi_aw_done && axi_w_done && !axi_b_valid_r) begin
                case (axi_aw_addr_r[7:0])
                    REG_TIME_SLICE_CFG: begin
                        axi_wr_time_slice_req <= 1'b1;
                        axi_wr_time_slice_val <= s_axi_wdata[TIME_SLICE_W-1:0];
                    end
                    REG_SCHED_TRIGGER: begin
                        if (s_axi_wdata[0]) begin
                            axi_wr_reschedule_req <= 1'b1;
                        end
                    end
                    REG_SCHEDULER_EN: begin
                        // scheduler_en is an input port; AXI write ignored
                        // Could be used for soft-override if needed
                    end
                    default: begin
                        // Ignore unknown registers
                    end
                endcase
            end
        end
    end

    // Read address channel
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_ar_ready_r <= 1'b0;
            axi_ar_addr_r  <= '0;
        end else begin
            if (s_axi_arvalid && !axi_r_valid_r) begin
                axi_ar_ready_r <= 1'b1;
                axi_ar_addr_r  <= s_axi_araddr;
            end else begin
                axi_ar_ready_r <= 1'b0;
            end
        end
    end

    // Read data channel
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_r_valid_r <= 1'b0;
            axi_r_data_r  <= '0;
            axi_r_resp_r  <= 2'b00;
        end else begin
            if (axi_ar_ready_r) begin
                axi_r_valid_r <= 1'b1;
                axi_r_resp_r  <= 2'b00; // OKAY
                case (axi_ar_addr_r[7:0])
                    REG_SCHEDULER_EN:   axi_r_data_r <= {31'b0, scheduler_en};
                    REG_SCHED_POLICY:   axi_r_data_r <= {30'b0, schedule_policy};
                    REG_CURRENT_TASK:   axi_r_data_r <= {{(32-TASK_ID_W){1'b0}}, current_task_id_r};
                    REG_NEXT_TASK:      axi_r_data_r <= {{(32-TASK_ID_W){1'b0}}, next_task_id_r};
                    REG_TASK_ACTIVE:    axi_r_data_r <= {31'b0, task_active_r};
                    REG_TASK_COUNT:     axi_r_data_r <= {28'b0, task_count};
                    REG_TIME_SLICE_CFG: axi_r_data_r <= {{(32-TIME_SLICE_W){1'b0}}, time_slice_config};
                    REG_FSM_STATE:      axi_r_data_r <= {28'b0, fsm_state};
                    REG_IRQ_STATUS:     axi_r_data_r <= {31'b0, timer_tick_pending};
                    REG_SCHED_TRIGGER:  axi_r_data_r <= {31'b0, need_reschedule};
                    default:            axi_r_data_r <= 32'hDEAD_BEEF;
                endcase
            end else if (s_axi_rready && axi_r_valid_r) begin
                axi_r_valid_r <= 1'b0;
            end
        end
    end

    // AXI4-Lite output assignments
    assign s_axi_awready = axi_aw_ready_r;
    assign s_axi_wready  = axi_w_ready_r;
    assign s_axi_bresp   = axi_b_resp_r;
    assign s_axi_bvalid  = axi_b_valid_r;
    assign s_axi_arready = axi_ar_ready_r;
    assign s_axi_rdata   = axi_r_data_r;
    assign s_axi_rresp   = axi_r_resp_r;
    assign s_axi_rvalid  = axi_r_valid_r;

endmodule : hw_rtos
