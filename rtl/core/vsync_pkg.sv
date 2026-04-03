// =============================================================================
// VSync - Common Package Definitions
// RISC-V RV32IM Processor with Hardware RTOS
//
// File: vsync_pkg.sv
// Description: Shared types, parameters, and definitions for all modules
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

package vsync_pkg;

    // =========================================================================
    // Global Parameters
    // =========================================================================
    parameter int XLEN        = 32;          // Register width
    parameter int ILEN        = 32;          // Instruction width
    parameter int NUM_REGS    = 32;          // Number of registers
    parameter int REG_ADDR_W  = 5;           // Register address width ($clog2(32))

    // =========================================================================
    // Memory Parameters
    // =========================================================================
    parameter int IMEM_SIZE   = 65536;       // 64KB instruction memory
    parameter int DMEM_SIZE   = 16384;       // 16KB data memory
    parameter int IMEM_ADDR_W = 16;          // $clog2(65536)
    parameter int DMEM_ADDR_W = 14;          // $clog2(16384)

    // =========================================================================
    // Address Map
    // =========================================================================
    parameter logic [31:0] ADDR_IMEM_BASE    = 32'h0000_0000;
    parameter logic [31:0] ADDR_IMEM_END     = 32'h0000_FFFF;
    parameter logic [31:0] ADDR_DMEM_BASE    = 32'h0001_0000;
    parameter logic [31:0] ADDR_DMEM_END     = 32'h0001_3FFF;
    parameter logic [31:0] ADDR_HYPERRAM_BASE= 32'h2000_0000;
    parameter logic [31:0] ADDR_HYPERRAM_END = 32'h2FFF_FFFF;
    parameter logic [31:0] ADDR_PLIC_BASE    = 32'h0C00_0000;
    parameter logic [31:0] ADDR_PLIC_END     = 32'h0C00_0FFF;
    parameter logic [31:0] ADDR_CLINT_BASE   = 32'h0200_0000;
    parameter logic [31:0] ADDR_CLINT_END    = 32'h0200_FFFF;
    parameter logic [31:0] ADDR_UART_BASE    = 32'h1000_0000;
    parameter logic [31:0] ADDR_UART_END     = 32'h1000_00FF;
    parameter logic [31:0] ADDR_GPIO_BASE    = 32'h1000_0100;
    parameter logic [31:0] ADDR_GPIO_END     = 32'h1000_01FF;
    parameter logic [31:0] ADDR_RTOS_BASE    = 32'h1100_0000;
    parameter logic [31:0] ADDR_RTOS_END     = 32'h1100_FFFF;
    parameter logic [31:0] ADDR_POSIX_BASE   = 32'h1200_0000;
    parameter logic [31:0] ADDR_POSIX_END    = 32'h1200_FFFF;

    // =========================================================================
    // Opcodes (RISC-V RV32IM)
    // =========================================================================
    typedef enum logic [6:0] {
        OP_LUI      = 7'b0110111,  // Load Upper Immediate
        OP_AUIPC    = 7'b0010111,  // Add Upper Immediate to PC
        OP_JAL      = 7'b1101111,  // Jump and Link
        OP_JALR     = 7'b1100111,  // Jump and Link Register
        OP_BRANCH   = 7'b1100011,  // Branch
        OP_LOAD     = 7'b0000011,  // Load
        OP_STORE    = 7'b0100011,  // Store
        OP_OP_IMM   = 7'b0010011,  // Arithmetic Immediate
        OP_OP       = 7'b0110011,  // Arithmetic Register
        OP_FENCE    = 7'b0001111,  // Fence
        OP_SYSTEM   = 7'b1110011   // System (ECALL, EBREAK, CSR)
    } opcode_t;

    // =========================================================================
    // Funct3 Encodings
    // =========================================================================

    // Branch funct3
    typedef enum logic [2:0] {
        F3_BEQ  = 3'b000,
        F3_BNE  = 3'b001,
        F3_BLT  = 3'b100,
        F3_BGE  = 3'b101,
        F3_BLTU = 3'b110,
        F3_BGEU = 3'b111
    } branch_funct3_t;

    // Load funct3
    typedef enum logic [2:0] {
        F3_LB   = 3'b000,
        F3_LH   = 3'b001,
        F3_LW   = 3'b010,
        F3_LBU  = 3'b100,
        F3_LHU  = 3'b101
    } load_funct3_t;

    // Store funct3
    typedef enum logic [2:0] {
        F3_SB   = 3'b000,
        F3_SH   = 3'b001,
        F3_SW   = 3'b010
    } store_funct3_t;

    // ALU funct3 (OP and OP_IMM)
    typedef enum logic [2:0] {
        F3_ADD_SUB = 3'b000,
        F3_SLL     = 3'b001,
        F3_SLT     = 3'b010,
        F3_SLTU    = 3'b011,
        F3_XOR     = 3'b100,
        F3_SRL_SRA = 3'b101,
        F3_OR      = 3'b110,
        F3_AND     = 3'b111
    } alu_funct3_t;

    // M-extension funct3
    typedef enum logic [2:0] {
        F3_MUL    = 3'b000,
        F3_MULH   = 3'b001,
        F3_MULHSU = 3'b010,
        F3_MULHU  = 3'b011,
        F3_DIV    = 3'b100,
        F3_DIVU   = 3'b101,
        F3_REM    = 3'b110,
        F3_REMU   = 3'b111
    } mext_funct3_t;

    // System/CSR funct3
    typedef enum logic [2:0] {
        F3_ECALL_EBREAK = 3'b000,
        F3_CSRRW        = 3'b001,
        F3_CSRRS        = 3'b010,
        F3_CSRRC        = 3'b011,
        F3_CSRRWI       = 3'b101,
        F3_CSRRSI       = 3'b110,
        F3_CSRRCI       = 3'b111
    } system_funct3_t;

    // =========================================================================
    // ALU Operation Encoding
    // =========================================================================
    typedef enum logic [3:0] {
        ALU_ADD  = 4'b0000,
        ALU_SUB  = 4'b0001,
        ALU_SLL  = 4'b0010,
        ALU_SLT  = 4'b0011,
        ALU_SLTU = 4'b0100,
        ALU_XOR  = 4'b0101,
        ALU_SRL  = 4'b0110,
        ALU_SRA  = 4'b0111,
        ALU_OR   = 4'b1000,
        ALU_AND  = 4'b1001,
        ALU_LUI  = 4'b1010,   // Pass operand B (for LUI)
        ALU_AUIPC= 4'b1011    // PC + operand B (for AUIPC)
    } alu_op_t;

    // =========================================================================
    // M-Extension Operation Encoding
    // =========================================================================
    typedef enum logic [2:0] {
        MEXT_MUL    = 3'b000,
        MEXT_MULH   = 3'b001,
        MEXT_MULHSU = 3'b010,
        MEXT_MULHU  = 3'b011,
        MEXT_DIV    = 3'b100,
        MEXT_DIVU   = 3'b101,
        MEXT_REM    = 3'b110,
        MEXT_REMU   = 3'b111
    } mext_op_t;

    // =========================================================================
    // Immediate Type Encoding
    // =========================================================================
    typedef enum logic [2:0] {
        IMM_I = 3'b000,
        IMM_S = 3'b001,
        IMM_B = 3'b010,
        IMM_U = 3'b011,
        IMM_J = 3'b100
    } imm_type_t;

    // =========================================================================
    // Pipeline Control Signals
    // =========================================================================

    // Decode stage output control signals
    typedef struct packed {
        // ALU control
        alu_op_t    alu_op;
        logic       alu_src_a;     // 0: rs1, 1: PC
        logic       alu_src_b;     // 0: rs2, 1: immediate
        // M-extension
        logic       mext_en;       // M-extension operation enable
        mext_op_t   mext_op;       // M-extension operation type
        // Register write
        logic       reg_write;     // Register file write enable
        logic [1:0] wb_sel;        // Writeback source: 00=ALU, 01=MEM, 10=PC+4, 11=CSR
        // Memory access
        logic       mem_read;      // Memory read enable
        logic       mem_write;     // Memory write enable
        logic [2:0] mem_funct3;    // Memory access size (funct3)
        // Branch/Jump
        logic       branch;        // Branch instruction
        logic       jal;           // JAL instruction
        logic       jalr;          // JALR instruction
        logic [2:0] branch_funct3; // Branch condition (funct3)
        // CSR
        logic       csr_en;        // CSR access enable
        logic [1:0] csr_op;        // CSR operation (RW=01, RS=10, RC=11)
        logic       csr_imm;       // CSR immediate mode
        // System
        logic       ecall;         // ECALL instruction
        logic       ebreak;        // EBREAK instruction
        logic       mret;          // MRET instruction
        logic       fence;         // FENCE instruction
        // Instruction info
        logic       illegal_instr; // Illegal instruction flag
    } ctrl_signals_t;

    // =========================================================================
    // Pipeline Register Structures
    // =========================================================================

    // IF/ID Pipeline Register
    typedef struct packed {
        logic [XLEN-1:0] pc;
        logic [ILEN-1:0] instruction;
        logic             valid;
    } if_id_reg_t;

    // ID/EX Pipeline Register
    typedef struct packed {
        logic [XLEN-1:0]      pc;
        logic [XLEN-1:0]      rs1_data;
        logic [XLEN-1:0]      rs2_data;
        logic [XLEN-1:0]      immediate;
        logic [REG_ADDR_W-1:0] rs1_addr;
        logic [REG_ADDR_W-1:0] rs2_addr;
        logic [REG_ADDR_W-1:0] rd_addr;
        logic [11:0]           csr_addr;
        ctrl_signals_t         ctrl;
        logic                  valid;
    } id_ex_reg_t;

    // EX/MEM Pipeline Register
    typedef struct packed {
        logic [XLEN-1:0]      pc;
        logic [XLEN-1:0]      alu_result;
        logic [XLEN-1:0]      rs2_data;       // Store data
        logic [XLEN-1:0]      csr_rdata;      // CSR read data
        logic [REG_ADDR_W-1:0] rd_addr;
        logic                  reg_write;
        logic [1:0]            wb_sel;
        logic                  mem_read;
        logic                  mem_write;
        logic [2:0]            mem_funct3;
        logic                  valid;
    } ex_mem_reg_t;

    // MEM/WB Pipeline Register
    typedef struct packed {
        logic [XLEN-1:0]      pc;
        logic [XLEN-1:0]      alu_result;
        logic [XLEN-1:0]      mem_rdata;
        logic [XLEN-1:0]      csr_rdata;
        logic [REG_ADDR_W-1:0] rd_addr;
        logic                  reg_write;
        logic [1:0]            wb_sel;
        logic                  valid;
    } mem_wb_reg_t;

    // =========================================================================
    // Hazard Unit Signals
    // =========================================================================
    typedef struct packed {
        logic stall_if;
        logic stall_id;
        logic stall_ex;
        logic flush_if;
        logic flush_id;
        logic flush_ex;
        logic flush_mem;
        // Forwarding
        logic [1:0] forward_a;  // 00: reg, 01: EX/MEM, 10: MEM/WB
        logic [1:0] forward_b;  // 00: reg, 01: EX/MEM, 10: MEM/WB
    } hazard_ctrl_t;

    // =========================================================================
    // CSR Addresses (Machine Mode)
    // =========================================================================
    parameter logic [11:0] CSR_MSTATUS   = 12'h300;
    parameter logic [11:0] CSR_MISA      = 12'h301;
    parameter logic [11:0] CSR_MIE       = 12'h304;
    parameter logic [11:0] CSR_MTVEC     = 12'h305;
    parameter logic [11:0] CSR_MSCRATCH  = 12'h340;
    parameter logic [11:0] CSR_MEPC      = 12'h341;
    parameter logic [11:0] CSR_MCAUSE    = 12'h342;
    parameter logic [11:0] CSR_MTVAL     = 12'h343;
    parameter logic [11:0] CSR_MIP       = 12'h344;
    parameter logic [11:0] CSR_MCYCLE    = 12'hB00;
    parameter logic [11:0] CSR_MCYCLEH   = 12'hB80;
    parameter logic [11:0] CSR_MINSTRET  = 12'hB02;
    parameter logic [11:0] CSR_MINSTRETH = 12'hB82;
    parameter logic [11:0] CSR_MVENDORID = 12'hF11;
    parameter logic [11:0] CSR_MARCHID   = 12'hF12;
    parameter logic [11:0] CSR_MIMPID    = 12'hF13;
    parameter logic [11:0] CSR_MHARTID   = 12'hF14;

    // =========================================================================
    // Exception/Interrupt Cause Codes
    // =========================================================================
    // Interrupts (mcause[31] = 1)
    parameter logic [31:0] CAUSE_M_SW_INT     = {1'b1, 31'd3};   // Machine SW interrupt
    parameter logic [31:0] CAUSE_M_TIMER_INT  = {1'b1, 31'd7};   // Machine timer interrupt
    parameter logic [31:0] CAUSE_M_EXT_INT    = {1'b1, 31'd11};  // Machine external interrupt

    // Exceptions (mcause[31] = 0)
    parameter logic [31:0] CAUSE_INSTR_MISALIGN  = {1'b0, 31'd0};
    parameter logic [31:0] CAUSE_INSTR_FAULT     = {1'b0, 31'd1};
    parameter logic [31:0] CAUSE_ILLEGAL_INSTR   = {1'b0, 31'd2};
    parameter logic [31:0] CAUSE_BREAKPOINT      = {1'b0, 31'd3};
    parameter logic [31:0] CAUSE_LOAD_MISALIGN   = {1'b0, 31'd4};
    parameter logic [31:0] CAUSE_LOAD_FAULT      = {1'b0, 31'd5};
    parameter logic [31:0] CAUSE_STORE_MISALIGN  = {1'b0, 31'd6};
    parameter logic [31:0] CAUSE_STORE_FAULT     = {1'b0, 31'd7};
    parameter logic [31:0] CAUSE_ECALL_M         = {1'b0, 31'd11};

    // =========================================================================
    // RTOS Task States
    // =========================================================================
    typedef enum logic [2:0] {
        TASK_READY     = 3'b000,
        TASK_RUNNING   = 3'b001,
        TASK_BLOCKED   = 3'b010,
        TASK_SUSPENDED = 3'b011,
        TASK_DORMANT   = 3'b100
    } task_state_t;

    // RTOS Parameters
    parameter int MAX_TASKS        = 16;
    parameter int TASK_ID_W        = 4;      // $clog2(MAX_TASKS)
    parameter int TASK_PRIORITY_W  = 4;      // 16 priority levels
    parameter int TIME_SLICE_W     = 16;     // Time slice counter width

    // =========================================================================
    // RTOS Task Control Block
    // =========================================================================
    typedef struct packed {
        logic [TASK_ID_W-1:0]       task_id;
        logic [TASK_PRIORITY_W-1:0] prio_level;
        task_state_t                state;
        logic [XLEN-1:0]           pc;
        logic [XLEN-1:0]           sp;
        logic [TIME_SLICE_W-1:0]   time_slice;
        logic                       valid;
    } tcb_t;

    // =========================================================================
    // AXI4 Parameters
    // =========================================================================
    parameter int AXI_ADDR_W   = 32;
    parameter int AXI_DATA_W   = 32;
    parameter int AXI_STRB_W   = AXI_DATA_W / 8;
    parameter int AXI_ID_W     = 4;
    parameter int AXI_LEN_W    = 8;

    // AXI4 Burst Types
    typedef enum logic [1:0] {
        AXI_BURST_FIXED = 2'b00,
        AXI_BURST_INCR  = 2'b01,
        AXI_BURST_WRAP  = 2'b10
    } axi_burst_t;

    // AXI4 Response Types
    typedef enum logic [1:0] {
        AXI_RESP_OKAY   = 2'b00,
        AXI_RESP_EXOKAY = 2'b01,
        AXI_RESP_SLVERR = 2'b10,
        AXI_RESP_DECERR = 2'b11
    } axi_resp_t;

    // =========================================================================
    // POSIX Syscall Numbers
    // =========================================================================
    // POSIX Syscall Numbers (per posix_mapping.md)
    // Organized by functional category with 8-bit encoding
    typedef enum logic [7:0] {
        // Thread Management (0x00-0x0F)
        SYS_PTHREAD_CREATE       = 8'h00,
        SYS_PTHREAD_EXIT         = 8'h01,
        SYS_PTHREAD_JOIN         = 8'h02,
        SYS_PTHREAD_DETACH       = 8'h03,
        SYS_PTHREAD_SELF         = 8'h04,
        SYS_PTHREAD_YIELD        = 8'h05,
        SYS_PTHREAD_SETSCHEDPARAM= 8'h06,
        SYS_PTHREAD_GETSCHEDPARAM= 8'h07,
        // Mutex Operations (0x10-0x1F)
        SYS_MUTEX_INIT           = 8'h10,
        SYS_MUTEX_LOCK           = 8'h11,
        SYS_MUTEX_TRYLOCK        = 8'h12,
        SYS_MUTEX_UNLOCK         = 8'h13,
        SYS_MUTEX_DESTROY        = 8'h14,
        // Semaphore Operations (0x20-0x2F)
        SYS_SEM_INIT             = 8'h20,
        SYS_SEM_WAIT             = 8'h21,
        SYS_SEM_TRYWAIT          = 8'h22,
        SYS_SEM_TIMEDWAIT        = 8'h23,
        SYS_SEM_POST             = 8'h24,
        SYS_SEM_GETVALUE         = 8'h25,
        SYS_SEM_DESTROY          = 8'h26,
        // Message Queue Operations (0x30-0x3F)
        SYS_MQ_OPEN              = 8'h30,
        SYS_MQ_SEND              = 8'h31,
        SYS_MQ_RECEIVE           = 8'h32,
        SYS_MQ_CLOSE             = 8'h33,
        SYS_MQ_TIMEDRECEIVE      = 8'h34,
        SYS_MQ_TIMEDSEND         = 8'h35,
        // Timer/Clock Operations (0x40-0x4F)
        SYS_CLOCK_GETTIME        = 8'h40,
        SYS_CLOCK_SETTIME        = 8'h41,
        SYS_NANOSLEEP            = 8'h42,
        SYS_TIMER_CREATE         = 8'h43,
        SYS_TIMER_SETTIME        = 8'h44,
        SYS_TIMER_DELETE         = 8'h45,
        SYS_TIMER_GETTIME        = 8'h46,
        // File I/O Operations (0x50-0x5F)
        SYS_OPEN                 = 8'h50,
        SYS_CLOSE                = 8'h51,
        SYS_READ                 = 8'h52,
        SYS_WRITE                = 8'h53,
        SYS_IOCTL                = 8'h54,
        SYS_LSEEK                = 8'h55,
        // Signal Operations (0x60-0x6F)
        SYS_KILL                 = 8'h60,
        SYS_SIGACTION            = 8'h61,
        SYS_SIGPROCMASK          = 8'h62,
        SYS_SIGWAIT              = 8'h63,
        SYS_RAISE                = 8'h64,
        // System Operations (0x70-0x7F)
        SYS_SYSCONF              = 8'h70,
        SYS_SCHED_GET_PRIO_MAX   = 8'h71,
        SYS_SCHED_GET_PRIO_MIN   = 8'h72,
        SYS_SBRK                 = 8'h73
    } syscall_num_t;

    // POSIX Error Codes (negative, 2's complement in 32-bit)
    parameter logic [31:0] POSIX_ENOMEM    = 32'hFFFF_FFF4; // -12
    parameter logic [31:0] POSIX_EINVAL    = 32'hFFFF_FFEA; // -22
    parameter logic [31:0] POSIX_EAGAIN    = 32'hFFFF_FFF5; // -11
    parameter logic [31:0] POSIX_EBUSY     = 32'hFFFF_FFF0; // -16
    parameter logic [31:0] POSIX_ETIMEDOUT = 32'hFFFF_FF92; // -110
    parameter logic [31:0] POSIX_ENOSYS    = 32'hFFFF_FFD8; // -38
    parameter logic [31:0] POSIX_EBADF     = 32'hFFFF_FFF7; // -9

    // POSIX Syscall Category Ranges
    parameter logic [7:0] SYSCALL_THREAD_BASE = 8'h00;
    parameter logic [7:0] SYSCALL_MUTEX_BASE  = 8'h10;
    parameter logic [7:0] SYSCALL_SEM_BASE    = 8'h20;
    parameter logic [7:0] SYSCALL_MSGQ_BASE   = 8'h30;
    parameter logic [7:0] SYSCALL_TIMER_BASE  = 8'h40;
    parameter logic [7:0] SYSCALL_FILE_BASE   = 8'h50;
    parameter logic [7:0] SYSCALL_SIGNAL_BASE = 8'h60;
    parameter logic [7:0] SYSCALL_SYSTEM_BASE = 8'h70;

    // =========================================================================
    // POSIX File Descriptor Parameters
    // =========================================================================
    parameter int MAX_FD       = 16;
    parameter int FD_WIDTH     = 4;    // $clog2(MAX_FD)

    typedef enum logic [2:0] {
        FD_TYPE_NONE   = 3'b000,
        FD_TYPE_UART   = 3'b001,
        FD_TYPE_GPIO   = 3'b010,
        FD_TYPE_MEM    = 3'b011,
        FD_TYPE_PIPE   = 3'b100
    } fd_type_t;

    typedef struct packed {
        logic           valid;
        fd_type_t       fd_type;
        logic [31:0]    base_addr;
        logic [15:0]    flags;
    } fd_entry_t;

endpackage : vsync_pkg
