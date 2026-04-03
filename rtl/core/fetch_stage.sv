// =============================================================================
// VSync - Fetch Stage (IF Stage)
// RISC-V RV32IM Processor Pipeline - Instruction Fetch
//
// File: fetch_stage.sv
// Description: Program Counter management, instruction memory address output,
//              pipeline stall/flush support, and IF/ID register generation.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module fetch_stage (
    // Clock and Reset
    input  logic                clk,        // System clock
    input  logic                rst_n,      // Active-low asynchronous reset

    // Pipeline Control
    input  logic                stall,      // Stall IF stage (hold PC)
    input  logic                flush,      // Flush IF/ID register

    // Branch/Jump Control
    input  logic                branch_taken,   // Branch/jump taken signal
    input  logic [XLEN-1:0]    branch_target,  // Branch/jump target address

    // Instruction Memory Interface
    output logic [XLEN-1:0]    imem_addr,      // Instruction memory read address
    input  logic [XLEN-1:0]    imem_rdata,     // Instruction memory read data

    // Pipeline Output
    output logic [XLEN-1:0]    pc,             // Current Program Counter value
    output if_id_reg_t         if_id_reg       // IF/ID pipeline register output
);

    // =========================================================================
    // Internal Signals
    // =========================================================================

    /** Next PC value (combinational) */
    logic [XLEN-1:0] pc_next;

    /** Delayed PC: tracks the address that was sent to instruction memory
        on the previous cycle, used to pair with returned instruction data. */
    logic [XLEN-1:0] pc_delayed;

    /** Suppress valid flag: asserted for exactly one cycle after reset or
        after a PC redirect (branch/exception) to account for the registered
        instruction memory latency. During this cycle, the memory has not yet
        returned valid data for the new PC address. */
    logic suppress_valid;

    // =========================================================================
    // Next PC Logic
    // =========================================================================
    // Priority:
    //   1. Branch/Jump taken -> target address
    //   2. Stall -> hold current PC
    //   3. Normal -> PC + 4
    // =========================================================================
    always_comb begin
        if (branch_taken) begin
            pc_next = branch_target;
        end else if (stall) begin
            pc_next = pc;
        end else begin
            pc_next = pc + 32'd4;
        end
    end

    // =========================================================================
    // Program Counter Register
    // =========================================================================
    // Resets to ADDR_IMEM_BASE (0x0000_0000)
    // Updates on every rising clock edge unless stalled
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= ADDR_IMEM_BASE;
        end else begin
            pc <= pc_next;
        end
    end

    // =========================================================================
    // Instruction Memory Address Output
    // =========================================================================
    // Send current PC to instruction memory. The memory is registered and
    // returns data one cycle later; pc_delayed tracks the address sent so
    // the IF/ID register can pair the returned instruction with its PC.
    // =========================================================================
    assign imem_addr = pc;

    // =========================================================================
    // Delayed PC and Suppress-Valid Tracking
    // =========================================================================
    // pc_delayed holds the PC that was sent to memory last cycle (the address
    // whose instruction data is arriving now via imem_rdata).
    //
    // suppress_valid is set:
    //   - On reset (first cycle, memory hasn't returned data yet)
    //   - When a branch/jump redirects the PC (the instruction arriving from
    //     memory was fetched from the OLD address, not the new target)
    // It is cleared on the next cycle when the correctly-addressed instruction
    // arrives from memory.
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_delayed     <= ADDR_IMEM_BASE;
            suppress_valid <= 1'b1;
        end else begin
            if (!stall) begin
                pc_delayed <= pc;
            end
            // Set suppress_valid when a branch redirect occurs (the memory
            // data arriving next cycle will be from the old PC, not the
            // branch target). Clear it one cycle later.
            if (branch_taken) begin
                suppress_valid <= 1'b1;
            end else if (suppress_valid && !stall) begin
                suppress_valid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // IF/ID Pipeline Register
    // =========================================================================
    // Captures the PC (delayed to match memory latency) and the fetched
    // instruction for the decode stage.
    // Flush inserts a bubble (NOP) by invalidating the register.
    // Stall holds the current values.
    // suppress_valid ensures the IF/ID register is marked invalid when the
    // instruction data from memory does not correspond to the current PC
    // (e.g., after reset or branch redirect).
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_reg.pc          <= ADDR_IMEM_BASE;
            if_id_reg.instruction <= 32'h0000_0013;  // NOP (ADDI x0, x0, 0)
            if_id_reg.valid       <= 1'b0;
        end else if (flush) begin
            // Flush: insert bubble (invalidate)
            if_id_reg.pc          <= ADDR_IMEM_BASE;
            if_id_reg.instruction <= 32'h0000_0013;  // NOP
            if_id_reg.valid       <= 1'b0;
        end else if (!stall) begin
            // Normal operation: latch delayed PC and instruction
            if_id_reg.pc          <= pc_delayed;
            if_id_reg.instruction <= imem_rdata;
            if_id_reg.valid       <= !suppress_valid;
        end
        // When stalled: hold current values (implicit)
    end

endmodule : fetch_stage
