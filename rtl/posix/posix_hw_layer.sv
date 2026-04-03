// =============================================================================
// VSync - POSIX Hardware Layer
// RISC-V RV32IM Processor with Hardware RTOS
//
// File: posix_hw_layer.sv
// Description: Hardware-implemented POSIX compatibility layer that dispatches
//              ECALL syscalls to appropriate hardware units (RTOS operations
//              or peripheral I/O). Implements syscall number decoding,
//              FD table management, and peripheral access control.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

module posix_hw_layer
    import vsync_pkg::*;
(
    // Clock & Reset
    input  logic                     clk,
    input  logic                     rst_n,

    // Syscall Dispatcher Interface (from rv32im_core)
    input  logic                     ecall_req,
    input  logic [7:0]               syscall_num,
    input  logic [XLEN-1:0]         syscall_arg0,
    input  logic [XLEN-1:0]         syscall_arg1,
    input  logic [XLEN-1:0]         syscall_arg2,
    output logic [XLEN-1:0]         syscall_ret,
    output logic                     syscall_done,

    // RTOS Control Output (to hw_rtos)
    output logic                     rtos_task_create,
    output logic [XLEN-1:0]         rtos_task_create_pc,
    output logic [XLEN-1:0]         rtos_task_create_sp,
    output logic [TASK_PRIORITY_W-1:0] rtos_task_create_prio,
    input  logic                     rtos_task_create_done,
    input  logic [TASK_ID_W-1:0]     rtos_task_create_id,
    output logic                     rtos_task_exit,
    output logic                     rtos_task_join,
    output logic [TASK_ID_W-1:0]     rtos_task_target_id,
    input  logic                     rtos_task_join_done,
    output logic                     rtos_task_yield,
    output logic [1:0]               rtos_sem_op,
    output logic [2:0]               rtos_sem_id,
    output logic [7:0]               rtos_sem_value,
    input  logic                     rtos_sem_done,
    input  logic                     rtos_sem_result,
    output logic [1:0]               rtos_mutex_op,
    output logic [2:0]               rtos_mutex_id,
    input  logic                     rtos_mutex_done,
    input  logic                     rtos_mutex_result,
    output logic [1:0]               rtos_msgq_op,
    output logic [1:0]               rtos_msgq_id,
    output logic [XLEN-1:0]         rtos_msgq_data,
    input  logic                     rtos_msgq_done,
    input  logic [XLEN-1:0]         rtos_msgq_result,
    input  logic                     rtos_msgq_success,

    // RTOS current task ID (for pthread_self, signal ops, etc.)
    input  logic [TASK_ID_W-1:0]     rtos_current_tid,

    // Peripheral Access Control
    output logic [XLEN-1:0]         periph_addr,
    output logic [XLEN-1:0]         periph_wdata,
    output logic                     periph_read,
    output logic                     periph_write,
    input  logic [XLEN-1:0]         periph_rdata,
    input  logic                     periph_ready,

    // AXI4 Slave Interface (FD table / status registers)
    input  logic [AXI_ADDR_W-1:0]   s_axi_awaddr,
    input  logic [2:0]               s_axi_awprot,
    input  logic                     s_axi_awvalid,
    output logic                     s_axi_awready,
    input  logic [AXI_DATA_W-1:0]   s_axi_wdata,
    input  logic [AXI_STRB_W-1:0]   s_axi_wstrb,
    input  logic                     s_axi_wvalid,
    output logic                     s_axi_wready,
    output logic [1:0]               s_axi_bresp,
    output logic                     s_axi_bvalid,
    input  logic                     s_axi_bready,
    input  logic [AXI_ADDR_W-1:0]   s_axi_araddr,
    input  logic [2:0]               s_axi_arprot,
    input  logic                     s_axi_arvalid,
    output logic                     s_axi_arready,
    output logic [AXI_DATA_W-1:0]   s_axi_rdata,
    output logic [1:0]               s_axi_rresp,
    output logic                     s_axi_rvalid,
    input  logic                     s_axi_rready
);

    // =========================================================================
    // Local Parameters
    // =========================================================================

    /** @brief Additional POSIX error codes not in vsync_pkg */
    localparam logic [31:0] POSIX_EMFILE  = 32'hFFFF_FFE4; // -28 (too many open files)
    localparam logic [31:0] POSIX_ENOENT  = 32'hFFFF_FFFE; // -2
    localparam logic [31:0] POSIX_EPERM   = 32'hFFFF_FFFF; // -1
    localparam logic [31:0] POSIX_ESPIPE  = 32'hFFFF_FFE3; // -29 (illegal seek)
    localparam logic [31:0] POSIX_ESRCH   = 32'hFFFF_FFFD; // -3

    /** @brief CLINT mtime addresses */
    localparam logic [31:0] ADDR_MTIME_LO = 32'h0200_BFF8;
    localparam logic [31:0] ADDR_MTIME_HI = 32'h0200_BFFC;

    /** @brief Sysconf constants */
    localparam int SC_NPROCESSORS_CONF  = 0;
    localparam int SC_NPROCESSORS_ONLN  = 1;
    localparam int SC_PAGE_SIZE         = 2;
    localparam int SC_THREAD_THREADS_MAX= 3;
    localparam int SC_SEM_NSEMS_MAX     = 4;
    localparam int SC_SEM_VALUE_MAX     = 5;
    localparam int SC_MQ_OPEN_MAX       = 6;
    localparam int SC_TIMER_MAX         = 7;
    localparam int SC_OPEN_MAX          = 8;
    localparam int SC_CLK_TCK           = 9;

    /** @brief Device base addresses for FD table */
    localparam logic [31:0] UART_BASE_ADDR = ADDR_UART_BASE;  // 0x1000_0000
    localparam logic [31:0] GPIO_BASE_ADDR = ADDR_GPIO_BASE;  // 0x1000_0100
    localparam logic [31:0] HRAM_BASE_ADDR = ADDR_HYPERRAM_BASE; // 0x2000_0000

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    typedef enum logic [3:0] {
        S_IDLE        = 4'h0,
        S_DECODE      = 4'h1,
        S_THREAD_OP   = 4'h2,
        S_MUTEX_OP    = 4'h3,
        S_SEM_OP      = 4'h4,
        S_MSGQ_OP     = 4'h5,
        S_TIMER_OP    = 4'h6,
        S_FILE_OP     = 4'h7,
        S_SIGNAL_OP   = 4'h8,
        S_SYSTEM_OP   = 4'h9,
        S_PERIPH_WAIT = 4'hA,
        S_WAIT_RTOS   = 4'hB,
        S_COMPLETE    = 4'hC
    } posix_state_t;

    // =========================================================================
    // Internal Signals and Registers
    // =========================================================================

    posix_state_t state_r, state_next;

    // Latched syscall parameters
    logic [7:0]       latched_syscall_num;
    logic [XLEN-1:0]  latched_arg0;
    logic [XLEN-1:0]  latched_arg1;
    logic [XLEN-1:0]  latched_arg2;

    // Syscall category (upper nibble) and sub-operation (lower nibble)
    wire [3:0] syscall_category = latched_syscall_num[7:4];
    wire [3:0] syscall_subop    = latched_syscall_num[3:0];

    // Return value register
    logic [XLEN-1:0] result_r;

    // FD Table (decomposed from fd_entry_t for iverilog compatibility)
    logic            fd_valid     [MAX_FD];
    logic [2:0]      fd_type_r    [MAX_FD]; // fd_type_t encoded
    logic [31:0]     fd_base_addr [MAX_FD];
    logic [15:0]     fd_flags     [MAX_FD];

    // Pending syscall counter (for debug)
    logic [7:0]  pending_syscall_cnt;
    logic [7:0]  last_syscall_num_r;
    logic [31:0] last_syscall_ret_r;

    // Heap break table (per-task)
    logic [XLEN-1:0] heap_brk [MAX_TASKS];

    // Signal tables (simplified: per-task pending and mask)
    logic [31:0] signal_pending [MAX_TASKS];
    logic [31:0] signal_mask    [MAX_TASKS];
    logic [31:0] sig_handler    [MAX_TASKS]; // Simplified: one handler addr per task

    // Signal wait set
    logic [31:0] sigwait_set [MAX_TASKS];

    // Current task ID tracker (read from hw_rtos; for signal/system ops we use arg)
    // Note: pthread_self needs current_task_id from hw_rtos. For this implementation,
    // we use rtos_task_create_id as a shared signal. In a full system, a dedicated
    // port would exist. Here we approximate with a local tracker.
    logic [TASK_ID_W-1:0] current_tid_r;

    // Peripheral access return-to state
    posix_state_t periph_return_state;

    // =========================================================================
    // FSM: State Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state_r <= S_IDLE;
        else
            state_r <= state_next;
    end

    // =========================================================================
    // Latch Syscall Parameters on ECALL Request
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latched_syscall_num <= 8'h0;
            latched_arg0        <= '0;
            latched_arg1        <= '0;
            latched_arg2        <= '0;
        end else if (ecall_req && state_r == S_IDLE) begin
            latched_syscall_num <= syscall_num;
            latched_arg0        <= syscall_arg0;
            latched_arg1        <= syscall_arg1;
            latched_arg2        <= syscall_arg2;
        end
    end

    // =========================================================================
    // Debug Counters
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_syscall_cnt <= 8'h0;
            last_syscall_num_r  <= 8'h0;
            last_syscall_ret_r  <= '0;
        end else begin
            if (ecall_req && state_r == S_IDLE)
                pending_syscall_cnt <= pending_syscall_cnt + 8'h1;
            if (state_r == S_COMPLETE) begin
                last_syscall_num_r <= latched_syscall_num;
                last_syscall_ret_r <= result_r;
            end
        end
    end

    // =========================================================================
    // FD Table Initialization and Management
    // =========================================================================

    /**
     * @brief Find first free FD slot (skip stdin/stdout/stderr 0-2)
     * @return Free FD index or MAX_FD if none available
     */
    logic [FD_WIDTH:0] free_fd_idx; // Extra bit for overflow detection
    always_comb begin
        free_fd_idx = MAX_FD[FD_WIDTH:0]; // Default: no free slot
        for (int i = 3; i < MAX_FD; i++) begin
            if (!fd_valid[i] && free_fd_idx == MAX_FD[FD_WIDTH:0]) begin
                free_fd_idx = i[FD_WIDTH:0];
            end
        end
    end

    /**
     * @brief Resolve device base address from fd_type
     */
    function automatic logic [31:0] get_device_base(fd_type_t dtype);
        case (dtype)
            FD_TYPE_UART: return UART_BASE_ADDR;
            FD_TYPE_GPIO: return GPIO_BASE_ADDR;
            FD_TYPE_MEM:  return HRAM_BASE_ADDR;
            default:      return '0;
        endcase
    endfunction

    // FD table reset and update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize all FD entries to invalid
            for (int i = 0; i < MAX_FD; i++) begin
                fd_valid[i]     <= 1'b0;
                fd_type_r[i]    <= FD_TYPE_NONE;
                fd_base_addr[i] <= '0;
                fd_flags[i]     <= '0;
            end
            // Pre-initialize stdin (fd=0): UART RX, read-only
            fd_valid[0]     <= 1'b1;
            fd_type_r[0]    <= FD_TYPE_UART;
            fd_base_addr[0] <= UART_BASE_ADDR;
            fd_flags[0]     <= 16'h0000; // O_RDONLY

            // Pre-initialize stdout (fd=1): UART TX, write-only
            fd_valid[1]     <= 1'b1;
            fd_type_r[1]    <= FD_TYPE_UART;
            fd_base_addr[1] <= UART_BASE_ADDR;
            fd_flags[1]     <= 16'h0001; // O_WRONLY

            // Pre-initialize stderr (fd=2): UART TX, write-only
            fd_valid[2]     <= 1'b1;
            fd_type_r[2]    <= FD_TYPE_UART;
            fd_base_addr[2] <= UART_BASE_ADDR;
            fd_flags[2]     <= 16'h0001; // O_WRONLY
        end else if (state_r == S_FILE_OP) begin
            case (syscall_subop)
                // open (0x50 -> subop=0x0)
                4'h0: begin
                    if (free_fd_idx < MAX_FD[FD_WIDTH:0]) begin
                        fd_valid[free_fd_idx[FD_WIDTH-1:0]]     <= 1'b1;
                        fd_type_r[free_fd_idx[FD_WIDTH-1:0]]    <= latched_arg0[2:0];
                        fd_base_addr[free_fd_idx[FD_WIDTH-1:0]] <= get_device_base(fd_type_t'(latched_arg0[2:0]));
                        fd_flags[free_fd_idx[FD_WIDTH-1:0]]     <= latched_arg1[15:0];
                    end
                end
                // close (0x51 -> subop=0x1)
                4'h1: begin
                    if (latched_arg0 < MAX_FD && fd_valid[latched_arg0[FD_WIDTH-1:0]]
                        && latched_arg0[FD_WIDTH-1:0] > 2) begin
                        fd_valid[latched_arg0[FD_WIDTH-1:0]]   <= 1'b0;
                        fd_type_r[latched_arg0[FD_WIDTH-1:0]]  <= FD_TYPE_NONE;
                    end
                end
                default: ; // read/write/ioctl/lseek handled via peripheral interface
            endcase
        end
    end

    // =========================================================================
    // Signal/Heap Table Management
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MAX_TASKS; i++) begin
                signal_pending[i] <= '0;
                signal_mask[i]    <= '0;
                sig_handler[i]    <= '0;
                sigwait_set[i]    <= '0;
                heap_brk[i]       <= '0;
            end
            current_tid_r <= '0;
        end else begin
            // REVIEW-008 fix: Synchronize current_tid_r from hw_rtos current_task_id
            // This ensures pthread_self() and signal ops use the correct task ID
            // after context switches, not just after task creation
            if (rtos_current_tid != current_tid_r) begin
                current_tid_r <= rtos_current_tid;
            end

            // Signal operations in S_SIGNAL_OP
            if (state_r == S_SIGNAL_OP) begin
                case (syscall_subop)
                    // kill (0x60 -> subop=0x0)
                    4'h0: begin
                        if (latched_arg0 < MAX_TASKS && latched_arg1 < 32 && latched_arg1 != 0)
                            signal_pending[latched_arg0[TASK_ID_W-1:0]] <=
                                signal_pending[latched_arg0[TASK_ID_W-1:0]] | (32'h1 << latched_arg1[4:0]);
                    end
                    // sigaction (0x61 -> subop=0x1)
                    4'h1: begin
                        if (latched_arg0 < 32 && latched_arg0 != 0 && latched_arg0 != 9)
                            sig_handler[current_tid_r] <= latched_arg1;
                    end
                    // sigprocmask (0x62 -> subop=0x2)
                    4'h2: begin
                        case (latched_arg0[1:0])
                            2'b00: signal_mask[current_tid_r] <=
                                      (signal_mask[current_tid_r] | latched_arg1) & ~(32'h1 << 9);
                            2'b01: signal_mask[current_tid_r] <=
                                      (signal_mask[current_tid_r] & ~latched_arg1) & ~(32'h1 << 9);
                            2'b10: signal_mask[current_tid_r] <=
                                      latched_arg1 & ~(32'h1 << 9);
                            default: ;
                        endcase
                    end
                    // sigwait (0x63 -> subop=0x3)
                    4'h3: begin
                        if (latched_arg0 != 0)
                            sigwait_set[current_tid_r] <= latched_arg0;
                    end
                    // raise (0x64 -> subop=0x4)
                    4'h4: begin
                        if (latched_arg0 < 32 && latched_arg0 != 0)
                            signal_pending[current_tid_r] <=
                                signal_pending[current_tid_r] | (32'h1 << latched_arg0[4:0]);
                    end
                    default: ;
                endcase
            end

            // sbrk updates in S_SYSTEM_OP
            if (state_r == S_SYSTEM_OP && syscall_subop == 4'h3) begin
                heap_brk[current_tid_r] <= heap_brk[current_tid_r] + latched_arg0;
            end
        end
    end

    // =========================================================================
    // FSM: Next State and Output Logic
    // =========================================================================
    always_comb begin
        // Default outputs
        state_next        = state_r;
        syscall_done      = 1'b0;
        syscall_ret       = '0;

        rtos_task_create   = 1'b0;
        rtos_task_create_pc  = '0;
        rtos_task_create_sp  = '0;
        rtos_task_create_prio= '0;
        rtos_task_exit     = 1'b0;
        rtos_task_join     = 1'b0;
        rtos_task_target_id = '0;
        rtos_task_yield    = 1'b0;

        rtos_sem_op        = 2'b00;
        rtos_sem_id        = 3'b000;
        rtos_sem_value     = 8'h00;

        rtos_mutex_op      = 2'b00;
        rtos_mutex_id      = 3'b000;

        rtos_msgq_op       = 2'b00;
        rtos_msgq_id       = 2'b00;
        rtos_msgq_data     = '0;

        periph_addr        = '0;
        periph_wdata       = '0;
        periph_read        = 1'b0;
        periph_write       = 1'b0;

        case (state_r)
            // -----------------------------------------------------------------
            // S_IDLE: Wait for ecall_req
            // -----------------------------------------------------------------
            S_IDLE: begin
                if (ecall_req)
                    state_next = S_DECODE;
            end

            // -----------------------------------------------------------------
            // S_DECODE: Route based on syscall category
            // -----------------------------------------------------------------
            S_DECODE: begin
                case (syscall_category)
                    4'h0: state_next = S_THREAD_OP;
                    4'h1: state_next = S_MUTEX_OP;
                    4'h2: state_next = S_SEM_OP;
                    4'h3: state_next = S_MSGQ_OP;
                    4'h4: state_next = S_TIMER_OP;
                    4'h5: state_next = S_FILE_OP;
                    4'h6: state_next = S_SIGNAL_OP;
                    4'h7: state_next = S_SYSTEM_OP;
                    default: begin
                        // Unsupported syscall category
                        state_next = S_COMPLETE;
                    end
                endcase
            end

            // -----------------------------------------------------------------
            // S_THREAD_OP: Thread management (0x00-0x0F)
            // -----------------------------------------------------------------
            S_THREAD_OP: begin
                case (syscall_subop)
                    // pthread_create (0x00)
                    4'h0: begin
                        rtos_task_create      = 1'b1;
                        rtos_task_create_pc   = latched_arg0;
                        rtos_task_create_sp   = latched_arg1;
                        rtos_task_create_prio = latched_arg2[TASK_PRIORITY_W-1:0];
                        state_next            = S_WAIT_RTOS;
                    end
                    // pthread_exit (0x01)
                    4'h1: begin
                        rtos_task_exit = 1'b1;
                        state_next     = S_COMPLETE;
                    end
                    // pthread_join (0x02) - dedicated join command to hw_rtos
                    // REVIEW-007 fix: Use dedicated rtos_task_join signal
                    4'h2: begin
                        rtos_task_join      = 1'b1;
                        rtos_task_target_id = latched_arg0[TASK_ID_W-1:0];
                        state_next          = S_WAIT_RTOS;
                    end
                    // pthread_self (0x04)
                    4'h4: begin
                        state_next = S_COMPLETE;
                    end
                    // pthread_yield (0x05)
                    4'h5: begin
                        rtos_task_yield = 1'b1;
                        state_next      = S_COMPLETE;
                    end
                    // pthread_setschedparam (0x06) - via hw_rtos
                    4'h6: begin
                        rtos_task_create      = 1'b1;
                        rtos_task_create_pc   = latched_arg0; // thread_id
                        rtos_task_create_sp   = latched_arg1; // new_priority
                        rtos_task_create_prio = '0;
                        state_next            = S_WAIT_RTOS;
                    end
                    // pthread_getschedparam (0x07) - via hw_rtos
                    4'h7: begin
                        rtos_task_create      = 1'b1;
                        rtos_task_create_pc   = latched_arg0; // thread_id
                        rtos_task_create_sp   = '0;
                        rtos_task_create_prio = '0;
                        state_next            = S_WAIT_RTOS;
                    end
                    // pthread_detach (0x03) and others
                    default: begin
                        state_next = S_COMPLETE;
                    end
                endcase
            end

            // -----------------------------------------------------------------
            // S_MUTEX_OP: Mutex operations (0x10-0x1F)
            // -----------------------------------------------------------------
            S_MUTEX_OP: begin
                rtos_mutex_id = latched_arg0[2:0];
                case (syscall_subop)
                    // mutex_init (0x10)
                    4'h0: begin
                        rtos_mutex_op = 2'b01;
                        state_next    = S_WAIT_RTOS;
                    end
                    // mutex_lock (0x11)
                    4'h1: begin
                        rtos_mutex_op = 2'b10;
                        state_next    = S_WAIT_RTOS;
                    end
                    // mutex_trylock (0x12)
                    4'h2: begin
                        rtos_mutex_op = 2'b10;
                        state_next    = S_WAIT_RTOS;
                    end
                    // mutex_unlock (0x13)
                    4'h3: begin
                        rtos_mutex_op = 2'b11;
                        state_next    = S_WAIT_RTOS;
                    end
                    // mutex_destroy (0x14)
                    4'h4: begin
                        rtos_mutex_op = 2'b01;
                        state_next    = S_WAIT_RTOS;
                    end
                    default: begin
                        state_next = S_COMPLETE;
                    end
                endcase
            end

            // -----------------------------------------------------------------
            // S_SEM_OP: Semaphore operations (0x20-0x2F)
            // -----------------------------------------------------------------
            S_SEM_OP: begin
                rtos_sem_id = latched_arg0[2:0];
                case (syscall_subop)
                    // sem_init (0x20)
                    4'h0: begin
                        rtos_sem_op    = 2'b01;
                        rtos_sem_value = latched_arg1[7:0];
                        state_next     = S_WAIT_RTOS;
                    end
                    // sem_wait (0x21)
                    4'h1: begin
                        rtos_sem_op = 2'b10;
                        state_next  = S_WAIT_RTOS;
                    end
                    // sem_trywait (0x22)
                    4'h2: begin
                        rtos_sem_op = 2'b10;
                        state_next  = S_WAIT_RTOS;
                    end
                    // sem_timedwait (0x23)
                    4'h3: begin
                        rtos_sem_op = 2'b10;
                        state_next  = S_WAIT_RTOS;
                    end
                    // sem_post (0x24)
                    4'h4: begin
                        rtos_sem_op = 2'b11;
                        state_next  = S_WAIT_RTOS;
                    end
                    // sem_getvalue (0x25)
                    4'h5: begin
                        rtos_sem_op = 2'b01;
                        state_next  = S_WAIT_RTOS;
                    end
                    // sem_destroy (0x26)
                    4'h6: begin
                        rtos_sem_op = 2'b01;
                        state_next  = S_WAIT_RTOS;
                    end
                    default: begin
                        state_next = S_COMPLETE;
                    end
                endcase
            end

            // -----------------------------------------------------------------
            // S_MSGQ_OP: Message queue operations (0x30-0x3F)
            // -----------------------------------------------------------------
            S_MSGQ_OP: begin
                rtos_msgq_id = latched_arg0[1:0];
                case (syscall_subop)
                    // mq_open (0x30)
                    4'h0: begin
                        rtos_msgq_op = 2'b01;
                        state_next   = S_WAIT_RTOS;
                    end
                    // mq_send (0x31)
                    4'h1: begin
                        rtos_msgq_op   = 2'b10;
                        rtos_msgq_data = latched_arg1;
                        state_next     = S_WAIT_RTOS;
                    end
                    // mq_receive (0x32)
                    4'h2: begin
                        rtos_msgq_op = 2'b11;
                        state_next   = S_WAIT_RTOS;
                    end
                    // mq_close (0x33)
                    4'h3: begin
                        rtos_msgq_op = 2'b01;
                        state_next   = S_WAIT_RTOS;
                    end
                    // mq_timedreceive (0x34)
                    4'h4: begin
                        rtos_msgq_op = 2'b11;
                        state_next   = S_WAIT_RTOS;
                    end
                    // mq_timedsend (0x35)
                    4'h5: begin
                        rtos_msgq_op   = 2'b10;
                        rtos_msgq_data = latched_arg1;
                        state_next     = S_WAIT_RTOS;
                    end
                    default: begin
                        state_next = S_COMPLETE;
                    end
                endcase
            end

            // -----------------------------------------------------------------
            // S_TIMER_OP: Timer operations via CLINT peripheral (0x40-0x4F)
            // -----------------------------------------------------------------
            S_TIMER_OP: begin
                case (syscall_subop)
                    // clock_gettime (0x40): read mtime_lo via periph
                    4'h0: begin
                        periph_addr = ADDR_MTIME_LO;
                        periph_read = 1'b1;
                        state_next  = S_PERIPH_WAIT;
                    end
                    // clock_settime (0x41): write mtime_hi first
                    4'h1: begin
                        periph_addr  = ADDR_MTIME_HI;
                        periph_wdata = latched_arg2;
                        periph_write = 1'b1;
                        state_next   = S_PERIPH_WAIT;
                    end
                    // nanosleep (0x42): write to CLINT mtimecmp via periph
                    4'h2: begin
                        // First read current mtime to compute deadline
                        periph_addr = ADDR_MTIME_LO;
                        periph_read = 1'b1;
                        state_next  = S_PERIPH_WAIT;
                    end
                    // timer_create through timer_gettime (0x43-0x46)
                    // Route through peripheral to CLINT
                    default: begin
                        periph_addr = ADDR_CLINT_BASE + {24'h0, latched_syscall_num[3:0], 4'h0};
                        periph_read = 1'b1;
                        state_next  = S_PERIPH_WAIT;
                    end
                endcase
            end

            // -----------------------------------------------------------------
            // S_FILE_OP: File I/O operations (0x50-0x5F)
            // -----------------------------------------------------------------
            S_FILE_OP: begin
                case (syscall_subop)
                    // open (0x50)
                    4'h0: begin
                        // FD table update handled in sequential block above
                        state_next = S_COMPLETE;
                    end
                    // close (0x51)
                    4'h1: begin
                        // FD table update handled in sequential block above
                        state_next = S_COMPLETE;
                    end
                    // read (0x52): route to peripheral based on fd_type
                    4'h2: begin
                        if (latched_arg0 < MAX_FD && fd_valid[latched_arg0[FD_WIDTH-1:0]]) begin
                            periph_addr = fd_base_addr[latched_arg0[FD_WIDTH-1:0]];
                            // For UART read: read from RX data register (base + 0x04)
                            if (fd_type_t'(fd_type_r[latched_arg0[FD_WIDTH-1:0]]) == FD_TYPE_UART)
                                periph_addr = fd_base_addr[latched_arg0[FD_WIDTH-1:0]] + 32'h04;
                            periph_read = 1'b1;
                            state_next  = S_PERIPH_WAIT;
                        end else begin
                            state_next = S_COMPLETE;
                        end
                    end
                    // write (0x53): route to peripheral based on fd_type
                    4'h3: begin
                        if (latched_arg0 < MAX_FD && fd_valid[latched_arg0[FD_WIDTH-1:0]]) begin
                            periph_addr  = fd_base_addr[latched_arg0[FD_WIDTH-1:0]];
                            // For UART write: write to TX data register (base + 0x00)
                            periph_wdata = latched_arg1;
                            periph_write = 1'b1;
                            state_next   = S_PERIPH_WAIT;
                        end else begin
                            state_next = S_COMPLETE;
                        end
                    end
                    // ioctl (0x54): route to peripheral
                    4'h4: begin
                        if (latched_arg0 < MAX_FD && fd_valid[latched_arg0[FD_WIDTH-1:0]]) begin
                            periph_addr  = fd_base_addr[latched_arg0[FD_WIDTH-1:0]] +
                                           {20'h0, latched_arg1[11:0]};
                            periph_wdata = latched_arg2;
                            periph_write = 1'b1;
                            state_next   = S_PERIPH_WAIT;
                        end else begin
                            state_next = S_COMPLETE;
                        end
                    end
                    // lseek (0x55): internal position update
                    4'h5: begin
                        state_next = S_COMPLETE;
                    end
                    default: begin
                        state_next = S_COMPLETE;
                    end
                endcase
            end

            // -----------------------------------------------------------------
            // S_SIGNAL_OP: Signal operations (0x60-0x6F) - internal processing
            // -----------------------------------------------------------------
            S_SIGNAL_OP: begin
                // All signal table updates in sequential block; compute result here
                state_next = S_COMPLETE;
            end

            // -----------------------------------------------------------------
            // S_SYSTEM_OP: System operations (0x70-0x7F) - internal processing
            // -----------------------------------------------------------------
            S_SYSTEM_OP: begin
                state_next = S_COMPLETE;
            end

            // -----------------------------------------------------------------
            // S_PERIPH_WAIT: Wait for peripheral access completion
            // -----------------------------------------------------------------
            S_PERIPH_WAIT: begin
                if (periph_ready)
                    state_next = S_COMPLETE;
            end

            // -----------------------------------------------------------------
            // S_WAIT_RTOS: Wait for RTOS operation completion
            // -----------------------------------------------------------------
            S_WAIT_RTOS: begin
                // Maintain operation signals while waiting
                case (syscall_category)
                    4'h0: begin // Thread ops
                        case (syscall_subop)
                            4'h0: begin // pthread_create
                                rtos_task_create      = 1'b1;
                                rtos_task_create_pc   = latched_arg0;
                                rtos_task_create_sp   = latched_arg1;
                                rtos_task_create_prio = latched_arg2[TASK_PRIORITY_W-1:0];
                                if (rtos_task_create_done)
                                    state_next = S_COMPLETE;
                            end
                            4'h2: begin // pthread_join - REVIEW-007 fix
                                rtos_task_join      = 1'b1;
                                rtos_task_target_id = latched_arg0[TASK_ID_W-1:0];
                                if (rtos_task_join_done)
                                    state_next = S_COMPLETE;
                            end
                            default: begin
                                if (rtos_task_create_done)
                                    state_next = S_COMPLETE;
                            end
                        endcase
                    end
                    4'h1: begin // Mutex ops
                        rtos_mutex_id = latched_arg0[2:0];
                        case (syscall_subop)
                            4'h0: rtos_mutex_op = 2'b01;
                            4'h1: rtos_mutex_op = 2'b10;
                            4'h2: rtos_mutex_op = 2'b10;
                            4'h3: rtos_mutex_op = 2'b11;
                            4'h4: rtos_mutex_op = 2'b01;
                            default: rtos_mutex_op = 2'b00;
                        endcase
                        if (rtos_mutex_done)
                            state_next = S_COMPLETE;
                    end
                    4'h2: begin // Semaphore ops
                        rtos_sem_id = latched_arg0[2:0];
                        case (syscall_subop)
                            4'h0: begin
                                rtos_sem_op    = 2'b01;
                                rtos_sem_value = latched_arg1[7:0];
                            end
                            4'h1, 4'h2, 4'h3: rtos_sem_op = 2'b10;
                            4'h4:              rtos_sem_op = 2'b11;
                            4'h5, 4'h6:        rtos_sem_op = 2'b01;
                            default:           rtos_sem_op = 2'b00;
                        endcase
                        if (rtos_sem_done)
                            state_next = S_COMPLETE;
                    end
                    4'h3: begin // MsgQ ops
                        rtos_msgq_id = latched_arg0[1:0];
                        case (syscall_subop)
                            4'h0, 4'h3: rtos_msgq_op = 2'b01;
                            4'h1, 4'h5: begin
                                rtos_msgq_op   = 2'b10;
                                rtos_msgq_data = latched_arg1;
                            end
                            4'h2, 4'h4: rtos_msgq_op = 2'b11;
                            default:    rtos_msgq_op = 2'b00;
                        endcase
                        if (rtos_msgq_done)
                            state_next = S_COMPLETE;
                    end
                    default: state_next = S_COMPLETE;
                endcase
            end

            // -----------------------------------------------------------------
            // S_COMPLETE: Assert syscall_done, return result
            // -----------------------------------------------------------------
            S_COMPLETE: begin
                syscall_done = 1'b1;
                syscall_ret  = result_r;
                state_next   = S_IDLE;
            end

            default: state_next = S_IDLE;
        endcase
    end

    // =========================================================================
    // Result Register Computation
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_r <= '0;
        end else begin
            case (state_r)
                S_DECODE: begin
                    // Default result for unsupported categories
                    if (syscall_category > 4'h7)
                        result_r <= POSIX_ENOSYS;
                    else
                        result_r <= '0;
                end

                // Thread operations result
                S_THREAD_OP: begin
                    case (syscall_subop)
                        4'h0: result_r <= '0; // Will be updated by RTOS done
                        4'h1: result_r <= '0; // pthread_exit: no return
                        4'h4: result_r <= {28'b0, current_tid_r}; // pthread_self
                        4'h5: result_r <= '0; // pthread_yield: return 0
                        default: result_r <= '0;
                    endcase
                end

                // Mutex result from RTOS
                S_MUTEX_OP: begin
                    result_r <= '0;
                end

                // Semaphore result
                S_SEM_OP: begin
                    result_r <= '0;
                end

                // MsgQ result
                S_MSGQ_OP: begin
                    result_r <= '0;
                end

                // File I/O results
                S_FILE_OP: begin
                    case (syscall_subop)
                        // open: return fd or error
                        4'h0: begin
                            // Validate device_type
                            if (latched_arg0[2:0] == 3'b000 ||
                                latched_arg0[2:0] == 3'b001 ||
                                latched_arg0[2:0] == 3'b010 ||
                                latched_arg0[2:0] == 3'b011 ||
                                latched_arg0[2:0] == 3'b100) begin
                                if (free_fd_idx < MAX_FD[FD_WIDTH:0])
                                    result_r <= {27'b0, free_fd_idx};
                                else
                                    result_r <= POSIX_EMFILE;
                            end else begin
                                result_r <= POSIX_ENOENT;
                            end
                        end
                        // close: return 0 or error
                        4'h1: begin
                            if (latched_arg0 >= MAX_FD ||
                                !fd_valid[latched_arg0[FD_WIDTH-1:0]])
                                result_r <= POSIX_EBADF;
                            else if (latched_arg0[FD_WIDTH-1:0] <= 2)
                                result_r <= POSIX_EPERM;
                            else
                                result_r <= '0;
                        end
                        // read: fd validation
                        4'h2: begin
                            if (latched_arg0 >= MAX_FD ||
                                !fd_valid[latched_arg0[FD_WIDTH-1:0]])
                                result_r <= POSIX_EBADF;
                            else if (latched_arg2 == '0)
                                result_r <= '0;
                            else
                                result_r <= '0; // Updated from periph_rdata
                        end
                        // write: fd validation
                        4'h3: begin
                            if (latched_arg0 >= MAX_FD ||
                                !fd_valid[latched_arg0[FD_WIDTH-1:0]])
                                result_r <= POSIX_EBADF;
                            else if (latched_arg2 == '0)
                                result_r <= '0;
                            else
                                result_r <= latched_arg2; // bytes_written
                        end
                        // ioctl
                        4'h4: begin
                            if (latched_arg0 >= MAX_FD ||
                                !fd_valid[latched_arg0[FD_WIDTH-1:0]])
                                result_r <= POSIX_EBADF;
                            else
                                result_r <= '0;
                        end
                        // lseek
                        4'h5: begin
                            if (latched_arg0 >= MAX_FD ||
                                !fd_valid[latched_arg0[FD_WIDTH-1:0]])
                                result_r <= POSIX_EBADF;
                            else if (fd_type_t'(fd_type_r[latched_arg0[FD_WIDTH-1:0]]) != FD_TYPE_MEM)
                                result_r <= POSIX_ESPIPE;
                            else
                                result_r <= latched_arg1; // new position
                        end
                        default: result_r <= POSIX_ENOSYS;
                    endcase
                end

                // Timer operation results from peripheral
                S_TIMER_OP: begin
                    result_r <= '0;
                end

                // Signal operation results
                S_SIGNAL_OP: begin
                    case (syscall_subop)
                        // kill
                        4'h0: begin
                            if (latched_arg0 >= MAX_TASKS)
                                result_r <= POSIX_ESRCH;
                            else if (latched_arg1 >= 32 || latched_arg1 == 0)
                                result_r <= POSIX_EINVAL;
                            else
                                result_r <= '0;
                        end
                        // sigaction
                        4'h1: begin
                            if (latched_arg0 >= 32 || latched_arg0 == 0 || latched_arg0 == 9)
                                result_r <= POSIX_EINVAL;
                            else
                                result_r <= '0;
                        end
                        // sigprocmask
                        4'h2: begin
                            if (latched_arg0 > 2)
                                result_r <= POSIX_EINVAL;
                            else
                                result_r <= signal_mask[current_tid_r]; // old_mask
                        end
                        // sigwait
                        4'h3: begin
                            if (latched_arg0 == 0)
                                result_r <= POSIX_EINVAL;
                            else begin
                                // Check if signal already pending
                                if ((signal_pending[current_tid_r] & latched_arg0) != '0)
                                    result_r <= '0; // Will return signal_num
                                else
                                    result_r <= '0; // Will block
                            end
                        end
                        // raise
                        4'h4: begin
                            if (latched_arg0 >= 32 || latched_arg0 == 0)
                                result_r <= POSIX_EINVAL;
                            else
                                result_r <= '0;
                        end
                        default: result_r <= POSIX_ENOSYS;
                    endcase
                end

                // System operation results
                S_SYSTEM_OP: begin
                    case (syscall_subop)
                        // sysconf (0x70)
                        4'h0: begin
                            case (latched_arg0[3:0])
                                SC_NPROCESSORS_CONF[3:0]:   result_r <= 32'd1;
                                SC_NPROCESSORS_ONLN[3:0]:   result_r <= 32'd1;
                                SC_PAGE_SIZE[3:0]:          result_r <= 32'd4096;
                                SC_THREAD_THREADS_MAX[3:0]: result_r <= MAX_TASKS[31:0];
                                SC_SEM_NSEMS_MAX[3:0]:      result_r <= 32'd8;
                                SC_SEM_VALUE_MAX[3:0]:      result_r <= 32'd65535;
                                SC_MQ_OPEN_MAX[3:0]:        result_r <= 32'd4;
                                SC_TIMER_MAX[3:0]:          result_r <= 32'd8;
                                SC_OPEN_MAX[3:0]:           result_r <= MAX_FD[31:0];
                                SC_CLK_TCK[3:0]:            result_r <= 32'd1000;
                                default:                    result_r <= POSIX_EINVAL;
                            endcase
                        end
                        // sched_get_priority_max (0x71)
                        4'h1: result_r <= 32'd15;
                        // sched_get_priority_min (0x72)
                        4'h2: result_r <= 32'd0;
                        // sbrk (0x73)
                        4'h3: result_r <= heap_brk[current_tid_r]; // prev_brk
                        default: result_r <= POSIX_ENOSYS;
                    endcase
                end

                // Peripheral wait: capture read data
                S_PERIPH_WAIT: begin
                    if (periph_ready)
                        result_r <= periph_rdata;
                end

                // RTOS wait: capture results
                S_WAIT_RTOS: begin
                    case (syscall_category)
                        4'h0: begin // Thread
                            if (syscall_subop == 4'h2) begin
                                // pthread_join: return 0 on success
                                if (rtos_task_join_done)
                                    result_r <= '0;
                            end else if (rtos_task_create_done) begin
                                result_r <= {28'b0, rtos_task_create_id};
                            end
                        end
                        4'h1: begin // Mutex
                            if (rtos_mutex_done)
                                result_r <= rtos_mutex_result ? '0 : POSIX_EBUSY;
                        end
                        4'h2: begin // Semaphore
                            if (rtos_sem_done)
                                result_r <= rtos_sem_result ? '0 : POSIX_EAGAIN;
                        end
                        4'h3: begin // MsgQ
                            if (rtos_msgq_done) begin
                                if (rtos_msgq_success)
                                    result_r <= rtos_msgq_result;
                                else
                                    result_r <= POSIX_EINVAL;
                            end
                        end
                        default: ;
                    endcase
                end

                default: ;
            endcase
        end
    end

    // =========================================================================
    // AXI4-Lite Slave Interface (Debug / Status Registers)
    // =========================================================================
    //
    // Register Map:
    //   Offset 0x00: Status register (FSM state [3:0], pending_syscall_cnt [15:8])
    //   Offset 0x04-0x3C: FD table entries (read-only, 16 entries x 4 bytes)
    //   Offset 0x40: Last syscall number
    //   Offset 0x44: Last syscall return value
    //
    // -------------------------------------------------------------------------

    // AXI Write channel
    logic        axi_aw_done_r;
    logic        axi_w_done_r;
    logic [15:0] axi_awaddr_r;  // Latched write address (lower 16 bits)

    // AXI Read channel
    logic        axi_ar_done_r;
    logic [15:0] axi_araddr_r;  // Latched read address (lower 16 bits)

    // Write address handshake
    assign s_axi_awready = !axi_aw_done_r;
    assign s_axi_wready  = !axi_w_done_r;

    // Write response
    assign s_axi_bresp = 2'b00; // OKAY

    // Read response
    assign s_axi_rresp = 2'b00; // OKAY

    // AXI Write FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_aw_done_r <= 1'b0;
            axi_w_done_r  <= 1'b0;
            axi_awaddr_r  <= '0;
            s_axi_bvalid  <= 1'b0;
        end else begin
            // Write address accept
            if (s_axi_awvalid && !axi_aw_done_r) begin
                axi_aw_done_r <= 1'b1;
                axi_awaddr_r  <= s_axi_awaddr[15:0];
            end

            // Write data accept
            if (s_axi_wvalid && !axi_w_done_r) begin
                axi_w_done_r <= 1'b1;
            end

            // Generate write response when both channels done
            if (axi_aw_done_r && axi_w_done_r && !s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;
            end

            // Clear when response accepted
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid  <= 1'b0;
                axi_aw_done_r <= 1'b0;
                axi_w_done_r  <= 1'b0;
            end
        end
    end

    // AXI Read FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_ar_done_r  <= 1'b0;
            axi_araddr_r   <= '0;
            s_axi_arready  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rdata    <= '0;
        end else begin
            s_axi_arready <= 1'b0;

            // Read address accept
            if (s_axi_arvalid && !axi_ar_done_r) begin
                axi_ar_done_r <= 1'b1;
                axi_araddr_r  <= s_axi_araddr[15:0];
                s_axi_arready <= 1'b1;
            end

            // Generate read data one cycle after address accepted
            if (axi_ar_done_r && !s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;

                case (axi_araddr_r[7:0])
                    // Status register
                    8'h00: s_axi_rdata <= {16'h0, pending_syscall_cnt, 4'h0, state_r};

                    // FD table entries (0x04-0x3C, 16 entries)
                    8'h04: s_axi_rdata <= {fd_flags[0], 5'h0, fd_type_r[0],
                                           7'h0, fd_valid[0]};
                    8'h08: s_axi_rdata <= {fd_flags[1], 5'h0, fd_type_r[1],
                                           7'h0, fd_valid[1]};
                    8'h0C: s_axi_rdata <= {fd_flags[2], 5'h0, fd_type_r[2],
                                           7'h0, fd_valid[2]};
                    8'h10: s_axi_rdata <= {fd_flags[3], 5'h0, fd_type_r[3],
                                           7'h0, fd_valid[3]};
                    8'h14: s_axi_rdata <= {fd_flags[4], 5'h0, fd_type_r[4],
                                           7'h0, fd_valid[4]};
                    8'h18: s_axi_rdata <= {fd_flags[5], 5'h0, fd_type_r[5],
                                           7'h0, fd_valid[5]};
                    8'h1C: s_axi_rdata <= {fd_flags[6], 5'h0, fd_type_r[6],
                                           7'h0, fd_valid[6]};
                    8'h20: s_axi_rdata <= {fd_flags[7], 5'h0, fd_type_r[7],
                                           7'h0, fd_valid[7]};
                    8'h24: s_axi_rdata <= {fd_flags[8], 5'h0, fd_type_r[8],
                                           7'h0, fd_valid[8]};
                    8'h28: s_axi_rdata <= {fd_flags[9], 5'h0, fd_type_r[9],
                                           7'h0, fd_valid[9]};
                    8'h2C: s_axi_rdata <= {fd_flags[10], 5'h0, fd_type_r[10],
                                           7'h0, fd_valid[10]};
                    8'h30: s_axi_rdata <= {fd_flags[11], 5'h0, fd_type_r[11],
                                           7'h0, fd_valid[11]};
                    8'h34: s_axi_rdata <= {fd_flags[12], 5'h0, fd_type_r[12],
                                           7'h0, fd_valid[12]};
                    8'h38: s_axi_rdata <= {fd_flags[13], 5'h0, fd_type_r[13],
                                           7'h0, fd_valid[13]};
                    8'h3C: s_axi_rdata <= {fd_flags[14], 5'h0, fd_type_r[14],
                                           7'h0, fd_valid[14]};

                    // Last syscall number
                    8'h40: s_axi_rdata <= {24'h0, last_syscall_num_r};

                    // Last syscall return value
                    8'h44: s_axi_rdata <= last_syscall_ret_r;

                    default: s_axi_rdata <= 32'hDEAD_BEEF;
                endcase
            end

            // Clear when read data accepted
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                axi_ar_done_r <= 1'b0;
            end
        end
    end

endmodule : posix_hw_layer
