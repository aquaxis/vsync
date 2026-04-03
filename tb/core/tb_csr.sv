// =============================================================================
// VSync - CSR (Control and Status Register) Test Bench
// =============================================================================
// Test IDs: CSR-001 ~ CSR-011
// - CSR-001: CSRRW/CSRRWI
// - CSR-002: CSRRS/CSRRSI
// - CSR-003: CSRRC/CSRRCI
// - CSR-004: mstatus
// - CSR-005: mtvec
// - CSR-006: mepc
// - CSR-007: mcause
// - CSR-008: mtval
// - CSR-009: mie/mip
// - CSR-010: mcycle/minstret
// - CSR-011: Invalid CSR access
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_csr;

    import test_utils::*;
    import vsync_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD = 10;
    localparam RST_CYCLES = 10;

    // CSR Addresses (local aliases for readability)
    localparam [11:0] ADDR_MSTATUS  = 12'h300;
    localparam [11:0] ADDR_MISA     = 12'h301;
    localparam [11:0] ADDR_MIE      = 12'h304;
    localparam [11:0] ADDR_MTVEC    = 12'h305;
    localparam [11:0] ADDR_MSCRATCH = 12'h340;
    localparam [11:0] ADDR_MEPC     = 12'h341;
    localparam [11:0] ADDR_MCAUSE   = 12'h342;
    localparam [11:0] ADDR_MTVAL    = 12'h343;
    localparam [11:0] ADDR_MIP      = 12'h344;
    localparam [11:0] ADDR_MCYCLE   = 12'hB00;
    localparam [11:0] ADDR_MINSTRET = 12'hB02;
    localparam [11:0] ADDR_MCYCLEH  = 12'hB80;
    localparam [11:0] ADDR_MINSTRETH= 12'hB82;

    // CSR operations
    localparam [1:0] CSR_NOP = 2'b00;
    localparam [1:0] CSR_RW  = 2'b01;
    localparam [1:0] CSR_RS  = 2'b10;
    localparam [1:0] CSR_RC  = 2'b11;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // CSR interface signals
    logic [11:0]       csr_addr;
    logic [XLEN-1:0]  csr_wdata;
    logic [1:0]        csr_op;
    logic              csr_en;
    logic              csr_imm;

    // Exception/interrupt interface
    logic              exception_taken;
    logic [XLEN-1:0]  exception_cause;
    logic [XLEN-1:0]  exception_pc;
    logic [XLEN-1:0]  exception_val;
    logic              mret;

    // Performance counter
    logic              retire_valid;

    // External interrupt sources
    logic              ext_irq;
    logic              timer_irq;
    logic              sw_irq;

    // CSR outputs
    logic [XLEN-1:0]  csr_rdata;
    logic [XLEN-1:0]  mtvec_out;
    logic [XLEN-1:0]  mepc_out;
    logic [XLEN-1:0]  mie_out;
    logic              mstatus_mie_out;
    logic              trap_pending;

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
    csr_unit u_csr (
        .clk              (clk),
        .rst_n            (rst_n),
        .csr_addr         (csr_addr),
        .csr_wdata        (csr_wdata),
        .csr_op           (csr_op),
        .csr_en           (csr_en),
        .csr_imm          (csr_imm),
        .exception_taken  (exception_taken),
        .exception_cause  (exception_cause),
        .exception_pc     (exception_pc),
        .exception_val    (exception_val),
        .mret             (mret),
        .retire_valid     (retire_valid),
        .ext_irq          (ext_irq),
        .timer_irq        (timer_irq),
        .sw_irq           (sw_irq),
        .csr_rdata        (csr_rdata),
        .mtvec            (mtvec_out),
        .mepc             (mepc_out),
        .mie_out          (mie_out),
        .mstatus_mie      (mstatus_mie_out),
        .trap_pending     (trap_pending)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_csr.vcd");
        $dumpvars(0, tb_csr);
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
    // Helper tasks
    // =========================================================================

    /** Reset all CSR input signals to default inactive state */
    task automatic reset_inputs();
        csr_addr         = 12'h0;
        csr_wdata        = 32'h0;
        csr_op           = CSR_NOP;
        csr_en           = 1'b0;
        csr_imm          = 1'b0;
        exception_taken  = 1'b0;
        exception_cause  = 32'h0;
        exception_pc     = 32'h0;
        exception_val    = 32'h0;
        mret             = 1'b0;
        retire_valid     = 1'b0;
        ext_irq          = 1'b0;
        timer_irq        = 1'b0;
        sw_irq           = 1'b0;
    endtask

    /** Perform a CSR write operation and capture the old read value.
     *  Asserts csr_en for exactly one clock cycle.
     */
    task automatic csr_write(
        input  logic [11:0]       addr,
        input  logic [XLEN-1:0]  wdata,
        input  logic [1:0]        op,
        input  logic              imm_mode,
        output logic [XLEN-1:0]  old_val
    );
        @(posedge clk);
        csr_addr  = addr;
        csr_wdata = wdata;
        csr_op    = op;
        csr_en    = 1'b1;
        csr_imm   = imm_mode;
        // Read the old value on the same cycle (combinational read)
        #1;
        old_val = csr_rdata;
        @(posedge clk);
        csr_en  = 1'b0;
        csr_op  = CSR_NOP;
    endtask

    /** Read a CSR register (CSRRS with wdata=0, which is read-only) */
    task automatic csr_read(
        input  logic [11:0]       addr,
        output logic [XLEN-1:0]  rdata
    );
        @(posedge clk);
        csr_addr  = addr;
        csr_wdata = 32'h0;
        csr_op    = CSR_RS;  // RS with 0 = read only
        csr_en    = 1'b1;
        csr_imm   = 1'b0;
        #1;
        rdata = csr_rdata;
        @(posedge clk);
        csr_en  = 1'b0;
        csr_op  = CSR_NOP;
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        reset_inputs();
        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("CSR Read/Write Tests");

        // === CSR-001: CSRRW/CSRRWI ===
        test_csrrw();
        test_csrrwi();

        // === CSR-002: CSRRS/CSRRSI ===
        test_csrrs();
        test_csrrsi();

        // === CSR-003: CSRRC/CSRRCI ===
        test_csrrc();
        test_csrrci();

        // === CSR-004: mstatus ===
        test_mstatus();

        // === CSR-005: mtvec ===
        test_mtvec();

        // === CSR-006: mepc ===
        test_mepc();

        // === CSR-007: mcause ===
        test_mcause();

        // === CSR-008: mtval ===
        test_mtval();

        // === CSR-009: mie/mip ===
        test_mie_mip();

        // === CSR-010: mcycle/minstret ===
        test_mcycle();
        test_minstret();

        // === CSR-011: Invalid CSR access ===
        test_invalid_csr_access();

    endtask

    // =========================================================================
    // CSR-001: CSRRW / CSRRWI
    // =========================================================================

    task automatic test_csrrw();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-001: CSRRW");

        // Write 0xDEADBEEF to mscratch via CSRRW
        csr_write(ADDR_MSCRATCH, 32'hDEADBEEF, CSR_RW, 1'b0, old_val);
        check_eq(old_val, 32'h0, "CSRRW: old value of mscratch should be 0 after reset");

        // Read back mscratch to verify new value
        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'hDEADBEEF, "CSRRW: mscratch should now be 0xDEADBEEF");

        // Write again - swap: old value should be 0xDEADBEEF
        csr_write(ADDR_MSCRATCH, 32'hCAFEBABE, CSR_RW, 1'b0, old_val);
        check_eq(old_val, 32'hDEADBEEF, "CSRRW: swap - old value should be 0xDEADBEEF");

        // Verify new value
        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'hCAFEBABE, "CSRRW: mscratch should now be 0xCAFEBABE");

        // Clean up
        csr_write(ADDR_MSCRATCH, 32'h0, CSR_RW, 1'b0, old_val);
    endtask

    task automatic test_csrrwi();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-001: CSRRWI");

        // CSRRWI: use 5-bit zero-extended immediate (csr_imm=1)
        // Write zimm=5'b10101 (=21) to mscratch
        csr_write(ADDR_MSCRATCH, 32'h00000015, CSR_RW, 1'b1, old_val);

        // Read back - should be zero-extended 5-bit value = 21
        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'd21, "CSRRWI: mscratch should be 21 (5-bit zimm zero-extended)");

        // Write zimm=0 to clear
        csr_write(ADDR_MSCRATCH, 32'h0, CSR_RW, 1'b1, old_val);
        check_eq(old_val, 32'd21, "CSRRWI: old value should be 21");

        // Verify zimm=31 (max 5-bit value)
        csr_write(ADDR_MSCRATCH, 32'h0000001F, CSR_RW, 1'b1, old_val);
        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'd31, "CSRRWI: mscratch should be 31 (max zimm)");

        // Clean up
        csr_write(ADDR_MSCRATCH, 32'h0, CSR_RW, 1'b0, old_val);
    endtask

    // =========================================================================
    // CSR-002: CSRRS / CSRRSI
    // =========================================================================

    task automatic test_csrrs();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-002: CSRRS");

        // First, clear mscratch
        csr_write(ADDR_MSCRATCH, 32'h0, CSR_RW, 1'b0, old_val);

        // Set some bits via CSRRS
        csr_write(ADDR_MSCRATCH, 32'h0000FF00, CSR_RS, 1'b0, old_val);
        check_eq(old_val, 32'h0, "CSRRS: old value should be 0");

        // Read back - bits should be set
        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'h0000FF00, "CSRRS: mscratch should have bits [15:8] set");

        // Set more bits - should OR with existing
        csr_write(ADDR_MSCRATCH, 32'hFF000000, CSR_RS, 1'b0, old_val);
        check_eq(old_val, 32'h0000FF00, "CSRRS: old value should be 0x0000FF00");

        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'hFF00FF00, "CSRRS: mscratch should have bits [31:24] and [15:8] set");

        // CSRRS with wdata=0 should be read-only (no write)
        csr_write(ADDR_MSCRATCH, 32'h0, CSR_RS, 1'b0, old_val);
        check_eq(old_val, 32'hFF00FF00, "CSRRS with 0: read-only, old value unchanged");

        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'hFF00FF00, "CSRRS with 0: value should remain unchanged");

        // Clean up
        csr_write(ADDR_MSCRATCH, 32'h0, CSR_RW, 1'b0, old_val);
    endtask

    task automatic test_csrrsi();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-002: CSRRSI");

        // Clear mscratch
        csr_write(ADDR_MSCRATCH, 32'h0, CSR_RW, 1'b0, old_val);

        // Set bits using 5-bit immediate (zimm=0b10101 = 21 = 0x15)
        csr_write(ADDR_MSCRATCH, 32'h15, CSR_RS, 1'b1, old_val);
        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'h00000015, "CSRRSI: bits set via 5-bit zimm");

        // Clean up
        csr_write(ADDR_MSCRATCH, 32'h0, CSR_RW, 1'b0, old_val);
    endtask

    // =========================================================================
    // CSR-003: CSRRC / CSRRCI
    // =========================================================================

    task automatic test_csrrc();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-003: CSRRC");

        // Write all ones to mscratch
        csr_write(ADDR_MSCRATCH, 32'hFFFFFFFF, CSR_RW, 1'b0, old_val);

        // Clear some bits via CSRRC
        csr_write(ADDR_MSCRATCH, 32'h0000FFFF, CSR_RC, 1'b0, old_val);
        check_eq(old_val, 32'hFFFFFFFF, "CSRRC: old value should be all ones");

        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'hFFFF0000, "CSRRC: lower 16 bits should be cleared");

        // Clear more bits
        csr_write(ADDR_MSCRATCH, 32'hFF000000, CSR_RC, 1'b0, old_val);
        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'h00FF0000, "CSRRC: only bits [23:16] should remain");

        // CSRRC with wdata=0 should be read-only
        csr_write(ADDR_MSCRATCH, 32'h0, CSR_RC, 1'b0, old_val);
        check_eq(old_val, 32'h00FF0000, "CSRRC with 0: read-only");
        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'h00FF0000, "CSRRC with 0: value unchanged");

        // Clean up
        csr_write(ADDR_MSCRATCH, 32'h0, CSR_RW, 1'b0, old_val);
    endtask

    task automatic test_csrrci();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-003: CSRRCI");

        // Write all ones to mscratch
        csr_write(ADDR_MSCRATCH, 32'hFFFFFFFF, CSR_RW, 1'b0, old_val);

        // Clear bits using 5-bit zimm = 0b11111 = 31 = 0x1F
        csr_write(ADDR_MSCRATCH, 32'h1F, CSR_RC, 1'b1, old_val);
        csr_read(ADDR_MSCRATCH, read_val);
        check_eq(read_val, 32'hFFFFFFE0, "CSRRCI: lower 5 bits cleared via zimm");

        // Clean up
        csr_write(ADDR_MSCRATCH, 32'h0, CSR_RW, 1'b0, old_val);
    endtask

    // =========================================================================
    // CSR-004 ~ CSR-010: Specific CSR Tests
    // =========================================================================

    task automatic test_mstatus();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-004: mstatus Register");

        // After reset, MIE=0, MPIE=0
        csr_read(ADDR_MSTATUS, read_val);
        check(read_val[3] === 1'b0, "mstatus: MIE=0 after reset");
        check(read_val[7] === 1'b0, "mstatus: MPIE=0 after reset");
        check(read_val[12:11] === 2'b11, "mstatus: MPP=11 (M-mode always)");

        // Set MIE bit (bit 3)
        csr_write(ADDR_MSTATUS, 32'h00000008, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MSTATUS, read_val);
        check(read_val[3] === 1'b1, "mstatus: MIE=1 after write");
        check(mstatus_mie_out === 1'b1, "mstatus_mie output should be 1");

        // Set MPIE bit (bit 7)
        csr_write(ADDR_MSTATUS, 32'h00000088, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MSTATUS, read_val);
        check(read_val[3] === 1'b1, "mstatus: MIE still 1");
        check(read_val[7] === 1'b1, "mstatus: MPIE=1 after write");

        // MPP should always read as 2'b11 (M-mode only implementation)
        check(read_val[12:11] === 2'b11, "mstatus: MPP always 11");

        // Clear MIE
        csr_write(ADDR_MSTATUS, 32'h00000080, CSR_RW, 1'b0, old_val);
        @(posedge clk); // Wait for registered output to update
        #1;
        check(mstatus_mie_out === 1'b0, "mstatus_mie output should be 0 after clearing MIE");

        // Clean up
        csr_write(ADDR_MSTATUS, 32'h0, CSR_RW, 1'b0, old_val);
    endtask

    task automatic test_mtvec();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-005: mtvec (Trap Vector)");

        // Write trap vector base address (aligned)
        csr_write(ADDR_MTVEC, 32'h00001000, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MTVEC, read_val);
        check_eq(read_val, 32'h00001000, "mtvec: write/read 0x1000");
        check_eq(mtvec_out, 32'h00001000, "mtvec output port matches");

        // Write with MODE=01 (vectored)
        csr_write(ADDR_MTVEC, 32'h00002001, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MTVEC, read_val);
        check_eq(read_val, 32'h00002001, "mtvec: vectored mode (MODE=01)");
        check(read_val[1:0] === 2'b01, "mtvec: MODE bits = 01");

        // Write a large address
        csr_write(ADDR_MTVEC, 32'h80000100, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MTVEC, read_val);
        check_eq(read_val, 32'h80000100, "mtvec: large address 0x80000100");

        // Clean up
        csr_write(ADDR_MTVEC, 32'h0, CSR_RW, 1'b0, old_val);
    endtask

    task automatic test_mepc();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-006: mepc (Exception PC)");

        // Write an aligned address
        csr_write(ADDR_MEPC, 32'h00001000, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MEPC, read_val);
        check_eq(read_val, 32'h00001000, "mepc: write/read aligned address");
        check_eq(mepc_out, 32'h00001000, "mepc output port matches");

        // Write an address with LSB=1 -> should be cleared (aligned to 2-byte)
        csr_write(ADDR_MEPC, 32'h00001001, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MEPC, read_val);
        check_eq(read_val, 32'h00001000, "mepc: LSB forced to 0 (IALIGN)");

        // Write odd address
        csr_write(ADDR_MEPC, 32'hDEADBEEF, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MEPC, read_val);
        check_eq(read_val, 32'hDEADBEEE, "mepc: bit[0] forced to 0");

        // Clean up
        csr_write(ADDR_MEPC, 32'h0, CSR_RW, 1'b0, old_val);
    endtask

    task automatic test_mcause();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-007: mcause (Exception Cause)");

        // Write an exception cause
        csr_write(ADDR_MCAUSE, 32'h00000002, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MCAUSE, read_val);
        check_eq(read_val, 32'h00000002, "mcause: write/read illegal instruction cause");

        // Write interrupt cause (bit 31 = 1)
        csr_write(ADDR_MCAUSE, 32'h8000000B, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MCAUSE, read_val);
        check_eq(read_val, 32'h8000000B, "mcause: write/read interrupt cause with bit31");

        // Clean up
        csr_write(ADDR_MCAUSE, 32'h0, CSR_RW, 1'b0, old_val);
    endtask

    task automatic test_mtval();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-008: mtval (Trap Value)");

        // Write a trap value
        csr_write(ADDR_MTVAL, 32'hBAADF00D, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MTVAL, read_val);
        check_eq(read_val, 32'hBAADF00D, "mtval: write/read trap value");

        // Write zero
        csr_write(ADDR_MTVAL, 32'h0, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MTVAL, read_val);
        check_eq(read_val, 32'h0, "mtval: clear to zero");
    endtask

    task automatic test_mie_mip();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;

        test_begin("CSR-009: mie/mip (Interrupt Enable/Pending)");

        // Enable all M-mode interrupts: MSIE(3), MTIE(7), MEIE(11)
        csr_write(ADDR_MIE, 32'h00000888, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MIE, read_val);
        check(read_val[3] === 1'b1, "mie: MSIE bit set");
        check(read_val[7] === 1'b1, "mie: MTIE bit set");
        check(read_val[11] === 1'b1, "mie: MEIE bit set");
        check_eq(mie_out, 32'h00000888, "mie_out matches");

        // Assert external IRQ, check mip reflects it
        @(posedge clk);
        ext_irq = 1'b1;
        @(posedge clk);  // Wait for mip_r to be updated
        @(posedge clk);
        csr_read(ADDR_MIP, read_val);
        check(read_val[11] === 1'b1, "mip: MEIP reflects ext_irq=1");

        // Assert timer IRQ
        timer_irq = 1'b1;
        @(posedge clk);
        @(posedge clk);
        csr_read(ADDR_MIP, read_val);
        check(read_val[7] === 1'b1, "mip: MTIP reflects timer_irq=1");

        // Assert software IRQ
        sw_irq = 1'b1;
        @(posedge clk);
        @(posedge clk);
        csr_read(ADDR_MIP, read_val);
        check(read_val[3] === 1'b1, "mip: MSIP reflects sw_irq=1");

        // Deassert IRQs
        ext_irq   = 1'b0;
        timer_irq = 1'b0;
        sw_irq    = 1'b0;
        @(posedge clk);
        @(posedge clk);
        csr_read(ADDR_MIP, read_val);
        check(read_val[11] === 1'b0, "mip: MEIP cleared when ext_irq=0");
        check(read_val[7] === 1'b0, "mip: MTIP cleared when timer_irq=0");
        check(read_val[3] === 1'b0, "mip: MSIP cleared when sw_irq=0");

        // Test trap_pending: enable MIE + MEIE + assert ext_irq
        csr_write(ADDR_MSTATUS, 32'h00000008, CSR_RW, 1'b0, old_val); // MIE=1
        ext_irq = 1'b1;
        @(posedge clk);
        @(posedge clk);
        check(trap_pending === 1'b1, "trap_pending=1 when MIE=1, MEIE=1, ext_irq=1");

        ext_irq = 1'b0;
        @(posedge clk);
        @(posedge clk);

        // Clean up
        csr_write(ADDR_MIE, 32'h0, CSR_RW, 1'b0, old_val);
        csr_write(ADDR_MSTATUS, 32'h0, CSR_RW, 1'b0, old_val);
    endtask

    task automatic test_mcycle();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val1;
        logic [XLEN-1:0] read_val2;

        test_begin("CSR-010: mcycle (Cycle Counter)");

        // Read mcycle
        csr_read(ADDR_MCYCLE, read_val1);

        // Wait several cycles
        repeat (10) @(posedge clk);

        // Read mcycle again - should have incremented
        csr_read(ADDR_MCYCLE, read_val2);
        check(read_val2 > read_val1, "mcycle: counter increments over time");

        // Write a known value to mcycle, then read back
        csr_write(ADDR_MCYCLE, 32'h00000100, CSR_RW, 1'b0, old_val);
        repeat (5) @(posedge clk);
        csr_read(ADDR_MCYCLE, read_val1);
        // Should be approximately 0x100 + a few cycles
        check(read_val1 > 32'h00000100, "mcycle: counter continues from written value");
        check(read_val1 < 32'h00000120, "mcycle: counter reasonably close to written value");
    endtask

    task automatic test_minstret();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val1;
        logic [XLEN-1:0] read_val2;

        test_begin("CSR-010: minstret (Instructions Retired)");

        // Reset minstret to a known value
        csr_write(ADDR_MINSTRET, 32'h0, CSR_RW, 1'b0, old_val);

        // Read minstret - should be small (just reset)
        repeat (2) @(posedge clk);
        csr_read(ADDR_MINSTRET, read_val1);

        // Pulse retire_valid a few times
        @(posedge clk);
        retire_valid = 1'b1;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        retire_valid = 1'b0;
        @(posedge clk);

        // Read minstret again - should have incremented by 3
        csr_read(ADDR_MINSTRET, read_val2);
        check_eq(read_val2, read_val1 + 32'd3, "minstret: incremented by 3 retire_valid pulses");
    endtask

    // =========================================================================
    // CSR-011: Invalid CSR Access
    // =========================================================================

    task automatic test_invalid_csr_access();
        logic [XLEN-1:0] old_val;
        logic [XLEN-1:0] read_val;
        logic [XLEN-1:0] misa_orig;

        test_begin("CSR-011: Invalid CSR Access (Exception Expected)");

        // Access non-existent CSR address
        csr_read(12'hFFF, read_val);
        check_eq(read_val, 32'h0, "Invalid CSR address 0xFFF reads as 0");

        // Access another non-existent address
        csr_read(12'h123, read_val);
        check_eq(read_val, 32'h0, "Invalid CSR address 0x123 reads as 0");

        // Read MISA to get its constant value
        csr_read(ADDR_MISA, misa_orig);

        // Try to write to read-only MISA
        csr_write(ADDR_MISA, 32'hDEADBEEF, CSR_RW, 1'b0, old_val);
        csr_read(ADDR_MISA, read_val);
        // MISA is read-only, writes should be ignored
        check_eq(read_val, misa_orig, "MISA: writes ignored, read-only value preserved");
    endtask

endmodule
