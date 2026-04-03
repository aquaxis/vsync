// =============================================================================
// VSync - AXI4 Bus Functional Model (BFM)
// =============================================================================
// AXI4 Master and Slave BFMs for testbench use.
// Supports single and burst read/write transactions.
// =============================================================================

`timescale 1ns / 1ps

// =============================================================================
// AXI4 Interface Definition
// =============================================================================
`ifndef IVERILOG
interface axi4_if #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input logic clk,
    input logic rst_n
);

    // Write Address Channel
    logic [ID_WIDTH-1:0]    awid;
    logic [ADDR_WIDTH-1:0]  awaddr;
    logic [7:0]             awlen;      // Burst length (0-255 = 1-256 beats)
    logic [2:0]             awsize;     // Burst size (bytes per beat)
    logic [1:0]             awburst;    // Burst type: 00=FIXED, 01=INCR, 10=WRAP
    logic                   awvalid;
    logic                   awready;

    // Write Data Channel
    logic [DATA_WIDTH-1:0]  wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                   wlast;
    logic                   wvalid;
    logic                   wready;

    // Write Response Channel
    logic [ID_WIDTH-1:0]    bid;
    logic [1:0]             bresp;      // 00=OKAY, 01=EXOKAY, 10=SLVERR, 11=DECERR
    logic                   bvalid;
    logic                   bready;

    // Read Address Channel
    logic [ID_WIDTH-1:0]    arid;
    logic [ADDR_WIDTH-1:0]  araddr;
    logic [7:0]             arlen;
    logic [2:0]             arsize;
    logic [1:0]             arburst;
    logic                   arvalid;
    logic                   arready;

    // Read Data Channel
    logic [ID_WIDTH-1:0]    rid;
    logic [DATA_WIDTH-1:0]  rdata;
    logic [1:0]             rresp;
    logic                   rlast;
    logic                   rvalid;
    logic                   rready;

    // Master modport
    modport master (
        output awid, awaddr, awlen, awsize, awburst, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bid, bresp, bvalid,
        output bready,
        output arid, araddr, arlen, arsize, arburst, arvalid,
        input  arready,
        input  rid, rdata, rresp, rlast, rvalid,
        output rready
    );

    // Slave modport
    modport slave (
        input  awid, awaddr, awlen, awsize, awburst, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bid, bresp, bvalid,
        input  bready,
        input  arid, araddr, arlen, arsize, arburst, arvalid,
        output arready,
        output rid, rdata, rresp, rlast, rvalid,
        input  rready
    );

endinterface
`endif // !IVERILOG

// =============================================================================
// AXI4 Master BFM
// =============================================================================
module axi4_master_bfm #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  logic clk,
    input  logic rst_n,

    // AXI4 Interface (directly connected signals)
    output logic [ID_WIDTH-1:0]    awid,
    output logic [ADDR_WIDTH-1:0]  awaddr,
    output logic [7:0]             awlen,
    output logic [2:0]             awsize,
    output logic [1:0]             awburst,
    output logic                   awvalid,
    input  logic                   awready,

    output logic [DATA_WIDTH-1:0]  wdata,
    output logic [DATA_WIDTH/8-1:0] wstrb,
    output logic                   wlast,
    output logic                   wvalid,
    input  logic                   wready,

    input  logic [ID_WIDTH-1:0]    bid,
    input  logic [1:0]             bresp,
    input  logic                   bvalid,
    output logic                   bready,

    output logic [ID_WIDTH-1:0]    arid,
    output logic [ADDR_WIDTH-1:0]  araddr,
    output logic [7:0]             arlen,
    output logic [2:0]             arsize,
    output logic [1:0]             arburst,
    output logic                   arvalid,
    input  logic                   arready,

    input  logic [ID_WIDTH-1:0]    rid,
    input  logic [DATA_WIDTH-1:0]  rdata,
    input  logic [1:0]             rresp,
    input  logic                   rlast,
    input  logic                   rvalid,
    output logic                   rready
);

    // =========================================================================
    // Signal initialization
    // =========================================================================
    initial begin
        awid    = '0;
        awaddr  = '0;
        awlen   = '0;
        awsize  = '0;
        awburst = '0;
        awvalid = 1'b0;
        wdata   = '0;
        wstrb   = '0;
        wlast   = 1'b0;
        wvalid  = 1'b0;
        bready  = 1'b0;
        arid    = '0;
        araddr  = '0;
        arlen   = '0;
        arsize  = '0;
        arburst = '0;
        arvalid = 1'b0;
        rready  = 1'b0;
    end

    // =========================================================================
    // Single write transaction
    // =========================================================================
    task automatic axi_write_single(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [DATA_WIDTH-1:0] data,
        input  logic [DATA_WIDTH/8-1:0] strobe,
        input  logic [ID_WIDTH-1:0]   id,
        output logic [1:0]            resp
    );
        // Write address phase
        @(posedge clk);
        awid    <= id;
        awaddr  <= addr;
        awlen   <= 8'h00;          // Single beat
        awsize  <= $clog2(DATA_WIDTH/8);
        awburst <= 2'b01;          // INCR
        awvalid <= 1'b1;

        // Write data phase (simultaneous)
        wdata   <= data;
        wstrb   <= strobe;
        wlast   <= 1'b1;
        wvalid  <= 1'b1;

        // Wait for address and data handshakes
        fork
            begin
                while (!awready) @(posedge clk);
                @(posedge clk);
                awvalid <= 1'b0;
            end
            begin
                while (!wready) @(posedge clk);
                @(posedge clk);
                wvalid <= 1'b0;
                wlast  <= 1'b0;
            end
        join

        // Wait for write response
        bready <= 1'b1;
        while (!bvalid) @(posedge clk);
        @(posedge clk);
        resp = bresp;
        @(posedge clk);
        bready <= 1'b0;
    endtask

    // =========================================================================
    // Single read transaction
    // =========================================================================
    task automatic axi_read_single(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [ID_WIDTH-1:0]   id,
        output logic [DATA_WIDTH-1:0] data,
        output logic [1:0]            resp
    );
        // Read address phase
        @(posedge clk);
        arid    <= id;
        araddr  <= addr;
        arlen   <= 8'h00;          // Single beat
        arsize  <= $clog2(DATA_WIDTH/8);
        arburst <= 2'b01;          // INCR
        arvalid <= 1'b1;

        // Wait for address handshake
        while (!arready) @(posedge clk);
        @(posedge clk);
        arvalid <= 1'b0;

        // Wait for read data
        rready <= 1'b1;
        while (!rvalid) @(posedge clk);
        @(posedge clk);
        data = rdata;
        resp = rresp;
        @(posedge clk);
        rready <= 1'b0;
    endtask

    // =========================================================================
    // Burst write transaction
    // =========================================================================
    task automatic axi_write_burst(
        input  logic [ADDR_WIDTH-1:0] start_addr,
        input  logic [DATA_WIDTH-1:0] data_array[],
        input  logic [1:0]            burst_type,
        input  logic [ID_WIDTH-1:0]   id,
        output logic [1:0]            resp
    );
        int beat_count;
        beat_count = data_array.size();

        // Write address phase
        @(posedge clk);
        awid    <= id;
        awaddr  <= start_addr;
        awlen   <= beat_count - 1;
        awsize  <= $clog2(DATA_WIDTH/8);
        awburst <= burst_type;
        awvalid <= 1'b1;

        while (!awready) @(posedge clk);
        @(posedge clk);
        awvalid <= 1'b0;

        // Write data beats
        for (int i = 0; i < beat_count; i++) begin
            @(posedge clk);
            wdata  <= data_array[i];
            wstrb  <= '1;
            wlast  <= (i == beat_count - 1) ? 1'b1 : 1'b0;
            wvalid <= 1'b1;

            while (!wready) @(posedge clk);
            @(posedge clk);
        end
        wvalid <= 1'b0;
        wlast  <= 1'b0;

        // Wait for write response
        bready <= 1'b1;
        while (!bvalid) @(posedge clk);
        @(posedge clk);
        resp = bresp;
        @(posedge clk);
        bready <= 1'b0;
    endtask

    // =========================================================================
    // Burst read transaction
    // =========================================================================
    task automatic axi_read_burst(
        input  logic [ADDR_WIDTH-1:0] start_addr,
        input  int                    beat_count,
        input  logic [1:0]            burst_type,
        input  logic [ID_WIDTH-1:0]   id,
        output logic [DATA_WIDTH-1:0] data_array[],
        output logic [1:0]            resp
    );
        // Read address phase
        @(posedge clk);
        arid    <= id;
        araddr  <= start_addr;
        arlen   <= beat_count - 1;
        arsize  <= $clog2(DATA_WIDTH/8);
        arburst <= burst_type;
        arvalid <= 1'b1;

        while (!arready) @(posedge clk);
        @(posedge clk);
        arvalid <= 1'b0;

        // Receive read data beats
        data_array = new[beat_count];
        rready <= 1'b1;
        for (int i = 0; i < beat_count; i++) begin
            while (!rvalid) @(posedge clk);
            @(posedge clk);
            data_array[i] = rdata;
            resp = rresp;
        end
        rready <= 1'b0;
    endtask

    // =========================================================================
    // Protocol assertions (disabled for iverilog)
    // =========================================================================
`ifndef IVERILOG
    // AWVALID must remain asserted until AWREADY
    property p_awvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        awvalid && !awready |=> awvalid;
    endproperty
    assert property (p_awvalid_stable)
        else $error("AXI Protocol Violation: AWVALID deasserted before AWREADY");

    // WVALID must remain asserted until WREADY
    property p_wvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        wvalid && !wready |=> wvalid;
    endproperty
    assert property (p_wvalid_stable)
        else $error("AXI Protocol Violation: WVALID deasserted before WREADY");

    // ARVALID must remain asserted until ARREADY
    property p_arvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        arvalid && !arready |=> arvalid;
    endproperty
    assert property (p_arvalid_stable)
        else $error("AXI Protocol Violation: ARVALID deasserted before ARREADY");
`endif // !IVERILOG

endmodule
