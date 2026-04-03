// =============================================================================
// VSync - RTOS Context Switch Testbench
// =============================================================================
// Tests: CTX-001 ~ CTX-006
//   CTX-001: Register save/restore (x1-x31) with value verification
//   CTX-002: PC save/restore
//   CTX-003: stall_pipeline behavior during switch
//   CTX-004: switch_req -> switch_done cycle count measurement
//   CTX-005: A->B->C->A circular context switch
//   CTX-006: busy signal behavior
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_context_switch;

    import test_utils::*;
    import vsync_pkg::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam CLK_PERIOD  = 10;
    localparam RST_CYCLES  = 10;
    localparam XLEN        = 32;
    localparam NUM_REGS    = 32;
    localparam TASK_ID_W   = 4;
    localparam MAX_TASKS   = 16;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // DUT interface signals
    logic                      switch_req_tb;
    logic [TASK_ID_W-1:0]      old_task_id_tb;
    logic [TASK_ID_W-1:0]      new_task_id_tb;
    logic [XLEN-1:0]           cpu_reg_rdata_tb;
    logic [XLEN-1:0]           cpu_pc_tb;
    logic [4:0]                cpu_reg_addr_out;
    logic [XLEN-1:0]           cpu_reg_wdata_out;
    logic [XLEN-1:0]           restore_pc_out;
    logic                      cpu_reg_we_out;
    logic                      switch_done_out;
    logic                      stall_pipeline_out;
    logic                      busy_out;

    // Emulated CPU register file
    logic [31:0] emu_regs [32];

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
    context_switch #(
        .XLEN      (32),
        .NUM_REGS  (32),
        .TASK_ID_W (4),
        .MAX_TASKS (16)
    ) u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .switch_req     (switch_req_tb),
        .old_task_id    (old_task_id_tb),
        .new_task_id    (new_task_id_tb),
        .cpu_reg_rdata  (cpu_reg_rdata_tb),
        .cpu_reg_addr   (cpu_reg_addr_out),
        .cpu_reg_wdata  (cpu_reg_wdata_out),
        .cpu_reg_we     (cpu_reg_we_out),
        .cpu_pc         (cpu_pc_tb),
        .switch_done    (switch_done_out),
        .restore_pc     (restore_pc_out),
        .stall_pipeline (stall_pipeline_out),
        .busy           (busy_out)
    );

    // =========================================================================
    // Register file emulation
    // =========================================================================
    // SAVE phase: DUT outputs cpu_reg_addr, TB supplies emu_regs[addr]
    always_comb begin
        cpu_reg_rdata_tb = emu_regs[cpu_reg_addr_out];
    end

    // LOAD phase: DUT asserts cpu_reg_we with addr and wdata
    always_ff @(posedge clk) begin
        if (cpu_reg_we_out) begin
            emu_regs[cpu_reg_addr_out] <= cpu_reg_wdata_out;
        end
    end

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_context_switch.vcd");
        $dumpvars(0, tb_context_switch);
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
        switch_req_tb  = 1'b0;
        old_task_id_tb = '0;
        new_task_id_tb = '0;
        cpu_pc_tb      = '0;
        for (int i = 0; i < 32; i++) emu_regs[i] = '0;

        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Helper task: perform context switch
    // =========================================================================
    task automatic do_context_switch(
        input logic [TASK_ID_W-1:0] old_id,
        input logic [TASK_ID_W-1:0] new_id
    );
        int timeout_cnt;
        @(posedge clk);
        switch_req_tb  <= 1'b1;
        old_task_id_tb <= old_id;
        new_task_id_tb <= new_id;
        @(posedge clk);
        switch_req_tb  <= 1'b0;
        timeout_cnt = 0;
        while (!switch_done_out && timeout_cnt < 200) begin
            @(posedge clk);
            timeout_cnt++;
        end
        @(posedge clk); // Let DONE state pass
    endtask

    // =========================================================================
    // Helper: set emu_regs with a pattern base+index
    // =========================================================================
    task automatic set_emu_regs(input logic [15:0] base);
        int i;
        emu_regs[0] = 32'h0;
        for (i = 1; i < 32; i++) begin
            emu_regs[i] = {base, i[15:0]};
        end
    endtask

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();
        test_suite_begin("RTOS Context Switch Tests");

        test_ctx_001_register_save_restore();
        test_ctx_002_pc_save_restore();
        test_ctx_003_stall_pipeline();
        test_ctx_004_cycle_count();
        test_ctx_005_circular_switch();
        test_ctx_006_busy_signal();
    endtask

    // -------------------------------------------------------------------------
    // CTX-001: Register save/restore with value verification
    // -------------------------------------------------------------------------
    task automatic test_ctx_001_register_save_restore();
        test_begin("CTX-001: Register Save/Restore (x1-x31)");

        // Set task A registers: x1=0xA0000001, x2=0xA0000002, ...
        set_emu_regs(16'hA000);
        cpu_pc_tb = 32'h0000_A000;

        // Switch task 1 (A) -> task 2 (B). Task 2 is empty (all zeros).
        do_context_switch(4'd1, 4'd2);

        // After loading task 2, emu_regs should be 0
        check_eq(emu_regs[1], 32'h0, "CTX-001: x1==0 after switch to empty task2");

        // Now set task B registers
        set_emu_regs(16'hB000);
        cpu_pc_tb = 32'h0000_B000;

        // Switch task 2 (B) -> task 1 (A)
        do_context_switch(4'd2, 4'd1);

        // Verify task A registers are restored
        check_eq(emu_regs[1],  32'hA000_0001, "CTX-001: x1 restored");
        check_eq(emu_regs[2],  32'hA000_0002, "CTX-001: x2 restored");
        check_eq(emu_regs[15], 32'hA000_000F, "CTX-001: x15 restored");
        check_eq(emu_regs[31], 32'hA000_001F, "CTX-001: x31 restored");
        check_eq(restore_pc_out, 32'h0000_A000, "CTX-001: PC restored");
    endtask

    // -------------------------------------------------------------------------
    // CTX-002: PC save/restore
    // -------------------------------------------------------------------------
    task automatic test_ctx_002_pc_save_restore();
        test_begin("CTX-002: PC Save/Restore");

        for (int i = 0; i < 32; i++) emu_regs[i] = '0;

        // Task 3 with specific PC
        cpu_pc_tb = 32'hDEAD_BEEF;
        do_context_switch(4'd3, 4'd4);

        // Task 4 with different PC
        cpu_pc_tb = 32'hCAFE_BABE;
        do_context_switch(4'd4, 4'd3);

        // Verify task 3 PC restored
        check_eq(restore_pc_out, 32'hDEAD_BEEF, "CTX-002: task3 PC restored");

        // Switch back to task 4
        cpu_pc_tb = 32'h1234_5678;
        do_context_switch(4'd3, 4'd4);

        // Verify task 4 PC restored
        check_eq(restore_pc_out, 32'hCAFE_BABE, "CTX-002: task4 PC restored");
    endtask

    // -------------------------------------------------------------------------
    // CTX-003: stall_pipeline behavior
    // -------------------------------------------------------------------------
    task automatic test_ctx_003_stall_pipeline();
        int stall_seen;
        test_begin("CTX-003: stall_pipeline during switch");

        // Before switch: stall should be 0
        check(stall_pipeline_out == 1'b0, "CTX-003: stall==0 before switch");

        // Start switch
        @(posedge clk);
        switch_req_tb  <= 1'b1;
        old_task_id_tb <= 4'd5;
        new_task_id_tb <= 4'd6;
        @(posedge clk);
        switch_req_tb  <= 1'b0;

        // Wait one cycle for FSM to enter SAVE
        @(posedge clk);

        // Check stall asserted during switch
        stall_seen = 0;
        while (!switch_done_out) begin
            if (stall_pipeline_out) stall_seen = 1;
            @(posedge clk);
        end
        check(stall_seen == 1, "CTX-003: stall==1 seen during switch");

        @(posedge clk); // DONE passes

        // After switch: stall should be 0
        @(posedge clk);
        check(stall_pipeline_out == 1'b0, "CTX-003: stall==0 after switch");
    endtask

    // -------------------------------------------------------------------------
    // CTX-004: switch cycle count measurement
    // -------------------------------------------------------------------------
    task automatic test_ctx_004_cycle_count();
        int cycle_count;
        test_begin("CTX-004: Switch cycle count measurement");

        for (int i = 0; i < 32; i++) emu_regs[i] = '0;

        @(posedge clk);
        switch_req_tb  <= 1'b1;
        old_task_id_tb <= 4'd7;
        new_task_id_tb <= 4'd8;
        @(posedge clk);
        switch_req_tb  <= 1'b0;

        cycle_count = 0;
        while (!switch_done_out && cycle_count < 200) begin
            @(posedge clk);
            cycle_count++;
        end

        $display("  CTX-004: Context switch took %0d cycles", cycle_count);
        check(cycle_count <= 70, "CTX-004: switch < 70 cycles");
        check(cycle_count > 0,  "CTX-004: switch > 0 cycles");

        @(posedge clk); // Let DONE pass
    endtask

    // -------------------------------------------------------------------------
    // CTX-005: A->B->C->A circular switch
    // -------------------------------------------------------------------------
    task automatic test_ctx_005_circular_switch();
        test_begin("CTX-005: A->B->C->A Circular Switch");

        // Setup task 10 (A)
        set_emu_regs(16'hAA00);
        cpu_pc_tb = 32'h0000_AA00;
        do_context_switch(4'd10, 4'd11);

        // Setup task 11 (B)
        set_emu_regs(16'hBB00);
        cpu_pc_tb = 32'h0000_BB00;
        do_context_switch(4'd11, 4'd12);

        // Setup task 12 (C)
        set_emu_regs(16'hCC00);
        cpu_pc_tb = 32'h0000_CC00;

        // C -> A
        do_context_switch(4'd12, 4'd10);
        check_eq(emu_regs[1],  32'hAA00_0001, "CTX-005: A x1 restored");
        check_eq(emu_regs[16], 32'hAA00_0010, "CTX-005: A x16 restored");
        check_eq(emu_regs[31], 32'hAA00_001F, "CTX-005: A x31 restored");
        check_eq(restore_pc_out, 32'h0000_AA00, "CTX-005: A PC restored");

        // A -> B
        cpu_pc_tb = 32'h0000_AA00;
        do_context_switch(4'd10, 4'd11);
        check_eq(emu_regs[1],  32'hBB00_0001, "CTX-005: B x1 restored");
        check_eq(emu_regs[31], 32'hBB00_001F, "CTX-005: B x31 restored");
        check_eq(restore_pc_out, 32'h0000_BB00, "CTX-005: B PC restored");

        // B -> C
        cpu_pc_tb = 32'h0000_BB00;
        do_context_switch(4'd11, 4'd12);
        check_eq(emu_regs[1],  32'hCC00_0001, "CTX-005: C x1 restored");
        check_eq(emu_regs[31], 32'hCC00_001F, "CTX-005: C x31 restored");
        check_eq(restore_pc_out, 32'h0000_CC00, "CTX-005: C PC restored");
    endtask

    // -------------------------------------------------------------------------
    // CTX-006: busy signal behavior
    // -------------------------------------------------------------------------
    task automatic test_ctx_006_busy_signal();
        test_begin("CTX-006: busy signal");

        // IDLE: busy == 0
        check(busy_out == 1'b0, "CTX-006: busy==0 in IDLE");

        // Start switch
        @(posedge clk);
        switch_req_tb  <= 1'b1;
        old_task_id_tb <= 4'd13;
        new_task_id_tb <= 4'd14;
        @(posedge clk);
        switch_req_tb  <= 1'b0;

        // During switch: busy == 1
        @(posedge clk);
        check(busy_out == 1'b1, "CTX-006: busy==1 during switch");

        // Wait for completion
        while (!switch_done_out) @(posedge clk);

        @(posedge clk); // DONE passes
        @(posedge clk); // Back to IDLE

        check(busy_out == 1'b0, "CTX-006: busy==0 after switch");
    endtask

endmodule
