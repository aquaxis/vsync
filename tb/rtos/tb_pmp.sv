// =============================================================================
// VSync - RTOS PMP (Physical Memory Protection) Testbench
// =============================================================================
// Tests: PMP-001 ~ PMP-006
//   PMP-001: Read permitted (NAPOT region)
//   PMP-002: Write forbidden
//   PMP-003: Execute forbidden
//   PMP-004: TOR/NAPOT/NA4 mode tests
//   PMP-005: Multiple region isolation
//   PMP-006: Lock bit protection
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_pmp;

    import test_utils::*;
    import vsync_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD    = 10;
    localparam RST_CYCLES    = 10;
    localparam NUM_PMP_ENTRY = 8;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // DUT interface signals
    logic        csr_pmpcfg_wr_tb;
    logic [0:0]  csr_pmpcfg_idx_tb;
    logic [31:0] csr_pmpcfg_wdata_tb;
    logic        csr_pmpaddr_wr_tb;
    logic [2:0]  csr_pmpaddr_idx_tb;
    logic [31:0] csr_pmpaddr_wdata_tb;
    logic [31:0] check_addr_tb;
    logic [2:0]  check_type_tb;
    logic        access_fault_out;

    // CSR read outputs - unpacked arrays for iverilog
    logic [31:0] pmpcfg_out_flat  [2];
    logic [31:0] pmpaddr_out_flat [8];

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
    pmp_unit #(
        .NUM_REGIONS (8),
        .XLEN        (32)
    ) u_dut (
        .clk               (clk),
        .rst_n              (rst_n),
        .csr_pmpcfg_wr      (csr_pmpcfg_wr_tb),
        .csr_pmpcfg_idx     (csr_pmpcfg_idx_tb),
        .csr_pmpcfg_wdata   (csr_pmpcfg_wdata_tb),
        .csr_pmpaddr_wr     (csr_pmpaddr_wr_tb),
        .csr_pmpaddr_idx    (csr_pmpaddr_idx_tb),
        .csr_pmpaddr_wdata  (csr_pmpaddr_wdata_tb),
        .check_addr         (check_addr_tb),
        .check_type         (check_type_tb),
        .access_fault       (access_fault_out),
        .pmpcfg_out         (pmpcfg_out_flat),
        .pmpaddr_out        (pmpaddr_out_flat)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_pmp.vcd");
        $dumpvars(0, tb_pmp);
    end

    // =========================================================================
    // Timeout watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 100000);
        $display("ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded maximum time");
    end

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        // Initialize signals
        csr_pmpcfg_wr_tb     = 1'b0;
        csr_pmpcfg_idx_tb    = 1'b0;
        csr_pmpcfg_wdata_tb  = 32'h0;
        csr_pmpaddr_wr_tb    = 1'b0;
        csr_pmpaddr_idx_tb   = 3'h0;
        csr_pmpaddr_wdata_tb = 32'h0;
        check_addr_tb        = 32'h0;
        check_type_tb        = 3'h0;

        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Helper tasks
    // =========================================================================

    /**
     * @brief Write a pmpcfg register (each holds 4 region configs)
     */
    task automatic write_pmpcfg(input logic [0:0] idx, input logic [31:0] data);
        @(posedge clk);
        csr_pmpcfg_wr_tb    <= 1'b1;
        csr_pmpcfg_idx_tb   <= idx;
        csr_pmpcfg_wdata_tb <= data;
        @(posedge clk);
        csr_pmpcfg_wr_tb    <= 1'b0;
        repeat (2) @(posedge clk);
    endtask

    /**
     * @brief Write a pmpaddr register
     */
    task automatic write_pmpaddr(input logic [2:0] idx, input logic [31:0] data);
        @(posedge clk);
        csr_pmpaddr_wr_tb    <= 1'b1;
        csr_pmpaddr_idx_tb   <= idx;
        csr_pmpaddr_wdata_tb <= data;
        @(posedge clk);
        csr_pmpaddr_wr_tb    <= 1'b0;
        repeat (2) @(posedge clk);
    endtask

    /**
     * @brief Check access and verify fault expectation
     */
    task automatic check_access(
        input logic [31:0] addr,
        input logic [2:0]  atype,
        input logic        expected_fault,
        input string       msg
    );
        check_addr_tb = addr;
        check_type_tb = atype;
        #1; // combinational settle
        check(access_fault_out == expected_fault, msg);
        check_addr_tb = 32'h0;
        check_type_tb = 3'h0;
    endtask

    /**
     * @brief Reset all PMP registers (write zeros to all cfg and addr)
     */
    task automatic reset_pmp_regs();
        write_pmpcfg(1'b0, 32'h0);
        write_pmpcfg(1'b1, 32'h0);
        write_pmpaddr(3'd0, 32'h0);
        write_pmpaddr(3'd1, 32'h0);
        write_pmpaddr(3'd2, 32'h0);
        write_pmpaddr(3'd3, 32'h0);
        write_pmpaddr(3'd4, 32'h0);
        write_pmpaddr(3'd5, 32'h0);
        write_pmpaddr(3'd6, 32'h0);
        write_pmpaddr(3'd7, 32'h0);
    endtask

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();
        test_suite_begin("RTOS PMP Protection Tests");

        test_pmp_001_read_napot();
        test_pmp_002_write_forbidden();
        test_pmp_003_execute_forbidden();
        test_pmp_004_addressing_modes();
        test_pmp_005_region_isolation();
        test_pmp_006_lock_bit();
    endtask

    // -------------------------------------------------------------------------
    // PMP-001: Read permitted in NAPOT region
    // -------------------------------------------------------------------------
    task automatic test_pmp_001_read_napot();
        test_begin("PMP-001: Read permitted in NAPOT region");

        reset_pmp_regs();

        // Configure region 0: NAPOT, R=1, W=1, X=0
        // pmpcfg byte: {L=0, 00, A=NAPOT(11), X=0, W=1, R=1} = 0x1B
        // 4KB region at 0x1000: pmpaddr = (0x1000>>2) | ((4096/2-1)>>2)
        //   = 0x400 | 0x1FF = 0x5FF
        write_pmpaddr(3'd0, 32'h0000_05FF);
        write_pmpcfg(1'b0, 32'h0000_001B);

        // Read inside region - should NOT fault
        check_access(32'h0000_1000, 3'b001, 1'b0, "PMP-001: Read at 0x1000 no fault");
        check_access(32'h0000_1800, 3'b001, 1'b0, "PMP-001: Read at 0x1800 no fault");

        // Write inside region - should NOT fault (W=1)
        check_access(32'h0000_1004, 3'b010, 1'b0, "PMP-001: Write at 0x1004 no fault");
    endtask

    // -------------------------------------------------------------------------
    // PMP-002: Write forbidden
    // -------------------------------------------------------------------------
    task automatic test_pmp_002_write_forbidden();
        test_begin("PMP-002: Write forbidden");

        reset_pmp_regs();

        // Configure region 0: NAPOT, R=1, W=0, X=0
        // pmpcfg: {L=0, 00, A=NAPOT(11), X=0, W=0, R=1} = 0x19
        write_pmpaddr(3'd0, 32'h0000_05FF);
        write_pmpcfg(1'b0, 32'h0000_0019);

        // Read inside - should NOT fault
        check_access(32'h0000_1000, 3'b001, 1'b0, "PMP-002: Read permitted");

        // Write inside - should fault (W=0)
        check_access(32'h0000_1000, 3'b010, 1'b1, "PMP-002: Write fault");
    endtask

    // -------------------------------------------------------------------------
    // PMP-003: Execute forbidden
    // -------------------------------------------------------------------------
    task automatic test_pmp_003_execute_forbidden();
        test_begin("PMP-003: Execute forbidden");

        reset_pmp_regs();

        // Configure region 0: NAPOT, R=1, W=1, X=0 = 0x1B
        write_pmpaddr(3'd0, 32'h0000_05FF);
        write_pmpcfg(1'b0, 32'h0000_001B);

        // Execute inside region - should fault (X=0)
        check_access(32'h0000_1000, 3'b100, 1'b1, "PMP-003: Execute fault");

        // Read inside - should NOT fault
        check_access(32'h0000_1000, 3'b001, 1'b0, "PMP-003: Read still permitted");

        // Now enable X: pmpcfg = {0,00,11,1,1,1} = 0x1F
        write_pmpcfg(1'b0, 32'h0000_001F);

        // Execute should now succeed
        check_access(32'h0000_1000, 3'b100, 1'b0, "PMP-003: Execute permitted with X=1");
    endtask

    // -------------------------------------------------------------------------
    // PMP-004: TOR/NAPOT/NA4 addressing modes
    // -------------------------------------------------------------------------
    task automatic test_pmp_004_addressing_modes();
        test_begin("PMP-004: TOR/NAPOT/NA4 modes");

        // --- TOR mode test ---
        reset_pmp_regs();

        // TOR: region 1 covers [pmpaddr[0], pmpaddr[1])
        // pmpaddr[0] = 0x1000>>2 = 0x0400
        // pmpaddr[1] = 0x2000>>2 = 0x0800
        // cfg[0] = OFF, cfg[1] = TOR, R=1, W=1, X=1 = {0,00,01,1,1,1} = 0x0F
        write_pmpaddr(3'd0, 32'h0000_0400);
        write_pmpaddr(3'd1, 32'h0000_0800);
        // pmpcfg0: byte0=region0(OFF=0x00), byte1=region1(TOR,RWX=0x0F)
        write_pmpcfg(1'b0, 32'h0000_0F00);

        // Inside TOR range [0x1000, 0x2000)
        check_access(32'h0000_1000, 3'b001, 1'b0, "PMP-004: TOR read 0x1000 no fault");
        check_access(32'h0000_1FFC, 3'b001, 1'b0, "PMP-004: TOR read 0x1FFC no fault");

        // --- NA4 mode test ---
        reset_pmp_regs();

        // NA4: exactly 4 bytes at address 0x3000
        // pmpaddr = 0x3000 >> 2 = 0x0C00
        // cfg: {0,00,10,1,1,1} = 0x17
        write_pmpaddr(3'd0, 32'h0000_0C00);
        write_pmpcfg(1'b0, 32'h0000_0017);

        // Exact match 0x3000
        check_access(32'h0000_3000, 3'b001, 1'b0, "PMP-004: NA4 read 0x3000 no fault");

        // Adjacent address should NOT match (no region match -> no fault in M-mode)
        check_access(32'h0000_3004, 3'b001, 1'b0, "PMP-004: NA4 0x3004 no match no fault");

        // --- NAPOT mode test (4KB at 0x4000) ---
        reset_pmp_regs();

        // 4KB NAPOT at 0x4000
        // pmpaddr = (0x4000>>2) | ((4096/2 - 1)>>2) = 0x1000 | 0x1FF = 0x11FF
        write_pmpaddr(3'd0, 32'h0000_11FF);
        // cfg: NAPOT, R=1, W=0, X=0 = {0,00,11,0,0,1} = 0x19
        write_pmpcfg(1'b0, 32'h0000_0019);

        // Read inside - no fault
        check_access(32'h0000_4000, 3'b001, 1'b0, "PMP-004: NAPOT read 0x4000 no fault");

        // Write inside - should fault (W=0)
        check_access(32'h0000_4000, 3'b010, 1'b1, "PMP-004: NAPOT write 0x4000 fault");
    endtask

    // -------------------------------------------------------------------------
    // PMP-005: Multiple region isolation
    // -------------------------------------------------------------------------
    task automatic test_pmp_005_region_isolation();
        test_begin("PMP-005: Region isolation");

        reset_pmp_regs();

        // Region 0: 0x1000-0x1FFF, NAPOT, R=1, W=1, X=0 (0x1B)
        write_pmpaddr(3'd0, 32'h0000_05FF);

        // Region 1: 0x2000-0x2FFF, NAPOT, R=1, W=0, X=0 (0x19)
        write_pmpaddr(3'd1, 32'h0000_09FF);

        // pmpcfg0: byte0=region0(0x1B), byte1=region1(0x19)
        write_pmpcfg(1'b0, 32'h0000_191B);

        // Region 0: RW allowed
        check_access(32'h0000_1000, 3'b001, 1'b0, "PMP-005: region0 read OK");
        check_access(32'h0000_1000, 3'b010, 1'b0, "PMP-005: region0 write OK");

        // Region 1: R allowed, W fault
        check_access(32'h0000_2000, 3'b001, 1'b0, "PMP-005: region1 read OK");
        check_access(32'h0000_2000, 3'b010, 1'b1, "PMP-005: region1 write fault");
    endtask

    // -------------------------------------------------------------------------
    // PMP-006: Lock bit protection
    // -------------------------------------------------------------------------
    // Verify lock by functional behavior: locked region permissions should
    // persist after rewrite attempt.
    task automatic test_pmp_006_lock_bit();
        test_begin("PMP-006: Lock bit");

        reset_pmp_regs();

        // Configure region 0: NAPOT 4KB at 0x1000, R=1, W=1, X=1, L=1 (locked)
        // pmpcfg: {L=1, 00, A=NAPOT(11), X=1, W=1, R=1} = 0x9F
        write_pmpaddr(3'd0, 32'h0000_05FF);
        write_pmpcfg(1'b0, 32'h0000_009F);

        // Verify original permissions: RWX all allowed
        check_access(32'h0000_1000, 3'b001, 1'b0, "PMP-006: locked read OK before rewrite");
        check_access(32'h0000_1000, 3'b010, 1'b0, "PMP-006: locked write OK before rewrite");
        check_access(32'h0000_1000, 3'b100, 1'b0, "PMP-006: locked exec OK before rewrite");

        // Try to rewrite pmpcfg to R-only (W=0, X=0): 0x19
        // This should be blocked because L=1
        write_pmpcfg(1'b0, 32'h0000_0019);

        // Verify permissions unchanged: RWX still allowed (lock prevented rewrite)
        check_access(32'h0000_1000, 3'b001, 1'b0, "PMP-006: locked read OK after rewrite attempt");
        check_access(32'h0000_1000, 3'b010, 1'b0, "PMP-006: locked write OK after rewrite attempt");
        check_access(32'h0000_1000, 3'b100, 1'b0, "PMP-006: locked exec OK after rewrite attempt");
    endtask

endmodule
