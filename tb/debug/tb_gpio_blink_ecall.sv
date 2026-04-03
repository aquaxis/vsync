// =============================================================================
// VSync - GPIO Blink ecall+ret Debug Testbench
//
// Focused testbench to diagnose: ret at 0x228 jumps to 0x7c instead of 0x260
// Loads gpio_blink firmware, provides auto-syscall response, traces PC/ra.
// =============================================================================

`timescale 1ns / 1ps

module tb_gpio_blink_ecall;

    import vsync_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam real CLK_PERIOD   = 10.0;   // 100 MHz
    localparam int  TIMEOUT      = 100000; // Simulation timeout in cycles
    localparam int  IMEM_DEPTH   = 16384;  // 64KB / 4 = 16K words
    localparam int  DMEM_DEPTH   = 4096;   // 16KB / 4 = 4K words

    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic                       clk;
    logic                       rst_n;

    // Instruction memory interface
    logic [IMEM_ADDR_W-1:0]     imem_addr;
    logic [XLEN-1:0]            imem_rdata;
    logic                       imem_en;

    // Data memory interface
    logic [XLEN-1:0]            mem_addr;
    logic [XLEN-1:0]            mem_wdata;
    logic                       mem_read;
    logic                       mem_write;
    logic [2:0]                 mem_size;
    logic [XLEN-1:0]            mem_rdata;
    logic                       mem_ready;
    logic                       mem_error;

    // Interrupts
    logic                       external_irq;
    logic                       timer_irq;
    logic                       software_irq;

    // RTOS Control (tied off)
    logic                       ctx_switch_req;
    logic                       ctx_switch_ack;
    logic                       ctx_save_en;
    logic [REG_ADDR_W-1:0]      ctx_save_reg_idx;
    logic [XLEN-1:0]            ctx_save_reg_data;
    logic [XLEN-1:0]            ctx_save_pc;
    logic                       ctx_restore_en;
    logic [REG_ADDR_W-1:0]      ctx_restore_reg_idx;
    logic [XLEN-1:0]            ctx_restore_reg_data;
    logic [XLEN-1:0]            ctx_restore_pc;
    logic [TASK_ID_W-1:0]       current_task_id_in;
    logic                       task_active_in;

    // POSIX Syscall
    logic                       ecall_req;
    logic [7:0]                 syscall_num;
    logic [XLEN-1:0]            syscall_arg0;
    logic [XLEN-1:0]            syscall_arg1;
    logic [XLEN-1:0]            syscall_arg2;
    logic [XLEN-1:0]            syscall_ret;
    logic                       syscall_done;

    // Debug
    logic                       debug_halt_req;
    logic                       debug_halted;
    logic [XLEN-1:0]            debug_pc;
    logic [XLEN-1:0]            debug_instr;
    logic [REG_ADDR_W-1:0]      debug_reg_addr;
    logic [XLEN-1:0]            debug_reg_data;

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_gpio_blink_ecall.vcd");
        $dumpvars(0, tb_gpio_blink_ecall);
    end

    // =========================================================================
    // Instruction Memory (BRAM)
    // =========================================================================
    localparam int IMEM_WORD_ADDR_W = IMEM_ADDR_W - 2;
    bram_imem #(
        .DEPTH      (IMEM_DEPTH),
        .ADDR_WIDTH (IMEM_WORD_ADDR_W),
        .DATA_WIDTH (32),
        .INIT_FILE  ("sw/tools/build/gpio_blink_i.hex")
    ) u_imem (
        .clk     (clk),
        .a_en    (imem_en),
        .a_addr  (imem_addr[IMEM_ADDR_W-1:2]),
        .a_rdata (imem_rdata),
        .b_en    (1'b0),
        .b_we    (1'b0),
        .b_be    (4'b0000),
        .b_addr  ({IMEM_WORD_ADDR_W{1'b0}}),
        .b_wdata (32'h0),
        .b_rdata ()
    );

    // =========================================================================
    // Data Memory Model (Simple synchronous memory)
    // =========================================================================
    logic [31:0] dmem [0:DMEM_DEPTH-1];

    wire [31:0] dmem_offset = mem_addr - 32'h0001_0000;
    wire [13:0] dmem_word_addr = dmem_offset[15:2];

    wire [13:0] dmem_addr_mux = (mem_addr < 32'h0001_0000)
                                ? mem_addr[15:2]
                                : dmem_word_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_rdata  <= '0;
            mem_ready  <= 1'b0;
        end else begin
            mem_ready <= 1'b0;
            if (mem_write) begin
                case (mem_size)
                    3'b010: dmem[dmem_addr_mux] <= mem_wdata;
                    3'b001: begin
                        if (mem_addr[1])
                            dmem[dmem_addr_mux][31:16] <= mem_wdata[15:0];
                        else
                            dmem[dmem_addr_mux][15:0]  <= mem_wdata[15:0];
                    end
                    3'b000: begin
                        case (mem_addr[1:0])
                            2'b00: dmem[dmem_addr_mux][ 7: 0] <= mem_wdata[7:0];
                            2'b01: dmem[dmem_addr_mux][15: 8] <= mem_wdata[7:0];
                            2'b10: dmem[dmem_addr_mux][23:16] <= mem_wdata[7:0];
                            2'b11: dmem[dmem_addr_mux][31:24] <= mem_wdata[7:0];
                        endcase
                    end
                    default: dmem[dmem_addr_mux] <= mem_wdata;
                endcase
                mem_ready <= 1'b1;
            end else if (mem_read) begin
                mem_rdata <= dmem[dmem_addr_mux];
                mem_ready <= 1'b1;
            end
        end
    end

    assign mem_error = 1'b0;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    rv32im_core u_dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .imem_addr          (imem_addr),
        .imem_rdata         (imem_rdata),
        .imem_en            (imem_en),
        .mem_addr           (mem_addr),
        .mem_wdata          (mem_wdata),
        .mem_read           (mem_read),
        .mem_write          (mem_write),
        .mem_size           (mem_size),
        .mem_rdata          (mem_rdata),
        .mem_ready          (mem_ready),
        .mem_error          (mem_error),
        .external_irq       (external_irq),
        .timer_irq          (timer_irq),
        .software_irq       (software_irq),
        .ctx_switch_req     (ctx_switch_req),
        .ctx_switch_ack     (ctx_switch_ack),
        .ctx_save_en        (ctx_save_en),
        .ctx_save_reg_idx   (ctx_save_reg_idx),
        .ctx_save_reg_data  (ctx_save_reg_data),
        .ctx_save_pc        (ctx_save_pc),
        .ctx_restore_en     (ctx_restore_en),
        .ctx_restore_reg_idx(ctx_restore_reg_idx),
        .ctx_restore_reg_data(ctx_restore_reg_data),
        .ctx_restore_pc     (ctx_restore_pc),
        .current_task_id    (current_task_id_in),
        .task_active        (task_active_in),
        .ecall_req          (ecall_req),
        .syscall_num        (syscall_num),
        .syscall_arg0       (syscall_arg0),
        .syscall_arg1       (syscall_arg1),
        .syscall_arg2       (syscall_arg2),
        .syscall_ret        (syscall_ret),
        .syscall_done       (syscall_done),
        .debug_halt_req     (debug_halt_req),
        .debug_halted       (debug_halted),
        .debug_pc           (debug_pc),
        .debug_instr        (debug_instr),
        .debug_reg_addr     (debug_reg_addr),
        .debug_reg_data     (debug_reg_data)
    );

    // =========================================================================
    // Tie-Off Signals
    // =========================================================================
    assign external_irq        = 1'b0;
    assign timer_irq           = 1'b0;
    assign software_irq        = 1'b0;
    assign ctx_switch_req      = 1'b0;
    assign ctx_restore_en      = 1'b0;
    assign ctx_restore_reg_idx = '0;
    assign ctx_restore_reg_data= '0;
    assign ctx_restore_pc      = '0;
    assign current_task_id_in  = '0;
    assign task_active_in      = 1'b0;
    initial debug_halt_req = 1'b0;
    initial debug_reg_addr = 5'd0;

    // =========================================================================
    // Auto Syscall Responder
    // =========================================================================
    // Responds to ecall_req after 5 cycles with a success return value.
    // Simulates posix_hw_layer behavior without the full SoC.
    // =========================================================================
    logic [7:0]  pending_syscall;
    int          syscall_delay;

    initial begin
        syscall_ret  = '0;
        syscall_done = 1'b0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            syscall_done  <= 1'b0;
            syscall_ret   <= '0;
            syscall_delay <= 0;
            pending_syscall <= '0;
        end else begin
            syscall_done <= 1'b0;  // Default: deassert

            if (ecall_req && !syscall_done && syscall_delay == 0) begin
                // New syscall request
                pending_syscall <= syscall_num;
                syscall_delay   <= 3;  // Respond after 3 cycles
                $display("[SYSCALL] t=%0t: ecall_req=1, num=%0d, a0=0x%08h, a1=0x%08h, a2=0x%08h",
                         $time, syscall_num, syscall_arg0, syscall_arg1, syscall_arg2);
            end else if (syscall_delay > 1) begin
                syscall_delay <= syscall_delay - 1;
            end else if (syscall_delay == 1) begin
                // Respond
                syscall_done <= 1'b1;
                syscall_delay <= 0;
                case (pending_syscall)
                    8'd80: begin  // SYS_OPEN
                        syscall_ret <= 32'd3;  // Return fd=3
                        $display("[SYSCALL] t=%0t: SYS_OPEN -> fd=3", $time);
                    end
                    8'd84: begin  // SYS_IOCTL
                        syscall_ret <= 32'd0;  // Return success
                        $display("[SYSCALL] t=%0t: SYS_IOCTL -> 0", $time);
                    end
                    8'd66: begin  // SYS_NANOSLEEP
                        syscall_ret <= 32'd0;  // Return success
                        $display("[SYSCALL] t=%0t: SYS_NANOSLEEP -> 0", $time);
                    end
                    default: begin
                        syscall_ret <= 32'd0;
                        $display("[SYSCALL] t=%0t: UNKNOWN(%0d) -> 0", $time, pending_syscall);
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // PC + ra Trace Monitor
    // =========================================================================
    // Track program counter and key register values every cycle
    // Focus on the critical addresses: 0x25c (jal), 0x220-0x228 (open), 0x260 (return)
    // =========================================================================

    // Access internal pipeline registers for monitoring
    wire [31:0] fetch_pc   = u_dut.u_fetch_stage.pc;
    wire [31:0] if_id_pc   = u_dut.if_id_reg.pc;
    wire        if_id_v    = u_dut.if_id_reg.valid;
    wire [31:0] id_ex_pc   = u_dut.id_ex_reg.pc;
    wire        id_ex_v    = u_dut.id_ex_reg.valid;
    wire [31:0] ex_mem_pc  = u_dut.u_execute_stage.ex_mem_reg.pc;
    wire        ex_mem_v   = u_dut.u_execute_stage.ex_mem_reg.valid;
    wire [31:0] mem_wb_pc  = u_dut.u_memory_stage.mem_wb_reg.pc;
    wire        mem_wb_v   = u_dut.u_memory_stage.mem_wb_reg.valid;

    // Register file access (ra = x1)
    wire [31:0] ra_value   = u_dut.u_register_file.regs[1];
    wire [31:0] sp_value   = u_dut.u_register_file.regs[2];
    wire [31:0] a7_value   = u_dut.u_register_file.regs[17];

    // Syscall state
    wire [2:0]  sys_state_val = u_dut.sys_state;
    wire        syscall_active_val = u_dut.syscall_active;
    wire        ecall_det_val = u_dut.ecall_detected;

    // Pipeline control
    wire        stall_if_val = u_dut.stall_if;
    wire        flush_if_val = u_dut.flush_if;
    wire        branch_taken_val = u_dut.pipe_branch_taken;
    wire [31:0] branch_target_val = u_dut.pipe_branch_target;

    // Forwarding
    wire [1:0]  fwd_a_val = u_dut.u_hazard_unit.fwd_a;
    wire [1:0]  fwd_b_val = u_dut.u_hazard_unit.fwd_b;

    // Register file write port
    wire        rf_we_val  = u_dut.rf_reg_write;
    wire [4:0]  rf_wa_val  = u_dut.rf_rd_addr;
    wire [31:0] rf_wd_val  = u_dut.rf_rd_data;

    // WB stage outputs
    wire        wb_rw_val  = u_dut.u_writeback_stage.reg_write;
    wire [4:0]  wb_rd_val  = u_dut.u_writeback_stage.rd_addr;
    wire [31:0] wb_data_val = u_dut.u_writeback_stage.rd_data;

    // Suppress valid
    wire        suppress_val = u_dut.u_fetch_stage.suppress_valid;

    // Branch unit
    wire        ex_branch_taken = u_dut.ex_branch_taken;
    wire [31:0] ex_branch_target = u_dut.ex_branch_target;

    // Exception signals
    wire        exc_redirect = u_dut.exc_redirect_valid;
    wire [31:0] exc_redirect_pc_val = u_dut.exc_redirect_pc;

    int cycle_count;

    // Detailed trace: print every cycle from key address range
    always_ff @(posedge clk) begin
        if (rst_n) begin
            cycle_count <= cycle_count + 1;

            // Always print when PC is in the critical range or special events
            if (fetch_pc >= 32'h220 && fetch_pc <= 32'h270 ||
                fetch_pc == 32'h7c ||
                ecall_det_val ||
                syscall_active_val ||
                branch_taken_val ||
                exc_redirect ||
                (rf_we_val && rf_wa_val == 5'd1) ||  // Write to ra
                (id_ex_pc >= 32'h220 && id_ex_pc <= 32'h270 && id_ex_v)) begin

                $display("[CYC %0d] t=%0t PC=%08h IF/ID=%08h(v=%b) ID/EX=%08h(v=%b) EX/MEM=%08h(v=%b) MEM/WB=%08h(v=%b) | ra=%08h sp=%08h a7=%08h | sys=%0d ecall=%b stall=%b flush=%b branch=%b target=%08h suppress=%b | rf_we=%b rf_wa=%0d rf_wd=%08h | fwd_a=%0d fwd_b=%0d | exc=%b exc_pc=%08h",
                    cycle_count, $time,
                    fetch_pc, if_id_pc, if_id_v, id_ex_pc, id_ex_v,
                    ex_mem_pc, ex_mem_v, mem_wb_pc, mem_wb_v,
                    ra_value, sp_value, a7_value,
                    sys_state_val, ecall_det_val,
                    stall_if_val, flush_if_val,
                    branch_taken_val, branch_target_val,
                    suppress_val,
                    rf_we_val, rf_wa_val, rf_wd_val,
                    fwd_a_val, fwd_b_val,
                    exc_redirect, exc_redirect_pc_val);
            end

            // ALERT: Detect the problem - ret jumping to wrong PC
            if (id_ex_v && id_ex_pc == 32'h228) begin
                $display("[ALERT] ret at 0x228 in EX stage! ra=%08h (expected 0x260)", ra_value);
            end

            // Track when jal at 0x25c writes ra
            if (rf_we_val && rf_wa_val == 5'd1) begin
                $display("[RA_WRITE] t=%0t: ra written = 0x%08h (by rf_we=%b, MEM/WB_pc=%08h)",
                         $time, rf_wd_val, rf_we_val, mem_wb_pc);
            end

            // Track branch from ret
            if (ex_branch_taken && id_ex_pc == 32'h228) begin
                $display("[RET_BRANCH] t=%0t: ret at 0x228 branching to 0x%08h, ra=%08h",
                         $time, ex_branch_target, ra_value);
            end

            // Track when we reach 0x7c (wrong target)
            if (fetch_pc == 32'h7c && cycle_count > 100) begin
                $display("[WRONG_PC] t=%0t: PC is at 0x7c! ra=%08h sp=%08h",
                         $time, ra_value, sp_value);
            end

            // Track exception redirect
            if (exc_redirect) begin
                $display("[EXCEPTION] t=%0t: Exception redirect to 0x%08h",
                         $time, exc_redirect_pc_val);
            end
        end
    end

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        cycle_count = 0;

        $display("==============================================");
        $display("  GPIO Blink ecall+ret Debug Testbench");
        $display("==============================================");

        // Initialize data memory
        for (int i = 0; i < DMEM_DEPTH; i++) begin
            dmem[i] = '0;
        end

        // Apply reset
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        $display("[TB] Reset released at %0t", $time);

        // Wait for the simulation to reach the first ecall (open at 0x224)
        // and the subsequent ret at 0x228
        // Or timeout
        fork
            begin
                // Wait for ret to execute or for 0x260 / 0x7c to appear
                wait(fetch_pc == 32'h260 || fetch_pc == 32'h7c || cycle_count > 50000);
                #(CLK_PERIOD * 50);  // Run 50 more cycles for context
            end
            begin
                #(TIMEOUT * CLK_PERIOD);
                $display("[TB] Timeout after %0d cycles", TIMEOUT);
            end
        join_any
        disable fork;

        $display("\n==============================================");
        $display("  FINAL STATE");
        $display("==============================================");
        $display("  PC    = 0x%08h", fetch_pc);
        $display("  ra    = 0x%08h", ra_value);
        $display("  sp    = 0x%08h", sp_value);
        $display("  a7    = 0x%08h", a7_value);
        $display("  sys_state = %0d", sys_state_val);
        $display("  cycles = %0d", cycle_count);
        $display("==============================================\n");

        if (fetch_pc == 32'h260) begin
            $display("[PASS] ret correctly returned to 0x260");
        end else if (fetch_pc == 32'h7c) begin
            $display("[FAIL] ret incorrectly returned to 0x7c (ra was not updated by JAL)");
        end else begin
            $display("[INFO] PC at 0x%08h", fetch_pc);
        end

        $finish;
    end

    // =========================================================================
    // Timeout Watchdog
    // =========================================================================
    initial begin
        #(TIMEOUT * CLK_PERIOD);
        $display("\n[ERROR] Simulation timeout after %0d cycles!", TIMEOUT);
        $finish;
    end

endmodule : tb_gpio_blink_ecall
