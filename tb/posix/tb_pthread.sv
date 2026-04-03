// =============================================================================
// VSync - POSIX pthread-equivalent Operations Testbench
// =============================================================================
// Tests: PTH-001 ~ PTH-005
//   PTH-001: pthread_create (thread creation via RTOS)
//   PTH-002: pthread_join (thread join/wait)
//   PTH-003: pthread_exit (thread self-termination)
//   PTH-004: mutex lock/unlock (mutex operations via RTOS)
//   PTH-005: sched_yield (yield execution via RTOS)
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_pthread;

    import test_utils::*;
    import vsync_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD = 10;
    localparam RST_CYCLES = 10;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // Syscall interface (TB drives)
    logic                     ecall_req;
    logic [7:0]               syscall_num_tb;
    logic [XLEN-1:0]         syscall_arg0;
    logic [XLEN-1:0]         syscall_arg1;
    logic [XLEN-1:0]         syscall_arg2;

    // Syscall interface (DUT outputs)
    logic [XLEN-1:0]         syscall_ret;
    logic                     syscall_done;

    // RTOS control outputs (from DUT, monitored by TB)
    logic                     rtos_task_create_out;
    logic [XLEN-1:0]         rtos_task_create_pc_out;
    logic [XLEN-1:0]         rtos_task_create_sp_out;
    logic [TASK_PRIORITY_W-1:0] rtos_task_create_prio_out;
    logic                     rtos_task_exit_out;
    logic                     rtos_task_join_out;
    logic [TASK_ID_W-1:0]     rtos_task_target_id_out;
    logic                     rtos_task_yield_out;
    logic [1:0]               rtos_sem_op_out;
    logic [2:0]               rtos_sem_id_out;
    logic [7:0]               rtos_sem_value_out;
    logic [1:0]               rtos_mutex_op_out;
    logic [2:0]               rtos_mutex_id_out;
    logic [1:0]               rtos_msgq_op_out;
    logic [1:0]               rtos_msgq_id_out;
    logic [XLEN-1:0]         rtos_msgq_data_out;

    // RTOS done/result inputs (TB drives into DUT)
    logic                     rtos_task_create_done_tb;
    logic [TASK_ID_W-1:0]     rtos_task_create_id_tb;
    logic                     rtos_task_join_done_tb;
    logic                     rtos_sem_done_tb;
    logic                     rtos_sem_result_tb;
    logic                     rtos_mutex_done_tb;
    logic                     rtos_mutex_result_tb;
    logic                     rtos_msgq_done_tb;
    logic [XLEN-1:0]         rtos_msgq_result_tb;
    logic                     rtos_msgq_success_tb;

    // RTOS current task ID
    logic [TASK_ID_W-1:0]     rtos_current_tid_tb;

    // Peripheral interface (from DUT)
    logic [XLEN-1:0]         periph_addr_out;
    logic [XLEN-1:0]         periph_wdata_out;
    logic                     periph_read_out;
    logic                     periph_write_out;

    // Peripheral response (TB drives)
    logic [XLEN-1:0]         periph_rdata_tb;
    logic                     periph_ready_tb;

    // AXI4 slave interface - tie off
    logic [AXI_ADDR_W-1:0]   s_axi_awaddr;
    logic [2:0]               s_axi_awprot;
    logic                     s_axi_awvalid;
    logic                     s_axi_awready;
    logic [AXI_DATA_W-1:0]   s_axi_wdata;
    logic [AXI_STRB_W-1:0]   s_axi_wstrb;
    logic                     s_axi_wvalid;
    logic                     s_axi_wready;
    logic [1:0]               s_axi_bresp;
    logic                     s_axi_bvalid;
    logic                     s_axi_bready;
    logic [AXI_ADDR_W-1:0]   s_axi_araddr;
    logic [2:0]               s_axi_arprot;
    logic                     s_axi_arvalid;
    logic                     s_axi_arready;
    logic [AXI_DATA_W-1:0]   s_axi_rdata;
    logic [1:0]               s_axi_rresp;
    logic                     s_axi_rvalid;
    logic                     s_axi_rready;

    // =========================================================================
    // Observation registers for monitoring RTOS output pulses
    // =========================================================================
    logic        saw_task_create;
    logic        saw_task_exit;
    logic        saw_task_join;
    logic        saw_task_yield;
    logic [1:0]  saw_mutex_op;
    logic [2:0]  saw_mutex_id;

    // =========================================================================
    // Clock and Reset Generation
    // =========================================================================
    clk_rst_gen #(
        .CLK_PERIOD_NS (CLK_PERIOD),
        .RST_CYCLES    (RST_CYCLES)
    ) u_clk_rst (
        .clk       (clk),
        .rst       (rst),
        .rst_n     (rst_n),
        .init_done (init_done)
    );

    // =========================================================================
    // DUT Instantiation: posix_hw_layer
    // =========================================================================
    posix_hw_layer u_dut (
        .clk                    (clk),
        .rst_n                  (rst_n),

        // Syscall dispatcher interface
        .ecall_req              (ecall_req),
        .syscall_num            (syscall_num_tb),
        .syscall_arg0           (syscall_arg0),
        .syscall_arg1           (syscall_arg1),
        .syscall_arg2           (syscall_arg2),
        .syscall_ret            (syscall_ret),
        .syscall_done           (syscall_done),

        // RTOS control outputs
        .rtos_task_create       (rtos_task_create_out),
        .rtos_task_create_pc    (rtos_task_create_pc_out),
        .rtos_task_create_sp    (rtos_task_create_sp_out),
        .rtos_task_create_prio  (rtos_task_create_prio_out),
        .rtos_task_create_done  (rtos_task_create_done_tb),
        .rtos_task_create_id    (rtos_task_create_id_tb),
        .rtos_task_exit         (rtos_task_exit_out),
        .rtos_task_join         (rtos_task_join_out),
        .rtos_task_target_id    (rtos_task_target_id_out),
        .rtos_task_join_done    (rtos_task_join_done_tb),
        .rtos_task_yield        (rtos_task_yield_out),
        .rtos_sem_op            (rtos_sem_op_out),
        .rtos_sem_id            (rtos_sem_id_out),
        .rtos_sem_value         (rtos_sem_value_out),
        .rtos_sem_done          (rtos_sem_done_tb),
        .rtos_sem_result        (rtos_sem_result_tb),
        .rtos_mutex_op          (rtos_mutex_op_out),
        .rtos_mutex_id          (rtos_mutex_id_out),
        .rtos_mutex_done        (rtos_mutex_done_tb),
        .rtos_mutex_result      (rtos_mutex_result_tb),
        .rtos_msgq_op           (rtos_msgq_op_out),
        .rtos_msgq_id           (rtos_msgq_id_out),
        .rtos_msgq_data         (rtos_msgq_data_out),
        .rtos_msgq_done         (rtos_msgq_done_tb),
        .rtos_msgq_result       (rtos_msgq_result_tb),
        .rtos_msgq_success      (rtos_msgq_success_tb),

        // Current task ID
        .rtos_current_tid       (rtos_current_tid_tb),

        // Peripheral access
        .periph_addr            (periph_addr_out),
        .periph_wdata           (periph_wdata_out),
        .periph_read            (periph_read_out),
        .periph_write           (periph_write_out),
        .periph_rdata           (periph_rdata_tb),
        .periph_ready           (periph_ready_tb),

        // AXI4 slave - tied off
        .s_axi_awaddr           (s_axi_awaddr),
        .s_axi_awprot           (s_axi_awprot),
        .s_axi_awvalid          (s_axi_awvalid),
        .s_axi_awready          (s_axi_awready),
        .s_axi_wdata            (s_axi_wdata),
        .s_axi_wstrb            (s_axi_wstrb),
        .s_axi_wvalid           (s_axi_wvalid),
        .s_axi_wready           (s_axi_wready),
        .s_axi_bresp            (s_axi_bresp),
        .s_axi_bvalid           (s_axi_bvalid),
        .s_axi_bready           (s_axi_bready),
        .s_axi_araddr           (s_axi_araddr),
        .s_axi_arprot           (s_axi_arprot),
        .s_axi_arvalid          (s_axi_arvalid),
        .s_axi_arready          (s_axi_arready),
        .s_axi_rdata            (s_axi_rdata),
        .s_axi_rresp            (s_axi_rresp),
        .s_axi_rvalid           (s_axi_rvalid),
        .s_axi_rready           (s_axi_rready)
    );

    // =========================================================================
    // AXI4 Tie-Off
    // =========================================================================
    assign s_axi_awaddr  = '0;
    assign s_axi_awprot  = '0;
    assign s_axi_awvalid = 1'b0;
    assign s_axi_wdata   = '0;
    assign s_axi_wstrb   = '0;
    assign s_axi_wvalid  = 1'b0;
    assign s_axi_bready  = 1'b1;
    assign s_axi_araddr  = '0;
    assign s_axi_arprot  = '0;
    assign s_axi_arvalid = 1'b0;
    assign s_axi_rready  = 1'b1;

    // =========================================================================
    // RTOS Auto-Respond Stubs
    // =========================================================================

    // Auto-respond to task_create
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rtos_task_create_done_tb <= 1'b0;
            rtos_task_create_id_tb   <= '0;
        end else begin
            rtos_task_create_done_tb <= 1'b0;
            if (rtos_task_create_out) begin
                rtos_task_create_done_tb <= 1'b1;
                rtos_task_create_id_tb   <= rtos_task_create_id_tb + 1;
            end
        end
    end

    // Auto-respond to task_join
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rtos_task_join_done_tb <= 1'b0;
        else begin
            rtos_task_join_done_tb <= 1'b0;
            if (rtos_task_join_out)
                rtos_task_join_done_tb <= 1'b1;
        end
    end

    // Auto-respond to semaphore ops
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rtos_sem_done_tb   <= 1'b0;
            rtos_sem_result_tb <= 1'b0;
        end else begin
            rtos_sem_done_tb <= 1'b0;
            if (rtos_sem_op_out != 2'b00) begin
                rtos_sem_done_tb   <= 1'b1;
                rtos_sem_result_tb <= 1'b1;
            end
        end
    end

    // Auto-respond to mutex ops
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rtos_mutex_done_tb   <= 1'b0;
            rtos_mutex_result_tb <= 1'b0;
        end else begin
            rtos_mutex_done_tb <= 1'b0;
            if (rtos_mutex_op_out != 2'b00) begin
                rtos_mutex_done_tb   <= 1'b1;
                rtos_mutex_result_tb <= 1'b1;
            end
        end
    end

    // Auto-respond to msgq ops
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rtos_msgq_done_tb    <= 1'b0;
            rtos_msgq_result_tb  <= '0;
            rtos_msgq_success_tb <= 1'b0;
        end else begin
            rtos_msgq_done_tb <= 1'b0;
            if (rtos_msgq_op_out != 2'b00) begin
                rtos_msgq_done_tb    <= 1'b1;
                rtos_msgq_result_tb  <= 32'hCAFE_BABE;
                rtos_msgq_success_tb <= 1'b1;
            end
        end
    end

    // Auto-respond to peripheral ops
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            periph_ready_tb <= 1'b0;
            periph_rdata_tb <= '0;
        end else begin
            periph_ready_tb <= 1'b0;
            if (periph_read_out || periph_write_out) begin
                periph_ready_tb <= 1'b1;
                periph_rdata_tb <= 32'hDEAD_BEEF;
            end
        end
    end

    // =========================================================================
    // Observation Logic: capture RTOS output pulses during syscalls
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_task_create <= 1'b0;
            saw_task_exit   <= 1'b0;
            saw_task_join   <= 1'b0;
            saw_task_yield  <= 1'b0;
            saw_mutex_op    <= 2'b00;
            saw_mutex_id    <= 3'b000;
        end else begin
            // Latch observations; tests clear them via clear_observations task
            if (rtos_task_create_out) saw_task_create <= 1'b1;
            if (rtos_task_exit_out)   saw_task_exit   <= 1'b1;
            if (rtos_task_join_out)   saw_task_join   <= 1'b1;
            if (rtos_task_yield_out)  saw_task_yield  <= 1'b1;
            if (rtos_mutex_op_out != 2'b00) begin
                saw_mutex_op <= rtos_mutex_op_out;
                saw_mutex_id <= rtos_mutex_id_out;
            end
        end
    end

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_pthread.vcd");
        $dumpvars(0, tb_pthread);
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 100000);
        $display("ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded maximum time");
    end

    // =========================================================================
    // Signal Initialization
    // =========================================================================
    initial begin
        ecall_req          = 1'b0;
        syscall_num_tb     = 8'h0;
        syscall_arg0       = '0;
        syscall_arg1       = '0;
        syscall_arg2       = '0;
        rtos_current_tid_tb = '0;
    end

    // =========================================================================
    // Helper Tasks
    // =========================================================================
    task automatic issue_syscall(
        input logic [7:0]  num,
        input logic [31:0] arg0,
        input logic [31:0] arg1,
        input logic [31:0] arg2
    );
        int timeout_cnt;
        @(posedge clk);
        ecall_req      <= 1;
        syscall_num_tb <= num;
        syscall_arg0   <= arg0;
        syscall_arg1   <= arg1;
        syscall_arg2   <= arg2;
        @(posedge clk);
        ecall_req <= 0;
        timeout_cnt = 0;
        while (!syscall_done && timeout_cnt < 500) begin
            @(posedge clk);
            timeout_cnt++;
        end
        repeat (2) @(posedge clk);
    endtask

    task automatic clear_observations();
        @(posedge clk);
        saw_task_create <= 1'b0;
        saw_task_exit   <= 1'b0;
        saw_task_join   <= 1'b0;
        saw_task_yield  <= 1'b0;
        saw_mutex_op    <= 2'b00;
        saw_mutex_id    <= 3'b000;
        @(posedge clk);
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();
        test_suite_begin("POSIX pthread Tests");

        test_pth_001_pthread_create();
        test_pth_002_pthread_join();
        test_pth_003_pthread_exit();
        test_pth_004_pthread_mutex();
        test_pth_005_sched_yield();
    endtask

    // -------------------------------------------------------------------------
    // PTH-001: pthread_create
    // Issue SYS_PTHREAD_CREATE and verify rtos_task_create is triggered
    // with correct PC, SP, and priority values
    // -------------------------------------------------------------------------
    task automatic test_pth_001_pthread_create();
        logic [31:0] test_pc, test_sp, test_prio;

        test_begin("PTH-001: pthread_create - thread creation");

        clear_observations();

        test_pc   = 32'h0000_2000;
        test_sp   = 32'h0001_0000;
        test_prio = 32'h0000_0005;

        issue_syscall(SYS_PTHREAD_CREATE, test_pc, test_sp, test_prio);

        // Verify rtos_task_create was asserted
        check(saw_task_create, "rtos_task_create was asserted");

        // Verify DUT passed correct arguments through to RTOS ports
        check_eq(u_dut.latched_arg0, test_pc,   "task PC passed to RTOS");
        check_eq(u_dut.latched_arg1, test_sp,    "task SP passed to RTOS");

        // Verify syscall completed and returned a task ID
        // The auto-responder increments from 0, so first create gets ID 1
        check_eq(u_dut.last_syscall_ret_r, 32'h0000_0001, "returned task ID = 1");
    endtask

    // -------------------------------------------------------------------------
    // PTH-002: pthread_join
    // Issue SYS_PTHREAD_JOIN and verify join completion through RTOS
    // -------------------------------------------------------------------------
    task automatic test_pth_002_pthread_join();
        logic [31:0] target_tid;

        test_begin("PTH-002: pthread_join - thread join/wait");

        clear_observations();

        target_tid = 32'h0000_0001; // Join thread 1

        issue_syscall(SYS_PTHREAD_JOIN, target_tid, 32'h0, 32'h0);

        // Verify rtos_task_join was asserted
        check(saw_task_join, "rtos_task_join was asserted");

        // Verify target ID was passed correctly
        check_eq(u_dut.latched_arg0, target_tid, "join target ID passed correctly");

        // Verify syscall returned 0 (success) upon join completion
        check_eq(u_dut.last_syscall_ret_r, 32'h0, "pthread_join returns 0 on success");
    endtask

    // -------------------------------------------------------------------------
    // PTH-003: pthread_exit
    // Issue SYS_PTHREAD_EXIT and verify rtos_task_exit is asserted
    // -------------------------------------------------------------------------
    task automatic test_pth_003_pthread_exit();
        test_begin("PTH-003: pthread_exit - thread self-termination");

        clear_observations();

        issue_syscall(SYS_PTHREAD_EXIT, 32'h0000_0042, 32'h0, 32'h0);

        // Verify rtos_task_exit was asserted
        check(saw_task_exit, "rtos_task_exit was asserted");

        // pthread_exit goes directly to S_COMPLETE (no wait for RTOS)
        // Return value for exit is 0
        check_eq(u_dut.last_syscall_ret_r, 32'h0, "pthread_exit return value is 0");
    endtask

    // -------------------------------------------------------------------------
    // PTH-004: mutex lock/unlock
    // Issue SYS_MUTEX_LOCK and SYS_MUTEX_UNLOCK and verify RTOS mutex ops
    // -------------------------------------------------------------------------
    task automatic test_pth_004_pthread_mutex();
        logic [31:0] mutex_id;

        test_begin("PTH-004: pthread_mutex - mutex operations");

        // --- Test mutex lock ---
        clear_observations();

        mutex_id = 32'h0000_0002; // mutex ID 2

        issue_syscall(SYS_MUTEX_LOCK, mutex_id, 32'h0, 32'h0);

        // Verify mutex op was issued - lock = 2'b10
        check_eq({30'h0, saw_mutex_op}, {30'h0, 2'b10}, "rtos_mutex_op = LOCK (2'b10)");
        check_eq({29'h0, saw_mutex_id}, {29'h0, mutex_id[2:0]}, "rtos_mutex_id matches requested ID");

        // Verify return 0 (success, since auto-responder returns result=1)
        check_eq(u_dut.last_syscall_ret_r, 32'h0, "mutex_lock returns 0 on success");

        // --- Test mutex unlock ---
        clear_observations();

        issue_syscall(SYS_MUTEX_UNLOCK, mutex_id, 32'h0, 32'h0);

        // Verify mutex op was issued - unlock = 2'b11
        check_eq({30'h0, saw_mutex_op}, {30'h0, 2'b11}, "rtos_mutex_op = UNLOCK (2'b11)");

        // Verify return 0 (success)
        check_eq(u_dut.last_syscall_ret_r, 32'h0, "mutex_unlock returns 0 on success");
    endtask

    // -------------------------------------------------------------------------
    // PTH-005: sched_yield
    // Issue SYS_PTHREAD_YIELD and verify rtos_task_yield is asserted
    // -------------------------------------------------------------------------
    task automatic test_pth_005_sched_yield();
        test_begin("PTH-005: sched_yield - yield execution");

        clear_observations();

        issue_syscall(SYS_PTHREAD_YIELD, 32'h0, 32'h0, 32'h0);

        // Verify rtos_task_yield was asserted
        check(saw_task_yield, "rtos_task_yield was asserted");

        // Verify return 0 (success)
        check_eq(u_dut.last_syscall_ret_r, 32'h0, "sched_yield returns 0");
    endtask

endmodule
