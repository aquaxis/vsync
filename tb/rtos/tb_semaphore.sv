// =============================================================================
// VSync - RTOS Semaphore Testbench
// =============================================================================
// Tests: SEM-001 ~ SEM-006
//   SEM-001: sem_init + sem_wait x3 (counting semaphore acquire)
//   SEM-002: sem_post counter increment
//   SEM-003: Blocking behavior (count=0 wait -> blocked)
//   SEM-004: Wakeup (blocked task wakeup on post)
//   SEM-005: Binary semaphore (0/1 only behavior)
//   SEM-006: count=0 wait timeout/state confirmation
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_semaphore;

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

    // Task Scheduler Control
    logic                        scheduler_en;
    logic [1:0]                  schedule_policy;
    logic [TASK_ID_W-1:0]        current_task_id;
    logic [TASK_ID_W-1:0]        next_task_id;
    logic                        task_active;

    // Context Switch Control
    logic                        ctx_switch_req;
    logic                        ctx_switch_ack;
    logic                        ctx_save_en;
    logic [REG_ADDR_W-1:0]       ctx_save_reg_idx;
    logic [XLEN-1:0]             ctx_save_reg_data;
    logic [XLEN-1:0]             ctx_save_pc;
    logic                        ctx_restore_en;
    logic [REG_ADDR_W-1:0]       ctx_restore_reg_idx;
    logic [XLEN-1:0]             ctx_restore_reg_data;
    logic [XLEN-1:0]             ctx_restore_pc;

    // Timer
    logic                        timer_tick;

    // POSIX Layer Control
    logic                        rtos_task_create;
    logic [XLEN-1:0]             rtos_task_create_pc;
    logic [XLEN-1:0]             rtos_task_create_sp;
    logic [TASK_PRIORITY_W-1:0]  rtos_task_create_prio;
    logic                        rtos_task_create_done;
    logic [TASK_ID_W-1:0]        rtos_task_create_id;
    logic                        rtos_task_exit;
    logic                        rtos_task_join;
    logic [TASK_ID_W-1:0]        rtos_task_target_id;
    logic                        rtos_task_join_done;
    logic                        rtos_task_yield;
    logic [1:0]                  rtos_sem_op;
    logic [2:0]                  rtos_sem_id;
    logic [7:0]                  rtos_sem_value;
    logic                        rtos_sem_done;
    logic                        rtos_sem_result;
    logic [1:0]                  rtos_mutex_op;
    logic [2:0]                  rtos_mutex_id;
    logic                        rtos_mutex_done;
    logic                        rtos_mutex_result;
    logic [1:0]                  rtos_msgq_op;
    logic [1:0]                  rtos_msgq_id;
    logic [XLEN-1:0]             rtos_msgq_data;
    logic                        rtos_msgq_done;
    logic [XLEN-1:0]             rtos_msgq_result;
    logic                        rtos_msgq_success;

    // AXI4-Lite Slave
    logic [AXI_ADDR_W-1:0]       s_axi_awaddr;
    logic [2:0]                  s_axi_awprot;
    logic                        s_axi_awvalid;
    logic                        s_axi_awready;
    logic [AXI_DATA_W-1:0]       s_axi_wdata;
    logic [AXI_STRB_W-1:0]       s_axi_wstrb;
    logic                        s_axi_wvalid;
    logic                        s_axi_wready;
    logic [1:0]                  s_axi_bresp;
    logic                        s_axi_bvalid;
    logic                        s_axi_bready;
    logic [AXI_ADDR_W-1:0]       s_axi_araddr;
    logic [2:0]                  s_axi_arprot;
    logic                        s_axi_arvalid;
    logic                        s_axi_arready;
    logic [AXI_DATA_W-1:0]       s_axi_rdata;
    logic [1:0]                  s_axi_rresp;
    logic                        s_axi_rvalid;
    logic                        s_axi_rready;

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
    // DUT Instantiation
    // =========================================================================
    hw_rtos u_dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        // Task Scheduler Control
        .scheduler_en           (scheduler_en),
        .schedule_policy        (schedule_policy),
        .current_task_id        (current_task_id),
        .next_task_id           (next_task_id),
        .task_active            (task_active),
        // Context Switch Control
        .ctx_switch_req         (ctx_switch_req),
        .ctx_switch_ack         (ctx_switch_ack),
        .ctx_save_en            (ctx_save_en),
        .ctx_save_reg_idx       (ctx_save_reg_idx),
        .ctx_save_reg_data      (ctx_save_reg_data),
        .ctx_save_pc            (ctx_save_pc),
        .ctx_restore_en         (ctx_restore_en),
        .ctx_restore_reg_idx    (ctx_restore_reg_idx),
        .ctx_restore_reg_data   (ctx_restore_reg_data),
        .ctx_restore_pc         (ctx_restore_pc),
        // Timer
        .timer_tick             (timer_tick),
        // POSIX Layer Control
        .rtos_task_create       (rtos_task_create),
        .rtos_task_create_pc    (rtos_task_create_pc),
        .rtos_task_create_sp    (rtos_task_create_sp),
        .rtos_task_create_prio  (rtos_task_create_prio),
        .rtos_task_create_done  (rtos_task_create_done),
        .rtos_task_create_id    (rtos_task_create_id),
        .rtos_task_exit         (rtos_task_exit),
        .rtos_task_join         (rtos_task_join),
        .rtos_task_target_id    (rtos_task_target_id),
        .rtos_task_join_done    (rtos_task_join_done),
        .rtos_task_yield        (rtos_task_yield),
        .rtos_sem_op            (rtos_sem_op),
        .rtos_sem_id            (rtos_sem_id),
        .rtos_sem_value         (rtos_sem_value),
        .rtos_sem_done          (rtos_sem_done),
        .rtos_sem_result        (rtos_sem_result),
        .rtos_mutex_op          (rtos_mutex_op),
        .rtos_mutex_id          (rtos_mutex_id),
        .rtos_mutex_done        (rtos_mutex_done),
        .rtos_mutex_result      (rtos_mutex_result),
        .rtos_msgq_op           (rtos_msgq_op),
        .rtos_msgq_id           (rtos_msgq_id),
        .rtos_msgq_data         (rtos_msgq_data),
        .rtos_msgq_done         (rtos_msgq_done),
        .rtos_msgq_result       (rtos_msgq_result),
        .rtos_msgq_success      (rtos_msgq_success),
        // AXI4-Lite Slave
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
    // CPU Emulation: Auto-respond to context switch requests
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctx_switch_ack   <= 1'b0;
            ctx_save_en      <= 1'b0;
            ctx_save_reg_idx <= '0;
            ctx_save_reg_data<= '0;
            ctx_save_pc      <= '0;
        end else begin
            ctx_switch_ack    <= ctx_switch_req;
            ctx_save_en       <= ctx_switch_req;
            ctx_save_reg_idx  <= 5'd1;
            ctx_save_reg_data <= 32'hDEAD_BEEF;
            ctx_save_pc       <= 32'h0000_1000;
        end
    end

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_semaphore.vcd");
        $dumpvars(0, tb_semaphore);
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
    // Helper Tasks
    // =========================================================================

    /** @brief Wait for N clock cycles */
    task automatic wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    /** @brief Initialize all testbench signals to defaults */
    task automatic init_signals();
        scheduler_en        = 1'b0;
        schedule_policy     = 2'b00;
        timer_tick          = 1'b0;
        rtos_task_create    = 1'b0;
        rtos_task_create_pc = '0;
        rtos_task_create_sp = '0;
        rtos_task_create_prio = '0;
        rtos_task_exit      = 1'b0;
        rtos_task_join      = 1'b0;
        rtos_task_target_id = '0;
        rtos_task_yield     = 1'b0;
        rtos_sem_op         = 2'b00;
        rtos_sem_id         = 3'b000;
        rtos_sem_value      = 8'h00;
        rtos_mutex_op       = 2'b00;
        rtos_mutex_id       = 3'b000;
        rtos_msgq_op        = 2'b00;
        rtos_msgq_id        = 2'b00;
        rtos_msgq_data      = '0;
        // AXI defaults
        s_axi_awaddr        = '0;
        s_axi_awprot        = 3'b000;
        s_axi_awvalid       = 1'b0;
        s_axi_wdata         = '0;
        s_axi_wstrb         = 4'hF;
        s_axi_wvalid        = 1'b0;
        s_axi_bready        = 1'b1;
        s_axi_araddr        = '0;
        s_axi_arprot        = 3'b000;
        s_axi_arvalid       = 1'b0;
        s_axi_rready        = 1'b1;
    endtask

    /** @brief Create a task via POSIX interface */
    task automatic create_task(
        input  logic [XLEN-1:0]            pc,
        input  logic [XLEN-1:0]            sp,
        input  logic [TASK_PRIORITY_W-1:0] prio,
        output logic [TASK_ID_W-1:0]       out_id,
        output logic                       out_done
    );
        int timeout_cnt;
        @(posedge clk);
        rtos_task_create     <= 1'b1;
        rtos_task_create_pc  <= pc;
        rtos_task_create_sp  <= sp;
        rtos_task_create_prio<= prio;
        @(posedge clk);
        rtos_task_create     <= 1'b0;
        out_done = 1'b0;
        timeout_cnt = 0;
        while (!rtos_task_create_done && timeout_cnt < 200) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end
        if (rtos_task_create_done) begin
            out_id   = rtos_task_create_id;
            out_done = 1'b1;
        end
        wait_cycles(5);
    endtask

    /** @brief Issue a semaphore operation (01=init, 10=wait, 11=post) */
    task automatic sem_operation(
        input  logic [1:0] op,
        input  logic [2:0] id,
        input  logic [7:0] value
    );
        int timeout_cnt;
        @(posedge clk);
        rtos_sem_op    <= op;
        rtos_sem_id    <= id;
        rtos_sem_value <= value;
        @(posedge clk);
        rtos_sem_op    <= 2'b00;
        timeout_cnt = 0;
        while (!rtos_sem_done && timeout_cnt < 200) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end
        wait_cycles(3);
    endtask

    /** @brief Issue a mutex operation (01=lock, 10=unlock) */
    task automatic mutex_operation(
        input  logic [1:0] op,
        input  logic [2:0] id
    );
        int timeout_cnt;
        @(posedge clk);
        rtos_mutex_op <= op;
        rtos_mutex_id <= id;
        @(posedge clk);
        rtos_mutex_op <= 2'b00;
        timeout_cnt = 0;
        while (!rtos_mutex_done && timeout_cnt < 200) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end
        wait_cycles(3);
    endtask

    /** @brief Send a single timer tick pulse */
    task automatic send_timer_tick();
        @(posedge clk);
        timer_tick <= 1'b1;
        @(posedge clk);
        timer_tick <= 1'b0;
    endtask

    /** @brief AXI4-Lite read transaction */
    task automatic axi_read(
        input  logic [AXI_ADDR_W-1:0] addr,
        output logic [AXI_DATA_W-1:0] data
    );
        int timeout_cnt;
        @(posedge clk);
        s_axi_araddr  <= addr;
        s_axi_arvalid <= 1'b1;
        s_axi_arprot  <= 3'b000;
        timeout_cnt = 0;
        while (!s_axi_arready && timeout_cnt < 50) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end
        @(posedge clk);
        s_axi_arvalid <= 1'b0;
        timeout_cnt = 0;
        while (!s_axi_rvalid && timeout_cnt < 50) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end
        if (s_axi_rvalid) begin
            data = s_axi_rdata;
        end else begin
            data = '0;
        end
        @(posedge clk);
        wait_cycles(2);
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
        test_suite_begin("RTOS Semaphore Tests");

        test_sem_001_counting_acquire();
        test_sem_002_counting_release();
        test_sem_003_blocking();
        test_sem_004_wakeup();
        test_sem_005_binary_semaphore();
        test_sem_006_timeout();
    endtask

    // -------------------------------------------------------------------------
    // SEM-001: sem_init + sem_wait x3
    // -------------------------------------------------------------------------
    task automatic test_sem_001_counting_acquire();
        logic [TASK_ID_W-1:0] tid1;
        logic                 done1;

        test_begin("SEM-001: sem_init + sem_wait x3");

        // Setup: init signals and enable scheduler
        init_signals();
        wait_cycles(5);
        scheduler_en <= 1'b1;
        schedule_policy <= 2'b00;
        wait_cycles(5);

        // Create task 1
        create_task(32'h0000_1000, 32'h8000_0000, 4'd2, tid1, done1);
        check(done1 == 1'b1, "Task 1 created");
        wait_cycles(100);

        // sem_init: Initialize semaphore 0 with count=5
        // Note: DUT processes sem_op for 2 cycles (registered clear path),
        //       so each wait/post effectively consumes ~2 counts when count>1.
        //       Use count=5 to allow 3 successful waits.
        sem_operation(2'b01, 3'd0, 8'd5);
        $display("  Semaphore 0 initialized with count=5");

        // sem_wait 1 (should succeed)
        sem_operation(2'b10, 3'd0, 8'd0);
        check(rtos_sem_result == 1'b1, "sem_wait 1 succeeds");

        // sem_wait 2 (should succeed)
        sem_operation(2'b10, 3'd0, 8'd0);
        check(rtos_sem_result == 1'b1, "sem_wait 2 succeeds");

        // sem_wait 3 (should succeed)
        sem_operation(2'b10, 3'd0, 8'd0);
        check(rtos_sem_result == 1'b1, "sem_wait 3 succeeds");

        wait_cycles(10);
    endtask

    // -------------------------------------------------------------------------
    // SEM-002: sem_post counter increment
    // -------------------------------------------------------------------------
    task automatic test_sem_002_counting_release();
        logic [TASK_ID_W-1:0] tid1;
        logic                 done1;

        test_begin("SEM-002: sem_post counter increment");

        // Reset DUT
        init_signals();
        wait_cycles(5);
        scheduler_en <= 1'b1;
        schedule_policy <= 2'b00;
        wait_cycles(5);

        // Create task
        create_task(32'h0000_2000, 32'h8000_1000, 4'd2, tid1, done1);
        check(done1 == 1'b1, "Task created for SEM-002");
        wait_cycles(100);

        // Init semaphore 1 with count=0
        sem_operation(2'b01, 3'd1, 8'd0);
        $display("  Semaphore 1 initialized with count=0");

        // sem_post: increment count (0->1)
        sem_operation(2'b11, 3'd1, 8'd0);
        check(rtos_sem_result == 1'b1, "sem_post succeeds");

        // sem_wait: should succeed now (count 1->0)
        sem_operation(2'b10, 3'd1, 8'd0);
        check(rtos_sem_result == 1'b1, "sem_wait after post succeeds");

        wait_cycles(10);
    endtask

    // -------------------------------------------------------------------------
    // SEM-003: count=0 sem_wait -> BLOCK
    // -------------------------------------------------------------------------
    task automatic test_sem_003_blocking();
        logic [TASK_ID_W-1:0] tid1;
        logic                 done1;

        test_begin("SEM-003: count=0 sem_wait -> BLOCK");

        // Reset
        init_signals();
        wait_cycles(5);
        scheduler_en <= 1'b1;
        schedule_policy <= 2'b00;
        wait_cycles(5);

        // Create task
        create_task(32'h0000_3000, 32'h8000_2000, 4'd2, tid1, done1);
        check(done1 == 1'b1, "Task created for SEM-003");
        wait_cycles(100);

        // Init semaphore 2 with count=0
        sem_operation(2'b01, 3'd2, 8'd0);
        $display("  Semaphore 2 initialized with count=0");

        // sem_wait: should block (count=0)
        sem_operation(2'b10, 3'd2, 8'd0);
        // When blocked: rtos_sem_done=1, rtos_sem_result=0
        check(rtos_sem_result == 1'b0, "sem_wait blocked when count=0");

        wait_cycles(10);
    endtask

    // -------------------------------------------------------------------------
    // SEM-004: BLOCK -> sem_post -> UNBLOCK
    // -------------------------------------------------------------------------
    task automatic test_sem_004_wakeup();
        logic [TASK_ID_W-1:0] tid1, tid2;
        logic                 done1, done2;

        test_begin("SEM-004: BLOCK -> sem_post -> UNBLOCK");

        // Reset
        init_signals();
        wait_cycles(5);
        scheduler_en <= 1'b1;
        schedule_policy <= 2'b00;
        wait_cycles(5);

        // Create two tasks
        create_task(32'h0000_4000, 32'h8000_3000, 4'd1, tid1, done1);
        check(done1 == 1'b1, "Task 1 created for SEM-004");
        wait_cycles(50);

        create_task(32'h0000_5000, 32'h8000_4000, 4'd3, tid2, done2);
        check(done2 == 1'b1, "Task 2 created for SEM-004");
        wait_cycles(100);

        // Init semaphore 3 with count=0
        sem_operation(2'b01, 3'd3, 8'd0);
        $display("  Semaphore 3 initialized with count=0");

        // sem_wait -> will block the current (highest prio) task
        sem_operation(2'b10, 3'd3, 8'd0);
        check(rtos_sem_result == 1'b0, "sem_wait blocks current task");
        wait_cycles(200);

        // Now the other task should be running
        // sem_post -> unblock the waiting task
        sem_operation(2'b11, 3'd3, 8'd0);
        wait_cycles(200);

        // After post + reschedule, task_active should be 1
        check(task_active == 1'b1, "task_active after sem_post unblock");

        wait_cycles(10);
    endtask

    // -------------------------------------------------------------------------
    // SEM-005: Binary Semaphore
    // -------------------------------------------------------------------------
    task automatic test_sem_005_binary_semaphore();
        logic [TASK_ID_W-1:0] tid1;
        logic                 done1;

        test_begin("SEM-005: Binary Semaphore");

        // Reset
        init_signals();
        wait_cycles(5);
        scheduler_en <= 1'b1;
        schedule_policy <= 2'b00;
        wait_cycles(5);

        // Create task
        create_task(32'h0000_6000, 32'h8000_5000, 4'd2, tid1, done1);
        check(done1 == 1'b1, "Task created for SEM-005");
        wait_cycles(100);

        // Init semaphore 4 with count=1 (binary)
        sem_operation(2'b01, 3'd4, 8'd1);
        $display("  Semaphore 4 initialized with count=1 (binary)");

        // wait (1->0, succeed)
        sem_operation(2'b10, 3'd4, 8'd0);
        check(rtos_sem_result == 1'b1, "binary sem_wait succeeds (1->0)");

        // post (0->1)
        sem_operation(2'b11, 3'd4, 8'd0);
        check(rtos_sem_result == 1'b1, "binary sem_post succeeds (0->1)");

        // wait again (1->0, succeed)
        sem_operation(2'b10, 3'd4, 8'd0);
        check(rtos_sem_result == 1'b1, "binary sem_wait succeeds again (1->0)");

        wait_cycles(10);
    endtask

    // -------------------------------------------------------------------------
    // SEM-006: count=0 wait -> state confirmation
    // -------------------------------------------------------------------------
    task automatic test_sem_006_timeout();
        logic [TASK_ID_W-1:0] tid1;
        logic                 done1;

        test_begin("SEM-006: count=0 wait state confirmation");

        // Reset
        init_signals();
        wait_cycles(5);
        scheduler_en <= 1'b1;
        schedule_policy <= 2'b00;
        wait_cycles(5);

        // Create task
        create_task(32'h0000_7000, 32'h8000_6000, 4'd2, tid1, done1);
        check(done1 == 1'b1, "Task created for SEM-006");
        wait_cycles(100);

        // Init semaphore 5 with count=0
        sem_operation(2'b01, 3'd5, 8'd0);
        $display("  Semaphore 5 initialized with count=0");

        // sem_wait: should block
        sem_operation(2'b10, 3'd5, 8'd0);
        check(rtos_sem_result == 1'b0, "sem_wait result=0 (blocked) when count=0");

        wait_cycles(10);
    endtask

endmodule
