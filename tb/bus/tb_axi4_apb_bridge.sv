// =============================================================================
// VSync - AXI4-APB Bridge Test Bench
// =============================================================================
// Test IDs: BRG-001 ~ BRG-006
// - BRG-001: Single read conversion (AXI4 Read -> APB Read)
// - BRG-002: Single write conversion (AXI4 Write -> APB Write)
// - BRG-003: Burst -> Sequential conversion
// - BRG-004: Error propagation (APB PSLVERR -> AXI4 SLVERR)
// - BRG-005: Address decode (correct peripheral selection)
// - BRG-006: Wait states (APB PREADY delay)
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_axi4_apb_bridge;

    import test_utils::*;
    import vsync_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD  = 10;
    localparam RST_CYCLES  = 10;
    localparam ADDR_WIDTH  = 32;
    localparam DATA_WIDTH  = 32;
    localparam ID_WIDTH    = 4;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // AXI4 side (master -> bridge)
    logic [ID_WIDTH-1:0]    awid, arid, bid, rid;
    logic [ADDR_WIDTH-1:0]  awaddr, araddr;
    logic [7:0]             awlen, arlen;
    logic [2:0]             awsize, arsize;
    logic [1:0]             awburst, arburst;
    logic                   awvalid, arvalid;
    logic                   awready, arready;
    logic [DATA_WIDTH-1:0]  wdata, rdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                   wlast, rlast;
    logic                   wvalid, rvalid;
    logic                   wready, rready;
    logic [1:0]             bresp, rresp;
    logic                   bvalid, bready;

    // APB side (bridge -> slave)
    logic [ADDR_WIDTH-1:0]  paddr;
    logic                   psel;
    logic                   penable;
    logic                   pwrite;
    logic [DATA_WIDTH-1:0]  pwdata;
    logic [DATA_WIDTH/8-1:0] pstrb;
    logic                   pready;
    logic [DATA_WIDTH-1:0]  prdata;
    logic                   pslverr;

    // APB side for wait-state slave (BRG-006)
    logic                   pready_ws;
    logic [DATA_WIDTH-1:0]  prdata_ws;
    logic                   pslverr_ws;

    // APB error responder signals (BRG-004)
    logic                   pready_err;
    logic [DATA_WIDTH-1:0]  prdata_err;
    logic                   pslverr_err;

    // Slave select: 0=normal, 1=wait-state, 2=error
    logic [1:0] slave_sel;

    // Muxed APB response signals going back to the bridge
    logic                   pready_mux;
    logic [DATA_WIDTH-1:0]  prdata_mux;
    logic                   pslverr_mux;

    assign pready_mux  = (slave_sel == 2'd2) ? pready_err  :
                          (slave_sel == 2'd1) ? pready_ws   : pready;
    assign prdata_mux  = (slave_sel == 2'd2) ? prdata_err  :
                          (slave_sel == 2'd1) ? prdata_ws   : prdata;
    assign pslverr_mux = (slave_sel == 2'd2) ? pslverr_err :
                          (slave_sel == 2'd1) ? pslverr_ws  : pslverr;

    // The bridge does not have a pstrb output; tie to all-ones for APB slave
    assign pstrb = '1;

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
    axi4_apb_bridge #(
        .AXI_ADDR_W(ADDR_WIDTH),
        .AXI_DATA_W(DATA_WIDTH),
        .APB_ADDR_W(ADDR_WIDTH),
        .APB_DATA_W(DATA_WIDTH),
        .AXI_ID_W(ID_WIDTH)
    ) u_bridge (
        .clk(clk),
        .rst_n(rst_n),
        // AXI4 slave port - Write Address Channel
        .s_axi_awid(awid),
        .s_axi_awaddr(awaddr),
        .s_axi_awlen(awlen),
        .s_axi_awsize(awsize),
        .s_axi_awburst(awburst),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),
        // AXI4 slave port - Write Data Channel
        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wlast(wlast),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),
        // AXI4 slave port - Write Response Channel
        .s_axi_bid(bid),
        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),
        // AXI4 slave port - Read Address Channel
        .s_axi_arid(arid),
        .s_axi_araddr(araddr),
        .s_axi_arlen(arlen),
        .s_axi_arsize(arsize),
        .s_axi_arburst(arburst),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),
        // AXI4 slave port - Read Data Channel
        .s_axi_rid(rid),
        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rlast(rlast),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),
        // APB master port
        .apb_psel(psel),
        .apb_penable(penable),
        .apb_pwrite(pwrite),
        .apb_paddr(paddr),
        .apb_pwdata(pwdata),
        .apb_prdata(prdata_mux),
        .apb_pready(pready_mux),
        .apb_pslverr(pslverr_mux)
    );

    // AXI4 Master BFM for stimulus
    axi4_master_bfm #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_axi4_master (
        .clk(clk), .rst_n(rst_n),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
        .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp), .rlast(rlast),
        .rvalid(rvalid), .rready(rready)
    );

    // APB Slave BFM for response (no wait states)
    apb_slave_bfm #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .MEM_SIZE    (1024),
        .WAIT_STATES (0)
    ) u_apb_slave (
        .clk     (clk),
        .rst_n   (rst_n),
        .paddr   (paddr),
        .psel    (psel & (slave_sel == 2'd0)),
        .penable (penable),
        .pwrite  (pwrite),
        .pwdata  (pwdata),
        .pstrb   (pstrb),
        .pready  (pready),
        .prdata  (prdata),
        .pslverr (pslverr)
    );

    // APB Slave BFM with wait states (for BRG-006)
    apb_slave_bfm #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .MEM_SIZE    (1024),
        .WAIT_STATES (3)
    ) u_apb_slave_ws (
        .clk     (clk),
        .rst_n   (rst_n),
        .paddr   (paddr),
        .psel    (psel & (slave_sel == 2'd1)),
        .penable (penable),
        .pwrite  (pwrite),
        .pwdata  (pwdata),
        .pstrb   (pstrb),
        .pready  (pready_ws),
        .prdata  (prdata_ws),
        .pslverr (pslverr_ws)
    );

    // =========================================================================
    // APB Error Responder (always returns pslverr=1)
    // =========================================================================
    // Simple APB slave that always responds with an error after 1 cycle
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pready_err  <= 1'b0;
            prdata_err  <= '0;
            pslverr_err <= 1'b0;
        end else begin
            if (psel && penable && (slave_sel == 2'd2)) begin
                pready_err  <= 1'b1;
                prdata_err  <= '0;
                pslverr_err <= 1'b1;
            end else begin
                pready_err  <= 1'b0;
                pslverr_err <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Initialize mux control
    // =========================================================================
    initial begin
        slave_sel = 2'd0;
    end

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_axi4_apb_bridge.vcd");
        $dumpvars(0, tb_axi4_apb_bridge);
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
    // Main test sequence
    // =========================================================================
    initial begin
        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("AXI4-APB Bridge Tests");

        test_single_read_conversion();
        test_single_write_conversion();
        test_burst_to_sequential();
        test_error_propagation();
        test_address_decode();
        test_wait_states();

    endtask

    // =========================================================================
    // BRG-001: Single Read Conversion (AXI4 Read -> APB Read)
    // =========================================================================
    task automatic test_single_read_conversion();
        logic [DATA_WIDTH-1:0] rd_data;
        logic [1:0]            wr_resp;
        logic [1:0]            rd_resp;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] wr_data;

        test_begin("BRG-001: Single Read Conversion (AXI4 -> APB)");

        // Step 1: Write data via AXI so APB slave memory has known content
        addr    = 32'h0000_0010;   // byte address (word index = 4)
        wr_data = 32'hCAFE_BABE;
        u_axi4_master.axi_write_single(addr, wr_data, 4'hF, 4'h1, wr_resp);
        check_eq(wr_resp, 2'b00, "Write for read-back: BRESP = OKAY");

        repeat (2) @(posedge clk);

        // Step 2: Read back via AXI and verify data
        u_axi4_master.axi_read_single(addr, 4'h1, rd_data, rd_resp);
        check_eq(rd_resp, 2'b00, "Read: RRESP = OKAY");
        check_eq(rd_data, wr_data, "Read data matches written data");

        repeat (2) @(posedge clk);

        // Step 3: Test with different data and address
        addr    = 32'h0000_0020;   // word index = 8
        wr_data = 32'hDEAD_BEEF;
        u_axi4_master.axi_write_single(addr, wr_data, 4'hF, 4'h2, wr_resp);
        check_eq(wr_resp, 2'b00, "Write 2 for read-back: BRESP = OKAY");

        repeat (2) @(posedge clk);

        u_axi4_master.axi_read_single(addr, 4'h2, rd_data, rd_resp);
        check_eq(rd_resp, 2'b00, "Read 2: RRESP = OKAY");
        check_eq(rd_data, wr_data, "Read 2 data matches written data");

        repeat (2) @(posedge clk);
    endtask

    // =========================================================================
    // BRG-002: Single Write Conversion (AXI4 Write -> APB Write)
    // =========================================================================
    task automatic test_single_write_conversion();
        logic [1:0]            wr_resp;
        logic [DATA_WIDTH-1:0] rd_data;
        logic [1:0]            rd_resp;
        logic [ADDR_WIDTH-1:0] addr;
        logic [DATA_WIDTH-1:0] wr_data;

        test_begin("BRG-002: Single Write Conversion (AXI4 -> APB)");

        // Step 1: Write known data via AXI
        addr    = 32'h0000_0100;   // word index = 64
        wr_data = 32'h1234_5678;
        u_axi4_master.axi_write_single(addr, wr_data, 4'hF, 4'h3, wr_resp);
        check_eq(wr_resp, 2'b00, "Write: BRESP = OKAY");

        repeat (2) @(posedge clk);

        // Step 2: Verify data reached APB slave by reading back
        u_axi4_master.axi_read_single(addr, 4'h3, rd_data, rd_resp);
        check_eq(rd_resp, 2'b00, "Read-back: RRESP = OKAY");
        check_eq(rd_data, wr_data, "APB slave received correct write data");

        repeat (2) @(posedge clk);

        // Step 3: Write another value to same address and verify overwrite
        wr_data = 32'hAAAA_BBBB;
        u_axi4_master.axi_write_single(addr, wr_data, 4'hF, 4'h4, wr_resp);
        check_eq(wr_resp, 2'b00, "Overwrite: BRESP = OKAY");

        repeat (2) @(posedge clk);

        u_axi4_master.axi_read_single(addr, 4'h4, rd_data, rd_resp);
        check_eq(rd_data, wr_data, "Overwrite data correct");

        repeat (2) @(posedge clk);

        // Step 4: Write with different transaction ID
        addr    = 32'h0000_0200;   // word index = 128
        wr_data = 32'hFEED_FACE;
        u_axi4_master.axi_write_single(addr, wr_data, 4'hF, 4'hA, wr_resp);
        check_eq(wr_resp, 2'b00, "Write with ID=0xA: BRESP = OKAY");

        repeat (2) @(posedge clk);

        u_axi4_master.axi_read_single(addr, 4'hA, rd_data, rd_resp);
        check_eq(rd_data, wr_data, "Write with ID=0xA: data correct");

        repeat (2) @(posedge clk);
    endtask

    // =========================================================================
    // BRG-003: Burst -> Sequential Conversion
    // =========================================================================
    // The axi4_apb_bridge only supports single-beat transfers (awlen/arlen = 0).
    // This test verifies that single-beat transfers work correctly for multiple
    // sequential addresses, simulating what a burst decomposition would do.
    task automatic test_burst_to_sequential();
        logic [1:0]            resp;
        logic [DATA_WIDTH-1:0] rd_data;
        logic [ADDR_WIDTH-1:0] base_addr;
        logic [DATA_WIDTH-1:0] test_data [0:3];

        test_begin("BRG-003: Burst -> Sequential Conversion");

        base_addr    = 32'h0000_0300;
        test_data[0] = 32'h1111_1111;
        test_data[1] = 32'h2222_2222;
        test_data[2] = 32'h3333_3333;
        test_data[3] = 32'h4444_4444;

        // Write 4 sequential words (single-beat each, as bridge requires)
        for (int i = 0; i < 4; i++) begin
            u_axi4_master.axi_write_single(
                base_addr + i * 4, test_data[i], 4'hF, 4'h5, resp
            );
            check_eq(resp, 2'b00, $sformatf("Sequential write[%0d]: BRESP = OKAY", i));
            repeat (2) @(posedge clk);
        end

        // Read back all 4 words and verify
        for (int i = 0; i < 4; i++) begin
            u_axi4_master.axi_read_single(
                base_addr + i * 4, 4'h5, rd_data, resp
            );
            check_eq(resp, 2'b00, $sformatf("Sequential read[%0d]: RRESP = OKAY", i));
            check_eq(rd_data, test_data[i],
                     $sformatf("Sequential read[%0d]: data matches", i));
            repeat (2) @(posedge clk);
        end
    endtask

    // =========================================================================
    // BRG-004: Error Propagation (APB PSLVERR -> AXI4 SLVERR)
    // =========================================================================
    // Use the error-injection APB responder (slave_sel=2) which always returns
    // pslverr=1, then verify the bridge propagates it as AXI SLVERR (2'b10).
    task automatic test_error_propagation();
        logic [1:0]            wr_resp;
        logic [1:0]            rd_resp;
        logic [DATA_WIDTH-1:0] rd_data;

        test_begin("BRG-004: Error Propagation (PSLVERR -> SLVERR)");

        // Switch to error responder
        slave_sel = 2'd2;
        repeat (2) @(posedge clk);

        // Step 1: Write transaction - error responder returns pslverr=1
        u_axi4_master.axi_write_single(32'h0000_0040, 32'hBAAD_F00D, 4'hF, 4'h6, wr_resp);
        check_eq(wr_resp, 2'b10, "Write with error slave: BRESP = SLVERR (2'b10)");

        repeat (2) @(posedge clk);

        // Step 2: Read transaction - error responder returns pslverr=1
        u_axi4_master.axi_read_single(32'h0000_0040, 4'h6, rd_data, rd_resp);
        check_eq(rd_resp, 2'b10, "Read with error slave: RRESP = SLVERR (2'b10)");

        repeat (2) @(posedge clk);

        // Step 3: Switch back to normal slave and verify bridge recovers
        slave_sel = 2'd0;
        repeat (2) @(posedge clk);

        u_axi4_master.axi_write_single(32'h0000_0050, 32'h0000_CAFE, 4'hF, 4'h7, wr_resp);
        check_eq(wr_resp, 2'b00, "Normal write after error: BRESP = OKAY");

        repeat (2) @(posedge clk);

        u_axi4_master.axi_read_single(32'h0000_0050, 4'h7, rd_data, rd_resp);
        check_eq(rd_resp, 2'b00, "Normal read after error: RRESP = OKAY");
        check_eq(rd_data, 32'h0000_CAFE, "Normal read data correct after error");

        repeat (2) @(posedge clk);
    endtask

    // =========================================================================
    // BRG-005: Address Decode
    // =========================================================================
    // Verify that paddr on the APB side matches the address provided on the
    // AXI4 side. Write to various addresses and read back to confirm correct
    // memory locations are accessed.
    task automatic test_address_decode();
        logic [1:0]            resp;
        logic [DATA_WIDTH-1:0] rd_data;

        test_begin("BRG-005: Address Decode");

        // Test address 0x000: word index 0
        u_axi4_master.axi_write_single(32'h0000_0000, 32'hAAAA_0000, 4'hF, 4'h8, resp);
        check_eq(resp, 2'b00, "Write to addr 0x000: BRESP = OKAY");
        repeat (2) @(posedge clk);

        // Test address 0x004: word index 1
        u_axi4_master.axi_write_single(32'h0000_0004, 32'hBBBB_0004, 4'hF, 4'h8, resp);
        check_eq(resp, 2'b00, "Write to addr 0x004: BRESP = OKAY");
        repeat (2) @(posedge clk);

        // Test address 0x100: word index 64
        u_axi4_master.axi_write_single(32'h0000_0100, 32'hCCCC_0100, 4'hF, 4'h8, resp);
        check_eq(resp, 2'b00, "Write to addr 0x100: BRESP = OKAY");
        repeat (2) @(posedge clk);

        // Test address 0x3FC: word index 255
        u_axi4_master.axi_write_single(32'h0000_03FC, 32'hDDDD_03FC, 4'hF, 4'h8, resp);
        check_eq(resp, 2'b00, "Write to addr 0x3FC: BRESP = OKAY");
        repeat (2) @(posedge clk);

        // Test address 0xFFC: word index 1023 (last valid word)
        u_axi4_master.axi_write_single(32'h0000_0FFC, 32'hEEEE_0FFC, 4'hF, 4'h8, resp);
        check_eq(resp, 2'b00, "Write to addr 0xFFC: BRESP = OKAY");
        repeat (2) @(posedge clk);

        // Read back each address and verify data integrity proves correct decode
        u_axi4_master.axi_read_single(32'h0000_0000, 4'h8, rd_data, resp);
        check_eq(rd_data, 32'hAAAA_0000, "Addr 0x000 decode correct");
        repeat (2) @(posedge clk);

        u_axi4_master.axi_read_single(32'h0000_0004, 4'h8, rd_data, resp);
        check_eq(rd_data, 32'hBBBB_0004, "Addr 0x004 decode correct");
        repeat (2) @(posedge clk);

        u_axi4_master.axi_read_single(32'h0000_0100, 4'h8, rd_data, resp);
        check_eq(rd_data, 32'hCCCC_0100, "Addr 0x100 decode correct");
        repeat (2) @(posedge clk);

        u_axi4_master.axi_read_single(32'h0000_03FC, 4'h8, rd_data, resp);
        check_eq(rd_data, 32'hDDDD_03FC, "Addr 0x3FC decode correct");
        repeat (2) @(posedge clk);

        u_axi4_master.axi_read_single(32'h0000_0FFC, 4'h8, rd_data, resp);
        check_eq(rd_data, 32'hEEEE_0FFC, "Addr 0xFFC decode correct");
        repeat (2) @(posedge clk);
    endtask

    // =========================================================================
    // BRG-006: Wait States (APB PREADY delay)
    // =========================================================================
    // Switch to the APB slave with WAIT_STATES=3 and verify the bridge
    // correctly waits for PREADY before completing the transaction.
    task automatic test_wait_states();
        logic [1:0]            resp;
        logic [DATA_WIDTH-1:0] rd_data;
        logic [DATA_WIDTH-1:0] wr_data;
        logic [ADDR_WIDTH-1:0] addr;

        test_begin("BRG-006: Wait States (PREADY delay)");

        // Switch to the wait-state slave (WAIT_STATES=3)
        slave_sel = 2'd1;
        repeat (2) @(posedge clk);

        // Step 1: Write data through bridge to wait-state slave
        addr    = 32'h0000_0040;   // word index = 16
        wr_data = 32'h1A17_DA7A;
        u_axi4_master.axi_write_single(addr, wr_data, 4'hF, 4'h9, resp);
        check_eq(resp, 2'b00, "Write with wait states: BRESP = OKAY");

        repeat (2) @(posedge clk);

        // Step 2: Read back through bridge from wait-state slave
        u_axi4_master.axi_read_single(addr, 4'h9, rd_data, resp);
        check_eq(resp, 2'b00, "Read with wait states: RRESP = OKAY");
        check_eq(rd_data, wr_data, "Read data correct with wait states");

        repeat (2) @(posedge clk);

        // Step 3: Multiple writes/reads with wait states to stress the bridge
        addr    = 32'h0000_0080;
        wr_data = 32'hFACE_B00C;
        u_axi4_master.axi_write_single(addr, wr_data, 4'hF, 4'hB, resp);
        check_eq(resp, 2'b00, "Write 2 with wait states: BRESP = OKAY");

        repeat (2) @(posedge clk);

        u_axi4_master.axi_read_single(addr, 4'hB, rd_data, resp);
        check_eq(resp, 2'b00, "Read 2 with wait states: RRESP = OKAY");
        check_eq(rd_data, wr_data, "Read 2 data correct with wait states");

        repeat (2) @(posedge clk);

        // Restore default slave
        slave_sel = 2'd0;
        repeat (2) @(posedge clk);
    endtask

endmodule
