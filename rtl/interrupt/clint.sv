// =============================================================================
// VSync - Core-Local Interruptor (CLINT)
//
// File: clint.sv
// Description: RISC-V CLINT with mtime, mtimecmp, msip registers.
//              Generates timer and software interrupts.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module clint #(
    parameter int TIMER_WIDTH = 64
) (
    // Clock & Reset
    input  logic        clk,
    input  logic        rst_n,

    // APB Slave Interface
    input  logic        apb_psel,
    input  logic        apb_penable,
    input  logic        apb_pwrite,
    input  logic [15:0] apb_paddr,
    input  logic [31:0] apb_pwdata,
    output logic [31:0] apb_prdata,
    output logic        apb_pready,
    output logic        apb_pslverr,

    // Interrupt Outputs
    output logic        timer_irq,
    output logic        sw_irq
);

    // =========================================================================
    // Register Address Offsets (CLINT_BASE relative)
    // =========================================================================
    localparam logic [15:0] ADDR_MSIP        = 16'h0000;
    localparam logic [15:0] ADDR_MTIMECMP_LO = 16'h4000;
    localparam logic [15:0] ADDR_MTIMECMP_HI = 16'h4004;
    localparam logic [15:0] ADDR_MTIME_LO    = 16'hBFF8;
    localparam logic [15:0] ADDR_MTIME_HI    = 16'hBFFC;

    // =========================================================================
    // Internal Registers
    // =========================================================================
    logic                      msip_r;
    logic [TIMER_WIDTH-1:0]    mtime_r;
    logic [TIMER_WIDTH-1:0]    mtimecmp_r;

    // =========================================================================
    // mtime Counter - Increments every clock cycle
    // =========================================================================
    /** @brief 64-bit mtime counter, increments every clock cycle */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime_r <= '0;
        end else begin
            // Allow APB writes to mtime, otherwise increment
            if (apb_write_en && apb_paddr == ADDR_MTIME_LO) begin
                mtime_r[31:0] <= apb_pwdata;
            end else if (apb_write_en && apb_paddr == ADDR_MTIME_HI) begin
                mtime_r[TIMER_WIDTH-1:32] <= apb_pwdata[TIMER_WIDTH-33:0];
            end else begin
                mtime_r <= mtime_r + 1'b1;
            end
        end
    end

    // =========================================================================
    // Timer Interrupt: mtime >= mtimecmp
    // =========================================================================
    /** @brief Timer interrupt asserted when mtime >= mtimecmp */
    assign timer_irq = (mtime_r >= mtimecmp_r);

    // =========================================================================
    // Software Interrupt: msip[0]
    // =========================================================================
    /** @brief Software interrupt directly from msip register */
    assign sw_irq = msip_r;

    // =========================================================================
    // APB Slave Interface
    // =========================================================================
    logic apb_write_en;
    logic apb_read_en;

    assign apb_write_en = apb_psel && apb_penable && apb_pwrite;
    assign apb_read_en  = apb_psel && apb_penable && !apb_pwrite;
    assign apb_pready   = apb_psel && apb_penable;  // Always ready
    assign apb_pslverr  = 1'b0;

    /** @brief APB register write logic (msip, mtimecmp) */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msip_r     <= 1'b0;
            mtimecmp_r <= {TIMER_WIDTH{1'b1}}; // Default to max (no timer IRQ)
        end else if (apb_write_en) begin
            case (apb_paddr)
                ADDR_MSIP: begin
                    msip_r <= apb_pwdata[0];
                end
                ADDR_MTIMECMP_LO: begin
                    mtimecmp_r[31:0] <= apb_pwdata;
                end
                ADDR_MTIMECMP_HI: begin
                    mtimecmp_r[TIMER_WIDTH-1:32] <= apb_pwdata[TIMER_WIDTH-33:0];
                end
                // MTIME writes handled in mtime counter block
                default: ;
            endcase
        end
    end

    /** @brief APB register read logic */
    always_comb begin
        apb_prdata = 32'h0;

        if (apb_read_en) begin
            case (apb_paddr)
                ADDR_MSIP: begin
                    apb_prdata = {31'h0, msip_r};
                end
                ADDR_MTIMECMP_LO: begin
                    apb_prdata = mtimecmp_r[31:0];
                end
                ADDR_MTIMECMP_HI: begin
                    apb_prdata = mtimecmp_r[TIMER_WIDTH-1:32];
                end
                ADDR_MTIME_LO: begin
                    apb_prdata = mtime_r[31:0];
                end
                ADDR_MTIME_HI: begin
                    apb_prdata = mtime_r[TIMER_WIDTH-1:32];
                end
                default: begin
                    apb_prdata = 32'h0;
                end
            endcase
        end
    end

endmodule : clint
