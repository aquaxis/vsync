// =============================================================================
// VSync - CSR Unit
// RISC-V RV32IM Processor
//
// File: csr_unit.sv
// Description: Machine-mode CSR register file with CSRRW/CSRRS/CSRRC operations,
//              exception/interrupt entry/exit, and performance counters.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module csr_unit (
    input  logic                clk,
    input  logic                rst_n,

    // CSR access interface
    input  logic [11:0]         csr_addr,
    input  logic [XLEN-1:0]    csr_wdata,
    input  logic [1:0]          csr_op,         // 00=NOP, 01=RW, 10=RS, 11=RC
    input  logic                csr_en,
    input  logic                csr_imm,        // 1: use zimm (csr_wdata[4:0] zero-extended)

    // Exception/interrupt interface
    input  logic                exception_taken,
    input  logic [XLEN-1:0]    exception_cause,
    input  logic [XLEN-1:0]    exception_pc,
    input  logic [XLEN-1:0]    exception_val,
    input  logic                mret,

    // Performance counter
    input  logic                retire_valid,

    // External interrupt sources
    input  logic                ext_irq,
    input  logic                timer_irq,
    input  logic                sw_irq,

    // CSR read output
    output logic [XLEN-1:0]    csr_rdata,

    // Outputs to other units
    output logic [XLEN-1:0]    mtvec,
    output logic [XLEN-1:0]    mepc,
    output logic [XLEN-1:0]    mie_out,
    output logic                mstatus_mie,
    output logic                trap_pending
);

    // =========================================================================
    // CSR Registers
    // =========================================================================

    // Machine status register
    logic        mstatus_mpie;
    logic        mstatus_mie_r;

    // Machine ISA register (read-only, RV32IM)
    // Bit layout: MXL[31:30]=01 (XLEN=32), Extensions: I(bit8)=1, M(bit12)=1
    localparam logic [XLEN-1:0] MISA_VALUE = 32'b01_0000_0000_0000_0001_0001_0000_0000;

    // Machine interrupt enable/pending
    logic [XLEN-1:0] mie_r;
    logic [XLEN-1:0] mip_r;

    // Machine trap vector
    logic [XLEN-1:0] mtvec_r;

    // Machine scratch register
    logic [XLEN-1:0] mscratch_r;

    // Machine exception program counter
    logic [XLEN-1:0] mepc_r;

    // Machine cause register
    logic [XLEN-1:0] mcause_r;

    // Machine trap value
    logic [XLEN-1:0] mtval_r;

    // Performance counters (64-bit)
    logic [63:0] mcycle_r;
    logic [63:0] minstret_r;

    // Read-only ID registers
    localparam logic [XLEN-1:0] MVENDORID_VALUE = 32'h0;   // Non-commercial
    localparam logic [XLEN-1:0] MARCHID_VALUE   = 32'h0;   // Not assigned
    localparam logic [XLEN-1:0] MIMPID_VALUE    = 32'h1;   // Implementation v1
    localparam logic [XLEN-1:0] MHARTID_VALUE   = 32'h0;   // Hart 0

    // =========================================================================
    // CSR Write Data Computation
    // =========================================================================
    logic [XLEN-1:0] csr_wdata_eff;     // Effective write data (reg or zimm)
    logic [XLEN-1:0] csr_rdata_int;     // Internal read data (old value)
    logic [XLEN-1:0] csr_new_value;     // New value to write

    // Effective write data: use zero-extended immediate or register value
    assign csr_wdata_eff = csr_imm ? {27'b0, csr_wdata[4:0]} : csr_wdata;

    // Compute new CSR value based on operation
    always_comb begin
        case (csr_op)
            2'b01:   csr_new_value = csr_wdata_eff;                         // CSRRW
            2'b10:   csr_new_value = csr_rdata_int | csr_wdata_eff;         // CSRRS
            2'b11:   csr_new_value = csr_rdata_int & ~csr_wdata_eff;        // CSRRC
            default: csr_new_value = csr_rdata_int;                          // NOP
        endcase
    end

    // =========================================================================
    // CSR Read Logic (combinational)
    // =========================================================================
    always_comb begin
        csr_rdata_int = '0;

        case (csr_addr)
            CSR_MSTATUS: begin
                csr_rdata_int        = '0;
                csr_rdata_int[3]     = mstatus_mie_r;   // MIE
                csr_rdata_int[7]     = mstatus_mpie;     // MPIE
                csr_rdata_int[12:11] = 2'b11;            // MPP = Machine mode
            end
            CSR_MISA:      csr_rdata_int = MISA_VALUE;
            CSR_MIE:       csr_rdata_int = mie_r;
            CSR_MTVEC:     csr_rdata_int = mtvec_r;
            CSR_MSCRATCH:  csr_rdata_int = mscratch_r;
            CSR_MEPC:      csr_rdata_int = mepc_r;
            CSR_MCAUSE:    csr_rdata_int = mcause_r;
            CSR_MTVAL:     csr_rdata_int = mtval_r;
            CSR_MIP:       csr_rdata_int = mip_r;
            CSR_MCYCLE:    csr_rdata_int = mcycle_r[31:0];
            CSR_MCYCLEH:   csr_rdata_int = mcycle_r[63:32];
            CSR_MINSTRET:  csr_rdata_int = minstret_r[31:0];
            CSR_MINSTRETH: csr_rdata_int = minstret_r[63:32];
            CSR_MVENDORID: csr_rdata_int = MVENDORID_VALUE;
            CSR_MARCHID:   csr_rdata_int = MARCHID_VALUE;
            CSR_MIMPID:    csr_rdata_int = MIMPID_VALUE;
            CSR_MHARTID:   csr_rdata_int = MHARTID_VALUE;
            default:       csr_rdata_int = '0;
        endcase
    end

    // Output read data (old value before write for CSR instructions)
    assign csr_rdata = csr_rdata_int;

    // =========================================================================
    // CSR Write Logic (sequential) - includes MIP external source reflection
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_mie_r <= 1'b0;
            mstatus_mpie  <= 1'b0;
            mie_r         <= '0;
            mip_r         <= '0;
            mtvec_r       <= '0;
            mscratch_r    <= '0;
            mepc_r        <= '0;
            mcause_r      <= '0;
            mtval_r       <= '0;
            mcycle_r      <= '0;
            minstret_r    <= '0;
        end else begin
            // -----------------------------------------------------------
            // MIP: reflect external interrupt sources every cycle
            // -----------------------------------------------------------
            mip_r[3]  <= sw_irq;       // MSIP - Machine software interrupt pending
            mip_r[7]  <= timer_irq;    // MTIP - Machine timer interrupt pending
            mip_r[11] <= ext_irq;      // MEIP - Machine external interrupt pending
            // -----------------------------------------------------------
            // Performance counters: always increment
            // -----------------------------------------------------------
            mcycle_r <= mcycle_r + 64'd1;

            if (retire_valid) begin
                minstret_r <= minstret_r + 64'd1;
            end

            // -----------------------------------------------------------
            // Exception entry: highest priority
            // -----------------------------------------------------------
            if (exception_taken) begin
                mepc_r        <= exception_pc;
                mcause_r      <= exception_cause;
                mtval_r       <= exception_val;
                mstatus_mpie  <= mstatus_mie_r;   // Save current MIE to MPIE
                mstatus_mie_r <= 1'b0;             // Disable interrupts
            end
            // -----------------------------------------------------------
            // MRET: restore interrupt state
            // -----------------------------------------------------------
            else if (mret) begin
                mstatus_mie_r <= mstatus_mpie;     // Restore MIE from MPIE
                mstatus_mpie  <= 1'b1;             // Set MPIE to 1
            end
            // -----------------------------------------------------------
            // CSR write operations
            // -----------------------------------------------------------
            else if (csr_en && (csr_op != 2'b00)) begin
                case (csr_addr)
                    CSR_MSTATUS: begin
                        mstatus_mie_r <= csr_new_value[3];
                        mstatus_mpie  <= csr_new_value[7];
                    end
                    // MISA is read-only, writes ignored
                    CSR_MIE:       mie_r      <= csr_new_value;
                    CSR_MTVEC:     mtvec_r    <= csr_new_value;
                    CSR_MSCRATCH:  mscratch_r <= csr_new_value;
                    CSR_MEPC:      mepc_r     <= {csr_new_value[XLEN-1:1], 1'b0}; // Align to 2-byte
                    CSR_MCAUSE:    mcause_r   <= csr_new_value;
                    CSR_MTVAL:     mtval_r    <= csr_new_value;
                    // MIP software-writable bits only (MSIP)
                    CSR_MIP:       mip_r[3]   <= csr_new_value[3];
                    CSR_MCYCLE:    mcycle_r[31:0]    <= csr_new_value;
                    CSR_MCYCLEH:   mcycle_r[63:32]   <= csr_new_value;
                    CSR_MINSTRET:  minstret_r[31:0]  <= csr_new_value;
                    CSR_MINSTRETH: minstret_r[63:32] <= csr_new_value;
                    // Read-only registers: MVENDORID, MARCHID, MIMPID, MHARTID - ignore writes
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // Output assignments
    // =========================================================================
    assign mtvec        = mtvec_r;
    assign mepc         = mepc_r;
    assign mie_out      = mie_r;
    assign mstatus_mie  = mstatus_mie_r;

    // =========================================================================
    // Trap pending detection
    // Trap is pending when MIE is enabled and any enabled interrupt is pending
    // =========================================================================
    assign trap_pending = mstatus_mie_r & |(mie_r & mip_r);

endmodule : csr_unit
