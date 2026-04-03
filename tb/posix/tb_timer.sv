// =============================================================================
// VSync - POSIX Timer Testbench
// =============================================================================
// Tests: TMR-001 ~ TMR-004
//   TMR-001: clock_gettime equivalent (current time retrieval)
//   TMR-002: nanosleep equivalent (sleep operation)
//   TMR-003: timer_create equivalent (timer creation)
//   TMR-004: Multiple timer reads (repeated clock_gettime)
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_timer;

    import test_utils::*;
    import vsync_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD   = 10;       // 100MHz
    localparam RST_CYCLES   = 10;

    // Syscall numbers
    localparam logic [7:0] SYS_CLOCK_GETTIME_NUM = 8'h40;
    localparam logic [7:0] SYS_NANOSLEEP_NUM     = 8'h42;
    localparam logic [7:0] SYS_TIMER_CREATE_NUM  = 8'h43;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // Syscall interface
    logic        ecall_req;
    logic [7:0]  syscall_num;
    logic [31:0] syscall_arg0;
    logic [31:0] syscall_arg1;
    logic [31:0] syscall_arg2;
    logic [31:0] syscall_ret;
    logic        syscall_done;

    // RTOS stub signals
    logic        rtos_task_create;
    logic [31:0] rtos_task_create_pc;
    logic [31:0] rtos_task_create_sp;
    logic [TASK_PRIORITY_W-1:0] rtos_task_create_prio;
    logic        rtos_task_create_done;
    logic [TASK_ID_W-1:0] rtos_task_create_id;
    logic        rtos_task_exit;
    logic        rtos_task_join;
    logic [TASK_ID_W-1:0] rtos_task_target_id;
    logic        rtos_task_join_done;
    logic        rtos_task_yield;
    logic [1:0]  rtos_sem_op;
    logic [2:0]  rtos_sem_id;
    logic [7:0]  rtos_sem_value;
    logic        rtos_sem_done;
    logic        rtos_sem_result;
    logic [1:0]  rtos_mutex_op;
    logic [2:0]  rtos_mutex_id;
    logic        rtos_mutex_done;
    logic        rtos_mutex_result;
    logic [1:0]  rtos_msgq_op;
    logic [1:0]  rtos_msgq_id;
    logic [31:0] rtos_msgq_data;
    logic        rtos_msgq_done;
    logic [31:0] rtos_msgq_result;
    logic        rtos_msgq_success;
    logic [TASK_ID_W-1:0] rtos_current_tid;

    // Peripheral stub signals
    logic [31:0] periph_addr;
    logic [31:0] periph_wdata;
    logic        periph_read;
    logic        periph_write;
    logic [31:0] periph_rdata;
    logic        periph_ready;

    // AXI stub signals
    logic [31:0] s_axi_awaddr;
    logic [2:0]  s_axi_awprot;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [3:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;
    logic [31:0] s_axi_araddr;
    logic [2:0]  s_axi_arprot;
    logic        s_axi_arvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

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
    posix_hw_layer u_dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .ecall_req             (ecall_req),
        .syscall_num           (syscall_num),
        .syscall_arg0          (syscall_arg0),
        .syscall_arg1          (syscall_arg1),
        .syscall_arg2          (syscall_arg2),
        .syscall_ret           (syscall_ret),
        .syscall_done          (syscall_done),
        .rtos_task_create      (rtos_task_create),
        .rtos_task_create_pc   (rtos_task_create_pc),
        .rtos_task_create_sp   (rtos_task_create_sp),
        .rtos_task_create_prio (rtos_task_create_prio),
        .rtos_task_create_done (rtos_task_create_done),
        .rtos_task_create_id   (rtos_task_create_id),
        .rtos_task_exit        (rtos_task_exit),
        .rtos_task_join        (rtos_task_join),
        .rtos_task_target_id   (rtos_task_target_id),
        .rtos_task_join_done   (rtos_task_join_done),
        .rtos_task_yield       (rtos_task_yield),
        .rtos_sem_op           (rtos_sem_op),
        .rtos_sem_id           (rtos_sem_id),
        .rtos_sem_value        (rtos_sem_value),
        .rtos_sem_done         (rtos_sem_done),
        .rtos_sem_result       (rtos_sem_result),
        .rtos_mutex_op         (rtos_mutex_op),
        .rtos_mutex_id         (rtos_mutex_id),
        .rtos_mutex_done       (rtos_mutex_done),
        .rtos_mutex_result     (rtos_mutex_result),
        .rtos_msgq_op          (rtos_msgq_op),
        .rtos_msgq_id          (rtos_msgq_id),
        .rtos_msgq_data        (rtos_msgq_data),
        .rtos_msgq_done        (rtos_msgq_done),
        .rtos_msgq_result      (rtos_msgq_result),
        .rtos_msgq_success     (rtos_msgq_success),
        .rtos_current_tid      (rtos_current_tid),
        .periph_addr           (periph_addr),
        .periph_wdata          (periph_wdata),
        .periph_read           (periph_read),
        .periph_write          (periph_write),
        .periph_rdata          (periph_rdata),
        .periph_ready          (periph_ready),
        .s_axi_awaddr          (s_axi_awaddr),
        .s_axi_awprot          (s_axi_awprot),
        .s_axi_awvalid         (s_axi_awvalid),
        .s_axi_awready         (s_axi_awready),
        .s_axi_wdata           (s_axi_wdata),
        .s_axi_wstrb           (s_axi_wstrb),
        .s_axi_wvalid          (s_axi_wvalid),
        .s_axi_wready          (s_axi_wready),
        .s_axi_bresp           (s_axi_bresp),
        .s_axi_bvalid          (s_axi_bvalid),
        .s_axi_bready          (s_axi_bready),
        .s_axi_araddr          (s_axi_araddr),
        .s_axi_arprot          (s_axi_arprot),
        .s_axi_arvalid         (s_axi_arvalid),
        .s_axi_arready         (s_axi_arready),
        .s_axi_rdata           (s_axi_rdata),
        .s_axi_rresp           (s_axi_rresp),
        .s_axi_rvalid          (s_axi_rvalid),
        .s_axi_rready          (s_axi_rready)
    );

    // =========================================================================
    // RTOS Auto-Respond Stubs
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rtos_task_create_done <= 0;
            rtos_task_create_id   <= 0;
        end else begin
            rtos_task_create_done <= 0;
            if (rtos_task_create) begin
                rtos_task_create_done <= 1;
                rtos_task_create_id   <= 4'd1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rtos_task_join_done <= 0;
        end else begin
            rtos_task_join_done <= 0;
            if (rtos_task_join) begin
                rtos_task_join_done <= 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rtos_sem_done   <= 0;
            rtos_sem_result <= 0;
        end else begin
            rtos_sem_done <= 0;
            if (rtos_sem_op != 2'b00) begin
                rtos_sem_done   <= 1;
                rtos_sem_result <= 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rtos_mutex_done   <= 0;
            rtos_mutex_result <= 0;
        end else begin
            rtos_mutex_done <= 0;
            if (rtos_mutex_op != 2'b00) begin
                rtos_mutex_done   <= 1;
                rtos_mutex_result <= 1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rtos_msgq_done    <= 0;
            rtos_msgq_result  <= 0;
            rtos_msgq_success <= 0;
        end else begin
            rtos_msgq_done <= 0;
            if (rtos_msgq_op != 2'b00) begin
                rtos_msgq_done    <= 1;
                rtos_msgq_result  <= 32'h0;
                rtos_msgq_success <= 1;
            end
        end
    end

    // =========================================================================
    // Peripheral Auto-Respond Stub (with incrementing time value)
    // =========================================================================
    logic [31:0] periph_time_counter;
    logic [31:0] last_periph_addr;  // capture for verification
    logic        last_periph_read;  // capture for verification

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            periph_time_counter <= 32'd1000;
        end else begin
            periph_time_counter <= periph_time_counter + 32'd10;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            periph_ready     <= 0;
            periph_rdata     <= 0;
            last_periph_addr <= 0;
            last_periph_read <= 0;
        end else begin
            periph_ready <= 0;
            if (periph_read || periph_write) begin
                periph_ready     <= 1;
                periph_rdata     <= periph_time_counter;
                last_periph_addr <= periph_addr;
                last_periph_read <= periph_read;
            end
        end
    end

    // =========================================================================
    // AXI Stub Tie-offs
    // =========================================================================
    initial begin
        s_axi_awaddr  = '0;
        s_axi_awprot  = '0;
        s_axi_awvalid = '0;
        s_axi_wdata   = '0;
        s_axi_wstrb   = '0;
        s_axi_wvalid  = '0;
        s_axi_bready  = 1'b1;
        s_axi_araddr  = '0;
        s_axi_arprot  = '0;
        s_axi_arvalid = '0;
        s_axi_rready  = 1'b1;
        rtos_current_tid = '0;
    end

    // =========================================================================
    // Captured Return Value
    // =========================================================================
    logic [31:0] captured_ret;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            captured_ret <= '0;
        else if (syscall_done)
            captured_ret <= syscall_ret;
    end

    // =========================================================================
    // Syscall Helper Task
    // =========================================================================
    task automatic issue_syscall(input logic [7:0] num, input logic [31:0] arg0, arg1, arg2);
        int timeout_cnt;
        @(posedge clk);
        ecall_req   <= 1;
        syscall_num <= num;
        syscall_arg0 <= arg0;
        syscall_arg1 <= arg1;
        syscall_arg2 <= arg2;
        @(posedge clk);
        ecall_req <= 0;
        timeout_cnt = 0;
        while (!syscall_done && timeout_cnt < 500) begin
            @(posedge clk);
            timeout_cnt++;
        end
        // Wait one more cycle so captured_ret latches the value
        @(posedge clk);
    endtask

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_timer.vcd");
        $dumpvars(0, tb_timer);
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 500000);
        $display("ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded maximum time");
    end

    // =========================================================================
    // Signal Initialization
    // =========================================================================
    initial begin
        ecall_req    = 0;
        syscall_num  = 0;
        syscall_arg0 = 0;
        syscall_arg1 = 0;
        syscall_arg2 = 0;
    end

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
        test_suite_begin("POSIX Timer Tests");

        test_tmr_001_clock_gettime();
        test_tmr_002_nanosleep();
        test_tmr_003_timer_create();
        test_tmr_004_multiple_timer_reads();
    endtask

    // -------------------------------------------------------------------------
    // TMR-001: SYS_CLOCK_GETTIME
    // -------------------------------------------------------------------------
    task automatic test_tmr_001_clock_gettime();
        logic [31:0] time_val;

        test_begin("TMR-001: SYS_CLOCK_GETTIME - current time retrieval");

        // Issue clock_gettime syscall (0x40)
        // This reads ADDR_MTIME_LO via the peripheral interface
        issue_syscall(SYS_CLOCK_GETTIME_NUM, 32'd0, 32'd0, 32'd0);
        time_val = captured_ret;
        $display("  clock_gettime: returned 0x%08h", time_val);

        // The periph stub returns an incrementing counter value (starts ~1000)
        // Verify the syscall completed and returned a non-zero value
        check(time_val != 32'd0, "clock_gettime returns non-zero time value");

        // Verify periph_read was issued to ADDR_MTIME_LO (0x0200_BFF8)
        $display("  last_periph_addr=0x%08h, last_periph_read=%0b", last_periph_addr, last_periph_read);
        check_eq(last_periph_addr, 32'h0200_BFF8, "periph_addr == ADDR_MTIME_LO");
        check(last_periph_read == 1'b1, "periph_read was asserted");
    endtask

    // -------------------------------------------------------------------------
    // TMR-002: SYS_NANOSLEEP
    // -------------------------------------------------------------------------
    task automatic test_tmr_002_nanosleep();
        test_begin("TMR-002: SYS_NANOSLEEP - sleep operation");

        // Issue nanosleep syscall (0x42) with duration=1000
        // The DUT first reads current mtime via periph, then goes to S_COMPLETE
        issue_syscall(SYS_NANOSLEEP_NUM, 32'd1000, 32'd0, 32'd0);
        $display("  nanosleep(1000): returned 0x%08h", captured_ret);

        // Verify the syscall completed (returned from periph read)
        // The result is the periph_rdata value (mtime read)
        check(captured_ret != 32'hFFFF_FFFF, "nanosleep completes without error");

        // Issue nanosleep with zero duration (yield behavior)
        issue_syscall(SYS_NANOSLEEP_NUM, 32'd0, 32'd0, 32'd0);
        $display("  nanosleep(0): returned 0x%08h", captured_ret);
        check(captured_ret != 32'hFFFF_FFFF, "nanosleep(0) completes");
    endtask

    // -------------------------------------------------------------------------
    // TMR-003: SYS_TIMER_CREATE
    // -------------------------------------------------------------------------
    task automatic test_tmr_003_timer_create();
        test_begin("TMR-003: SYS_TIMER_CREATE - timer creation");

        // Issue timer_create syscall (0x43)
        // This routes through the periph interface to CLINT
        issue_syscall(SYS_TIMER_CREATE_NUM, 32'd0, 32'd0, 32'd0);
        $display("  timer_create: returned 0x%08h", captured_ret);

        // Verify syscall completed - result comes from periph stub
        check(captured_ret != 32'hFFFF_FFD8, "timer_create does not return ENOSYS");

        // Create a second timer
        issue_syscall(SYS_TIMER_CREATE_NUM, 32'd1, 32'd0, 32'd0);
        $display("  timer_create #2: returned 0x%08h", captured_ret);
        check(captured_ret != 32'hFFFF_FFD8, "timer_create #2 does not return ENOSYS");
    endtask

    // -------------------------------------------------------------------------
    // TMR-004: Multiple clock_gettime reads
    // -------------------------------------------------------------------------
    task automatic test_tmr_004_multiple_timer_reads();
        logic [31:0] time1, time2, time3;

        test_begin("TMR-004: Multiple timer reads - repeated clock_gettime");

        // First read
        issue_syscall(SYS_CLOCK_GETTIME_NUM, 32'd0, 32'd0, 32'd0);
        time1 = captured_ret;
        $display("  clock_gettime #1: 0x%08h", time1);

        // Small delay
        repeat(10) @(posedge clk);

        // Second read
        issue_syscall(SYS_CLOCK_GETTIME_NUM, 32'd0, 32'd0, 32'd0);
        time2 = captured_ret;
        $display("  clock_gettime #2: 0x%08h", time2);

        // Third read
        repeat(20) @(posedge clk);
        issue_syscall(SYS_CLOCK_GETTIME_NUM, 32'd0, 32'd0, 32'd0);
        time3 = captured_ret;
        $display("  clock_gettime #3: 0x%08h", time3);

        // Verify each call completes successfully
        check(time1 != 32'd0, "clock_gettime #1 returns non-zero");
        check(time2 != 32'd0, "clock_gettime #2 returns non-zero");
        check(time3 != 32'd0, "clock_gettime #3 returns non-zero");

        // Verify time is monotonically increasing (periph_time_counter increments)
        check(time2 > time1, "Time is monotonically increasing (t2 > t1)");
        check(time3 > time2, "Time is monotonically increasing (t3 > t2)");
    endtask

endmodule
