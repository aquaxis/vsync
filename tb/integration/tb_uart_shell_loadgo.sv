// =============================================================================
// VSync - UART Shell Load/Go Integration Testbench
// =============================================================================
// Integration test that verifies the hardware path of the UART shell
// load/go concept: CPU fetches instructions from IMEM, executes them, and
// produces UART serial output.
//
// Architecture (bypasses vsync_top due to iverilog unpacked array limitation):
//   rv32im_core (CPU) → bram_imem (instruction fetch, Port A)
//                      → Memory Map FSM → uart_apb (serial TX output)
//                                       → Simple DMEM array (data memory)
//
// Test Strategy (Alternative C - Staged Approach):
//   Phase 1: Testbench loads test program to IMEM via backdoor during reset
//            CPU boots from PC=0x0 and executes program
//            Program writes 'O', 'K', '\n' to UART TX register (0x10000000)
//            Testbench captures UART TX serial output and verifies each byte
//
// No shell.c dependency (avoids POSIX ecall requirements).
// No vsync_top dependency (avoids iverilog unpacked array compilation errors).
//
// Simulation:
//   iverilog -g2012 -DIVERILOG -I rtl/core -I tb/common -o sim.vvp \
//       <rtl_files> tb/integration/tb_uart_shell_loadgo.sv
//   vvp sim.vvp
// =============================================================================

`timescale 1ns / 1ps

`include "test_utils.sv"

module tb_uart_shell_loadgo;

    import vsync_pkg::*;
    import test_utils::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int  CLK_FREQ       = 10_000_000;   // 10 MHz for faster sim
    localparam int  BAUD_RATE      = 115200;
    localparam real CLK_PERIOD_NS  = 100.0;        // 10 MHz => 100 ns period
    localparam int  RST_CYCLES     = 10;

    // UART timing (fractional baud rate divider)
    localparam int  BAUD_DIV       = (CLK_FREQ + BAUD_RATE / 2) / BAUD_RATE;  // = 87
    localparam int  CLKS_PER_BIT   = BAUD_DIV;                                // = 87
    localparam int  CLKS_PER_FRAME = CLKS_PER_BIT * 10;            // = 800

    // Memory sizes
    localparam int  IMEM_DEPTH     = 16384;  // 64KB / 4 = 16K words
    localparam int  DMEM_DEPTH     = 4096;   // 16KB / 4 = 4K words

    // Number of test program words
    localparam int  NUM_PROG_WORDS = 8;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // CPU <-> IMEM Interface
    logic [IMEM_ADDR_W-1:0]  imem_addr;
    logic [XLEN-1:0]         imem_rdata;
    logic                    imem_en;

    // CPU Data Memory Interface
    logic [XLEN-1:0]         mem_addr;
    logic [XLEN-1:0]         mem_wdata;
    logic                    mem_read;
    logic                    mem_write;
    logic [2:0]              mem_size;
    logic [XLEN-1:0]         mem_rdata;
    logic                    mem_ready;
    logic                    mem_error;

    // CPU Interrupt Inputs (all tied off)
    logic                    external_irq;
    logic                    timer_irq;
    logic                    software_irq;

    // RTOS Control (all tied off)
    logic                    ctx_switch_req;
    logic                    ctx_switch_ack;
    logic                    ctx_save_en;
    logic [REG_ADDR_W-1:0]  ctx_save_reg_idx;
    logic [XLEN-1:0]        ctx_save_reg_data;
    logic [XLEN-1:0]        ctx_save_pc;
    logic                    ctx_restore_en;
    logic [REG_ADDR_W-1:0]  ctx_restore_reg_idx;
    logic [XLEN-1:0]        ctx_restore_reg_data;
    logic [XLEN-1:0]        ctx_restore_pc;
    logic [TASK_ID_W-1:0]   current_task_id_in;
    logic                    task_active_in;

    // POSIX Syscall (all tied off)
    logic                    ecall_req;
    logic [7:0]              syscall_num;
    logic [XLEN-1:0]        syscall_arg0;
    logic [XLEN-1:0]        syscall_arg1;
    logic [XLEN-1:0]        syscall_arg2;
    logic [XLEN-1:0]        syscall_ret;
    logic                    syscall_done;

    // Debug (all tied off)
    logic                    debug_halt_req;
    logic                    debug_halted;
    logic [XLEN-1:0]        debug_pc;
    logic [XLEN-1:0]        debug_instr;
    logic [REG_ADDR_W-1:0]  debug_reg_addr;
    logic [XLEN-1:0]        debug_reg_data;

    // UART APB Interface
    logic        apb_psel;
    logic        apb_penable;
    logic        apb_pwrite;
    logic [7:0]  apb_paddr;
    logic [31:0] apb_pwdata;
    logic [31:0] apb_prdata;
    logic        apb_pready;
    logic        apb_pslverr;
    logic        uart_tx;
    logic        uart_irq;

    // Simple DMEM (testbench-local memory for non-UART data accesses)
    logic [31:0] dmem [0:DMEM_DEPTH-1];

    // Memory Map FSM states
    localparam [1:0] MEM_IDLE       = 2'b00;
    localparam [1:0] MEM_APB_SETUP  = 2'b01;
    localparam [1:0] MEM_APB_ACCESS = 2'b10;
    logic [1:0] mem_state;

    // =========================================================================
    // Clock and Reset Generator
    // =========================================================================
    clk_rst_gen #(
        .CLK_PERIOD_NS (CLK_PERIOD_NS),
        .RST_CYCLES    (RST_CYCLES)
    ) u_clk_rst (
        .clk       (clk),
        .rst       (rst),
        .rst_n     (rst_n),
        .init_done (init_done)
    );

    // =========================================================================
    // Instruction Memory (bram_imem, Port A only - read for CPU fetch)
    // =========================================================================
    // CRITICAL: CPU outputs BYTE addresses (PC=0x00,0x04,0x08,...) but
    // bram_imem uses WORD addresses (mem[0],mem[1],mem[2],...).
    // Must convert: word_addr = byte_addr >> 2 = imem_addr[IMEM_ADDR_W-1:2]
    localparam int IMEM_WORD_ADDR_W = IMEM_ADDR_W - 2;  // 14 bits for word addr

    bram_imem #(
        .DEPTH      (IMEM_DEPTH),
        .ADDR_WIDTH (IMEM_WORD_ADDR_W),   // Word address width (14 bits)
        .DATA_WIDTH (32),
        .INIT_FILE  ("")
    ) u_imem (
        .clk     (clk),
        // Port A - CPU Instruction Fetch (read-only)
        .a_en    (imem_en),
        .a_addr  (imem_addr[IMEM_ADDR_W-1:2]),  // Byte→word address conversion
        .a_rdata (imem_rdata),
        // Port B - Unused (tied off)
        .b_en    (1'b0),
        .b_we    (1'b0),
        .b_be    (4'b0000),
        .b_addr  ({IMEM_WORD_ADDR_W{1'b0}}),
        .b_wdata (32'h0),
        .b_rdata ()
    );

    // =========================================================================
    // UART Peripheral (APB interface, serial TX output)
    // =========================================================================
    uart_apb #(
        .CLK_FREQ     (CLK_FREQ),
        .DEFAULT_BAUD (BAUD_RATE),
        .FIFO_DEPTH   (16)
    ) u_uart (
        .clk          (clk),
        .rst_n        (rst_n),
        .apb_psel     (apb_psel),
        .apb_penable  (apb_penable),
        .apb_pwrite   (apb_pwrite),
        .apb_paddr    (apb_paddr),
        .apb_pwdata   (apb_pwdata),
        .apb_prdata   (apb_prdata),
        .apb_pready   (apb_pready),
        .apb_pslverr  (apb_pslverr),
        .uart_rx      (1'b1),      // UART RX idle high (no input)
        .uart_tx      (uart_tx),
        .irq          (uart_irq)
    );

    // =========================================================================
    // CPU Core (rv32im_core)
    // =========================================================================
    rv32im_core u_cpu (
        .clk                (clk),
        .rst_n              (rst_n),
        // Instruction Memory
        .imem_addr          (imem_addr),
        .imem_rdata         (imem_rdata),
        .imem_en            (imem_en),
        // Data Memory (routed through Memory Map FSM)
        .mem_addr           (mem_addr),
        .mem_wdata          (mem_wdata),
        .mem_read           (mem_read),
        .mem_write          (mem_write),
        .mem_size           (mem_size),
        .mem_rdata          (mem_rdata),
        .mem_ready          (mem_ready),
        .mem_error          (mem_error),
        // Interrupts (all tied off)
        .external_irq       (external_irq),
        .timer_irq          (timer_irq),
        .software_irq       (software_irq),
        // RTOS Control (all tied off)
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
        // POSIX Syscall (all tied off)
        .ecall_req          (ecall_req),
        .syscall_num        (syscall_num),
        .syscall_arg0       (syscall_arg0),
        .syscall_arg1       (syscall_arg1),
        .syscall_arg2       (syscall_arg2),
        .syscall_ret        (syscall_ret),
        .syscall_done       (syscall_done),
        // Debug (all tied off)
        .debug_halt_req     (debug_halt_req),
        .debug_halted       (debug_halted),
        .debug_pc           (debug_pc),
        .debug_instr        (debug_instr),
        .debug_reg_addr     (debug_reg_addr),
        .debug_reg_data     (debug_reg_data)
    );

    // =========================================================================
    // Tie-Off: Interrupts, RTOS, POSIX, Debug
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
    assign syscall_ret         = '0;
    assign syscall_done        = 1'b0;
    assign debug_halt_req      = 1'b0;
    initial debug_reg_addr     = 5'd0;

    assign mem_error           = 1'b0;

    // =========================================================================
    // Memory Map FSM
    // =========================================================================
    // Routes CPU data memory accesses based on address:
    //   0x10000000 - 0x100000FF  → UART APB (2-cycle APB protocol)
    //   All other addresses      → Simple DMEM array (1-cycle response)
    //
    // UART address detection
    wire mem_is_uart = (mem_addr[31:8] == 24'h100000);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_state   <= MEM_IDLE;
            mem_ready   <= 1'b0;
            mem_rdata   <= 32'h0;
            apb_psel    <= 1'b0;
            apb_penable <= 1'b0;
            apb_pwrite  <= 1'b0;
            apb_paddr   <= 8'h0;
            apb_pwdata  <= 32'h0;
        end else begin
            mem_ready <= 1'b0;  // Default: deassert ready

            case (mem_state)
                MEM_IDLE: begin
                    apb_psel    <= 1'b0;
                    apb_penable <= 1'b0;

                    // Guard: !mem_ready prevents re-triggering on the stale
                    // mem_write signal. When mem_ready=1 (just completed),
                    // the pipeline un-stalls but the EX/MEM register hasn't
                    // advanced yet, so mem_write is still asserted from the
                    // old instruction. Skip this cycle; on the next cycle
                    // mem_ready=0 (default) and the pipeline has advanced.
                    if (!mem_ready) begin
                        if ((mem_write || mem_read) && mem_is_uart) begin
                            // UART range: start 2-cycle APB transaction
                            apb_psel    <= 1'b1;
                            apb_penable <= 1'b0;
                            apb_pwrite  <= mem_write;
                            apb_paddr   <= mem_addr[7:0];
                            apb_pwdata  <= mem_wdata;
                            mem_state   <= MEM_APB_SETUP;
                        end else if (mem_write) begin
                            // Non-UART write: store to DMEM (1-cycle response)
                            dmem[mem_addr[15:2]] <= mem_wdata;
                            mem_ready <= 1'b1;
                        end else if (mem_read) begin
                            // Non-UART read: load from DMEM (1-cycle response)
                            mem_rdata <= dmem[mem_addr[15:2]];
                            mem_ready <= 1'b1;
                        end
                    end
                end

                MEM_APB_SETUP: begin
                    // APB access phase (penable asserted)
                    apb_penable <= 1'b1;
                    mem_state   <= MEM_APB_ACCESS;
                end

                MEM_APB_ACCESS: begin
                    if (apb_pready) begin
                        // APB transaction complete
                        if (!apb_pwrite)
                            mem_rdata <= apb_prdata;
                        apb_psel    <= 1'b0;
                        apb_penable <= 1'b0;
                        mem_ready   <= 1'b1;
                        mem_state   <= MEM_IDLE;
                    end
                end

                default: begin
                    mem_state <= MEM_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Backdoor IMEM Load (during reset period)
    // =========================================================================
    // Test Program: RV32I machine code that outputs "OK\n" via UART TX
    //
    //   0x00: lui  x1, 0x10000     ; x1 = 0x10000000 (UART_BASE)
    //   0x04: addi x2, x0, 0x4F   ; x2 = 'O' (79)
    //   0x08: sw   x2, 0(x1)      ; UART_TX_DATA <- 'O'
    //   0x0C: addi x2, x0, 0x4B   ; x2 = 'K' (75)
    //   0x10: sw   x2, 0(x1)      ; UART_TX_DATA <- 'K'
    //   0x14: addi x2, x0, 0x0A   ; x2 = '\n' (10)
    //   0x18: sw   x2, 0(x1)      ; UART_TX_DATA <- '\n'
    //   0x1C: jal  x0, 0          ; infinite loop (jump to self)

    initial begin
        #1;  // Small delay to ensure BRAM memory exists
        u_imem.mem[0] = 32'h100000B7;  // lui  x1, 0x10000
        u_imem.mem[1] = 32'h04F00113;  // addi x2, x0, 0x4F  ('O')
        u_imem.mem[2] = 32'h0020A023;  // sw   x2, 0(x1)
        u_imem.mem[3] = 32'h04B00113;  // addi x2, x0, 0x4B  ('K')
        u_imem.mem[4] = 32'h0020A023;  // sw   x2, 0(x1)
        u_imem.mem[5] = 32'h00A00113;  // addi x2, x0, 0x0A  ('\n')
        u_imem.mem[6] = 32'h0020A023;  // sw   x2, 0(x1)
        u_imem.mem[7] = 32'h0000006F;  // jal  x0, 0  (infinite loop)
        $display("[TB] Test program loaded to IMEM via backdoor (%0d words)", NUM_PROG_WORDS);
    end

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_uart_shell_loadgo.vcd");
        $dumpvars(0, tb_uart_shell_loadgo);
    end

    // =========================================================================
    // Debug Monitor: APB transaction completions (minimal output)
    // =========================================================================
    always @(posedge clk) begin
        if (apb_psel && apb_penable && apb_pready && apb_pwrite)
            $display("[TB] APB write complete: addr=%02h data=%08h", apb_paddr, apb_pwdata);
    end

    // =========================================================================
    // Timeout Watchdog (5 million cycles = 500ms sim time @ 10MHz)
    // =========================================================================
    initial begin
        #(CLK_PERIOD_NS * 5_000_000);
        $display("[TB] ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded 5M cycles");
    end

    // =========================================================================
    // UART TX Capture Task
    // =========================================================================
    // Monitors the uart_tx serial line and captures one 8N1 frame.
    // Waits for start bit falling edge, samples each bit at mid-bit,
    // returns the captured byte. Based on tb_uart.sv pattern.

    task automatic uart_capture_byte(output logic [7:0] data);
        integer i;

        // Wait for start bit (falling edge on uart_tx)
        @(negedge uart_tx);

        // Advance to the middle of the start bit
        repeat (CLKS_PER_BIT / 2) @(posedge clk);

        // Verify start bit is still low
        if (uart_tx !== 1'b0)
            $display("WARNING: Start bit not stable at mid-point");

        // Sample each data bit at the middle of the bit period (LSB first)
        for (i = 0; i < 8; i++) begin
            repeat (CLKS_PER_BIT) @(posedge clk);
            data[i] = uart_tx;
        end

        // Advance to middle of stop bit and verify
        repeat (CLKS_PER_BIT) @(posedge clk);
        if (uart_tx !== 1'b1)
            $display("WARNING: Stop bit not high");

        // Wait for remainder of stop bit
        repeat (CLKS_PER_BIT / 2) @(posedge clk);
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        @(posedge init_done);
        repeat (10) @(posedge clk);  // Stabilization wait

        test_main();

        test_finish();
    end

    task automatic test_main();
        logic [7:0] rx_byte;

        test_suite_begin("UART Shell Load/Go Integration Test");

        // -----------------------------------------------------------------
        // Test: IMEM Backdoor Load + CPU Execute + UART Serial Output
        // -----------------------------------------------------------------
        // The test program has been loaded into IMEM via backdoor.
        // After reset, CPU fetches from PC=0x0 and executes:
        //   lui  x1, 0x10000     -> x1 = 0x10000000 (UART_BASE)
        //   addi x2, x0, 'O'    -> x2 = 0x4F
        //   sw   x2, 0(x1)      -> write to 0x10000000 (UART TX_DATA)
        //   addi x2, x0, 'K'    -> x2 = 0x4B
        //   sw   x2, 0(x1)      -> write to 0x10000000 (UART TX_DATA)
        //   addi x2, x0, '\n'   -> x2 = 0x0A
        //   sw   x2, 0(x1)      -> write to 0x10000000 (UART TX_DATA)
        //   jal  x0, 0          -> infinite loop
        //
        // Memory Map FSM routes writes to 0x10000000 → uart_apb via APB.
        // UART serializes each byte on uart_tx at 115200 baud.
        // Testbench captures serial output and verifies.

        test_begin("IMEM Load and CPU Execute - UART Output OK+newline");

        $display("[TB] CPU executing from IMEM...");
        $display("[TB] Waiting for UART TX output...");
        $display("[TB] Expected: 'O' (0x4F), 'K' (0x4B), '\\n' (0x0A)");

        // Capture byte 0: 'O' (0x4F)
        uart_capture_byte(rx_byte);
        $display("[TB] Captured byte 0: 0x%02h (expected 0x4F 'O')", rx_byte);
        check_eq({24'h0, rx_byte}, 32'h0000_004F, "UART byte 0 = 'O'");

        // Capture byte 1: 'K' (0x4B)
        uart_capture_byte(rx_byte);
        $display("[TB] Captured byte 1: 0x%02h (expected 0x4B 'K')", rx_byte);
        check_eq({24'h0, rx_byte}, 32'h0000_004B, "UART byte 1 = 'K'");

        // Capture byte 2: '\n' (0x0A)
        uart_capture_byte(rx_byte);
        $display("[TB] Captured byte 2: 0x%02h (expected 0x0A '\\n')", rx_byte);
        check_eq({24'h0, rx_byte}, 32'h0000_000A, "UART byte 2 = newline");

        // Only report pass if all checks above succeeded (test_utils tracks failures)
        $display("[TB] All 3 UART bytes captured and checked");

        test_suite_end();
    endtask

endmodule : tb_uart_shell_loadgo
