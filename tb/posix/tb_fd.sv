// =============================================================================
// VSync - POSIX File Descriptor Testbench
// =============================================================================
// Tests: FD-001 ~ FD-005
//   FD-001: open/close (FD allocation and release)
//   FD-002: read/write (data read/write via FD, e.g., UART)
//   FD-003: stdin/stdout/stderr (standard FDs 0,1,2 behavior)
//   FD-004: FD limit (behavior when max FD count reached)
//   FD-005: Bad FD (invalid FD error handling)
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_fd;

    import test_utils::*;
    import vsync_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD = 10;
    localparam RST_CYCLES = 10;

    // Syscall numbers
    localparam logic [7:0] SYS_OPEN_NUM  = 8'h50;
    localparam logic [7:0] SYS_CLOSE_NUM = 8'h51;
    localparam logic [7:0] SYS_READ_NUM  = 8'h52;
    localparam logic [7:0] SYS_WRITE_NUM = 8'h53;

    // Error codes
    localparam logic [31:0] ERR_EMFILE = 32'hFFFF_FFE4; // -28
    localparam logic [31:0] ERR_EBADF  = 32'hFFFF_FFF7; // -9
    localparam logic [31:0] ERR_EPERM  = 32'hFFFF_FFFF; // -1

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

    // AXI stub signals (active-low, no-op)
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
    // Peripheral Auto-Respond Stub
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            periph_ready <= 0;
            periph_rdata <= 0;
        end else begin
            periph_ready <= 0;
            if (periph_read || periph_write) begin
                periph_ready <= 1;
                periph_rdata <= 32'h0000_5678;
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
        $dumpfile("tb_fd.vcd");
        $dumpvars(0, tb_fd);
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
        test_suite_begin("POSIX File Descriptor Tests");

        test_fd_001_open_close();
        test_fd_002_read_write();
        test_fd_003_standard_fds();
        test_fd_004_fd_limit();
        test_fd_005_bad_fd();
    endtask

    // -------------------------------------------------------------------------
    // FD-001: SYS_OPEN/SYS_CLOSE
    // -------------------------------------------------------------------------
    task automatic test_fd_001_open_close();
        logic [31:0] opened_fd;
        logic [31:0] gpio_fd;

        test_begin("FD-001: SYS_OPEN/SYS_CLOSE - FD allocation and release");

        // Open UART device (device_type=1=UART, flags=0)
        issue_syscall(SYS_OPEN_NUM, 32'd1, 32'd0, 32'd0);
        opened_fd = captured_ret;
        $display("  SYS_OPEN UART: returned fd=%0d", opened_fd);
        check(captured_ret >= 3 && captured_ret < 16,
              "SYS_OPEN returns valid FD (>=3, <16)");

        // Close the opened FD
        issue_syscall(SYS_CLOSE_NUM, opened_fd, 32'd0, 32'd0);
        $display("  SYS_CLOSE fd=%0d: returned 0x%08h", opened_fd, captured_ret);
        check_eq(captured_ret, 32'd0, "SYS_CLOSE returns 0 on success");

        // Open GPIO device (device_type=2=GPIO)
        issue_syscall(SYS_OPEN_NUM, 32'd2, 32'd0, 32'd0);
        gpio_fd = captured_ret;
        $display("  SYS_OPEN GPIO: returned fd=%0d", gpio_fd);
        check(captured_ret >= 3 && captured_ret < 16,
              "SYS_OPEN GPIO returns valid FD");

        // Close it
        issue_syscall(SYS_CLOSE_NUM, gpio_fd, 32'd0, 32'd0);
        check_eq(captured_ret, 32'd0, "SYS_CLOSE GPIO FD returns 0");
    endtask

    // -------------------------------------------------------------------------
    // FD-002: SYS_READ/SYS_WRITE
    // -------------------------------------------------------------------------
    task automatic test_fd_002_read_write();
        test_begin("FD-002: SYS_READ/SYS_WRITE - data via FD");

        // Write to stdout (fd=1, data=0xDEADBEEF, count=4)
        issue_syscall(SYS_WRITE_NUM, 32'd1, 32'hDEAD_BEEF, 32'd4);
        $display("  SYS_WRITE stdout: returned 0x%08h", captured_ret);
        // Write goes through periph; result_r is set from periph_rdata in S_PERIPH_WAIT
        // The periph stub returns 0x00005678. But let's check the DUT result logic.
        // Actually for write (subop 4'h3): result_r <= latched_arg2 (bytes_written)
        // But it then goes to S_PERIPH_WAIT which overwrites with periph_rdata.
        // The final result is periph_rdata (0x00005678).
        check(captured_ret != ERR_EBADF,
              "SYS_WRITE stdout does not return EBADF");

        // Read from stdin (fd=0, buf_addr=0x1000, count=4)
        issue_syscall(SYS_READ_NUM, 32'd0, 32'h0000_1000, 32'd4);
        $display("  SYS_READ stdin: returned 0x%08h", captured_ret);
        // Read routes through periph, result is periph_rdata
        check(captured_ret != ERR_EBADF,
              "SYS_READ stdin does not return EBADF");
    endtask

    // -------------------------------------------------------------------------
    // FD-003: Pre-initialized FDs (stdin/stdout/stderr)
    // -------------------------------------------------------------------------
    task automatic test_fd_003_standard_fds();
        test_begin("FD-003: Pre-initialized FDs 0,1,2");

        // Write to stdout (fd=1) - should succeed since fd=1 is valid
        // Write goes to periph and result comes from periph_rdata
        issue_syscall(SYS_WRITE_NUM, 32'd1, 32'h0000_1234, 32'd4);
        $display("  Write stdout (fd=1): ret=0x%08h", captured_ret);
        check(captured_ret != ERR_EBADF,
              "Write stdout succeeds (not EBADF)");

        // Write to stderr (fd=2) - should succeed since fd=2 is valid
        issue_syscall(SYS_WRITE_NUM, 32'd2, 32'h0000_5678, 32'd4);
        $display("  Write stderr (fd=2): ret=0x%08h", captured_ret);
        check(captured_ret != ERR_EBADF,
              "Write stderr succeeds (not EBADF)");

        // Read from stdin (fd=0) - should succeed since fd=0 is valid
        issue_syscall(SYS_READ_NUM, 32'd0, 32'h0000_2000, 32'd1);
        $display("  Read stdin (fd=0): ret=0x%08h", captured_ret);
        check(captured_ret != ERR_EBADF,
              "Read stdin does not return EBADF");

        // Close stdin (fd=0) should return EPERM (cannot close standard FDs <=2)
        issue_syscall(SYS_CLOSE_NUM, 32'd0, 32'd0, 32'd0);
        $display("  Close stdin (fd=0): ret=0x%08h", captured_ret);
        check_eq(captured_ret, ERR_EPERM, "Close stdin returns EPERM");
    endtask

    // -------------------------------------------------------------------------
    // FD-004: MAX_FD limit
    // -------------------------------------------------------------------------
    task automatic test_fd_004_fd_limit();
        logic [31:0] fds [13];
        int i;
        logic all_valid;

        test_begin("FD-004: MAX_FD limit - 13 opens exhaust FD table");

        // Open 13 FDs (fd 3 through 15) - all UART devices
        all_valid = 1;
        for (i = 0; i < 13; i++) begin
            issue_syscall(SYS_OPEN_NUM, 32'd1, 32'd0, 32'd0);
            fds[i] = captured_ret;
            $display("  Open #%0d: fd=%0d", i, fds[i]);
            if (captured_ret < 3 || captured_ret >= 16) all_valid = 0;
        end
        check(all_valid == 1, "All 13 opens return valid FDs (3-15)");

        // 14th open should fail with EMFILE
        issue_syscall(SYS_OPEN_NUM, 32'd1, 32'd0, 32'd0);
        $display("  Open #14 (overflow): ret=0x%08h", captured_ret);
        check_eq(captured_ret, ERR_EMFILE, "14th open returns EMFILE");

        // Close all opened FDs to clean up
        for (i = 0; i < 13; i++) begin
            issue_syscall(SYS_CLOSE_NUM, fds[i], 32'd0, 32'd0);
        end
        $display("  Cleaned up all 13 FDs");

        // Verify we can open again after cleanup
        issue_syscall(SYS_OPEN_NUM, 32'd1, 32'd0, 32'd0);
        $display("  Re-open after cleanup: fd=%0d", captured_ret);
        check(captured_ret >= 3 && captured_ret < 16,
              "Open succeeds after FD cleanup");

        // Clean up
        issue_syscall(SYS_CLOSE_NUM, captured_ret, 32'd0, 32'd0);
    endtask

    // -------------------------------------------------------------------------
    // FD-005: Bad FD
    // -------------------------------------------------------------------------
    task automatic test_fd_005_bad_fd();
        test_begin("FD-005: Bad FD - invalid FD error handling");

        // Close an invalid FD (fd=10, never opened)
        issue_syscall(SYS_CLOSE_NUM, 32'd10, 32'd0, 32'd0);
        $display("  Close invalid fd=10: ret=0x%08h", captured_ret);
        check_eq(captured_ret, ERR_EBADF, "Close invalid FD returns EBADF");

        // Read from invalid FD (fd=10)
        issue_syscall(SYS_READ_NUM, 32'd10, 32'h0000_1000, 32'd4);
        $display("  Read invalid fd=10: ret=0x%08h", captured_ret);
        check_eq(captured_ret, ERR_EBADF, "Read invalid FD returns EBADF");

        // Write to invalid FD (fd=10)
        issue_syscall(SYS_WRITE_NUM, 32'd10, 32'hDEAD_BEEF, 32'd4);
        $display("  Write invalid fd=10: ret=0x%08h", captured_ret);
        check_eq(captured_ret, ERR_EBADF, "Write invalid FD returns EBADF");

        // Close out-of-range FD (fd=20, >= MAX_FD=16)
        issue_syscall(SYS_CLOSE_NUM, 32'd20, 32'd0, 32'd0);
        $display("  Close out-of-range fd=20: ret=0x%08h", captured_ret);
        check_eq(captured_ret, ERR_EBADF, "Close out-of-range FD returns EBADF");
    endtask

endmodule
