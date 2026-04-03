// =============================================================================
// rv32im_core.sv - RISC-V RV32IM 5-Stage Pipelined Processor Core
// =============================================================================
// Description:
//   Top-level CPU core module integrating all pipeline stages, register file,
//   hazard detection/forwarding, CSR unit, exception handling, and M-extension
//   multiplier/divider. Supports context switching (RTOS), POSIX syscall
//   interface, and debug halt.
//
// Architecture:
//   5-stage pipeline: IF -> ID -> EX -> MEM -> WB
//   With full forwarding, hazard detection, and pipeline flush on
//   branch/exception/context-switch.
// =============================================================================

module rv32im_core
    import vsync_pkg::*;
(
    // Clock & Reset
    input  logic                    clk,
    input  logic                    rst_n,

    // Instruction Memory Interface
    output logic [IMEM_ADDR_W-1:0]  imem_addr,
    input  logic [XLEN-1:0]         imem_rdata,
    output logic                     imem_en,

    // Data Memory Interface (to axi4_master)
    output logic [XLEN-1:0]         mem_addr,
    output logic [XLEN-1:0]         mem_wdata,
    output logic                     mem_read,
    output logic                     mem_write,
    output logic [2:0]               mem_size,
    input  logic [XLEN-1:0]         mem_rdata,
    input  logic                     mem_ready,
    input  logic                     mem_error,

    // Interrupt Inputs
    input  logic                     external_irq,
    input  logic                     timer_irq,
    input  logic                     software_irq,

    // RTOS Control Interface
    input  logic                     ctx_switch_req,
    output logic                     ctx_switch_ack,
    output logic                     ctx_save_en,
    output logic [REG_ADDR_W-1:0]    ctx_save_reg_idx,
    output logic [XLEN-1:0]         ctx_save_reg_data,
    output logic [XLEN-1:0]         ctx_save_pc,
    input  logic                     ctx_restore_en,
    input  logic [REG_ADDR_W-1:0]    ctx_restore_reg_idx,
    input  logic [XLEN-1:0]         ctx_restore_reg_data,
    input  logic [XLEN-1:0]         ctx_restore_pc,
    input  logic [TASK_ID_W-1:0]     current_task_id,
    input  logic                     task_active,

    // POSIX Syscall Interface
    output logic                     ecall_req,
    output logic [7:0]               syscall_num,
    output logic [XLEN-1:0]         syscall_arg0,
    output logic [XLEN-1:0]         syscall_arg1,
    output logic [XLEN-1:0]         syscall_arg2,
    input  logic [XLEN-1:0]         syscall_ret,
    input  logic                     syscall_done,

    // Debug Interface (optional)
    input  logic                     debug_halt_req,
    output logic                     debug_halted,
    output logic [XLEN-1:0]         debug_pc,
    output logic [XLEN-1:0]         debug_instr,
    input  logic [REG_ADDR_W-1:0]    debug_reg_addr,
    output logic [XLEN-1:0]         debug_reg_data
);

    // =========================================================================
    // Internal Signal Declarations
    // =========================================================================

    // --- Pipeline register buses ---
    if_id_reg_t                 if_id_reg;
    id_ex_reg_t                 id_ex_reg;
    ex_mem_reg_t                ex_mem_reg;
    mem_wb_reg_t                mem_wb_reg;

    // --- Fetch stage signals ---
    logic [XLEN-1:0]           fetch_imem_addr;    // 32-bit from fetch_stage
    logic [XLEN-1:0]           fetch_pc;

    // --- Decode stage signals ---
    logic [REG_ADDR_W-1:0]     dec_rs1_addr;
    logic [REG_ADDR_W-1:0]     dec_rs2_addr;

    // --- Execute stage signals ---
    logic                       ex_branch_taken;
    logic [XLEN-1:0]           ex_branch_target;
    logic                       ex_mext_busy;

    // --- Memory stage signals ---
    logic [XLEN-1:0]           mem_dmem_addr;
    logic [XLEN-1:0]           mem_dmem_wdata;
    logic                       mem_dmem_we;
    logic [3:0]                 mem_dmem_be;
    logic                       mem_dmem_re;

    // --- Writeback stage signals ---
    logic [REG_ADDR_W-1:0]     wb_rd_addr;
    logic [XLEN-1:0]           wb_rd_data;
    logic                       wb_reg_write;

    // --- Register file port signals (after muxing) ---
    logic [REG_ADDR_W-1:0]     rf_rs1_addr;
    logic [XLEN-1:0]           rf_rs1_data;
    logic [REG_ADDR_W-1:0]     rf_rs2_addr;
    logic [XLEN-1:0]           rf_rs2_data;
    logic [REG_ADDR_W-1:0]     rf_rd_addr;
    logic [XLEN-1:0]           rf_rd_data;
    logic                       rf_reg_write;

    // --- Hazard control ---
    hazard_ctrl_t               hazard_ctrl;

    // --- CSR signals ---
    logic [XLEN-1:0]           csr_rdata;
    logic [XLEN-1:0]           csr_mtvec;
    logic [XLEN-1:0]           csr_mepc;
    logic [XLEN-1:0]           csr_mie_out;
    logic                       csr_mstatus_mie;
    logic                       csr_trap_pending;

    // --- Exception unit signals ---
    logic                       exc_exception_taken;
    logic [XLEN-1:0]           exc_exception_cause;
    logic [XLEN-1:0]           exc_exception_pc;
    logic [XLEN-1:0]           exc_exception_val;
    logic                       exc_mret_taken;
    logic [XLEN-1:0]           exc_redirect_pc;
    logic                       exc_redirect_valid;
    logic                       exc_flush_all;

    // --- MIP register (interrupt pending, constructed from external sources) ---
    logic [XLEN-1:0]           mip;

    // --- Pipeline stall/flush control ---
    logic                       stall_if;
    logic                       stall_id;
    logic                       stall_ex;
    logic                       stall_mem;
    logic                       flush_if;
    logic                       flush_id;
    logic                       flush_ex;
    logic                       flush_mem;

    // --- Branch resolution (combined with exception redirect) ---
    logic                       pipe_branch_taken;
    logic [XLEN-1:0]           pipe_branch_target;

    // --- Memory stall (for multi-cycle memory access) ---
    logic                       mem_stall;

    // --- Misalignment exception signals ---
    logic                       exc_load_misalign;
    logic                       exc_store_misalign;
    logic                       exc_instr_misalign;

    // --- Context switch state machine ---
    typedef enum logic [2:0] {
        CTX_IDLE,
        CTX_FLUSH,
        CTX_SAVE_REGS,
        CTX_SAVE_PC,
        CTX_WAIT_RESTORE,
        CTX_RESTORE_REGS,
        CTX_RESUME
    } ctx_state_t;

    ctx_state_t                 ctx_state;
    logic [REG_ADDR_W-1:0]     ctx_reg_counter;
    logic                       ctx_active;

    // --- Syscall state machine ---
    typedef enum logic [2:0] {
        SYS_IDLE,
        SYS_READ_A7,
        SYS_READ_A0,
        SYS_READ_A1,
        SYS_READ_A2,
        SYS_WAIT,
        SYS_WRITEBACK
    } syscall_state_t;

    syscall_state_t             sys_state;
    logic                       syscall_active;
    logic                       syscall_wb_en;
    logic [XLEN-1:0]           syscall_ret_data;
    logic [7:0]                 latched_syscall_num;
    logic [XLEN-1:0]           latched_syscall_arg0;
    logic [XLEN-1:0]           latched_syscall_arg1;
    logic [XLEN-1:0]           latched_syscall_arg2;

    // --- Debug state ---
    logic                       debug_halt_state;

    // --- Debug probe wires (for testbench hierarchical access in iverilog) ---
`ifdef IVERILOG
    wire [31:0] dbg_id_ex_pc        = id_ex_reg.pc;
    wire        dbg_id_ex_valid     = id_ex_reg.valid;
    wire [31:0] dbg_id_ex_rs1_data  = id_ex_reg.rs1_data;
    wire [4:0]  dbg_id_ex_rs1_addr  = id_ex_reg.rs1_addr;
    wire [31:0] dbg_ex_mem_pc       = ex_mem_reg.pc;
    wire        dbg_ex_mem_valid    = ex_mem_reg.valid;
    wire [31:0] dbg_ex_mem_alu      = ex_mem_reg.alu_result;
    wire [4:0]  dbg_ex_mem_rd       = ex_mem_reg.rd_addr;
    wire        dbg_ex_mem_rw       = ex_mem_reg.reg_write;
    wire        dbg_ex_mem_memrd    = ex_mem_reg.mem_read;
    wire [2:0]  dbg_ex_mem_funct3   = ex_mem_reg.mem_funct3;
    wire [31:0] dbg_mem_wb_pc       = mem_wb_reg.pc;
    wire        dbg_mem_wb_valid    = mem_wb_reg.valid;
    wire [31:0] dbg_mem_wb_memrdata = mem_wb_reg.mem_rdata;
    wire [31:0] dbg_mem_wb_alu      = mem_wb_reg.alu_result;
    wire [4:0]  dbg_mem_wb_rd       = mem_wb_reg.rd_addr;
    wire        dbg_mem_wb_rw       = mem_wb_reg.reg_write;
    wire [1:0]  dbg_mem_wb_wbsel    = mem_wb_reg.wb_sel;
    wire [1:0]  dbg_fwd_a           = hazard_ctrl.forward_a;
    wire [1:0]  dbg_fwd_b           = hazard_ctrl.forward_b;
    wire        dbg_stall_if_h      = hazard_ctrl.stall_if;
    wire        dbg_stall_id_h      = hazard_ctrl.stall_id;
    wire        dbg_flush_ex_h      = hazard_ctrl.flush_ex;
    wire        dbg_flush_if_h      = hazard_ctrl.flush_if;
    wire        dbg_flush_id_h      = hazard_ctrl.flush_id;
`endif

    // --- Memory request tracking ---
    // Tracks whether we have been stalling for the current memory operation.
    // This prevents a stale mem_ready from a previous operation from being
    // incorrectly accepted for a new operation.
    logic                       mem_req_sent;

    // =========================================================================
    // Pipeline Stall/Flush Logic
    // =========================================================================

    // A memory operation is present in the MEM stage
    logic mem_op_active;
    assign mem_op_active = (ex_mem_reg.mem_read || ex_mem_reg.mem_write) &&
                           ex_mem_reg.valid;

    // Memory request tracking: set on the first stall cycle of a memory
    // operation, cleared when the pipeline advances (mem_ready received
    // and no more stall). On the first cycle a memory operation enters MEM,
    // mem_req_sent is 0, forcing a stall regardless of mem_ready. This
    // ensures at least one cycle of latency for the memory to respond.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_req_sent <= 1'b0;
        end else begin
            if (mem_op_active && !mem_req_sent) begin
                // First cycle of memory operation: mark request as sent
                mem_req_sent <= 1'b1;
            end else if (mem_req_sent && mem_ready) begin
                // Memory responded: clear for next operation
                mem_req_sent <= 1'b0;
            end
        end
    end

    // Memory stall: pipeline stalls while waiting for memory.
    // Stalls until mem_req_sent is set (at least 1 cycle) AND mem_ready
    // is received from the memory subsystem.
    assign mem_stall = mem_op_active && !(mem_req_sent && mem_ready);

    // Combined stall signals
    assign stall_if  = hazard_ctrl.stall_if  || mem_stall || ctx_active ||
                       syscall_active || debug_halt_state || ex_mext_busy;
    assign stall_id  = hazard_ctrl.stall_id  || mem_stall || ctx_active ||
                       syscall_active || debug_halt_state || ex_mext_busy;
    assign stall_ex  = hazard_ctrl.stall_ex  || mem_stall || ctx_active ||
                       syscall_active || debug_halt_state || ex_mext_busy;
    assign stall_mem = mem_stall || ctx_active || syscall_active || debug_halt_state;

    // Combined flush signals - context switch flush takes effect during CTX_FLUSH
    // ecall_detected flushes IF/ID/EX to clear in-flight instructions, but NOT MEM
    // so that the instruction immediately before ecall (in MEM stage) completes its writeback.
    //
    // BUG FIX: Gate hazard_ctrl.flush_id (branch_taken) with !stall_ex.
    // When a branch/jump (JAL/JALR) in ID/EX triggers branch_taken simultaneously
    // with a stall (e.g., mem_stall from a store ahead in the pipeline):
    //   - execute_stage: stall > flush → EX/MEM holds, can't accept the branch
    //   - decode_stage:  flush > stall → ID/EX is cleared
    // This loses the branch instruction entirely — it's flushed from ID/EX but
    // never enters EX/MEM, so it never reaches WB and its link register write
    // (JAL: rd=ra, PC+4) never happens. By suppressing flush_id during stall_ex,
    // the branch instruction is preserved in ID/EX and replays when stall clears.
    assign flush_if  = hazard_ctrl.flush_if  || exc_flush_all || (ctx_state == CTX_FLUSH) || ecall_detected;
    assign flush_id  = (hazard_ctrl.flush_id && !stall_ex) || exc_flush_all || (ctx_state == CTX_FLUSH) || ecall_detected;
    assign flush_ex  = hazard_ctrl.flush_ex  || exc_flush_all || (ctx_state == CTX_FLUSH) || ecall_detected;
    assign flush_mem = hazard_ctrl.flush_mem || exc_flush_all || (ctx_state == CTX_FLUSH);

    // Branch/redirect mux: exception redirect takes priority, then ecall redirect, then branch
    //
    // BUG FIX: Gate ex_branch_taken with the same !load_use_hazard_ex condition
    // used for flush_if/flush_id (via hazard_ctrl.flush_if).
    // When load_use_hazard_ex is active, the branch instruction in EX has
    // UNRELIABLE operands (stale register value or wrong EX/MEM forwarding),
    // so its branch_taken result must NOT redirect the PC. The branch will be
    // correctly re-evaluated on the next cycle when the load data becomes
    // available via MEM/WB forwarding and load_use_hazard clears.
    // hazard_ctrl.flush_if = branch_taken && !load_use_hazard_ex, which is
    // exactly the gated branch signal needed here.
    assign pipe_branch_taken  = exc_redirect_valid ? 1'b1            :
                                ecall_detected     ? 1'b1            :
                                hazard_ctrl.flush_if;
    assign pipe_branch_target = exc_redirect_valid ? exc_redirect_pc :
                                ecall_detected     ? (id_ex_reg.pc + 32'd4) :
                                ex_branch_target;

    // =========================================================================
    // Instruction Memory Interface
    // =========================================================================

    // Truncate 32-bit fetch address to IMEM address width
    assign imem_addr = fetch_imem_addr[IMEM_ADDR_W-1:0];

    // Enable instruction memory when not stalled
    assign imem_en = !stall_if;

    // =========================================================================
    // Data Memory Interface Mapping
    // =========================================================================

    assign mem_addr  = mem_dmem_addr;
    assign mem_wdata = mem_dmem_wdata;
    assign mem_read  = mem_dmem_re  & ex_mem_reg.valid;
    assign mem_write = mem_dmem_we  & ex_mem_reg.valid;
    assign mem_size  = ex_mem_reg.mem_funct3;

    // =========================================================================
    // MIP (Machine Interrupt Pending) register construction
    // =========================================================================

    always_comb begin
        mip        = '0;
        mip[3]     = software_irq;     // MSIP
        mip[7]     = timer_irq;        // MTIP
        mip[11]    = external_irq;     // MEIP
    end

    // =========================================================================
    // Register File Read-Port Muxing
    // =========================================================================
    // RS1 port: context save reads x0-x31 sequentially; debug reads debug_reg_addr;
    //           normal operation reads dec_rs1_addr.
    // RS2 port: syscall reads a7/a0/a1/a2 sequentially; normal reads dec_rs2_addr.

    always_comb begin
        // RS1 port address mux
        if (ctx_state == CTX_SAVE_REGS) begin
            rf_rs1_addr = ctx_reg_counter;
        end else if (debug_halt_state) begin
            rf_rs1_addr = debug_reg_addr;
        end else begin
            rf_rs1_addr = dec_rs1_addr;
        end

        // RS2 port address mux
        case (sys_state)
            SYS_READ_A7: rf_rs2_addr = 5'd17;  // a7
            SYS_READ_A0: rf_rs2_addr = 5'd10;  // a0
            SYS_READ_A1: rf_rs2_addr = 5'd11;  // a1
            SYS_READ_A2: rf_rs2_addr = 5'd12;  // a2
            default:      rf_rs2_addr = dec_rs2_addr;
        endcase
    end

    // Register file write-port mux: context restore > syscall writeback > normal WB
    always_comb begin
        if (ctx_state == CTX_RESTORE_REGS && ctx_restore_en) begin
            rf_rd_addr   = ctx_restore_reg_idx;
            rf_rd_data   = ctx_restore_reg_data;
            rf_reg_write = 1'b1;
        end else if (syscall_wb_en) begin
            rf_rd_addr   = 5'd10;               // a0 = x10
            rf_rd_data   = syscall_ret_data;
            rf_reg_write = 1'b1;
        end else begin
            rf_rd_addr   = wb_rd_addr;
            rf_rd_data   = wb_rd_data;
            rf_reg_write = wb_reg_write;
        end
    end

    // =========================================================================
    // Fetch Stage
    // =========================================================================

    fetch_stage u_fetch_stage (
        .clk            (clk),
        .rst_n          (rst_n),
        .stall          (stall_if),
        .flush          (flush_if),
        .branch_taken   (pipe_branch_taken),
        .branch_target  (pipe_branch_target),
        .imem_addr      (fetch_imem_addr),
        .imem_rdata     (imem_rdata),
        .pc             (fetch_pc),
        .if_id_reg      (if_id_reg)
    );

    // =========================================================================
    // Decode Stage
    // =========================================================================

    decode_stage u_decode_stage (
        .clk            (clk),
        .rst_n          (rst_n),
        .if_id_reg      (if_id_reg),
        .stall          (stall_id),
        .flush          (flush_id),
        .rs1_data       (rf_rs1_data),
        .rs2_data       (rf_rs2_data),
        .rs1_addr       (dec_rs1_addr),
        .rs2_addr       (dec_rs2_addr),
        .id_ex_reg      (id_ex_reg)
    );

    // =========================================================================
    // Execute Stage
    // =========================================================================

    execute_stage u_execute_stage (
        .clk                (clk),
        .rst_n              (rst_n),
        .id_ex_reg          (id_ex_reg),
        .forward_a          (hazard_ctrl.forward_a),
        .forward_b          (hazard_ctrl.forward_b),
        .ex_mem_alu_result  (ex_mem_reg.alu_result),
        .wb_data            (wb_rd_data),
        .stall              (stall_ex),
        .flush              (flush_ex),
        .ex_mem_reg         (ex_mem_reg),
        .branch_taken       (ex_branch_taken),
        .branch_target      (ex_branch_target),
        .mext_busy          (ex_mext_busy)
    );

    // =========================================================================
    // Memory Stage
    // =========================================================================

    memory_stage u_memory_stage (
        .clk            (clk),
        .rst_n          (rst_n),
        .ex_mem_reg     (ex_mem_reg),
        .dmem_rdata     (mem_rdata),
        .dmem_addr      (mem_dmem_addr),
        .dmem_wdata     (mem_dmem_wdata),
        .dmem_we        (mem_dmem_we),
        .dmem_be        (mem_dmem_be),
        .dmem_re        (mem_dmem_re),
        .stall          (stall_mem),
        .flush          (flush_mem),
        .mem_wb_reg     (mem_wb_reg)
    );

    // =========================================================================
    // Writeback Stage
    // =========================================================================

    writeback_stage u_writeback_stage (
        .mem_wb_reg     (mem_wb_reg),
        .rd_addr        (wb_rd_addr),
        .rd_data        (wb_rd_data),
        .reg_write      (wb_reg_write)
    );

    // =========================================================================
    // Register File
    // =========================================================================

    register_file u_register_file (
        .clk            (clk),
        .rst_n          (rst_n),
        .rs1_addr       (rf_rs1_addr),
        .rs1_data       (rf_rs1_data),
        .rs2_addr       (rf_rs2_addr),
        .rs2_data       (rf_rs2_data),
        .rd_addr        (rf_rd_addr),
        .rd_data        (rf_rd_data),
        .reg_write      (rf_reg_write)
    );

    // =========================================================================
    // Hazard Unit
    // =========================================================================

    hazard_unit u_hazard_unit (
        .id_rs1_addr        (dec_rs1_addr),           // For load-use detection (ID stage)
        .id_rs2_addr        (dec_rs2_addr),           // For load-use detection (ID stage)
        .ex_rs1_addr        (id_ex_reg.rs1_addr),     // For forwarding (EX stage)
        .ex_rs2_addr        (id_ex_reg.rs2_addr),     // For forwarding (EX stage)
        .ex_mem_rd_addr     (ex_mem_reg.rd_addr),
        .ex_mem_reg_write   (ex_mem_reg.reg_write),
        .ex_mem_mem_read    (ex_mem_reg.mem_read),
        .mem_wb_rd_addr     (mem_wb_reg.rd_addr),
        .mem_wb_reg_write   (mem_wb_reg.reg_write),
        .branch_taken       (ex_branch_taken),
        .hazard_ctrl        (hazard_ctrl)
    );

    // =========================================================================
    // CSR Unit
    // =========================================================================

    // ---- iverilog workaround: extract packed struct fields via continuous assign ----
    // iverilog passes the full 189-bit struct instead of individual fields to ports.
`ifdef IVERILOG
    wire [1:0] iv_csr_op        = id_ex_reg.ctrl.csr_op;
    wire       iv_csr_en        = id_ex_reg.ctrl.csr_en;
    wire       iv_csr_imm       = id_ex_reg.ctrl.csr_imm;
    wire       iv_illegal_instr = id_ex_reg.ctrl.illegal_instr;
    wire       iv_ecall         = id_ex_reg.ctrl.ecall;
    wire       iv_ebreak        = id_ex_reg.ctrl.ebreak;
    wire       iv_mret          = id_ex_reg.ctrl.mret;
`endif

    csr_unit u_csr_unit (
        .clk                (clk),
        .rst_n              (rst_n),
        .csr_addr           (id_ex_reg.csr_addr),
        .csr_wdata          (id_ex_reg.rs1_data),
    `ifdef IVERILOG
        .csr_op             (iv_csr_op),
        .csr_en             (iv_csr_en & id_ex_reg.valid),
        .csr_imm            (iv_csr_imm),
    `else
        .csr_op             (id_ex_reg.ctrl.csr_op),
        .csr_en             (id_ex_reg.ctrl.csr_en & id_ex_reg.valid),
        .csr_imm            (id_ex_reg.ctrl.csr_imm),
    `endif
        .exception_taken    (exc_exception_taken),
        .exception_cause    (exc_exception_cause),
        .exception_pc       (exc_exception_pc),
        .exception_val      (exc_exception_val),
        .mret               (exc_mret_taken),
        .retire_valid       (mem_wb_reg.valid),
        .ext_irq            (external_irq),
        .timer_irq          (timer_irq),
        .sw_irq             (software_irq),
        .csr_rdata          (csr_rdata),
        .mtvec              (csr_mtvec),
        .mepc               (csr_mepc),
        .mie_out            (csr_mie_out),
        .mstatus_mie        (csr_mstatus_mie),
        .trap_pending       (csr_trap_pending)
    );

    // =========================================================================
    // Exception Unit
    // =========================================================================

    // Address misalignment detection
    always_comb begin
        exc_load_misalign  = 1'b0;
        exc_store_misalign = 1'b0;
        exc_instr_misalign = 1'b0;

        // Load alignment check based on funct3
        if (ex_mem_reg.valid && ex_mem_reg.mem_read) begin
            case (ex_mem_reg.mem_funct3[1:0])
                2'b01:   exc_load_misalign = ex_mem_reg.alu_result[0];      // Halfword
                2'b10:   exc_load_misalign = |ex_mem_reg.alu_result[1:0];   // Word
                default: exc_load_misalign = 1'b0;                          // Byte
            endcase
        end

        // Store alignment check based on funct3
        if (ex_mem_reg.valid && ex_mem_reg.mem_write) begin
            case (ex_mem_reg.mem_funct3[1:0])
                2'b01:   exc_store_misalign = ex_mem_reg.alu_result[0];
                2'b10:   exc_store_misalign = |ex_mem_reg.alu_result[1:0];
                default: exc_store_misalign = 1'b0;
            endcase
        end

        // Instruction address misalignment (branch/jump to non-aligned address)
        if (ex_branch_taken) begin
            exc_instr_misalign = |ex_branch_target[1:0];
        end
    end

    exception_unit u_exception_unit (
        .clk                (clk),
        .rst_n              (rst_n),
    `ifdef IVERILOG
        .illegal_instr      (iv_illegal_instr & id_ex_reg.valid),
        .ecall              (1'b0),
        .ebreak             (iv_ebreak        & id_ex_reg.valid),
        .mret               (iv_mret          & id_ex_reg.valid),
    `else
        .illegal_instr      (id_ex_reg.ctrl.illegal_instr & id_ex_reg.valid),
        .ecall              (1'b0),
        .ebreak             (id_ex_reg.ctrl.ebreak         & id_ex_reg.valid),
        .mret               (id_ex_reg.ctrl.mret           & id_ex_reg.valid),
    `endif
        .load_misalign      (exc_load_misalign),
        .store_misalign     (exc_store_misalign),
        .instr_misalign     (exc_instr_misalign),
        .pc                 (id_ex_reg.pc),
        .mstatus_mie        (csr_mstatus_mie & ~syscall_active),
        .mie                (csr_mie_out),
        .mip                (mip),
        .mtvec              (csr_mtvec),
        .mepc               (csr_mepc),
        .exception_taken    (exc_exception_taken),
        .exception_cause    (exc_exception_cause),
        .exception_pc       (exc_exception_pc),
        .exception_val      (exc_exception_val),
        .mret_taken         (exc_mret_taken),
        .redirect_pc        (exc_redirect_pc),
        .redirect_valid     (exc_redirect_valid),
        .flush_all          (exc_flush_all)
    );

    // =========================================================================
    // ECALL / Syscall Interface State Machine
    // =========================================================================
    //
    // When the decode stage detects an ECALL instruction, the pipeline is
    // stalled and we read a7 (x17), a0 (x10), a1 (x11), a2 (x12) from the
    // register file over 4 cycles using the rs2 read port. Then we assert
    // ecall_req and wait for syscall_done. On completion, syscall_ret is
    // written back to a0 (x10) via the register file write port.
    // =========================================================================

    logic ecall_detected;
`ifdef IVERILOG
    assign ecall_detected = id_ex_reg.valid && iv_ecall &&
                            (sys_state == SYS_IDLE);
`else
    assign ecall_detected = id_ex_reg.valid && id_ex_reg.ctrl.ecall &&
                            (sys_state == SYS_IDLE);
`endif

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sys_state            <= SYS_IDLE;
            latched_syscall_num  <= '0;
            latched_syscall_arg0 <= '0;
            latched_syscall_arg1 <= '0;
            latched_syscall_arg2 <= '0;
            syscall_ret_data     <= '0;
        end else begin
            case (sys_state)
                SYS_IDLE: begin
                    if (ecall_detected) begin
                        // Start reading a7 via rs2 port (address set combinationally)
                        sys_state <= SYS_READ_A7;
                    end
                end

                SYS_READ_A7: begin
                    // rs2 port was addressed to x17 (a7); latch data now
                    latched_syscall_num <= rf_rs2_data[7:0];
                    sys_state <= SYS_READ_A0;
                end

                SYS_READ_A0: begin
                    // rs2 port was addressed to x10 (a0); latch data now
                    latched_syscall_arg0 <= rf_rs2_data;
                    sys_state <= SYS_READ_A1;
                end

                SYS_READ_A1: begin
                    // rs2 port was addressed to x11 (a1); latch data now
                    latched_syscall_arg1 <= rf_rs2_data;
                    sys_state <= SYS_READ_A2;
                end

                SYS_READ_A2: begin
                    // rs2 port was addressed to x12 (a2); latch data now
                    latched_syscall_arg2 <= rf_rs2_data;
                    sys_state <= SYS_WAIT;
                end

                SYS_WAIT: begin
                    if (syscall_done) begin
                        syscall_ret_data <= syscall_ret;
                        sys_state <= SYS_WRITEBACK;
                    end
                end

                SYS_WRITEBACK: begin
                    // One cycle to write syscall_ret to a0 via write port mux
                    sys_state <= SYS_IDLE;
                end

                default: sys_state <= SYS_IDLE;
            endcase
        end
    end

    assign syscall_active = (sys_state != SYS_IDLE);
    assign ecall_req      = (sys_state == SYS_WAIT);
    assign syscall_wb_en  = (sys_state == SYS_WRITEBACK);

    // Syscall argument outputs (directly from latched values)
    assign syscall_num  = latched_syscall_num;
    assign syscall_arg0 = latched_syscall_arg0;
    assign syscall_arg1 = latched_syscall_arg1;
    assign syscall_arg2 = latched_syscall_arg2;

    // =========================================================================
    // Context Switch State Machine
    // =========================================================================
    //
    // Sequence:
    //   1. CTX_IDLE   -> CTX_FLUSH   : pipeline flush on ctx_switch_req
    //   2. CTX_FLUSH  -> CTX_SAVE_REGS: iterate x0-x31, output via ctx_save_*
    //   3. CTX_SAVE_REGS -> CTX_SAVE_PC: save current PC
    //   4. CTX_SAVE_PC -> CTX_WAIT_RESTORE: wait for hw_rtos to begin restore
    //   5. CTX_WAIT_RESTORE -> CTX_RESTORE_REGS: accept ctx_restore_en pulses
    //   6. CTX_RESTORE_REGS -> CTX_RESUME: when all regs restored
    //   7. CTX_RESUME -> CTX_IDLE: assert ctx_switch_ack, resume fetch at
    //      ctx_restore_pc
    // =========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctx_state       <= CTX_IDLE;
            ctx_reg_counter <= '0;
        end else begin
            case (ctx_state)
                CTX_IDLE: begin
                    if (ctx_switch_req && !syscall_active) begin
                        ctx_state       <= CTX_FLUSH;
                        ctx_reg_counter <= '0;
                    end
                end

                CTX_FLUSH: begin
                    // One cycle to flush the pipeline
                    ctx_state       <= CTX_SAVE_REGS;
                    ctx_reg_counter <= '0;
                end

                CTX_SAVE_REGS: begin
                    // Read x0..x31 via rs1 port (address = ctx_reg_counter)
                    if (ctx_reg_counter == 5'd31) begin
                        ctx_state <= CTX_SAVE_PC;
                    end else begin
                        ctx_reg_counter <= ctx_reg_counter + 5'd1;
                    end
                end

                CTX_SAVE_PC: begin
                    // PC is output this cycle; move to wait
                    ctx_state <= CTX_WAIT_RESTORE;
                end

                CTX_WAIT_RESTORE: begin
                    if (ctx_restore_en) begin
                        ctx_state       <= CTX_RESTORE_REGS;
                        ctx_reg_counter <= '0;
                    end
                end

                CTX_RESTORE_REGS: begin
                    // hw_rtos drives ctx_restore_en with idx/data each cycle
                    if (ctx_restore_en) begin
                        ctx_reg_counter <= ctx_reg_counter + 5'd1;
                    end
                    // After all 32 registers restored (counter wraps or restore_en drops)
                    if (!ctx_restore_en && ctx_reg_counter > 0) begin
                        ctx_state <= CTX_RESUME;
                    end
                end

                CTX_RESUME: begin
                    // Assert ack for one cycle, then resume
                    ctx_state <= CTX_IDLE;
                end

                default: ctx_state <= CTX_IDLE;
            endcase
        end
    end

    assign ctx_active = (ctx_state != CTX_IDLE);

    // Context switch output signals
    assign ctx_switch_ack    = (ctx_state == CTX_RESUME);
    assign ctx_save_en       = (ctx_state == CTX_SAVE_REGS);
    assign ctx_save_reg_idx  = ctx_reg_counter;
    assign ctx_save_reg_data = rf_rs1_data;     // Read through rs1 port
    assign ctx_save_pc       = fetch_pc;

    // =========================================================================
    // Debug Interface
    // =========================================================================

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debug_halt_state <= 1'b0;
        end else begin
            if (debug_halt_req && !debug_halt_state) begin
                debug_halt_state <= 1'b1;
            end else if (!debug_halt_req && debug_halt_state) begin
                debug_halt_state <= 1'b0;
            end
        end
    end

    assign debug_halted   = debug_halt_state;
    assign debug_pc       = fetch_pc;
    assign debug_instr    = if_id_reg.instruction;
    assign debug_reg_data = rf_rs1_data;    // Read through rs1 port when halted

endmodule : rv32im_core
