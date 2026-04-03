// =============================================================================
// VSync - BRAM Test Bench
// =============================================================================
// Test IDs: BRAM-001 ~ BRAM-006
// - BRAM-001: Instruction memory read (fetch)
// - BRAM-002: Data memory R/W (word/halfword/byte)
// - BRAM-003: Boundary address R/W
// - BRAM-004: Continuous access (back-to-back)
// - BRAM-005: Simultaneous access (instruction fetch + data access conflict)
// - BRAM-006: Initialization verification
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_bram;

    import test_utils::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD  = 10;
    localparam RST_CYCLES  = 10;

    // Small sizes for testing
    localparam IMEM_DEPTH  = 256;
    localparam IMEM_AW     = 8;
    localparam DMEM_DEPTH  = 256;
    localparam DMEM_AW     = 8;
    localparam DATA_WIDTH  = 32;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // Instruction port A (read-only fetch)
    logic [IMEM_AW-1:0]    imem_addr;
    logic [DATA_WIDTH-1:0]  imem_rdata;
    logic                   imem_valid;

    // Instruction port B (data bus R/W)
    logic [IMEM_AW-1:0]    imem_b_addr;
    logic [DATA_WIDTH-1:0]  imem_b_wdata;
    logic [DATA_WIDTH-1:0]  imem_b_rdata;
    logic [3:0]             imem_b_be;
    logic                   imem_b_en;
    logic                   imem_b_we;

    // Data port (read/write)
    logic [DMEM_AW-1:0]    dmem_addr;
    logic [DATA_WIDTH-1:0]  dmem_wdata;
    logic [DATA_WIDTH-1:0]  dmem_rdata;
    logic [3:0]             dmem_wstrb;
    logic                   dmem_read;
    logic                   dmem_write;

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
    bram_imem #(
        .DEPTH      (IMEM_DEPTH),
        .ADDR_WIDTH (IMEM_AW)
    ) u_imem (
        .clk     (clk),
        // Port A - Instruction Fetch (read-only)
        .a_en    (imem_valid),
        .a_addr  (imem_addr),
        .a_rdata (imem_rdata),
        // Port B - Data Bus Access (read/write)
        .b_en    (imem_b_en),
        .b_we    (imem_b_we),
        .b_be    (imem_b_be),
        .b_addr  (imem_b_addr),
        .b_wdata (imem_b_wdata),
        .b_rdata (imem_b_rdata)
    );

    bram_dmem #(
        .DEPTH      (DMEM_DEPTH),
        .ADDR_WIDTH (DMEM_AW)
    ) u_dmem (
        .clk   (clk),
        .addr  (dmem_addr),
        .wdata (dmem_wdata),
        .we    (dmem_write),
        .be    (dmem_wstrb),
        .re    (dmem_read),
        .rdata (dmem_rdata)
    );

    // =========================================================================
    // Pre-initialize instruction memory for tests
    // =========================================================================
    initial begin
        u_imem.mem[0] = 32'hDEADBEEF;
        u_imem.mem[1] = 32'hCAFEBABE;
        u_imem.mem[2] = 32'h12345678;
        u_imem.mem[3] = 32'h9ABCDEF0;
        u_imem.mem[4] = 32'h00000001;
        u_imem.mem[5] = 32'hFFFFFFFF;
        u_imem.mem[6] = 32'h55AA55AA;
        u_imem.mem[7] = 32'hAA55AA55;
    end

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_bram.vcd");
        $dumpvars(0, tb_bram);
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
        // Initialize signals
        imem_addr    = '0;
        imem_valid   = 1'b0;
        imem_b_addr  = '0;
        imem_b_wdata = '0;
        imem_b_be    = '0;
        imem_b_en    = 1'b0;
        imem_b_we    = 1'b0;
        dmem_addr    = '0;
        dmem_wdata   = '0;
        dmem_wstrb   = '0;
        dmem_read    = 1'b0;
        dmem_write   = 1'b0;

        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("BRAM Tests");

        test_instruction_read();
        test_data_rw();
        test_boundary_address();
        test_continuous_access();
        test_simultaneous_access();
        test_initialization();

    endtask

    // =========================================================================
    // Helper Tasks
    // =========================================================================
    // Timing convention: set signals shortly after posedge (#1 delay)
    // so they are stable well before the next posedge where BRAM samples them.
    // After the sampling posedge, wait #1 for NBA to settle, then read output.

    /** Read from instruction memory (1-cycle latency) */
    task automatic imem_do_read(
        input  logic [IMEM_AW-1:0]   addr,
        output logic [DATA_WIDTH-1:0] data
    );
        @(posedge clk);
        #1;
        imem_addr  = addr;
        imem_valid = 1'b1;
        @(posedge clk);    // BRAM registers: rdata <= mem[addr]
        #1;                // Let NBA settle
        imem_valid = 1'b0;
        data = imem_rdata;
    endtask

    /** Write to data memory (1-cycle latency) */
    task automatic dmem_do_write(
        input logic [DMEM_AW-1:0]   addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic [3:0]            strb
    );
        @(posedge clk);
        #1;
        dmem_addr  = addr;
        dmem_wdata = data;
        dmem_wstrb = strb;
        dmem_write = 1'b1;
        dmem_read  = 1'b0;
        @(posedge clk);    // Write takes effect at this edge
        #1;
        dmem_write = 1'b0;
        dmem_wstrb = 4'b0000;
    endtask

    /** Read from data memory (1-cycle latency) */
    task automatic dmem_do_read(
        input  logic [DMEM_AW-1:0]   addr,
        output logic [DATA_WIDTH-1:0] data
    );
        @(posedge clk);
        #1;
        dmem_addr  = addr;
        dmem_read  = 1'b1;
        dmem_write = 1'b0;
        @(posedge clk);    // BRAM registers: rdata <= mem[addr]
        #1;                // Let NBA settle
        dmem_read  = 1'b0;
        data = dmem_rdata;
    endtask

    // =========================================================================
    // BRAM-001: Instruction Memory Read (Fetch)
    // =========================================================================
    task automatic test_instruction_read();
        logic [DATA_WIDTH-1:0] rdata;
        logic [DATA_WIDTH-1:0] expected [0:7];

        test_begin("BRAM-001: Instruction Memory Read (Fetch)");

        expected[0] = 32'hDEADBEEF;
        expected[1] = 32'hCAFEBABE;
        expected[2] = 32'h12345678;
        expected[3] = 32'h9ABCDEF0;
        expected[4] = 32'h00000001;
        expected[5] = 32'hFFFFFFFF;
        expected[6] = 32'h55AA55AA;
        expected[7] = 32'hAA55AA55;

        // Read sequential addresses and verify 1-cycle read latency
        for (int i = 0; i < 8; i++) begin
            imem_do_read(i[IMEM_AW-1:0], rdata);
            check_eq(rdata, expected[i], $sformatf("imem[%0d]", i));
        end

        // Verify disable: when en=0, rdata should hold previous value
        @(posedge clk);
        #1;
        imem_addr  = 8'd0;
        imem_valid = 1'b0;
        @(posedge clk);
        #1;
        // rdata should still hold the last read value (addr 7 = 0xAA55AA55)
        check_eq(imem_rdata, 32'hAA55AA55, "en=0 holds last value");
    endtask

    // =========================================================================
    // BRAM-002: Data Memory R/W (Word/Halfword/Byte)
    // =========================================================================
    task automatic test_data_rw();
        logic [DATA_WIDTH-1:0] rdata;

        test_begin("BRAM-002: Data Memory R/W (Word/Halfword/Byte)");

        // --- Word write/read ---
        dmem_do_write(8'd0, 32'hCAFEBABE, 4'b1111);
        dmem_do_read(8'd0, rdata);
        check_eq(rdata, 32'hCAFEBABE, "Word write/read addr=0");

        // --- Halfword write: lower half (be=0011) ---
        // First write a full word
        dmem_do_write(8'd1, 32'hAAAABBBB, 4'b1111);
        // Now write only lower halfword
        dmem_do_write(8'd1, 32'h0000ABCD, 4'b0011);
        dmem_do_read(8'd1, rdata);
        check_eq(rdata, 32'hAAAA_ABCD, "Halfword write lower (be=0011): upper unchanged");

        // --- Halfword write: upper half (be=1100) ---
        dmem_do_write(8'd1, 32'h12340000, 4'b1100);
        dmem_do_read(8'd1, rdata);
        check_eq(rdata, 32'h1234_ABCD, "Halfword write upper (be=1100): lower unchanged");

        // --- Byte write: byte 0 (be=0001) ---
        dmem_do_write(8'd2, 32'h00000000, 4'b1111);  // Clear first
        dmem_do_write(8'd2, 32'h000000FF, 4'b0001);
        dmem_do_read(8'd2, rdata);
        check_eq(rdata, 32'h000000FF, "Byte write byte0 (be=0001)");

        // --- Byte write: byte 1 (be=0010) ---
        dmem_do_write(8'd2, 32'h0000EE00, 4'b0010);
        dmem_do_read(8'd2, rdata);
        check_eq(rdata, 32'h0000EEFF, "Byte write byte1 (be=0010): byte0 unchanged");

        // --- Byte write: byte 2 (be=0100) ---
        dmem_do_write(8'd2, 32'h00DD0000, 4'b0100);
        dmem_do_read(8'd2, rdata);
        check_eq(rdata, 32'h00DDEEFF, "Byte write byte2 (be=0100): bytes 0-1 unchanged");

        // --- Byte write: byte 3 (be=1000) ---
        dmem_do_write(8'd2, 32'hCC000000, 4'b1000);
        dmem_do_read(8'd2, rdata);
        check_eq(rdata, 32'hCCDDEEFF, "Byte write byte3 (be=1000): bytes 0-2 unchanged");

        // --- Write with all zeros strobe (no write) ---
        dmem_do_write(8'd2, 32'h11111111, 4'b0000);
        dmem_do_read(8'd2, rdata);
        check_eq(rdata, 32'hCCDDEEFF, "be=0000 no write occurs");
    endtask

    // =========================================================================
    // BRAM-003: Boundary Address R/W
    // =========================================================================
    task automatic test_boundary_address();
        logic [DATA_WIDTH-1:0] rdata;

        test_begin("BRAM-003: Boundary Address R/W");

        // --- R/W at address 0 ---
        dmem_do_write(8'd0, 32'h11223344, 4'b1111);
        dmem_do_read(8'd0, rdata);
        check_eq(rdata, 32'h11223344, "Write/Read addr=0");

        // --- R/W at address DMEM_DEPTH-1 (255) ---
        dmem_do_write(DMEM_DEPTH - 1, 32'hAABBCCDD, 4'b1111);
        dmem_do_read(DMEM_DEPTH - 1, rdata);
        check_eq(rdata, 32'hAABBCCDD, "Write/Read addr=DMEM_DEPTH-1 (255)");

        // --- Verify addr 0 is not corrupted by addr 255 write ---
        dmem_do_read(8'd0, rdata);
        check_eq(rdata, 32'h11223344, "addr=0 unchanged after addr=255 write");

        // --- Instruction memory boundary ---
        imem_do_read(8'd0, rdata);
        check_eq(rdata, 32'hDEADBEEF, "imem addr=0 read");

        imem_do_read(8'd7, rdata);
        check_eq(rdata, 32'hAA55AA55, "imem addr=7 read");
    endtask

    // =========================================================================
    // BRAM-004: Continuous (Back-to-Back) Access
    // =========================================================================
    task automatic test_continuous_access();
        logic [DATA_WIDTH-1:0] rdata;
        logic [DATA_WIDTH-1:0] expected_data [0:3];

        test_begin("BRAM-004: Continuous (Back-to-Back) Access");

        expected_data[0] = 32'hAAAA0000;
        expected_data[1] = 32'hBBBB1111;
        expected_data[2] = 32'hCCCC2222;
        expected_data[3] = 32'hDDDD3333;

        // --- Back-to-back writes: write to addr 10,11,12,13 consecutively ---
        // Each write occupies one clock cycle
        for (int i = 0; i < 4; i++) begin
            @(posedge clk);
            #1;
            dmem_addr  = 8'd10 + i[DMEM_AW-1:0];
            dmem_wdata = expected_data[i];
            dmem_wstrb = 4'b1111;
            dmem_write = 1'b1;
            dmem_read  = 1'b0;
        end
        @(posedge clk);  // Let last write take effect
        #1;
        dmem_write = 1'b0;
        dmem_wstrb = 4'b0000;

        // --- Back-to-back reads: read addr 10,11,12,13 consecutively ---
        for (int i = 0; i < 4; i++) begin
            dmem_do_read(8'd10 + i[DMEM_AW-1:0], rdata);
            check_eq(rdata, expected_data[i], $sformatf("Back-to-back read addr=%0d", 10 + i));
        end
    endtask

    // =========================================================================
    // BRAM-005: Simultaneous Access (Instruction + Data)
    // =========================================================================
    task automatic test_simultaneous_access();
        logic [DATA_WIDTH-1:0] imem_data;
        logic [DATA_WIDTH-1:0] dmem_data;

        test_begin("BRAM-005: Simultaneous Access (Instruction + Data)");

        // Pre-write a known value to dmem
        dmem_do_write(8'd20, 32'hFACEFACE, 4'b1111);

        // Simultaneous: imem read + dmem read in same cycle
        @(posedge clk);
        #1;
        imem_addr  = 8'd0;
        imem_valid = 1'b1;
        dmem_addr  = 8'd20;
        dmem_read  = 1'b1;
        dmem_write = 1'b0;

        @(posedge clk);    // Both BRAMs register
        #1;
        imem_valid = 1'b0;
        dmem_read  = 1'b0;

        imem_data = imem_rdata;
        dmem_data = dmem_rdata;

        check_eq(imem_data, 32'hDEADBEEF, "Simultaneous: imem read correct");
        check_eq(dmem_data, 32'hFACEFACE, "Simultaneous: dmem read correct");

        // Simultaneous: imem read + dmem write in same cycle
        @(posedge clk);
        #1;
        imem_addr  = 8'd1;
        imem_valid = 1'b1;
        dmem_addr  = 8'd21;
        dmem_wdata = 32'hBEEFBEEF;
        dmem_wstrb = 4'b1111;
        dmem_write = 1'b1;
        dmem_read  = 1'b0;

        @(posedge clk);    // Both register
        #1;
        imem_valid = 1'b0;
        dmem_write = 1'b0;
        dmem_wstrb = 4'b0000;

        check_eq(imem_rdata, 32'hCAFEBABE, "Simultaneous: imem read during dmem write");

        // Verify dmem write succeeded
        dmem_do_read(8'd21, dmem_data);
        check_eq(dmem_data, 32'hBEEFBEEF, "Simultaneous: dmem write correct");
    endtask

    // =========================================================================
    // BRAM-006: Initialization Verification
    // =========================================================================
    task automatic test_initialization();
        logic [DATA_WIDTH-1:0] rdata;

        test_begin("BRAM-006: Initialization Verification");

        // Write known values to dmem
        dmem_do_write(8'd50, 32'h12345678, 4'b1111);
        dmem_do_write(8'd51, 32'h9ABCDEF0, 4'b1111);

        // Read them back to confirm persistence
        dmem_do_read(8'd50, rdata);
        check_eq(rdata, 32'h12345678, "dmem persistence check addr=50");

        dmem_do_read(8'd51, rdata);
        check_eq(rdata, 32'h9ABCDEF0, "dmem persistence check addr=51");

        // Verify imem initial values still intact after all tests
        imem_do_read(8'd0, rdata);
        check_eq(rdata, 32'hDEADBEEF, "imem[0] still intact");

        imem_do_read(8'd3, rdata);
        check_eq(rdata, 32'h9ABCDEF0, "imem[3] still intact");

        imem_do_read(8'd7, rdata);
        check_eq(rdata, 32'hAA55AA55, "imem[7] still intact");
    endtask

endmodule
