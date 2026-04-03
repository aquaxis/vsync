// =============================================================================
// VSync - Physical Memory Protection Unit
// RISC-V RV32IM Processor with Hardware RTOS
//
// File: pmp_unit.sv
// Description: RISC-V PMP (Physical Memory Protection) unit supporting
//              TOR, NA4, and NAPOT address matching modes with lock bit.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module pmp_unit #(
    parameter int NUM_REGIONS = 8,
    parameter int XLEN        = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // CSR write interface for pmpcfg
    input  logic                    csr_pmpcfg_wr,
    input  logic [$clog2((NUM_REGIONS+3)/4)-1:0] csr_pmpcfg_idx, // pmpcfg register index (0 or 1 for 8 regions)
    input  logic [XLEN-1:0]        csr_pmpcfg_wdata,

    // CSR write interface for pmpaddr
    input  logic                    csr_pmpaddr_wr,
    input  logic [$clog2(NUM_REGIONS)-1:0] csr_pmpaddr_idx, // pmpaddr register index (0..NUM_REGIONS-1)
    input  logic [XLEN-1:0]        csr_pmpaddr_wdata,

    // Access check interface
    input  logic [XLEN-1:0]        check_addr,
    input  logic [2:0]             check_type,     // bit0=Read, bit1=Write, bit2=Execute

    // Outputs
    output logic                    access_fault,

    // CSR read interface
    output logic [XLEN-1:0]        pmpcfg_out  [((NUM_REGIONS + 3) / 4)],
    output logic [XLEN-1:0]        pmpaddr_out [NUM_REGIONS]
);

    // =========================================================================
    // PMP Configuration field encoding
    // =========================================================================
    // pmpcfg byte: { L(1), 00(2), A(2), X(1), W(1), R(1) }
    localparam int CFG_R_BIT = 0;   // Read permission
    localparam int CFG_W_BIT = 1;   // Write permission
    localparam int CFG_X_BIT = 2;   // Execute permission
    localparam int CFG_A_LO  = 3;   // Address matching mode low bit
    localparam int CFG_A_HI  = 4;   // Address matching mode high bit
    localparam int CFG_L_BIT = 7;   // Lock bit

    // Address matching modes
    localparam logic [1:0] PMP_OFF   = 2'b00;
    localparam logic [1:0] PMP_TOR   = 2'b01;
    localparam logic [1:0] PMP_NA4   = 2'b10;
    localparam logic [1:0] PMP_NAPOT = 2'b11;

    // =========================================================================
    // PMP registers
    // =========================================================================
    logic [7:0]          pmpcfg_r  [NUM_REGIONS];
    logic [XLEN-1:0]    pmpaddr_r [NUM_REGIONS];

    // Number of pmpcfg registers (each holds 4 entries for RV32)
    localparam int NUM_CFG_REGS = (NUM_REGIONS + 3) / 4;

    // =========================================================================
    // CSR write logic
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_REGIONS; i++) begin
                pmpcfg_r[i]  <= 8'h0;
                pmpaddr_r[i] <= '0;
            end
        end else begin
            // pmpcfg write: update 4 entries per register write
            if (csr_pmpcfg_wr) begin
                for (int b = 0; b < 4; b++) begin
                    if ((int'(csr_pmpcfg_idx) * 4 + b) < NUM_REGIONS) begin
                        // Only write if not locked
                        if (!pmpcfg_r[int'(csr_pmpcfg_idx) * 4 + b][CFG_L_BIT]) begin
                            pmpcfg_r[int'(csr_pmpcfg_idx) * 4 + b] <= csr_pmpcfg_wdata[b*8 +: 8];
                        end
                    end
                end
            end

            // pmpaddr write
            if (csr_pmpaddr_wr) begin
                if (int'(csr_pmpaddr_idx) < NUM_REGIONS) begin
                    // Only write if not locked
                    // Also check if next entry is TOR and locked (which also locks this addr)
                    if (!pmpcfg_r[csr_pmpaddr_idx][CFG_L_BIT]) begin
                        pmpaddr_r[csr_pmpaddr_idx] <= csr_pmpaddr_wdata;
                    end
                end
            end
        end
    end

    // =========================================================================
    // CSR read logic
    // =========================================================================
    always_comb begin
        for (int r = 0; r < NUM_CFG_REGS; r++) begin
            pmpcfg_out[r] = '0;
            for (int b = 0; b < 4; b++) begin
                if ((r * 4 + b) < NUM_REGIONS) begin
                    pmpcfg_out[r][b*8 +: 8] = pmpcfg_r[r * 4 + b];
                end
            end
        end

        for (int i = 0; i < NUM_REGIONS; i++) begin
            pmpaddr_out[i] = pmpaddr_r[i];
        end
    end

    // =========================================================================
    // Address matching logic (combinational)
    // =========================================================================
    // PMP address registers store address[33:2] (shifted right by 2)
    // For address comparison, we convert to full byte addresses

    logic [NUM_REGIONS-1:0] region_match;
    logic [XLEN-1:0]        region_mask [NUM_REGIONS];  // NAPOT mask

`ifdef IVERILOG
    // iverilog 12.0 workaround: bit-select on array elements inside always_*
    // blocks is not supported. Use generate blocks with per-region local wires
    // and assign statements to avoid array access inside always_comb entirely.
    logic [NUM_REGIONS-1:0] cfg_r_bit;
    logic [NUM_REGIONS-1:0] cfg_w_bit;
    logic [NUM_REGIONS-1:0] cfg_x_bit;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_REGIONS; gi = gi + 1) begin : gen_pmp_match
            // Per-region local wires (not arrays - no array indexing needed)
            wire [1:0]      lcl_a_field = pmpcfg_r[gi][CFG_A_HI:CFG_A_LO];
            wire [XLEN-1:0] lcl_addr    = pmpaddr_r[gi];
            wire [XLEN-1:0] lcl_mask    = napot_mask(lcl_addr);

            // Extract permission bits via continuous assign
            assign cfg_r_bit[gi] = pmpcfg_r[gi][CFG_R_BIT];
            assign cfg_w_bit[gi] = pmpcfg_r[gi][CFG_W_BIT];
            assign cfg_x_bit[gi] = pmpcfg_r[gi][CFG_X_BIT];

            // Per-region match using only local wires (no array bit-select)
            if (gi == 0) begin : gen_tor_first
                assign region_match[gi] =
                    (lcl_a_field == PMP_OFF)   ? 1'b0 :
                    (lcl_a_field == PMP_TOR)   ? (check_addr < {lcl_addr[XLEN-3:0], 2'b00}) :
                    (lcl_a_field == PMP_NA4)   ? (check_addr[XLEN-1:2] == lcl_addr[XLEN-3:0]) :
                    (lcl_a_field == PMP_NAPOT) ? ((check_addr[XLEN-1:2] & lcl_mask[XLEN-3:0]) ==
                                                  (lcl_addr[XLEN-3:0] & lcl_mask[XLEN-3:0])) :
                    1'b0;
            end else begin : gen_tor_other
                wire [XLEN-1:0] lcl_prev_addr = pmpaddr_r[gi-1];
                assign region_match[gi] =
                    (lcl_a_field == PMP_OFF)   ? 1'b0 :
                    (lcl_a_field == PMP_TOR)   ? ((check_addr >= {lcl_prev_addr[XLEN-3:0], 2'b00}) &&
                                                  (check_addr <  {lcl_addr[XLEN-3:0], 2'b00})) :
                    (lcl_a_field == PMP_NA4)   ? (check_addr[XLEN-1:2] == lcl_addr[XLEN-3:0]) :
                    (lcl_a_field == PMP_NAPOT) ? ((check_addr[XLEN-1:2] & lcl_mask[XLEN-3:0]) ==
                                                  (lcl_addr[XLEN-3:0] & lcl_mask[XLEN-3:0])) :
                    1'b0;
            end
            assign region_mask[gi] = lcl_mask;
        end
    endgenerate
`else
    always_comb begin
        for (int i = 0; i < NUM_REGIONS; i++) begin
            region_match[i] = 1'b0;
            region_mask[i]  = '0;

            case (pmpcfg_r[i][CFG_A_HI:CFG_A_LO])
                // OFF: region disabled
                PMP_OFF: begin
                    region_match[i] = 1'b0;
                end

                // TOR: Top of Range
                // Match if prev_addr <= check_addr < pmpaddr[i]
                // Addresses are in units of 4 bytes (shifted right by 2)
                PMP_TOR: begin
                    if (i == 0) begin
                        // First entry: range is [0, pmpaddr[0])
                        region_match[i] = (check_addr < {pmpaddr_r[i][XLEN-3:0], 2'b00});
                    end else begin
                        region_match[i] = (check_addr >= {pmpaddr_r[i-1][XLEN-3:0], 2'b00}) &&
                                          (check_addr <  {pmpaddr_r[i][XLEN-3:0], 2'b00});
                    end
                end

                // NA4: Naturally Aligned 4-byte region
                PMP_NA4: begin
                    region_match[i] = (check_addr[XLEN-1:2] == pmpaddr_r[i][XLEN-3:0]);
                end

                // NAPOT: Naturally Aligned Power-of-Two
                // pmpaddr encoding: trailing 1s determine region size
                // Size = 2^(trailing_ones + 3) bytes
                PMP_NAPOT: begin
                    // Compute NAPOT mask: find trailing ones in pmpaddr
                    // mask = all bits from trailing-ones position upward
                    region_mask[i] = napot_mask(pmpaddr_r[i]);
                    region_match[i] = ((check_addr[XLEN-1:2] & region_mask[i][XLEN-3:0]) ==
                                       (pmpaddr_r[i][XLEN-3:0] & region_mask[i][XLEN-3:0]));
                end

                default: begin
                    region_match[i] = 1'b0;
                end
            endcase
        end
    end
`endif

    // =========================================================================
    // NAPOT mask computation function
    // Finds trailing ones in pmpaddr and creates comparison mask
    // =========================================================================
`ifdef IVERILOG
    function logic [XLEN-1:0] napot_mask(input logic [XLEN-1:0] addr);
`else
    function automatic logic [XLEN-1:0] napot_mask(input logic [XLEN-1:0] addr);
`endif
        logic [XLEN-1:0] mask;
        logic             found;
        begin
            mask  = '0;
            found = 1'b0;
            // Scan from bit 0 upward, find first 0
            for (int b = 0; b < XLEN; b++) begin
                if (!found && !addr[b]) begin
                    found = 1'b1;
                end
                if (found) begin
                    mask[b] = 1'b1;
                end
            end
            // If all ones (entire address space), mask is 0 (match everything)
            if (!found) begin
                mask = '0;
            end
            napot_mask = mask;
        end
    endfunction

    // =========================================================================
    // Access permission check (priority: lowest index first)
    // =========================================================================
`ifdef IVERILOG
    // iverilog 12.0 workaround: compute per-region fault using generate,
    // then OR-reduce to get the final access_fault signal.
    logic [NUM_REGIONS-1:0] region_fault;

    generate
        for (gi = 0; gi < NUM_REGIONS; gi = gi + 1) begin : gen_pmp_fault
            assign region_fault[gi] = region_match[gi] && (
                (check_type[0] && !cfg_r_bit[gi]) ||
                (check_type[1] && !cfg_w_bit[gi]) ||
                (check_type[2] && !cfg_x_bit[gi])
            );
        end
    endgenerate

    assign access_fault = |region_fault;
`else
    always_comb begin
        access_fault = 1'b0;

        // Machine mode with no PMP match: allow all access (M-mode default)
        // If any PMP entry matches, enforce permissions
        for (int i = 0; i < NUM_REGIONS; i++) begin
            if (region_match[i]) begin
                // Check permissions based on access type
                if (check_type[0] && !pmpcfg_r[i][CFG_R_BIT]) begin
                    access_fault = 1'b1;  // Read access, no R permission
                end
                if (check_type[1] && !pmpcfg_r[i][CFG_W_BIT]) begin
                    access_fault = 1'b1;  // Write access, no W permission
                end
                if (check_type[2] && !pmpcfg_r[i][CFG_X_BIT]) begin
                    access_fault = 1'b1;  // Execute access, no X permission
                end
            end
        end

        // No matching region in M-mode: access is allowed (no fault)
        // For U-mode (if supported), no match = denied, but we only have M-mode
    end
`endif

endmodule : pmp_unit
