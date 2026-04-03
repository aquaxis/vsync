// =============================================================================
// VSync - APB Bus Functional Model (BFM)
// =============================================================================
// APB Master and Slave BFMs for testbench use.
// Compliant with AMBA APB protocol specification.
// =============================================================================

`timescale 1ns / 1ps

// =============================================================================
// APB Interface Definition
// =============================================================================
`ifndef IVERILOG
interface apb_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    logic [ADDR_WIDTH-1:0]  paddr;
    logic                   psel;
    logic                   penable;
    logic                   pwrite;
    logic [DATA_WIDTH-1:0]  pwdata;
    logic [DATA_WIDTH/8-1:0] pstrb;
    logic                   pready;
    logic [DATA_WIDTH-1:0]  prdata;
    logic                   pslverr;

    // Master modport
    modport master (
        output paddr, psel, penable, pwrite, pwdata, pstrb,
        input  pready, prdata, pslverr
    );

    // Slave modport
    modport slave (
        input  paddr, psel, penable, pwrite, pwdata, pstrb,
        output pready, prdata, pslverr
    );

endinterface
`endif // !IVERILOG

// =============================================================================
// APB Master BFM
// =============================================================================
module apb_master_bfm #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // APB signals
    output logic [ADDR_WIDTH-1:0]  paddr,
    output logic                   psel,
    output logic                   penable,
    output logic                   pwrite,
    output logic [DATA_WIDTH-1:0]  pwdata,
    output logic [DATA_WIDTH/8-1:0] pstrb,
    input  logic                   pready,
    input  logic [DATA_WIDTH-1:0]  prdata,
    input  logic                   pslverr
);

    // =========================================================================
    // Signal initialization
    // =========================================================================
    initial begin
        paddr   = '0;
        psel    = 1'b0;
        penable = 1'b0;
        pwrite  = 1'b0;
        pwdata  = '0;
        pstrb   = '0;
    end

    // =========================================================================
    // APB Write transaction
    // =========================================================================
    task automatic apb_write(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [DATA_WIDTH-1:0] data,
        input  logic [DATA_WIDTH/8-1:0] strobe,
        output logic                  error
    );
        // Setup phase
        @(posedge clk);
        paddr   <= addr;
        psel    <= 1'b1;
        penable <= 1'b0;
        pwrite  <= 1'b1;
        pwdata  <= data;
        pstrb   <= strobe;

        // Access phase
        @(posedge clk);
        penable <= 1'b1;

        // Wait for PREADY
        while (!pready) @(posedge clk);
        @(posedge clk);
        error = pslverr;

        // Idle
        psel    <= 1'b0;
        penable <= 1'b0;
        pwrite  <= 1'b0;
    endtask

    // =========================================================================
    // APB Read transaction
    // =========================================================================
    task automatic apb_read(
        input  logic [ADDR_WIDTH-1:0] addr,
        output logic [DATA_WIDTH-1:0] data,
        output logic                  error
    );
        // Setup phase
        @(posedge clk);
        paddr   <= addr;
        psel    <= 1'b1;
        penable <= 1'b0;
        pwrite  <= 1'b0;

        // Access phase
        @(posedge clk);
        penable <= 1'b1;

        // Wait for PREADY
        while (!pready) @(posedge clk);
        @(posedge clk);
        data  = prdata;
        error = pslverr;

        // Idle
        psel    <= 1'b0;
        penable <= 1'b0;
    endtask

    // =========================================================================
    // Protocol assertions (disabled for iverilog)
    // =========================================================================
`ifndef IVERILOG
    // PSEL must be asserted for at least one cycle before PENABLE
    property p_setup_before_enable;
        @(posedge clk) disable iff (!rst_n)
        $rose(psel) |=> ##[0:$] penable;
    endproperty

    // PENABLE must be asserted only when PSEL is asserted
    property p_enable_requires_sel;
        @(posedge clk) disable iff (!rst_n)
        penable |-> psel;
    endproperty
    assert property (p_enable_requires_sel)
        else $error("APB Protocol Violation: PENABLE without PSEL");

    // Address must be stable during access phase
    property p_addr_stable;
        @(posedge clk) disable iff (!rst_n)
        (psel && !penable) ##1 (psel && penable) |->
        $stable(paddr);
    endproperty
    assert property (p_addr_stable)
        else $error("APB Protocol Violation: PADDR changed during access phase");

    // Write data must be stable during access phase
    property p_wdata_stable;
        @(posedge clk) disable iff (!rst_n)
        (psel && !penable && pwrite) ##1 (psel && penable && pwrite) |->
        $stable(pwdata);
    endproperty
    assert property (p_wdata_stable)
        else $error("APB Protocol Violation: PWDATA changed during access phase");
`endif // !IVERILOG

endmodule

// =============================================================================
// APB Slave BFM (Simple memory-mapped)
// =============================================================================
module apb_slave_bfm #(
    parameter ADDR_WIDTH  = 32,
    parameter DATA_WIDTH  = 32,
    parameter MEM_SIZE    = 1024,    // Memory size in words
    parameter WAIT_STATES = 0        // Number of wait states
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // APB signals
    input  logic [ADDR_WIDTH-1:0]  paddr,
    input  logic                   psel,
    input  logic                   penable,
    input  logic                   pwrite,
    input  logic [DATA_WIDTH-1:0]  pwdata,
    input  logic [DATA_WIDTH/8-1:0] pstrb,
    output logic                   pready,
    output logic [DATA_WIDTH-1:0]  prdata,
    output logic                   pslverr
);

    // Internal memory
    logic [DATA_WIDTH-1:0] mem [0:MEM_SIZE-1];

    // Wait state counter
    int wait_cnt;

    // Address bounds check
    logic addr_valid;
    assign addr_valid = (paddr[$clog2(MEM_SIZE)+$clog2(DATA_WIDTH/8)-1:$clog2(DATA_WIDTH/8)] < MEM_SIZE);

    // Word address
    logic [$clog2(MEM_SIZE)-1:0] word_addr;
    assign word_addr = paddr[$clog2(MEM_SIZE)+$clog2(DATA_WIDTH/8)-1:$clog2(DATA_WIDTH/8)];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pready  <= 1'b0;
            prdata  <= '0;
            pslverr <= 1'b0;
            wait_cnt <= 0;
        end else begin
            if (psel && penable) begin
                if (wait_cnt < WAIT_STATES) begin
                    pready <= 1'b0;
                    wait_cnt <= wait_cnt + 1;
                end else begin
                    pready <= 1'b1;
                    wait_cnt <= 0;

                    if (!addr_valid) begin
                        pslverr <= 1'b1;
                        prdata  <= '0;
                    end else if (pwrite) begin
                        // Write with byte strobes
                        for (int i = 0; i < DATA_WIDTH/8; i++) begin
                            if (pstrb[i])
                                mem[word_addr][i*8 +: 8] <= pwdata[i*8 +: 8];
                        end
                        pslverr <= 1'b0;
                    end else begin
                        // Read
                        prdata  <= mem[word_addr];
                        pslverr <= 1'b0;
                    end
                end
            end else begin
                pready  <= 1'b0;
                pslverr <= 1'b0;
                wait_cnt <= 0;
            end
        end
    end

    // Memory initialization
    initial begin
        for (int i = 0; i < MEM_SIZE; i++)
            mem[i] = '0;
    end

endmodule
