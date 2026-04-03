// =============================================================================
// VSync - Exception Unit
// RISC-V RV32IM Processor
//
// File: exception_unit.sv
// Description: Exception and interrupt detection, prioritization, and handling.
//              Generates trap vector redirect and pipeline flush signals.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module exception_unit (
    input  logic                clk,
    input  logic                rst_n,

    // Exception source signals
    input  logic                illegal_instr,
    input  logic                ecall,
    input  logic                ebreak,
    input  logic                mret,
    input  logic                load_misalign,
    input  logic                store_misalign,
    input  logic                instr_misalign,

    // Current PC
    input  logic [XLEN-1:0]    pc,

    // CSR inputs for interrupt evaluation
    input  logic                mstatus_mie,
    input  logic [XLEN-1:0]    mie,
    input  logic [XLEN-1:0]    mip,
    input  logic [XLEN-1:0]    mtvec,
    input  logic [XLEN-1:0]    mepc,

    // Exception outputs to CSR unit
    output logic                exception_taken,
    output logic [XLEN-1:0]    exception_cause,
    output logic [XLEN-1:0]    exception_pc,
    output logic [XLEN-1:0]    exception_val,

    // MRET output
    output logic                mret_taken,

    // Pipeline redirect
    output logic [XLEN-1:0]    redirect_pc,
    output logic                redirect_valid,

    // Pipeline flush
    output logic                flush_all
);

    // =========================================================================
    // Internal signals
    // =========================================================================
    logic        irq_pending;
    logic        any_exception;
    logic        irq_taken;

    // Individual interrupt pending signals
    logic        m_sw_irq_pending;
    logic        m_timer_irq_pending;
    logic        m_ext_irq_pending;

    // =========================================================================
    // Interrupt pending detection
    // Interrupts are only taken when mstatus.MIE is set
    // =========================================================================
    assign m_sw_irq_pending    = mstatus_mie & mie[3]  & mip[3];   // MSIE & MSIP
    assign m_timer_irq_pending = mstatus_mie & mie[7]  & mip[7];   // MTIE & MTIP
    assign m_ext_irq_pending   = mstatus_mie & mie[11] & mip[11];  // MEIE & MEIP

    assign irq_pending = m_ext_irq_pending | m_timer_irq_pending | m_sw_irq_pending;

    // =========================================================================
    // Exception detection (any synchronous exception)
    // =========================================================================
    assign any_exception = illegal_instr | ecall | ebreak |
                           load_misalign | store_misalign | instr_misalign;

    // =========================================================================
    // Priority: Interrupts > Exceptions (when both in same cycle)
    // Interrupt priority: External > Timer > Software
    // =========================================================================
    always_comb begin
        exception_taken = 1'b0;
        exception_cause = '0;
        exception_pc    = pc;
        exception_val   = '0;
        irq_taken       = 1'b0;
        mret_taken      = 1'b0;
        redirect_pc     = '0;
        redirect_valid  = 1'b0;
        flush_all       = 1'b0;

        if (irq_pending) begin
            // -----------------------------------------------------------------
            // Interrupt handling (highest priority)
            // Priority: External > Timer > Software
            // -----------------------------------------------------------------
            exception_taken = 1'b1;
            irq_taken       = 1'b1;
            exception_pc    = pc;   // Save current PC for return
            flush_all       = 1'b1;
            redirect_valid  = 1'b1;

            if (m_ext_irq_pending) begin
                exception_cause = CAUSE_M_EXT_INT;
            end else if (m_timer_irq_pending) begin
                exception_cause = CAUSE_M_TIMER_INT;
            end else begin
                exception_cause = CAUSE_M_SW_INT;
            end

            // Compute trap vector address
            // DIRECT mode (mtvec[1:0] == 2'b00): PC = mtvec[31:2] << 2
            // VECTORED mode (mtvec[1:0] == 2'b01): PC = (mtvec[31:2] << 2) + (cause * 4)
            if (mtvec[1:0] == 2'b01) begin
                // Vectored mode: base + cause*4 (only for interrupts)
                redirect_pc = {mtvec[XLEN-1:2], 2'b00} + {exception_cause[29:0], 2'b00};
            end else begin
                // Direct mode
                redirect_pc = {mtvec[XLEN-1:2], 2'b00};
            end

        end else if (any_exception) begin
            // -----------------------------------------------------------------
            // Synchronous exception handling
            // -----------------------------------------------------------------
            exception_taken = 1'b1;
            exception_pc    = pc;
            flush_all       = 1'b1;
            redirect_valid  = 1'b1;

            // Always use direct mode for exceptions
            redirect_pc = {mtvec[XLEN-1:2], 2'b00};

            // Determine cause and trap value
            if (instr_misalign) begin
                exception_cause = CAUSE_INSTR_MISALIGN;
                exception_val   = pc;
            end else if (illegal_instr) begin
                exception_cause = CAUSE_ILLEGAL_INSTR;
                exception_val   = '0;  // Could carry faulting instruction
            end else if (ecall) begin
                exception_cause = CAUSE_ECALL_M;
                exception_val   = '0;
            end else if (ebreak) begin
                exception_cause = CAUSE_BREAKPOINT;
                exception_val   = pc;
            end else if (load_misalign) begin
                exception_cause = CAUSE_LOAD_MISALIGN;
                exception_val   = '0;  // Could carry faulting address
            end else if (store_misalign) begin
                exception_cause = CAUSE_STORE_MISALIGN;
                exception_val   = '0;  // Could carry faulting address
            end

        end else if (mret) begin
            // -----------------------------------------------------------------
            // MRET: Return from machine-mode trap
            // -----------------------------------------------------------------
            mret_taken     = 1'b1;
            redirect_pc    = mepc;
            redirect_valid = 1'b1;
            flush_all      = 1'b1;
        end
    end

endmodule : exception_unit
