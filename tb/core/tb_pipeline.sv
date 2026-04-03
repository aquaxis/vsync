// =============================================================================
// VSync - Pipeline Hazard & Forwarding Test Bench
// =============================================================================
// Test IDs: PIPE-001 ~ PIPE-008, FWD-001 ~ FWD-005
// Pipeline hazard detection and data forwarding verification
//
// Approach: Instantiate rv32im_core with inline instruction and data memories.
// For each test, load instructions, apply reset, let the pipeline execute,
// then halt and read registers via debug interface to verify results.
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_pipeline;

    import test_utils::*;
    import vsync_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD = 10;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst_n;

    // Instruction memory interface
    logic [IMEM_ADDR_W-1:0] imem_addr;
    logic [XLEN-1:0]        imem_rdata;
    logic                    imem_en;

    // Data memory interface
    logic [XLEN-1:0]  mem_addr;
    logic [XLEN-1:0]  mem_wdata;
    logic              mem_read;
    logic              mem_write;
    logic [2:0]        mem_size;
    logic [XLEN-1:0]  mem_rdata;
    logic              mem_ready;
    logic              mem_error;

    // Debug Interface
    logic              debug_halt_req;
    logic              debug_halted;
    logic [XLEN-1:0]  debug_pc;
    logic [XLEN-1:0]  debug_instr;
    logic [REG_ADDR_W-1:0] debug_reg_addr;
    logic [XLEN-1:0]  debug_reg_data;

    // Unused outputs
    logic              ctx_switch_ack;
    logic              ctx_save_en;
    logic [REG_ADDR_W-1:0] ctx_save_reg_idx;
    logic [XLEN-1:0]  ctx_save_reg_data;
    logic [XLEN-1:0]  ctx_save_pc;
    logic              ecall_req;
    logic [7:0]        syscall_num;
    logic [XLEN-1:0]  syscall_arg0;
    logic [XLEN-1:0]  syscall_arg1;
    logic [XLEN-1:0]  syscall_arg2;

    // =========================================================================
    // Clock Generation
    // =========================================================================
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // =========================================================================
    // Inline Instruction Memory (256 words)
    // =========================================================================
    logic [31:0] imem [0:255];
    logic [31:0] imem_rdata_r;

    always_ff @(posedge clk) begin
        if (imem_en)
            imem_rdata_r <= imem[imem_addr[9:2]];
    end
    assign imem_rdata = imem_rdata_r;

    // =========================================================================
    // Inline Data Memory (256 words)
    // =========================================================================
    logic [31:0] dmem [0:255];
    logic [31:0] dmem_rdata_r;
    logic        dmem_ready_r;

    always_ff @(posedge clk) begin
        dmem_ready_r <= mem_read || mem_write;
        if (mem_write) dmem[mem_addr[9:2]] <= mem_wdata;
        if (mem_read)  dmem_rdata_r <= dmem[mem_addr[9:2]];
    end
    assign mem_rdata = dmem_rdata_r;
    assign mem_ready = dmem_ready_r;
    assign mem_error = 1'b0;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    rv32im_core u_core (
        .clk                (clk),
        .rst_n              (rst_n),
        .imem_addr          (imem_addr),
        .imem_rdata         (imem_rdata),
        .imem_en            (imem_en),
        .mem_addr           (mem_addr),
        .mem_wdata          (mem_wdata),
        .mem_read           (mem_read),
        .mem_write          (mem_write),
        .mem_size           (mem_size),
        .mem_rdata          (mem_rdata),
        .mem_ready          (mem_ready),
        .mem_error          (mem_error),
        .external_irq       (1'b0),
        .timer_irq          (1'b0),
        .software_irq       (1'b0),
        .ctx_switch_req     (1'b0),
        .ctx_switch_ack     (ctx_switch_ack),
        .ctx_save_en        (ctx_save_en),
        .ctx_save_reg_idx   (ctx_save_reg_idx),
        .ctx_save_reg_data  (ctx_save_reg_data),
        .ctx_save_pc        (ctx_save_pc),
        .ctx_restore_en     (1'b0),
        .ctx_restore_reg_idx(5'd0),
        .ctx_restore_reg_data(32'd0),
        .ctx_restore_pc     (32'd0),
        .current_task_id    (4'd0),
        .task_active        (1'b0),
        .ecall_req          (ecall_req),
        .syscall_num        (syscall_num),
        .syscall_arg0       (syscall_arg0),
        .syscall_arg1       (syscall_arg1),
        .syscall_arg2       (syscall_arg2),
        .syscall_ret        (32'd0),
        .syscall_done       (1'b0),
        .debug_halt_req     (debug_halt_req),
        .debug_halted       (debug_halted),
        .debug_pc           (debug_pc),
        .debug_instr        (debug_instr),
        .debug_reg_addr     (debug_reg_addr),
        .debug_reg_data     (debug_reg_data)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_pipeline.vcd");
        $dumpvars(0, tb_pipeline);
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
    // Instruction Encoding Functions
    // =========================================================================

    function automatic logic [31:0] encode_nop();
        return {12'b0, 5'd0, 3'b000, 5'd0, 7'b0010011};
    endfunction

    function automatic logic [31:0] encode_addi(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm12
    );
        return {imm12, rs1, 3'b000, rd, 7'b0010011};
    endfunction

    function automatic logic [31:0] encode_add(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );
        return {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction

    function automatic logic [31:0] encode_sub(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );
        return {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011};
    endfunction

    function automatic logic [31:0] encode_sw(
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [11:0] offset
    );
        return {offset[11:5], rs2, rs1, 3'b010, offset[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] encode_lw(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] offset
    );
        return {offset, rs1, 3'b010, rd, 7'b0000011};
    endfunction

    function automatic logic [31:0] encode_beq(
        input logic [4:0]  rs1,
        input logic [4:0]  rs2,
        input logic [12:0] offset
    );
        return {offset[12], offset[10:5], rs2, rs1, 3'b000,
                offset[4:1], offset[11], 7'b1100011};
    endfunction

    function automatic logic [31:0] encode_bne(
        input logic [4:0]  rs1,
        input logic [4:0]  rs2,
        input logic [12:0] offset
    );
        return {offset[12], offset[10:5], rs2, rs1, 3'b001,
                offset[4:1], offset[11], 7'b1100011};
    endfunction

    function automatic logic [31:0] encode_jal(
        input logic [4:0]  rd,
        input logic [20:0] offset
    );
        return {offset[20], offset[10:1], offset[11], offset[19:12], rd, 7'b1101111};
    endfunction

    // =========================================================================
    // Helper Tasks
    // =========================================================================

    /** Fill instruction memory with NOPs */
    task automatic clear_imem();
        integer i;
        for (i = 0; i < 256; i = i + 1)
            imem[i] = encode_nop();
    endtask

    /** Fill data memory with zeros */
    task automatic clear_dmem();
        integer i;
        for (i = 0; i < 256; i = i + 1)
            dmem[i] = 32'h0;
    endtask

    /** Apply reset to core, release, then let pipeline run for N cycles, then halt */
    task automatic reset_run_halt(input int run_cycles);
        // Assert reset
        rst_n = 1'b0;
        debug_halt_req = 1'b0;
        repeat (5) @(posedge clk);

        // Release reset
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Let the pipeline execute
        repeat (run_cycles) @(posedge clk);

        // Halt the CPU via debug interface
        debug_halt_req = 1'b1;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
    endtask

    /** Read a register value via debug interface (CPU must be halted) */
    task automatic read_reg(
        input  logic [4:0]        reg_idx,
        output logic [XLEN-1:0]  value
    );
        debug_reg_addr = reg_idx;
        @(posedge clk);
        @(posedge clk);
        #1;
        value = debug_reg_data;
    endtask

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin
        rst_n = 1'b0;
        debug_halt_req = 1'b0;
        debug_reg_addr = 5'd0;
        clear_imem();
        clear_dmem();

        // Initial reset
        repeat (15) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("Pipeline Hazard & Forwarding Tests");

        // === PIPE: Pipeline Hazard Tests ===
        test_raw_alu_alu();
        test_raw_load_use();
        test_raw_load_alu_use();
        test_ctrl_branch_taken();
        test_ctrl_branch_not_taken();
        test_jal_jalr_pipeline();
        test_consecutive_branches();
        test_stall_chain();

        // === FWD: Forwarding Tests ===
        test_fwd_ex_to_ex();
        test_fwd_mem_to_ex();
        test_fwd_wb_to_ex();
        test_fwd_double();
        test_fwd_priority();

    endtask

    // =========================================================================
    // PIPE: Pipeline Hazard Tests
    // =========================================================================

    task automatic test_raw_alu_alu();
        logic [XLEN-1:0] val;

        test_begin("PIPE-001: RAW Hazard (ALU->ALU)");

        clear_imem();
        imem[0] = encode_addi(5'd1, 5'd0, 12'd10);   // x1 = 10
        imem[1] = encode_addi(5'd2, 5'd0, 12'd20);   // x2 = 20
        imem[2] = encode_add(5'd3, 5'd1, 5'd2);      // x3 = x1 + x2 = 30

        reset_run_halt(20);

        read_reg(5'd1, val);
        check_eq(val, 32'd10, "x1 = 10");

        read_reg(5'd2, val);
        check_eq(val, 32'd20, "x2 = 20");

        read_reg(5'd3, val);
        check_eq(val, 32'd30, "x3 = 30 (RAW: x1+x2 forwarded correctly)");
    endtask

    task automatic test_raw_load_use();
        logic [XLEN-1:0] val;

        test_begin("PIPE-002: RAW Hazard (Load->Use)");

        clear_imem();
        clear_dmem();
        imem[0] = encode_addi(5'd1, 5'd0, 12'd42);   // x1 = 42
        imem[1] = encode_sw(5'd1, 5'd0, 12'd0);      // dmem[0] = 42
        imem[2] = encode_lw(5'd2, 5'd0, 12'd0);      // x2 = dmem[0] = 42
        imem[3] = encode_addi(5'd3, 5'd2, 12'd1);    // x3 = x2 + 1 = 43

        reset_run_halt(30);

        read_reg(5'd1, val);
        check_eq(val, 32'd42, "x1 = 42");

        read_reg(5'd2, val);
        check_eq(val, 32'd42, "x2 = 42 (loaded from memory)");

        read_reg(5'd3, val);
        check_eq(val, 32'd43, "x3 = 43 (load-use hazard handled: x2+1)");
    endtask

    task automatic test_raw_load_alu_use();
        logic [XLEN-1:0] val;

        test_begin("PIPE-003: RAW Hazard (Load->ALU->Use)");

        clear_imem();
        clear_dmem();
        imem[0] = encode_addi(5'd1, 5'd0, 12'd100);  // x1 = 100
        imem[1] = encode_sw(5'd1, 5'd0, 12'd0);      // dmem[0] = 100
        imem[2] = encode_lw(5'd2, 5'd0, 12'd0);      // x2 = 100
        imem[3] = encode_addi(5'd5, 5'd0, 12'd7);    // x5 = 7 (independent)
        imem[4] = encode_add(5'd3, 5'd2, 5'd5);      // x3 = x2 + x5 = 107

        reset_run_halt(30);

        read_reg(5'd2, val);
        check_eq(val, 32'd100, "x2 = 100 (loaded)");

        read_reg(5'd5, val);
        check_eq(val, 32'd7, "x5 = 7");

        read_reg(5'd3, val);
        check_eq(val, 32'd107, "x3 = 107 (load->ALU->use, forwarding from MEM)");
    endtask

    task automatic test_ctrl_branch_taken();
        logic [XLEN-1:0] val;

        test_begin("PIPE-004: Control Hazard (Branch Taken)");

        clear_imem();
        // addr 0: ADDI x1, x0, 5
        // addr 1: BEQ  x1, x1, +12     -> taken, target = PC(4) + 12 = 16 -> addr 4
        // addr 2: ADDI x2, x0, 99      -> flushed
        // addr 3: ADDI x3, x0, 99      -> flushed
        // addr 4: ADDI x4, x0, 44      -> branch target
        imem[0] = encode_addi(5'd1, 5'd0, 12'd5);
        imem[1] = encode_beq(5'd1, 5'd1, 13'd12);
        imem[2] = encode_addi(5'd2, 5'd0, 12'd99);
        imem[3] = encode_addi(5'd3, 5'd0, 12'd99);
        imem[4] = encode_addi(5'd4, 5'd0, 12'd44);

        reset_run_halt(25);

        read_reg(5'd1, val);
        check_eq(val, 32'd5, "x1 = 5");

        read_reg(5'd4, val);
        check_eq(val, 32'd44, "x4 = 44 (branch target executed)");

        read_reg(5'd2, val);
        check_eq(val, 32'd0, "x2 = 0 (flushed, branch taken)");

        read_reg(5'd3, val);
        check_eq(val, 32'd0, "x3 = 0 (flushed, branch taken)");
    endtask

    task automatic test_ctrl_branch_not_taken();
        logic [XLEN-1:0] val;

        test_begin("PIPE-005: Control Hazard (Branch Not Taken)");

        clear_imem();
        // BNE x0, x0, +12  -> not taken (x0 == x0, BNE needs not-equal)
        imem[0] = encode_addi(5'd1, 5'd0, 12'd1);
        imem[1] = encode_bne(5'd0, 5'd0, 13'd12);
        imem[2] = encode_addi(5'd2, 5'd0, 12'd77);
        imem[3] = encode_addi(5'd3, 5'd0, 12'd88);

        reset_run_halt(25);

        read_reg(5'd1, val);
        check_eq(val, 32'd1, "x1 = 1");

        read_reg(5'd2, val);
        check_eq(val, 32'd77, "x2 = 77 (sequential after branch not taken)");

        read_reg(5'd3, val);
        check_eq(val, 32'd88, "x3 = 88 (sequential after branch not taken)");
    endtask

    task automatic test_jal_jalr_pipeline();
        logic [XLEN-1:0] val;

        test_begin("PIPE-006: JAL/JALR Pipeline State");

        clear_imem();
        // addr 0: ADDI x1, x0, 55
        // addr 1: JAL  x5, +12          -> x5 = PC+4 = 8, jump to addr 4 (PC=4+12=16)
        // addr 2: ADDI x2, x0, 99      -> flushed
        // addr 3: ADDI x3, x0, 99      -> flushed
        // addr 4: ADDI x6, x0, 66      -> jump target
        imem[0] = encode_addi(5'd1, 5'd0, 12'd55);
        imem[1] = encode_jal(5'd5, 21'd12);
        imem[2] = encode_addi(5'd2, 5'd0, 12'd99);
        imem[3] = encode_addi(5'd3, 5'd0, 12'd99);
        imem[4] = encode_addi(5'd6, 5'd0, 12'd66);

        reset_run_halt(25);

        read_reg(5'd1, val);
        check_eq(val, 32'd55, "x1 = 55");

        read_reg(5'd6, val);
        check_eq(val, 32'd66, "x6 = 66 (JAL target executed)");

        // x5 = return address = JAL PC + 4 = 4 + 4 = 8
        read_reg(5'd5, val);
        check_eq(val, 32'd8, "x5 = 8 (link register: JAL PC+4)");

        read_reg(5'd2, val);
        check_eq(val, 32'd0, "x2 = 0 (flushed after JAL)");
    endtask

    task automatic test_consecutive_branches();
        logic [XLEN-1:0] val;

        test_begin("PIPE-007: Consecutive Branches");

        clear_imem();
        // addr 0: ADDI x1, x0, 1
        // addr 1: BEQ  x0, x0, +8      -> taken, jump to addr 3
        // addr 2: ADDI x10, x0, 99     -> flushed
        // addr 3: ADDI x2, x0, 2
        // addr 4: BEQ  x0, x0, +8      -> taken, jump to addr 6
        // addr 5: ADDI x11, x0, 99     -> flushed
        // addr 6: ADDI x3, x0, 3
        imem[0] = encode_addi(5'd1, 5'd0, 12'd1);
        imem[1] = encode_beq(5'd0, 5'd0, 13'd8);
        imem[2] = encode_addi(5'd10, 5'd0, 12'd99);
        imem[3] = encode_addi(5'd2, 5'd0, 12'd2);
        imem[4] = encode_beq(5'd0, 5'd0, 13'd8);
        imem[5] = encode_addi(5'd11, 5'd0, 12'd99);
        imem[6] = encode_addi(5'd3, 5'd0, 12'd3);

        reset_run_halt(30);

        read_reg(5'd1, val);
        check_eq(val, 32'd1, "x1 = 1");

        read_reg(5'd2, val);
        check_eq(val, 32'd2, "x2 = 2 (first branch target)");

        read_reg(5'd3, val);
        check_eq(val, 32'd3, "x3 = 3 (second branch target)");

        read_reg(5'd10, val);
        check_eq(val, 32'd0, "x10 = 0 (flushed after first branch)");

        read_reg(5'd11, val);
        check_eq(val, 32'd0, "x11 = 0 (flushed after second branch)");
    endtask

    task automatic test_stall_chain();
        logic [XLEN-1:0] val;

        test_begin("PIPE-008: Stall Chain (Multi-stage)");

        clear_imem();
        // Chain of back-to-back dependent ADDI instructions
        imem[0] = encode_addi(5'd1, 5'd0, 12'd10);   // x1 = 10
        imem[1] = encode_addi(5'd2, 5'd1, 12'd5);    // x2 = x1 + 5 = 15
        imem[2] = encode_addi(5'd3, 5'd2, 12'd3);    // x3 = x2 + 3 = 18
        imem[3] = encode_addi(5'd4, 5'd3, 12'd1);    // x4 = x3 + 1 = 19
        imem[4] = encode_addi(5'd5, 5'd4, 12'd2);    // x5 = x4 + 2 = 21

        reset_run_halt(25);

        read_reg(5'd1, val);
        check_eq(val, 32'd10, "x1 = 10");

        read_reg(5'd2, val);
        check_eq(val, 32'd15, "x2 = 15 (chain dep on x1)");

        read_reg(5'd3, val);
        check_eq(val, 32'd18, "x3 = 18 (chain dep on x2)");

        read_reg(5'd4, val);
        check_eq(val, 32'd19, "x4 = 19 (chain dep on x3)");

        read_reg(5'd5, val);
        check_eq(val, 32'd21, "x5 = 21 (chain dep on x4)");
    endtask

    // =========================================================================
    // FWD: Forwarding Tests
    // =========================================================================

    task automatic test_fwd_ex_to_ex();
        logic [XLEN-1:0] val;

        test_begin("FWD-001: EX->EX Forwarding");

        clear_imem();
        imem[0] = encode_addi(5'd1, 5'd0, 12'd100);  // x1 = 100
        imem[1] = encode_addi(5'd2, 5'd1, 12'd50);   // x2 = x1 + 50 = 150

        reset_run_halt(20);

        read_reg(5'd1, val);
        check_eq(val, 32'd100, "x1 = 100");

        read_reg(5'd2, val);
        check_eq(val, 32'd150, "x2 = 150 (EX->EX forwarding: x1+50)");
    endtask

    task automatic test_fwd_mem_to_ex();
        logic [XLEN-1:0] val;

        test_begin("FWD-002: MEM->EX Forwarding");

        clear_imem();
        imem[0] = encode_addi(5'd1, 5'd0, 12'd200);  // x1 = 200
        imem[1] = encode_nop();                         // 1 cycle gap
        imem[2] = encode_addi(5'd2, 5'd1, 12'd25);   // x2 = x1 + 25 = 225

        reset_run_halt(20);

        read_reg(5'd1, val);
        check_eq(val, 32'd200, "x1 = 200");

        read_reg(5'd2, val);
        check_eq(val, 32'd225, "x2 = 225 (MEM->EX forwarding: x1+25)");
    endtask

    task automatic test_fwd_wb_to_ex();
        logic [XLEN-1:0] val;

        test_begin("FWD-003: WB->EX Forwarding");

        clear_imem();
        imem[0] = encode_addi(5'd1, 5'd0, 12'd300);  // x1 = 300
        imem[1] = encode_nop();
        imem[2] = encode_nop();
        imem[3] = encode_addi(5'd2, 5'd1, 12'd10);   // x2 = x1 + 10 = 310

        reset_run_halt(20);

        read_reg(5'd1, val);
        check_eq(val, 32'd300, "x1 = 300");

        read_reg(5'd2, val);
        check_eq(val, 32'd310, "x2 = 310 (WB->EX or regfile: x1+10)");
    endtask

    task automatic test_fwd_double();
        logic [XLEN-1:0] val;

        test_begin("FWD-004: Double Forwarding (rs1 and rs2)");

        clear_imem();
        imem[0] = encode_addi(5'd1, 5'd0, 12'd11);   // x1 = 11
        imem[1] = encode_addi(5'd2, 5'd0, 12'd22);   // x2 = 22
        imem[2] = encode_add(5'd3, 5'd1, 5'd2);      // x3 = x1 + x2 = 33

        reset_run_halt(20);

        read_reg(5'd1, val);
        check_eq(val, 32'd11, "x1 = 11");

        read_reg(5'd2, val);
        check_eq(val, 32'd22, "x2 = 22");

        read_reg(5'd3, val);
        check_eq(val, 32'd33, "x3 = 33 (double forwarding: x1+x2)");
    endtask

    task automatic test_fwd_priority();
        logic [XLEN-1:0] val;

        test_begin("FWD-005: Forwarding Priority");

        clear_imem();
        imem[0] = encode_addi(5'd1, 5'd0, 12'd111);  // x1 = 111 (old)
        imem[1] = encode_addi(5'd1, 5'd0, 12'd222);  // x1 = 222 (new, overwrites)
        imem[2] = encode_addi(5'd2, 5'd1, 12'd0);    // x2 = x1 (should be 222)

        reset_run_halt(20);

        read_reg(5'd1, val);
        check_eq(val, 32'd222, "x1 = 222 (most recent write)");

        read_reg(5'd2, val);
        check_eq(val, 32'd222, "x2 = 222 (forwarding priority: most recent x1)");
    endtask

endmodule
