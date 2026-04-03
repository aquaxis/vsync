// =============================================================================
// VSync - Exception Handling Test Bench
// =============================================================================
// Test IDs: EXC-001 ~ EXC-008
// - EXC-001: Illegal instruction exception
// - EXC-002: Instruction misaligned fetch
// - EXC-003: Load misalignment
// - EXC-004: Store misalignment
// - EXC-005: ECALL (environment call)
// - EXC-006: EBREAK (breakpoint)
// - EXC-007: Nested exception (exception during exception)
// - EXC-008: MRET (exception return)
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_exception;

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

    // DUT inputs
    logic              illegal_instr;
    logic              ecall;
    logic              ebreak;
    logic              mret_in;
    logic              load_misalign;
    logic              store_misalign;
    logic              instr_misalign;
    logic [XLEN-1:0]  pc;
    logic              mstatus_mie;
    logic [XLEN-1:0]  mie;
    logic [XLEN-1:0]  mip;
    logic [XLEN-1:0]  mtvec;
    logic [XLEN-1:0]  mepc;

    // DUT outputs
    logic              exception_taken;
    logic [XLEN-1:0]  exception_cause;
    logic [XLEN-1:0]  exception_pc;
    logic [XLEN-1:0]  exception_val;
    logic              mret_taken;
    logic [XLEN-1:0]  redirect_pc;
    logic              redirect_valid;
    logic              flush_all;

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
    exception_unit u_exc (
        .clk              (clk),
        .rst_n            (rst_n),
        .illegal_instr    (illegal_instr),
        .ecall            (ecall),
        .ebreak           (ebreak),
        .mret             (mret_in),
        .load_misalign    (load_misalign),
        .store_misalign   (store_misalign),
        .instr_misalign   (instr_misalign),
        .pc               (pc),
        .mstatus_mie      (mstatus_mie),
        .mie              (mie),
        .mip              (mip),
        .mtvec            (mtvec),
        .mepc             (mepc),
        .exception_taken  (exception_taken),
        .exception_cause  (exception_cause),
        .exception_pc     (exception_pc),
        .exception_val    (exception_val),
        .mret_taken       (mret_taken),
        .redirect_pc      (redirect_pc),
        .redirect_valid   (redirect_valid),
        .flush_all        (flush_all)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_exception.vcd");
        $dumpvars(0, tb_exception);
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 200000);
        $display("ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded maximum time");
    end

    // =========================================================================
    // Helper tasks
    // =========================================================================

    /** Reset all input signals to inactive state */
    task automatic reset_inputs();
        illegal_instr  = 1'b0;
        ecall          = 1'b0;
        ebreak         = 1'b0;
        mret_in        = 1'b0;
        load_misalign  = 1'b0;
        store_misalign = 1'b0;
        instr_misalign = 1'b0;
        pc             = 32'h0000_1000;
        mstatus_mie    = 1'b0;
        mie            = 32'h0;
        mip            = 32'h0;
        mtvec          = 32'h0000_0100;  // Direct mode, base=0x100
        mepc           = 32'h0000_2000;
    endtask

    /** Clear all exception source signals */
    task automatic clear_exceptions();
        illegal_instr  = 1'b0;
        ecall          = 1'b0;
        ebreak         = 1'b0;
        mret_in        = 1'b0;
        load_misalign  = 1'b0;
        store_misalign = 1'b0;
        instr_misalign = 1'b0;
        mstatus_mie    = 1'b0;
        mie            = 32'h0;
        mip            = 32'h0;
        #1;
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        reset_inputs();
        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("Exception Handling Tests");

        // === EXC-001: Illegal Instruction ===
        test_illegal_instruction();

        // === EXC-002: Instruction Misaligned Fetch ===
        test_misaligned_fetch();

        // === EXC-003: Load Misalignment ===
        test_load_misalign();

        // === EXC-004: Store Misalignment ===
        test_store_misalign();

        // === EXC-005: ECALL ===
        test_ecall();

        // === EXC-006: EBREAK ===
        test_ebreak();

        // === EXC-007: Nested Exception ===
        test_nested_exception();

        // === EXC-008: MRET ===
        test_mret();

        // === Additional Exception Tests ===
        test_exception_csr_state();
        test_trap_vector_modes();

    endtask

    // =========================================================================
    // EXC-001: Illegal Instruction
    // =========================================================================

    task automatic test_illegal_instruction();
        test_begin("EXC-001: Illegal Instruction Exception");

        clear_exceptions();
        pc    = 32'h0000_1000;
        mtvec = 32'h0000_0100;  // Direct mode

        // Assert illegal_instr
        illegal_instr = 1'b1;
        #1;

        check(exception_taken === 1'b1, "exception_taken asserted");
        check_eq(exception_cause, CAUSE_ILLEGAL_INSTR, "cause = CAUSE_ILLEGAL_INSTR");
        check_eq(exception_pc, 32'h0000_1000, "exception_pc = current PC");
        check_eq(redirect_pc, 32'h0000_0100, "redirect_pc = mtvec base (direct mode)");
        check(redirect_valid === 1'b1, "redirect_valid asserted");
        check(flush_all === 1'b1, "flush_all asserted");

        illegal_instr = 1'b0;
        #1;
    endtask

    // =========================================================================
    // EXC-002: Instruction Misaligned Fetch
    // =========================================================================

    task automatic test_misaligned_fetch();
        test_begin("EXC-002: Instruction Misaligned Fetch");

        clear_exceptions();
        pc    = 32'h0000_2003;  // Misaligned PC
        mtvec = 32'h0000_0100;

        instr_misalign = 1'b1;
        #1;

        check(exception_taken === 1'b1, "exception_taken asserted");
        check_eq(exception_cause, CAUSE_INSTR_MISALIGN, "cause = CAUSE_INSTR_MISALIGN");
        check_eq(exception_val, 32'h0000_2003, "exception_val = misaligned PC");
        check_eq(redirect_pc, 32'h0000_0100, "redirect_pc = mtvec base");
        check(flush_all === 1'b1, "flush_all asserted");

        instr_misalign = 1'b0;
        #1;
    endtask

    // =========================================================================
    // EXC-003: Load Misalignment
    // =========================================================================

    task automatic test_load_misalign();
        test_begin("EXC-003: Load Misalignment");

        clear_exceptions();
        pc    = 32'h0000_1004;
        mtvec = 32'h0000_0100;

        load_misalign = 1'b1;
        #1;

        check(exception_taken === 1'b1, "exception_taken asserted");
        check_eq(exception_cause, CAUSE_LOAD_MISALIGN, "cause = CAUSE_LOAD_MISALIGN");
        check_eq(redirect_pc, 32'h0000_0100, "redirect_pc = mtvec base");
        check(flush_all === 1'b1, "flush_all asserted");

        load_misalign = 1'b0;
        #1;
    endtask

    // =========================================================================
    // EXC-004: Store Misalignment
    // =========================================================================

    task automatic test_store_misalign();
        test_begin("EXC-004: Store Misalignment");

        clear_exceptions();
        pc    = 32'h0000_1008;
        mtvec = 32'h0000_0100;

        store_misalign = 1'b1;
        #1;

        check(exception_taken === 1'b1, "exception_taken asserted");
        check_eq(exception_cause, CAUSE_STORE_MISALIGN, "cause = CAUSE_STORE_MISALIGN");
        check_eq(redirect_pc, 32'h0000_0100, "redirect_pc = mtvec base");
        check(flush_all === 1'b1, "flush_all asserted");

        store_misalign = 1'b0;
        #1;
    endtask

    // =========================================================================
    // EXC-005: ECALL
    // =========================================================================

    task automatic test_ecall();
        test_begin("EXC-005: ECALL (Environment Call)");

        clear_exceptions();
        pc    = 32'h0000_100C;
        mtvec = 32'h0000_0100;

        ecall = 1'b1;
        #1;

        check(exception_taken === 1'b1, "exception_taken asserted");
        check_eq(exception_cause, CAUSE_ECALL_M, "cause = CAUSE_ECALL_M (11)");
        check_eq(exception_pc, 32'h0000_100C, "exception_pc = ECALL instruction address");
        check_eq(redirect_pc, 32'h0000_0100, "redirect_pc = mtvec base");
        check(redirect_valid === 1'b1, "redirect_valid asserted");
        check(flush_all === 1'b1, "flush_all asserted");

        ecall = 1'b0;
        #1;
    endtask

    // =========================================================================
    // EXC-006: EBREAK
    // =========================================================================

    task automatic test_ebreak();
        test_begin("EXC-006: EBREAK (Breakpoint)");

        clear_exceptions();
        pc    = 32'h0000_1010;
        mtvec = 32'h0000_0100;

        ebreak = 1'b1;
        #1;

        check(exception_taken === 1'b1, "exception_taken asserted");
        check_eq(exception_cause, CAUSE_BREAKPOINT, "cause = CAUSE_BREAKPOINT (3)");
        check_eq(exception_val, 32'h0000_1010, "exception_val = EBREAK PC");
        check_eq(exception_pc, 32'h0000_1010, "exception_pc = EBREAK instruction address");
        check_eq(redirect_pc, 32'h0000_0100, "redirect_pc = mtvec base");
        check(flush_all === 1'b1, "flush_all asserted");

        ebreak = 1'b0;
        #1;
    endtask

    // =========================================================================
    // EXC-007: Nested Exception (Priority test)
    // =========================================================================

    task automatic test_nested_exception();
        test_begin("EXC-007: Nested Exception");

        // The exception_unit is combinational. When both an interrupt and
        // exception are asserted simultaneously, interrupt takes priority.
        clear_exceptions();
        pc    = 32'h0000_1014;
        mtvec = 32'h0000_0100;

        // Enable interrupts and assert ext_irq + illegal_instr simultaneously
        mstatus_mie = 1'b1;
        mie         = 32'h00000800;  // MEIE (bit 11) enabled
        mip         = 32'h00000800;  // MEIP (bit 11) pending
        illegal_instr = 1'b1;
        #1;

        // Interrupt should take priority over exception
        check(exception_taken === 1'b1, "exception_taken asserted");
        check_eq(exception_cause, CAUSE_M_EXT_INT, "cause = ext interrupt (priority over exception)");
        check(flush_all === 1'b1, "flush_all asserted");

        // Now clear interrupt, exception should be visible
        mstatus_mie = 1'b0;
        mip         = 32'h0;
        #1;

        check(exception_taken === 1'b1, "exception still taken (illegal_instr)");
        check_eq(exception_cause, CAUSE_ILLEGAL_INSTR, "cause = illegal instr when no interrupt");

        illegal_instr = 1'b0;
        #1;
    endtask

    // =========================================================================
    // EXC-008: MRET
    // =========================================================================

    task automatic test_mret();
        test_begin("EXC-008: MRET (Exception Return)");

        clear_exceptions();
        mepc  = 32'h0000_2000;
        mtvec = 32'h0000_0100;

        mret_in = 1'b1;
        #1;

        check(mret_taken === 1'b1, "mret_taken asserted");
        check_eq(redirect_pc, 32'h0000_2000, "redirect_pc = mepc (0x2000)");
        check(redirect_valid === 1'b1, "redirect_valid asserted");
        check(flush_all === 1'b1, "flush_all asserted");
        check(exception_taken === 1'b0, "exception_taken NOT asserted for MRET");

        mret_in = 1'b0;
        #1;

        // Test with different mepc
        mepc = 32'h0000_4000;
        mret_in = 1'b1;
        #1;

        check_eq(redirect_pc, 32'h0000_4000, "redirect_pc = new mepc (0x4000)");

        mret_in = 1'b0;
        #1;
    endtask

    // =========================================================================
    // Additional Exception Tests
    // =========================================================================

    task automatic test_exception_csr_state();
        test_begin("Exception CSR State Verification");

        // Verify no exception/redirect when all inputs are deasserted
        clear_exceptions();
        pc    = 32'h0000_1000;
        mtvec = 32'h0000_0100;
        #1;

        check(exception_taken === 1'b0, "No exception when all inputs clear");
        check(redirect_valid === 1'b0, "No redirect when all inputs clear");
        check(flush_all === 1'b0, "No flush when all inputs clear");
        check(mret_taken === 1'b0, "No mret when all inputs clear");

        // Verify exception_pc tracks current pc
        pc = 32'hDEAD_BEE0;
        ecall = 1'b1;
        #1;
        check_eq(exception_pc, 32'hDEAD_BEE0, "exception_pc tracks current PC");
        ecall = 1'b0;
        #1;

        // Test exception priority: instr_misalign > illegal_instr
        // (instr_misalign is checked first in the RTL)
        pc = 32'h0000_3003;
        instr_misalign = 1'b1;
        illegal_instr  = 1'b1;
        #1;
        check_eq(exception_cause, CAUSE_INSTR_MISALIGN, "instr_misalign has priority over illegal_instr");

        instr_misalign = 1'b0;
        illegal_instr  = 1'b0;
        #1;
    endtask

    task automatic test_trap_vector_modes();
        test_begin("Trap Vector Modes (Direct/Vectored)");

        clear_exceptions();
        pc = 32'h0000_1000;

        // === Direct mode (mtvec[1:0] == 2'b00) ===
        mtvec = 32'h0000_0200;  // base=0x200, MODE=00 (direct)
        illegal_instr = 1'b1;
        #1;
        check_eq(redirect_pc, 32'h0000_0200, "Direct mode: redirect_pc = mtvec base for exception");
        illegal_instr = 1'b0;
        #1;

        // === Vectored mode (mtvec[1:0] == 2'b01) for interrupts ===
        mtvec = 32'h0000_0201;  // base=0x200, MODE=01 (vectored)

        // External interrupt: cause = {1'b1, 31'd11} -> cause[29:0]*4 = 11*4 = 44 = 0x2C
        // redirect_pc = 0x200 + 0x2C = 0x22C
        mstatus_mie = 1'b1;
        mie         = 32'h00000800;  // MEIE
        mip         = 32'h00000800;  // MEIP
        #1;
        check(exception_taken === 1'b1, "Vectored: external IRQ taken");
        check_eq(exception_cause, CAUSE_M_EXT_INT, "Vectored: cause = ext interrupt");
        check_eq(redirect_pc, 32'h0000_022C, "Vectored: redirect_pc = base + cause*4 = 0x200+0x2C");

        mip = 32'h0;
        mstatus_mie = 1'b0;
        #1;

        // Timer interrupt in vectored mode: cause = {1'b1, 31'd7} -> 7*4=28=0x1C
        // redirect_pc = 0x200 + 0x1C = 0x21C
        mstatus_mie = 1'b1;
        mie         = 32'h00000080;  // MTIE
        mip         = 32'h00000080;  // MTIP
        #1;
        check(exception_taken === 1'b1, "Vectored: timer IRQ taken");
        check_eq(exception_cause, CAUSE_M_TIMER_INT, "Vectored: cause = timer interrupt");
        check_eq(redirect_pc, 32'h0000_021C, "Vectored: redirect_pc = base + 7*4 = 0x21C");

        mip = 32'h0;
        mstatus_mie = 1'b0;
        #1;

        // SW interrupt in vectored mode: cause = {1'b1, 31'd3} -> 3*4=12=0xC
        // redirect_pc = 0x200 + 0xC = 0x20C
        mstatus_mie = 1'b1;
        mie         = 32'h00000008;  // MSIE
        mip         = 32'h00000008;  // MSIP
        #1;
        check(exception_taken === 1'b1, "Vectored: SW IRQ taken");
        check_eq(exception_cause, CAUSE_M_SW_INT, "Vectored: cause = SW interrupt");
        check_eq(redirect_pc, 32'h0000_020C, "Vectored: redirect_pc = base + 3*4 = 0x20C");

        mip = 32'h0;
        mstatus_mie = 1'b0;
        #1;

        // Exceptions always use direct mode even with vectored mtvec
        mtvec = 32'h0000_0201;  // Vectored
        illegal_instr = 1'b1;
        #1;
        check_eq(redirect_pc, 32'h0000_0200, "Vectored mtvec: exceptions still use direct mode base");
        illegal_instr = 1'b0;
        #1;

        // === Interrupt priority: ext > timer > sw ===
        mtvec       = 32'h0000_0200;  // Direct mode for simplicity
        mstatus_mie = 1'b1;
        mie         = 32'h00000888;  // All interrupts enabled
        mip         = 32'h00000888;  // All interrupts pending
        #1;
        check_eq(exception_cause, CAUSE_M_EXT_INT, "Priority: ext > timer > sw");

        // Clear ext, timer should win
        mip = 32'h00000088;  // Timer + SW pending
        #1;
        check_eq(exception_cause, CAUSE_M_TIMER_INT, "Priority: timer > sw (ext cleared)");

        // Clear timer, sw should win
        mip = 32'h00000008;  // Only SW pending
        #1;
        check_eq(exception_cause, CAUSE_M_SW_INT, "Priority: sw only");

        clear_exceptions();
    endtask

endmodule
