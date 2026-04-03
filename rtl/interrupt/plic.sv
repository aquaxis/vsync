// =============================================================================
// VSync - Platform-Level Interrupt Controller (PLIC)
//
// File: plic.sv
// Description: RISC-V PLIC with priority management, claim/complete mechanism,
//              and APB slave interface.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module plic #(
    parameter int NUM_SOURCES   = 16,
    parameter int NUM_TARGETS   = 1,
    parameter int PRIORITY_BITS = 3
) (
    // Clock & Reset
    input  logic                       clk,
    input  logic                       rst_n,

    // APB Slave Interface
    input  logic                       apb_psel,
    input  logic                       apb_penable,
    input  logic                       apb_pwrite,
    input  logic [15:0]                apb_paddr,
    input  logic [31:0]                apb_pwdata,
    output logic [31:0]                apb_prdata,
    output logic                       apb_pready,
    output logic                       apb_pslverr,

    // Interrupt Sources
    input  logic [NUM_SOURCES-1:0]     irq_sources,

    // External Interrupt Output (to CSR mip.MEIP)
    output logic [NUM_TARGETS-1:0]     ext_irq
);

    // =========================================================================
    // Local Parameters
    // =========================================================================
    localparam int SRC_ID_BITS = $clog2(NUM_SOURCES) + 1;

    // =========================================================================
    // Address Map (relative offsets)
    // =========================================================================
    // 0x000 - 0x03C: Source priority[0..NUM_SOURCES-1] (each 4 bytes)
    // 0x080:          Pending bits (bit field)
    // 0x100:          Target 0 enable bits (bit field)
    // 0x200:          Target 0 priority threshold
    // 0x204:          Target 0 claim/complete

    localparam logic [15:0] ADDR_PRIORITY_BASE  = 16'h0000;
    localparam logic [15:0] ADDR_PRIORITY_END   = ADDR_PRIORITY_BASE + 16'(NUM_SOURCES * 4);
    localparam logic [15:0] ADDR_PENDING        = 16'h0080;
    localparam logic [15:0] ADDR_ENABLE_BASE    = 16'h0100;
    localparam logic [15:0] ADDR_THRESHOLD_BASE = 16'h0200;
    localparam logic [15:0] ADDR_CLAIM_BASE     = 16'h0204;

    // =========================================================================
    // Internal Registers
    // =========================================================================
    logic [PRIORITY_BITS-1:0] source_priority [NUM_SOURCES];
    logic [NUM_SOURCES-1:0]   pending_r;
    logic [NUM_SOURCES-1:0]   enable_r        [NUM_TARGETS];
    logic [PRIORITY_BITS-1:0] threshold_r     [NUM_TARGETS];
    logic [NUM_SOURCES-1:0]   claimed_r;

    // =========================================================================
    // APB Interface Signals
    // =========================================================================
    logic apb_write_en;
    logic apb_read_en;

    assign apb_write_en = apb_psel && apb_penable && apb_pwrite;
    assign apb_read_en  = apb_psel && apb_penable && !apb_pwrite;
    assign apb_pready   = apb_psel && apb_penable;
    assign apb_pslverr  = 1'b0;

    // =========================================================================
    // Address Decode Helpers
    // =========================================================================
    // Compute source index from priority register address
    logic [15:0] prio_addr_offset;
    logic [15:0] prio_src_idx;
    logic        prio_addr_valid;

    assign prio_addr_offset = apb_paddr - ADDR_PRIORITY_BASE;
    assign prio_src_idx     = prio_addr_offset >> 2;
    assign prio_addr_valid  = (apb_paddr >= ADDR_PRIORITY_BASE) &&
                              (apb_paddr < ADDR_PRIORITY_END);

    // Complete write source ID
    logic [SRC_ID_BITS-1:0] complete_id;
    logic                   complete_valid;

    assign complete_id    = apb_pwdata[SRC_ID_BITS-1:0];
    assign complete_valid = (complete_id != '0) && (complete_id <= SRC_ID_BITS'(NUM_SOURCES));

    // =========================================================================
    // Edge Detection for Interrupt Sources
    // =========================================================================
    logic [NUM_SOURCES-1:0] irq_sources_prev;
    logic [NUM_SOURCES-1:0] irq_rising_edge;

    /** @brief Interrupt source edge detection */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            irq_sources_prev <= '0;
        end else begin
            irq_sources_prev <= irq_sources;
        end
    end

    assign irq_rising_edge = irq_sources & ~irq_sources_prev;

    // =========================================================================
    // Claim/Complete Mechanism
    // =========================================================================
    logic                   claim_read;
    logic [SRC_ID_BITS-1:0] claim_id;

    // =========================================================================
    // Pending Register Update
    // =========================================================================
    /** @brief Pending bits: set on rising edge, cleared on claim read */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_r <= '0;
        end else begin
            for (int i = 0; i < NUM_SOURCES; i++) begin
                if (irq_rising_edge[i]) begin
                    pending_r[i] <= 1'b1;
                end else if (claim_read && (claim_id == SRC_ID_BITS'(i + 1))) begin
                    pending_r[i] <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // Priority Arbitration (per target)
    // =========================================================================
    logic [SRC_ID_BITS-1:0]   best_id   [NUM_TARGETS];
    logic [PRIORITY_BITS-1:0] best_prio [NUM_TARGETS];

    /** @brief Priority arbitration: select highest priority interrupt per target */
    always_comb begin
        for (int t = 0; t < NUM_TARGETS; t++) begin
            best_id[t]   = '0;
            best_prio[t] = '0;

            for (int s = 0; s < NUM_SOURCES; s++) begin
                if (pending_r[s] && enable_r[t][s] && !claimed_r[s]) begin
                    if (source_priority[s] > best_prio[t]) begin
                        best_prio[t] = source_priority[s];
                        best_id[t]   = SRC_ID_BITS'(s + 1);
                    end
                end
            end
        end
    end

    // =========================================================================
    // External Interrupt Output
    // =========================================================================
    /** @brief Assert ext_irq when best priority exceeds threshold */
    always_comb begin
        for (int t = 0; t < NUM_TARGETS; t++) begin
            ext_irq[t] = (best_id[t] != '0) && (best_prio[t] > threshold_r[t]);
        end
    end

    // =========================================================================
    // APB Register Write Logic
    // =========================================================================
    /** @brief APB register write and claimed status management */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_SOURCES; i++) begin
                source_priority[i] <= '0;
            end
            for (int t = 0; t < NUM_TARGETS; t++) begin
                enable_r[t]    <= '0;
                threshold_r[t] <= '0;
            end
            claimed_r <= '0;
        end else begin
            // Handle claim read - mark source as claimed
            if (claim_read && (claim_id != '0)) begin
                claimed_r[claim_id - 1] <= 1'b1;
            end

            if (apb_write_en) begin
                // Source Priority registers (0x000 - 0x03C)
                if (prio_addr_valid) begin
                    for (int i = 0; i < NUM_SOURCES; i++) begin
                        if (prio_src_idx == 16'(i)) begin
                            source_priority[i] <= apb_pwdata[PRIORITY_BITS-1:0];
                        end
                    end
                end

                // Enable register (0x100)
                if (apb_paddr == ADDR_ENABLE_BASE) begin
                    enable_r[0] <= apb_pwdata[NUM_SOURCES-1:0];
                end

                // Threshold register (0x200)
                if (apb_paddr == ADDR_THRESHOLD_BASE) begin
                    threshold_r[0] <= apb_pwdata[PRIORITY_BITS-1:0];
                end

                // Complete write (0x204) - release claimed interrupt
                if (apb_paddr == ADDR_CLAIM_BASE) begin
                    if (complete_valid) begin
                        claimed_r[complete_id - 1] <= 1'b0;
                    end
                end
            end
        end
    end

    // =========================================================================
    // APB Register Read Logic
    // =========================================================================
    /** @brief APB register read logic with claim side-effect */
    always_comb begin
        apb_prdata = 32'h0;
        claim_read = 1'b0;
        claim_id   = '0;

        if (apb_read_en) begin
            // Source Priority registers (0x000 - 0x03C)
            if (prio_addr_valid) begin
                for (int i = 0; i < NUM_SOURCES; i++) begin
                    if (prio_src_idx == 16'(i)) begin
                        apb_prdata = {{(32-PRIORITY_BITS){1'b0}}, source_priority[i]};
                    end
                end
            end

            // Pending register (0x080)
            if (apb_paddr == ADDR_PENDING) begin
                apb_prdata = {{(32-NUM_SOURCES){1'b0}}, pending_r};
            end

            // Enable register (0x100)
            if (apb_paddr == ADDR_ENABLE_BASE) begin
                apb_prdata = {{(32-NUM_SOURCES){1'b0}}, enable_r[0]};
            end

            // Threshold register (0x200)
            if (apb_paddr == ADDR_THRESHOLD_BASE) begin
                apb_prdata = {{(32-PRIORITY_BITS){1'b0}}, threshold_r[0]};
            end

            // Claim read (0x204) - returns highest priority pending ID, clears pending
            if (apb_paddr == ADDR_CLAIM_BASE) begin
                claim_read = 1'b1;
                claim_id   = best_id[0];
                apb_prdata = {{(32-SRC_ID_BITS){1'b0}}, best_id[0]};
            end
        end
    end

endmodule : plic
