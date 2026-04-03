# VSync Module I/O Port Specification

## Document Information

| Item | Detail |
|------|--------|
| Document ID | ARCH-IO-001 |
| Version | 1.1 |
| Date | 2026-02-21 |
| Project | VSync - RISC-V RV32IM with Hardware RTOS |
| Target Device | Xilinx Spartan UltraScale+ |
| Language | SystemVerilog (IEEE 1800-2017) |
| Reference | vsync_pkg.sv (common types and parameters) |

---

## Table of Contents

1. [rv32im_core - RISC-V CPU Core](#1-rv32im_core---risc-v-cpu-core)
2. [hw_rtos - Hardware RTOS Engine](#2-hw_rtos---hardware-rtos-engine)
3. [posix_hw_layer - POSIX Hardware Layer](#3-posix_hw_layer---posix-hardware-layer)
4. [axi4_master - AXI4 Master Interface](#4-axi4_master---axi4-master-interface)
5. [axi4_interconnect - AXI4 Interconnect](#5-axi4_interconnect---axi4-interconnect)
6. [axi4_apb_bridge - AXI4 to APB Bridge](#6-axi4_apb_bridge---axi4-to-apb-bridge)
7. [bram_imem - Instruction Memory (64KB)](#7-bram_imem---instruction-memory-64kb)
8. [bram_dmem - Data Memory (16KB)](#8-bram_dmem---data-memory-16kb)
9. [hyperram_ctrl - HyperRAM Controller](#9-hyperram_ctrl---hyperram-controller)
10. [uart_apb - UART Controller](#10-uart_apb---uart-controller)
11. [gpio_apb - GPIO Controller](#11-gpio_apb---gpio-controller)
12. [plic - Platform-Level Interrupt Controller](#12-plic---platform-level-interrupt-controller)
13. [clint - Core Local Interruptor](#13-clint---core-local-interruptor)
14. [vsync_top - Top Module](#14-vsync_top---top-module)

---

## Common Conventions

- All modules import `vsync_pkg::*` for shared parameters and types
- Clock: `clk` (positive edge triggered)
- Reset: `rst_n` (active-low, synchronous de-assertion)
- AXI4 parameters: ADDR_W=32, DATA_W=32, STRB_W=4, ID_W=4, LEN_W=8
- APB parameters: ADDR_W=32, DATA_W=32
- Signal naming: `{interface}_{signal}` (e.g., `axi_awaddr`, `apb_paddr`)

### Address Map Reference (from vsync_pkg.sv)

| Region | Base Address | End Address | Size |
|--------|-------------|-------------|------|
| IMEM (BRAM) | `0x0000_0000` | `0x0000_FFFF` | 64KB |
| DMEM (BRAM) | `0x0001_0000` | `0x0001_3FFF` | 16KB |
| CLINT | `0x0200_0000` | `0x0200_FFFF` | 64KB |
| PLIC | `0x0C00_0000` | `0x0C00_0FFF` | 4KB |
| UART | `0x1000_0000` | `0x1000_00FF` | 256B |
| GPIO | `0x1000_0100` | `0x1000_01FF` | 256B |
| HW_RTOS | `0x1100_0000` | `0x1100_FFFF` | 64KB |
| POSIX | `0x1200_0000` | `0x1200_FFFF` | 64KB |
| HyperRAM | `0x2000_0000` | `0x2FFF_FFFF` | 256MB |

### Global Parameters (from vsync_pkg.sv)

| Parameter | Value | Description |
|-----------|-------|-------------|
| `XLEN` | 32 | Register / data bus width |
| `ILEN` | 32 | Instruction width |
| `NUM_REGS` | 32 | Number of registers |
| `REG_ADDR_W` | 5 | Register address width |
| `IMEM_SIZE` | 65536 | 64KB instruction memory |
| `DMEM_SIZE` | 16384 | 16KB data memory |
| `IMEM_ADDR_W` | 16 | Instruction memory address width |
| `DMEM_ADDR_W` | 14 | Data memory address width |
| `AXI_ADDR_W` | 32 | AXI address width |
| `AXI_DATA_W` | 32 | AXI data width |
| `AXI_ID_W` | 4 | AXI transaction ID width |
| `AXI_STRB_W` | 4 | AXI write strobe width |
| `AXI_LEN_W` | 8 | AXI burst length width |
| `MAX_TASKS` | 16 | Maximum RTOS task count |
| `TASK_ID_W` | 4 | Task ID width |
| `TASK_PRIORITY_W` | 4 | Task priority width (16 levels) |
| `TIME_SLICE_W` | 16 | Time slice counter width |
| `MAX_FD` | 16 | Maximum file descriptors |
| `FD_WIDTH` | 4 | File descriptor width |

---

## 1. rv32im_core - RISC-V CPU Core

5-stage pipelined RISC-V RV32IM processor with CSR unit, hazard detection, forwarding, and M-extension (multiply/divide).

### 1.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| **Instruction Memory Interface (direct to bram_imem)** ||||
| `imem_addr` | output | 16 | Instruction memory byte address [15:0] |
| `imem_rdata` | input | 32 | Instruction read data (1-cycle latency) |
| `imem_en` | output | 1 | Instruction memory enable |
| **Data Memory Interface (to axi4_master)** ||||
| `mem_addr` | output | 32 | Data memory address (full 32-bit) |
| `mem_wdata` | output | 32 | Write data |
| `mem_read` | output | 1 | Read request |
| `mem_write` | output | 1 | Write request |
| `mem_size` | output | 3 | Access size (funct3: 000=B, 001=H, 010=W) |
| `mem_rdata` | input | 32 | Read data from memory subsystem |
| `mem_ready` | input | 1 | Memory access complete (handshake) |
| `mem_error` | input | 1 | Memory access error |
| **Interrupt Inputs** ||||
| `external_irq` | input | 1 | External interrupt (from PLIC) |
| `timer_irq` | input | 1 | Timer interrupt (from CLINT) |
| `software_irq` | input | 1 | Software interrupt (from CLINT) |
| **RTOS Control Interface (to/from hw_rtos)** ||||
| `ctx_switch_req` | input | 1 | Context switch request from RTOS |
| `ctx_switch_ack` | output | 1 | Context switch acknowledgment |
| `ctx_save_en` | output | 1 | Register save data valid (pulses for each reg) |
| `ctx_save_reg_idx` | output | 5 | Register index being saved (0-31) |
| `ctx_save_reg_data` | output | 32 | Register data being saved |
| `ctx_save_pc` | output | 32 | PC value being saved |
| `ctx_restore_en` | input | 1 | Register restore data valid |
| `ctx_restore_reg_idx` | input | 5 | Register index being restored (0-31) |
| `ctx_restore_reg_data` | input | 32 | Register data being restored |
| `ctx_restore_pc` | input | 32 | PC value being restored |
| `current_task_id` | input | 4 | Current active task ID from RTOS |
| `task_active` | input | 1 | Task execution is active |
| **POSIX Syscall Interface (to/from posix_hw_layer)** ||||
| `ecall_req` | output | 1 | ECALL instruction detected |
| `syscall_num` | output | 8 | Syscall number (register a7 value) |
| `syscall_arg0` | output | 32 | Syscall argument 0 (register a0) |
| `syscall_arg1` | output | 32 | Syscall argument 1 (register a1) |
| `syscall_arg2` | output | 32 | Syscall argument 2 (register a2) |
| `syscall_ret` | input | 32 | Syscall return value (written to a0) |
| `syscall_done` | input | 1 | Syscall processing complete |
| **Debug Interface (optional)** ||||
| `debug_halt_req` | input | 1 | Debug halt request |
| `debug_halted` | output | 1 | CPU is halted |
| `debug_pc` | output | 32 | Current PC value |
| `debug_instr` | output | 32 | Current instruction |
| `debug_reg_addr` | input | 5 | Debug register read address |
| `debug_reg_data` | output | 32 | Debug register read data |

### 1.2 Module Skeleton

```systemverilog
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
    // Internal: IF, ID, EX, MEM, WB pipeline stages
    // Internal: Register file (x0-x31)
    // Internal: ALU, M-extension unit (MUL/DIV)
    // Internal: CSR unit (mstatus, mepc, mcause, etc.)
    // Internal: Hazard unit (forwarding, stall, flush)
    // Internal: Branch predictor
endmodule : rv32im_core
```

---

## 2. hw_rtos - Hardware RTOS Engine

Hardware-implemented real-time operating system with priority-based preemptive scheduler, TCB management, semaphores, mutexes, and message queues.

### 2.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| **Task Scheduler Control** ||||
| `scheduler_en` | input | 1 | Scheduler enable |
| `schedule_policy` | input | 2 | 00=priority, 01=round-robin, 10=priority+RR |
| `current_task_id` | output | 4 | Currently running task ID |
| `next_task_id` | output | 4 | Next task to schedule |
| `task_active` | output | 1 | A task is currently active |
| **Context Switch Control (to/from rv32im_core)** ||||
| `ctx_switch_req` | output | 1 | Request context switch to CPU |
| `ctx_switch_ack` | input | 1 | Context switch acknowledged by CPU |
| `ctx_save_en` | input | 1 | Register save data valid (from CPU) |
| `ctx_save_reg_idx` | input | 5 | Register index being saved |
| `ctx_save_reg_data` | input | 32 | Register data being saved |
| `ctx_save_pc` | input | 32 | PC value being saved |
| `ctx_restore_en` | output | 1 | Register restore data valid (to CPU) |
| `ctx_restore_reg_idx` | output | 5 | Register index being restored |
| `ctx_restore_reg_data` | output | 32 | Register data being restored |
| `ctx_restore_pc` | output | 32 | PC value being restored |
| **Timer Input (from CLINT)** ||||
| `timer_tick` | input | 1 | System timer tick (for time-slicing) |
| **POSIX Layer Control Input (from posix_hw_layer)** ||||
| `rtos_task_create` | input | 1 | Create new task command |
| `rtos_task_create_pc` | input | 32 | New task entry point (PC) |
| `rtos_task_create_sp` | input | 32 | New task stack pointer |
| `rtos_task_create_prio` | input | 4 | New task priority (0=highest) |
| `rtos_task_create_done` | output | 1 | Task creation complete |
| `rtos_task_create_id` | output | 4 | Created task ID |
| `rtos_task_exit` | input | 1 | Exit current task |
| `rtos_task_yield` | input | 1 | Yield current task (voluntary preemption) |
| `rtos_sem_op` | input | 2 | Semaphore op: 00=none, 01=init, 10=wait, 11=post |
| `rtos_sem_id` | input | 3 | Semaphore ID (0-7) |
| `rtos_sem_value` | input | 8 | Semaphore initial value (for init op) |
| `rtos_sem_done` | output | 1 | Semaphore operation complete |
| `rtos_sem_result` | output | 1 | Semaphore operation success (1=ok, 0=blocked) |
| `rtos_mutex_op` | input | 2 | Mutex op: 00=none, 01=init, 10=lock, 11=unlock |
| `rtos_mutex_id` | input | 3 | Mutex ID (0-7) |
| `rtos_mutex_done` | output | 1 | Mutex operation complete |
| `rtos_mutex_result` | output | 1 | Mutex operation success |
| `rtos_msgq_op` | input | 2 | MsgQ op: 00=none, 01=create, 10=send, 11=recv |
| `rtos_msgq_id` | input | 2 | Message queue ID (0-3) |
| `rtos_msgq_data` | input | 32 | Message data (for send) |
| `rtos_msgq_done` | output | 1 | MsgQ operation complete |
| `rtos_msgq_result` | output | 32 | MsgQ result data (for recv) |
| `rtos_msgq_success` | output | 1 | MsgQ operation success |
| **AXI4 Slave Interface (configuration register access)** ||||
| `s_axi_awaddr` | input | 32 | Write address |
| `s_axi_awprot` | input | 3 | Write protection |
| `s_axi_awvalid` | input | 1 | Write address valid |
| `s_axi_awready` | output | 1 | Write address ready |
| `s_axi_wdata` | input | 32 | Write data |
| `s_axi_wstrb` | input | 4 | Write strobes |
| `s_axi_wvalid` | input | 1 | Write data valid |
| `s_axi_wready` | output | 1 | Write data ready |
| `s_axi_bresp` | output | 2 | Write response |
| `s_axi_bvalid` | output | 1 | Write response valid |
| `s_axi_bready` | input | 1 | Write response ready |
| `s_axi_araddr` | input | 32 | Read address |
| `s_axi_arprot` | input | 3 | Read protection |
| `s_axi_arvalid` | input | 1 | Read address valid |
| `s_axi_arready` | output | 1 | Read address ready |
| `s_axi_rdata` | output | 32 | Read data |
| `s_axi_rresp` | output | 2 | Read response |
| `s_axi_rvalid` | output | 1 | Read data valid |
| `s_axi_rready` | input | 1 | Read data ready |

### 2.2 Module Skeleton

```systemverilog
module hw_rtos
    import vsync_pkg::*;
(
    // Clock & Reset
    input  logic                     clk,
    input  logic                     rst_n,

    // Task Scheduler Control
    input  logic                     scheduler_en,
    input  logic [1:0]               schedule_policy,
    output logic [TASK_ID_W-1:0]     current_task_id,
    output logic [TASK_ID_W-1:0]     next_task_id,
    output logic                     task_active,

    // Context Switch Control (to/from rv32im_core)
    output logic                     ctx_switch_req,
    input  logic                     ctx_switch_ack,
    input  logic                     ctx_save_en,
    input  logic [REG_ADDR_W-1:0]    ctx_save_reg_idx,
    input  logic [XLEN-1:0]         ctx_save_reg_data,
    input  logic [XLEN-1:0]         ctx_save_pc,
    output logic                     ctx_restore_en,
    output logic [REG_ADDR_W-1:0]    ctx_restore_reg_idx,
    output logic [XLEN-1:0]         ctx_restore_reg_data,
    output logic [XLEN-1:0]         ctx_restore_pc,

    // Timer Input (from CLINT)
    input  logic                     timer_tick,

    // POSIX Layer Control Input
    input  logic                     rtos_task_create,
    input  logic [XLEN-1:0]         rtos_task_create_pc,
    input  logic [XLEN-1:0]         rtos_task_create_sp,
    input  logic [TASK_PRIORITY_W-1:0] rtos_task_create_prio,
    output logic                     rtos_task_create_done,
    output logic [TASK_ID_W-1:0]     rtos_task_create_id,
    input  logic                     rtos_task_exit,
    input  logic                     rtos_task_yield,
    input  logic [1:0]               rtos_sem_op,
    input  logic [2:0]               rtos_sem_id,
    input  logic [7:0]               rtos_sem_value,
    output logic                     rtos_sem_done,
    output logic                     rtos_sem_result,
    input  logic [1:0]               rtos_mutex_op,
    input  logic [2:0]               rtos_mutex_id,
    output logic                     rtos_mutex_done,
    output logic                     rtos_mutex_result,
    input  logic [1:0]               rtos_msgq_op,
    input  logic [1:0]               rtos_msgq_id,
    input  logic [XLEN-1:0]         rtos_msgq_data,
    output logic                     rtos_msgq_done,
    output logic [XLEN-1:0]         rtos_msgq_result,
    output logic                     rtos_msgq_success,

    // AXI4 Slave Interface (AXI4-Lite subset for config registers)
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
    // Internal: TCB memory (tcb_t tcb[MAX_TASKS])
    // Internal: Context save/restore memory (32 regs x MAX_TASKS)
    // Internal: Scheduler FSM (priority queue + round-robin)
    // Internal: Semaphore array [8] with wait queues
    // Internal: Mutex array [8] with owner tracking
    // Internal: Message queue array [4] with circular buffers
endmodule : hw_rtos
```

---

## 3. posix_hw_layer - POSIX Hardware Layer

Hardware-implemented POSIX compatibility layer that dispatches ECALL syscalls to appropriate hardware units (RTOS operations or peripheral I/O).

### 3.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| **Syscall Dispatcher Interface (from rv32im_core)** ||||
| `ecall_req` | input | 1 | ECALL instruction detected |
| `syscall_num` | input | 8 | Syscall number (from a7) |
| `syscall_arg0` | input | 32 | Syscall argument 0 (from a0) |
| `syscall_arg1` | input | 32 | Syscall argument 1 (from a1) |
| `syscall_arg2` | input | 32 | Syscall argument 2 (from a2) |
| `syscall_ret` | output | 32 | Syscall return value (to a0) |
| `syscall_done` | output | 1 | Syscall processing complete |
| **RTOS Control Output (to hw_rtos)** ||||
| `rtos_task_create` | output | 1 | Create new task |
| `rtos_task_create_pc` | output | 32 | New task entry point |
| `rtos_task_create_sp` | output | 32 | New task stack pointer |
| `rtos_task_create_prio` | output | 4 | New task priority |
| `rtos_task_create_done` | input | 1 | Task creation complete |
| `rtos_task_create_id` | input | 4 | Created task ID |
| `rtos_task_exit` | output | 1 | Exit current task |
| `rtos_task_yield` | output | 1 | Yield current task |
| `rtos_sem_op` | output | 2 | Semaphore operation |
| `rtos_sem_id` | output | 3 | Semaphore ID |
| `rtos_sem_value` | output | 8 | Semaphore initial value |
| `rtos_sem_done` | input | 1 | Semaphore operation complete |
| `rtos_sem_result` | input | 1 | Semaphore operation success |
| `rtos_mutex_op` | output | 2 | Mutex operation |
| `rtos_mutex_id` | output | 3 | Mutex ID |
| `rtos_mutex_done` | input | 1 | Mutex operation complete |
| `rtos_mutex_result` | input | 1 | Mutex operation success |
| `rtos_msgq_op` | output | 2 | Message queue operation |
| `rtos_msgq_id` | output | 2 | Message queue ID |
| `rtos_msgq_data` | output | 32 | Message data (for send) |
| `rtos_msgq_done` | input | 1 | MsgQ operation complete |
| `rtos_msgq_result` | input | 32 | MsgQ result data (for recv) |
| `rtos_msgq_success` | input | 1 | MsgQ operation success |
| **Peripheral Access Control (for I/O syscalls)** ||||
| `periph_addr` | output | 32 | Peripheral access address |
| `periph_wdata` | output | 32 | Peripheral write data |
| `periph_read` | output | 1 | Peripheral read request |
| `periph_write` | output | 1 | Peripheral write request |
| `periph_rdata` | input | 32 | Peripheral read data |
| `periph_ready` | input | 1 | Peripheral access complete |
| **AXI4 Slave Interface (FD table / status registers)** ||||
| `s_axi_awaddr` | input | 32 | Write address |
| `s_axi_awprot` | input | 3 | Write protection |
| `s_axi_awvalid` | input | 1 | Write address valid |
| `s_axi_awready` | output | 1 | Write address ready |
| `s_axi_wdata` | input | 32 | Write data |
| `s_axi_wstrb` | input | 4 | Write strobes |
| `s_axi_wvalid` | input | 1 | Write data valid |
| `s_axi_wready` | output | 1 | Write data ready |
| `s_axi_bresp` | output | 2 | Write response |
| `s_axi_bvalid` | output | 1 | Write response valid |
| `s_axi_bready` | input | 1 | Write response ready |
| `s_axi_araddr` | input | 32 | Read address |
| `s_axi_arprot` | input | 3 | Read protection |
| `s_axi_arvalid` | input | 1 | Read address valid |
| `s_axi_arready` | output | 1 | Read address ready |
| `s_axi_rdata` | output | 32 | Read data |
| `s_axi_rresp` | output | 2 | Read response |
| `s_axi_rvalid` | output | 1 | Read data valid |
| `s_axi_rready` | input | 1 | Read data ready |

### 3.2 Module Skeleton

```systemverilog
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
    // Internal: FD table (fd_entry_t fd_table[MAX_FD])
    // Internal: Syscall dispatcher FSM
    // Internal: Peripheral access arbiter
endmodule : posix_hw_layer
```

---

## 4. axi4_master - AXI4 Master Interface

Converts CPU memory access requests (simple read/write) into AXI4 bus transactions with full protocol compliance including burst support.

### 4.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| **CPU Interface (from rv32im_core)** ||||
| `cpu_addr` | input | 32 | Access address |
| `cpu_wdata` | input | 32 | Write data |
| `cpu_read` | input | 1 | Read request |
| `cpu_write` | input | 1 | Write request |
| `cpu_size` | input | 3 | Access size (funct3: 000=B, 001=H, 010=W) |
| `cpu_rdata` | output | 32 | Read data response |
| `cpu_ready` | output | 1 | Access complete |
| `cpu_error` | output | 1 | Access error (SLVERR/DECERR) |
| **AXI4 Master - Write Address Channel (AW)** ||||
| `m_axi_awid` | output | 4 | Write address ID |
| `m_axi_awaddr` | output | 32 | Write address |
| `m_axi_awlen` | output | 8 | Burst length minus 1 (0=1 beat) |
| `m_axi_awsize` | output | 3 | Burst size (log2 bytes per beat) |
| `m_axi_awburst` | output | 2 | Burst type (FIXED/INCR/WRAP) |
| `m_axi_awlock` | output | 1 | Lock type |
| `m_axi_awcache` | output | 4 | Memory type |
| `m_axi_awprot` | output | 3 | Protection type |
| `m_axi_awvalid` | output | 1 | Write address valid |
| `m_axi_awready` | input | 1 | Write address ready |
| **AXI4 Master - Write Data Channel (W)** ||||
| `m_axi_wdata` | output | 32 | Write data |
| `m_axi_wstrb` | output | 4 | Write byte strobes |
| `m_axi_wlast` | output | 1 | Last beat of write burst |
| `m_axi_wvalid` | output | 1 | Write data valid |
| `m_axi_wready` | input | 1 | Write data ready |
| **AXI4 Master - Write Response Channel (B)** ||||
| `m_axi_bid` | input | 4 | Write response ID |
| `m_axi_bresp` | input | 2 | Write response (OKAY/SLVERR/DECERR) |
| `m_axi_bvalid` | input | 1 | Write response valid |
| `m_axi_bready` | output | 1 | Write response ready |
| **AXI4 Master - Read Address Channel (AR)** ||||
| `m_axi_arid` | output | 4 | Read address ID |
| `m_axi_araddr` | output | 32 | Read address |
| `m_axi_arlen` | output | 8 | Burst length |
| `m_axi_arsize` | output | 3 | Burst size |
| `m_axi_arburst` | output | 2 | Burst type |
| `m_axi_arlock` | output | 1 | Lock type |
| `m_axi_arcache` | output | 4 | Memory type |
| `m_axi_arprot` | output | 3 | Protection type |
| `m_axi_arvalid` | output | 1 | Read address valid |
| `m_axi_arready` | input | 1 | Read address ready |
| **AXI4 Master - Read Data Channel (R)** ||||
| `m_axi_rid` | input | 4 | Read data ID |
| `m_axi_rdata` | input | 32 | Read data |
| `m_axi_rresp` | input | 2 | Read response |
| `m_axi_rlast` | input | 1 | Last beat of read burst |
| `m_axi_rvalid` | input | 1 | Read data valid |
| `m_axi_rready` | output | 1 | Read data ready |

### 4.2 Module Skeleton

```systemverilog
module axi4_master
    import vsync_pkg::*;
(
    input  logic                     clk,
    input  logic                     rst_n,

    // CPU Interface
    input  logic [XLEN-1:0]         cpu_addr,
    input  logic [XLEN-1:0]         cpu_wdata,
    input  logic                     cpu_read,
    input  logic                     cpu_write,
    input  logic [2:0]               cpu_size,
    output logic [XLEN-1:0]         cpu_rdata,
    output logic                     cpu_ready,
    output logic                     cpu_error,

    // AXI4 Master - Write Address Channel (AW)
    output logic [AXI_ID_W-1:0]     m_axi_awid,
    output logic [AXI_ADDR_W-1:0]   m_axi_awaddr,
    output logic [AXI_LEN_W-1:0]    m_axi_awlen,
    output logic [2:0]               m_axi_awsize,
    output logic [1:0]               m_axi_awburst,
    output logic                     m_axi_awlock,
    output logic [3:0]               m_axi_awcache,
    output logic [2:0]               m_axi_awprot,
    output logic                     m_axi_awvalid,
    input  logic                     m_axi_awready,

    // AXI4 Master - Write Data Channel (W)
    output logic [AXI_DATA_W-1:0]   m_axi_wdata,
    output logic [AXI_STRB_W-1:0]   m_axi_wstrb,
    output logic                     m_axi_wlast,
    output logic                     m_axi_wvalid,
    input  logic                     m_axi_wready,

    // AXI4 Master - Write Response Channel (B)
    input  logic [AXI_ID_W-1:0]     m_axi_bid,
    input  logic [1:0]               m_axi_bresp,
    input  logic                     m_axi_bvalid,
    output logic                     m_axi_bready,

    // AXI4 Master - Read Address Channel (AR)
    output logic [AXI_ID_W-1:0]     m_axi_arid,
    output logic [AXI_ADDR_W-1:0]   m_axi_araddr,
    output logic [AXI_LEN_W-1:0]    m_axi_arlen,
    output logic [2:0]               m_axi_arsize,
    output logic [1:0]               m_axi_arburst,
    output logic                     m_axi_arlock,
    output logic [3:0]               m_axi_arcache,
    output logic [2:0]               m_axi_arprot,
    output logic                     m_axi_arvalid,
    input  logic                     m_axi_arready,

    // AXI4 Master - Read Data Channel (R)
    input  logic [AXI_ID_W-1:0]     m_axi_rid,
    input  logic [AXI_DATA_W-1:0]   m_axi_rdata,
    input  logic [1:0]               m_axi_rresp,
    input  logic                     m_axi_rlast,
    input  logic                     m_axi_rvalid,
    output logic                     m_axi_rready
);
    // Internal: Read/Write transaction FSM
    // Internal: WSTRB generation from cpu_size and address alignment
    // Internal: Burst management (single beat for CPU, burst for DMA if added)
endmodule : axi4_master
```

---

## 5. axi4_interconnect - AXI4 Interconnect

1-Master to 5-Slave address-based router/crossbar with full AXI4 protocol support.

### 5.1 Address Decode Configuration

| Slave Port | Target | Base Address | End Address | Mask |
|-----------|--------|-------------|-------------|------|
| M0 | bram_dmem | 0x0001_0000 | 0x0001_3FFF | 0xFFFF_C000 |
| M1 | hyperram_ctrl | 0x2000_0000 | 0x2FFF_FFFF | 0xF000_0000 |
| M2 | axi4_apb_bridge | (multiple) | (multiple) | - |
| M3 | hw_rtos | 0x1100_0000 | 0x1100_FFFF | 0xFFFF_0000 |
| M4 | posix_hw_layer | 0x1200_0000 | 0x1200_FFFF | 0xFFFF_0000 |

APB bridge address ranges (Slave M2):
- CLINT: 0x0200_0000 - 0x0200_FFFF
- PLIC: 0x0C00_0000 - 0x0C00_0FFF
- UART: 0x1000_0000 - 0x1000_00FF
- GPIO: 0x1000_0100 - 0x1000_01FF

### 5.2 Module Skeleton

```systemverilog
module axi4_interconnect
    import vsync_pkg::*;
#(
    parameter int NUM_SLAVES = 5
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // === AXI4 Slave Port (from axi4_master) - Input Side ===
    // Write Address Channel
    input  logic [AXI_ID_W-1:0]     s_axi_awid,
    input  logic [AXI_ADDR_W-1:0]   s_axi_awaddr,
    input  logic [AXI_LEN_W-1:0]    s_axi_awlen,
    input  logic [2:0]               s_axi_awsize,
    input  logic [1:0]               s_axi_awburst,
    input  logic                     s_axi_awlock,
    input  logic [3:0]               s_axi_awcache,
    input  logic [2:0]               s_axi_awprot,
    input  logic                     s_axi_awvalid,
    output logic                     s_axi_awready,
    // Write Data Channel
    input  logic [AXI_DATA_W-1:0]   s_axi_wdata,
    input  logic [AXI_STRB_W-1:0]   s_axi_wstrb,
    input  logic                     s_axi_wlast,
    input  logic                     s_axi_wvalid,
    output logic                     s_axi_wready,
    // Write Response Channel
    output logic [AXI_ID_W-1:0]     s_axi_bid,
    output logic [1:0]               s_axi_bresp,
    output logic                     s_axi_bvalid,
    input  logic                     s_axi_bready,
    // Read Address Channel
    input  logic [AXI_ID_W-1:0]     s_axi_arid,
    input  logic [AXI_ADDR_W-1:0]   s_axi_araddr,
    input  logic [AXI_LEN_W-1:0]    s_axi_arlen,
    input  logic [2:0]               s_axi_arsize,
    input  logic [1:0]               s_axi_arburst,
    input  logic                     s_axi_arlock,
    input  logic [3:0]               s_axi_arcache,
    input  logic [2:0]               s_axi_arprot,
    input  logic                     s_axi_arvalid,
    output logic                     s_axi_arready,
    // Read Data Channel
    output logic [AXI_ID_W-1:0]     s_axi_rid,
    output logic [AXI_DATA_W-1:0]   s_axi_rdata,
    output logic [1:0]               s_axi_rresp,
    output logic                     s_axi_rlast,
    output logic                     s_axi_rvalid,
    input  logic                     s_axi_rready,

    // === AXI4 Master Ports (to slaves) - Output Side ===
    // Port 0: bram_dmem
    output logic [AXI_ID_W-1:0]     m0_axi_awid,    output logic [AXI_ADDR_W-1:0] m0_axi_awaddr,
    output logic [AXI_LEN_W-1:0]    m0_axi_awlen,   output logic [2:0]            m0_axi_awsize,
    output logic [1:0]               m0_axi_awburst, output logic                  m0_axi_awvalid,
    input  logic                     m0_axi_awready,
    output logic [AXI_DATA_W-1:0]   m0_axi_wdata,   output logic [AXI_STRB_W-1:0] m0_axi_wstrb,
    output logic                     m0_axi_wlast,   output logic                  m0_axi_wvalid,
    input  logic                     m0_axi_wready,
    input  logic [AXI_ID_W-1:0]     m0_axi_bid,     input  logic [1:0]            m0_axi_bresp,
    input  logic                     m0_axi_bvalid,  output logic                  m0_axi_bready,
    output logic [AXI_ID_W-1:0]     m0_axi_arid,    output logic [AXI_ADDR_W-1:0] m0_axi_araddr,
    output logic [AXI_LEN_W-1:0]    m0_axi_arlen,   output logic [2:0]            m0_axi_arsize,
    output logic [1:0]               m0_axi_arburst, output logic                  m0_axi_arvalid,
    input  logic                     m0_axi_arready,
    input  logic [AXI_ID_W-1:0]     m0_axi_rid,     input  logic [AXI_DATA_W-1:0] m0_axi_rdata,
    input  logic [1:0]               m0_axi_rresp,   input  logic                  m0_axi_rlast,
    input  logic                     m0_axi_rvalid,  output logic                  m0_axi_rready,

    // Port 1: hyperram_ctrl (same signal pattern as Port 0)
    output logic [AXI_ID_W-1:0]     m1_axi_awid,    output logic [AXI_ADDR_W-1:0] m1_axi_awaddr,
    output logic [AXI_LEN_W-1:0]    m1_axi_awlen,   output logic [2:0]            m1_axi_awsize,
    output logic [1:0]               m1_axi_awburst, output logic                  m1_axi_awvalid,
    input  logic                     m1_axi_awready,
    output logic [AXI_DATA_W-1:0]   m1_axi_wdata,   output logic [AXI_STRB_W-1:0] m1_axi_wstrb,
    output logic                     m1_axi_wlast,   output logic                  m1_axi_wvalid,
    input  logic                     m1_axi_wready,
    input  logic [AXI_ID_W-1:0]     m1_axi_bid,     input  logic [1:0]            m1_axi_bresp,
    input  logic                     m1_axi_bvalid,  output logic                  m1_axi_bready,
    output logic [AXI_ID_W-1:0]     m1_axi_arid,    output logic [AXI_ADDR_W-1:0] m1_axi_araddr,
    output logic [AXI_LEN_W-1:0]    m1_axi_arlen,   output logic [2:0]            m1_axi_arsize,
    output logic [1:0]               m1_axi_arburst, output logic                  m1_axi_arvalid,
    input  logic                     m1_axi_arready,
    input  logic [AXI_ID_W-1:0]     m1_axi_rid,     input  logic [AXI_DATA_W-1:0] m1_axi_rdata,
    input  logic [1:0]               m1_axi_rresp,   input  logic                  m1_axi_rlast,
    input  logic                     m1_axi_rvalid,  output logic                  m1_axi_rready,

    // Port 2: axi4_apb_bridge (same signal pattern)
    output logic [AXI_ID_W-1:0]     m2_axi_awid,    output logic [AXI_ADDR_W-1:0] m2_axi_awaddr,
    output logic [AXI_LEN_W-1:0]    m2_axi_awlen,   output logic [2:0]            m2_axi_awsize,
    output logic [1:0]               m2_axi_awburst, output logic                  m2_axi_awvalid,
    input  logic                     m2_axi_awready,
    output logic [AXI_DATA_W-1:0]   m2_axi_wdata,   output logic [AXI_STRB_W-1:0] m2_axi_wstrb,
    output logic                     m2_axi_wlast,   output logic                  m2_axi_wvalid,
    input  logic                     m2_axi_wready,
    input  logic [AXI_ID_W-1:0]     m2_axi_bid,     input  logic [1:0]            m2_axi_bresp,
    input  logic                     m2_axi_bvalid,  output logic                  m2_axi_bready,
    output logic [AXI_ID_W-1:0]     m2_axi_arid,    output logic [AXI_ADDR_W-1:0] m2_axi_araddr,
    output logic [AXI_LEN_W-1:0]    m2_axi_arlen,   output logic [2:0]            m2_axi_arsize,
    output logic [1:0]               m2_axi_arburst, output logic                  m2_axi_arvalid,
    input  logic                     m2_axi_arready,
    input  logic [AXI_ID_W-1:0]     m2_axi_rid,     input  logic [AXI_DATA_W-1:0] m2_axi_rdata,
    input  logic [1:0]               m2_axi_rresp,   input  logic                  m2_axi_rlast,
    input  logic                     m2_axi_rvalid,  output logic                  m2_axi_rready,

    // Port 3: hw_rtos (same signal pattern)
    output logic [AXI_ID_W-1:0]     m3_axi_awid,    output logic [AXI_ADDR_W-1:0] m3_axi_awaddr,
    output logic [AXI_LEN_W-1:0]    m3_axi_awlen,   output logic [2:0]            m3_axi_awsize,
    output logic [1:0]               m3_axi_awburst, output logic                  m3_axi_awvalid,
    input  logic                     m3_axi_awready,
    output logic [AXI_DATA_W-1:0]   m3_axi_wdata,   output logic [AXI_STRB_W-1:0] m3_axi_wstrb,
    output logic                     m3_axi_wlast,   output logic                  m3_axi_wvalid,
    input  logic                     m3_axi_wready,
    input  logic [AXI_ID_W-1:0]     m3_axi_bid,     input  logic [1:0]            m3_axi_bresp,
    input  logic                     m3_axi_bvalid,  output logic                  m3_axi_bready,
    output logic [AXI_ID_W-1:0]     m3_axi_arid,    output logic [AXI_ADDR_W-1:0] m3_axi_araddr,
    output logic [AXI_LEN_W-1:0]    m3_axi_arlen,   output logic [2:0]            m3_axi_arsize,
    output logic [1:0]               m3_axi_arburst, output logic                  m3_axi_arvalid,
    input  logic                     m3_axi_arready,
    input  logic [AXI_ID_W-1:0]     m3_axi_rid,     input  logic [AXI_DATA_W-1:0] m3_axi_rdata,
    input  logic [1:0]               m3_axi_rresp,   input  logic                  m3_axi_rlast,
    input  logic                     m3_axi_rvalid,  output logic                  m3_axi_rready,

    // Port 4: posix_hw_layer (same signal pattern)
    output logic [AXI_ID_W-1:0]     m4_axi_awid,    output logic [AXI_ADDR_W-1:0] m4_axi_awaddr,
    output logic [AXI_LEN_W-1:0]    m4_axi_awlen,   output logic [2:0]            m4_axi_awsize,
    output logic [1:0]               m4_axi_awburst, output logic                  m4_axi_awvalid,
    input  logic                     m4_axi_awready,
    output logic [AXI_DATA_W-1:0]   m4_axi_wdata,   output logic [AXI_STRB_W-1:0] m4_axi_wstrb,
    output logic                     m4_axi_wlast,   output logic                  m4_axi_wvalid,
    input  logic                     m4_axi_wready,
    input  logic [AXI_ID_W-1:0]     m4_axi_bid,     input  logic [1:0]            m4_axi_bresp,
    input  logic                     m4_axi_bvalid,  output logic                  m4_axi_bready,
    output logic [AXI_ID_W-1:0]     m4_axi_arid,    output logic [AXI_ADDR_W-1:0] m4_axi_araddr,
    output logic [AXI_LEN_W-1:0]    m4_axi_arlen,   output logic [2:0]            m4_axi_arsize,
    output logic [1:0]               m4_axi_arburst, output logic                  m4_axi_arvalid,
    input  logic                     m4_axi_arready,
    input  logic [AXI_ID_W-1:0]     m4_axi_rid,     input  logic [AXI_DATA_W-1:0] m4_axi_rdata,
    input  logic [1:0]               m4_axi_rresp,   input  logic                  m4_axi_rlast,
    input  logic                     m4_axi_rvalid,  output logic                  m4_axi_rready
);
    // Internal: Address decode logic
    // Internal: Write channel routing (AW → slave select → W → B mux)
    // Internal: Read channel routing (AR → slave select → R mux)
    // Internal: DECERR generation for unmapped addresses
endmodule : axi4_interconnect
```

---

## 6. axi4_apb_bridge - AXI4 to APB Bridge

Converts AXI4 transactions to APB protocol for low-speed peripheral access. Supports 4 APB slaves with address-based PSEL generation.

### 6.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| **AXI4 Slave Interface (all 5 channels)** ||||
| `s_axi_awid` | input | 4 | Write address ID |
| `s_axi_awaddr` | input | 32 | Write address |
| `s_axi_awlen` | input | 8 | Burst length |
| `s_axi_awsize` | input | 3 | Burst size |
| `s_axi_awburst` | input | 2 | Burst type |
| `s_axi_awvalid` | input | 1 | Write address valid |
| `s_axi_awready` | output | 1 | Write address ready |
| `s_axi_wdata` | input | 32 | Write data |
| `s_axi_wstrb` | input | 4 | Write strobes |
| `s_axi_wlast` | input | 1 | Write last beat |
| `s_axi_wvalid` | input | 1 | Write data valid |
| `s_axi_wready` | output | 1 | Write data ready |
| `s_axi_bid` | output | 4 | Write response ID |
| `s_axi_bresp` | output | 2 | Write response |
| `s_axi_bvalid` | output | 1 | Write response valid |
| `s_axi_bready` | input | 1 | Write response ready |
| `s_axi_arid` | input | 4 | Read address ID |
| `s_axi_araddr` | input | 32 | Read address |
| `s_axi_arlen` | input | 8 | Burst length |
| `s_axi_arsize` | input | 3 | Burst size |
| `s_axi_arburst` | input | 2 | Burst type |
| `s_axi_arvalid` | input | 1 | Read address valid |
| `s_axi_arready` | output | 1 | Read address ready |
| `s_axi_rid` | output | 4 | Read data ID |
| `s_axi_rdata` | output | 32 | Read data |
| `s_axi_rresp` | output | 2 | Read response |
| `s_axi_rlast` | output | 1 | Read last beat |
| `s_axi_rvalid` | output | 1 | Read data valid |
| `s_axi_rready` | input | 1 | Read data ready |
| **APB Master Interface** ||||
| `apb_paddr` | output | 32 | APB address bus |
| `apb_psel` | output | 4 | Peripheral select (1 bit per slave) |
| `apb_penable` | output | 1 | APB enable (2nd phase) |
| `apb_pwrite` | output | 1 | Write enable (1=write, 0=read) |
| `apb_pwdata` | output | 32 | Write data |
| `apb_pstrb` | output | 4 | Write strobes (APB4 extension) |
| `apb_prdata` | input | 32 | Read data (muxed from selected slave) |
| `apb_pready` | input | 1 | Slave ready (for wait states) |
| `apb_pslverr` | input | 1 | Slave error response |

### 6.2 Module Skeleton

```systemverilog
module axi4_apb_bridge
    import vsync_pkg::*;
#(
    parameter int NUM_APB_SLAVES = 4
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // AXI4 Slave Interface
    input  logic [AXI_ID_W-1:0]     s_axi_awid,
    input  logic [AXI_ADDR_W-1:0]   s_axi_awaddr,
    input  logic [AXI_LEN_W-1:0]    s_axi_awlen,
    input  logic [2:0]               s_axi_awsize,
    input  logic [1:0]               s_axi_awburst,
    input  logic                     s_axi_awvalid,
    output logic                     s_axi_awready,
    input  logic [AXI_DATA_W-1:0]   s_axi_wdata,
    input  logic [AXI_STRB_W-1:0]   s_axi_wstrb,
    input  logic                     s_axi_wlast,
    input  logic                     s_axi_wvalid,
    output logic                     s_axi_wready,
    output logic [AXI_ID_W-1:0]     s_axi_bid,
    output logic [1:0]               s_axi_bresp,
    output logic                     s_axi_bvalid,
    input  logic                     s_axi_bready,
    input  logic [AXI_ID_W-1:0]     s_axi_arid,
    input  logic [AXI_ADDR_W-1:0]   s_axi_araddr,
    input  logic [AXI_LEN_W-1:0]    s_axi_arlen,
    input  logic [2:0]               s_axi_arsize,
    input  logic [1:0]               s_axi_arburst,
    input  logic                     s_axi_arvalid,
    output logic                     s_axi_arready,
    output logic [AXI_ID_W-1:0]     s_axi_rid,
    output logic [AXI_DATA_W-1:0]   s_axi_rdata,
    output logic [1:0]               s_axi_rresp,
    output logic                     s_axi_rlast,
    output logic                     s_axi_rvalid,
    input  logic                     s_axi_rready,

    // APB Master Interface
    output logic [AXI_ADDR_W-1:0]        apb_paddr,
    output logic [NUM_APB_SLAVES-1:0]    apb_psel,
    output logic                          apb_penable,
    output logic                          apb_pwrite,
    output logic [AXI_DATA_W-1:0]        apb_pwdata,
    output logic [AXI_STRB_W-1:0]        apb_pstrb,
    input  logic [AXI_DATA_W-1:0]        apb_prdata,
    input  logic                          apb_pready,
    input  logic                          apb_pslverr
);
    // Internal: AXI4→APB conversion FSM (IDLE→SETUP→ACCESS)
    // Internal: Burst handling (APB is single-beat, burst unrolled)
    // Internal: APB address decode for PSEL generation
endmodule : axi4_apb_bridge
```

---

## 7. bram_imem - Instruction Memory (64KB)

Xilinx BRAM inference pattern for instruction memory. Single-port synchronous read, word-aligned access.

### 7.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| `clk` | input | 1 | System clock |
| `en` | input | 1 | Memory enable |
| `addr` | input | 16 | Byte address [15:0] (word index = addr[15:2]) |
| `rdata` | output | 32 | Read data (1-cycle latency, synchronous) |

### 7.2 Module Skeleton

```systemverilog
module bram_imem
    import vsync_pkg::*;
#(
    parameter string INIT_FILE = "firmware.hex"
)(
    input  logic                     clk,
    input  logic                     en,
    input  logic [IMEM_ADDR_W-1:0]   addr,
    output logic [XLEN-1:0]          rdata
);
    // Xilinx BRAM inference pattern (single-port, read-only for instruction fetch)
    logic [XLEN-1:0] mem [0:(IMEM_SIZE/4)-1];  // 16K x 32-bit words = 64KB

    initial begin
        $readmemh(INIT_FILE, mem);
    end

    always_ff @(posedge clk) begin
        if (en) begin
            rdata <= mem[addr[IMEM_ADDR_W-1:2]];  // Word-aligned access
        end
    end
endmodule : bram_imem
```

### 7.3 BRAM Inference Notes
- Array: `logic [31:0] mem [0:16383]` → 16K words = 64KB
- Synchronous read inside `always_ff @(posedge clk)` for BRAM inference on Xilinx
- `$readmemh()` for firmware hex initialization
- Single-port, read-only (instruction fetch path)
- addr[1:0] ignored (word-aligned), addr[15:2] used as word index

---

## 8. bram_dmem - Data Memory (16KB)

AXI4 slave wrapping Xilinx BRAM for data memory with byte-enable write support.

### 8.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| **AXI4 Slave Interface (full)** ||||
| `s_axi_awid` | input | 4 | Write address ID |
| `s_axi_awaddr` | input | 32 | Write address |
| `s_axi_awlen` | input | 8 | Burst length |
| `s_axi_awsize` | input | 3 | Burst size |
| `s_axi_awburst` | input | 2 | Burst type |
| `s_axi_awvalid` | input | 1 | Write address valid |
| `s_axi_awready` | output | 1 | Write address ready |
| `s_axi_wdata` | input | 32 | Write data |
| `s_axi_wstrb` | input | 4 | Write byte strobes (per-byte enable) |
| `s_axi_wlast` | input | 1 | Write last beat |
| `s_axi_wvalid` | input | 1 | Write data valid |
| `s_axi_wready` | output | 1 | Write data ready |
| `s_axi_bid` | output | 4 | Write response ID |
| `s_axi_bresp` | output | 2 | Write response |
| `s_axi_bvalid` | output | 1 | Write response valid |
| `s_axi_bready` | input | 1 | Write response ready |
| `s_axi_arid` | input | 4 | Read address ID |
| `s_axi_araddr` | input | 32 | Read address |
| `s_axi_arlen` | input | 8 | Burst length |
| `s_axi_arsize` | input | 3 | Burst size |
| `s_axi_arburst` | input | 2 | Burst type |
| `s_axi_arvalid` | input | 1 | Read address valid |
| `s_axi_arready` | output | 1 | Read address ready |
| `s_axi_rid` | output | 4 | Read data ID |
| `s_axi_rdata` | output | 32 | Read data |
| `s_axi_rresp` | output | 2 | Read response |
| `s_axi_rlast` | output | 1 | Read last beat |
| `s_axi_rvalid` | output | 1 | Read data valid |
| `s_axi_rready` | input | 1 | Read data ready |

### 8.2 Module Skeleton

```systemverilog
module bram_dmem
    import vsync_pkg::*;
#(
    parameter string INIT_FILE = ""
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // AXI4 Slave Interface
    input  logic [AXI_ID_W-1:0]     s_axi_awid,
    input  logic [AXI_ADDR_W-1:0]   s_axi_awaddr,
    input  logic [AXI_LEN_W-1:0]    s_axi_awlen,
    input  logic [2:0]               s_axi_awsize,
    input  logic [1:0]               s_axi_awburst,
    input  logic                     s_axi_awvalid,
    output logic                     s_axi_awready,
    input  logic [AXI_DATA_W-1:0]   s_axi_wdata,
    input  logic [AXI_STRB_W-1:0]   s_axi_wstrb,
    input  logic                     s_axi_wlast,
    input  logic                     s_axi_wvalid,
    output logic                     s_axi_wready,
    output logic [AXI_ID_W-1:0]     s_axi_bid,
    output logic [1:0]               s_axi_bresp,
    output logic                     s_axi_bvalid,
    input  logic                     s_axi_bready,
    input  logic [AXI_ID_W-1:0]     s_axi_arid,
    input  logic [AXI_ADDR_W-1:0]   s_axi_araddr,
    input  logic [AXI_LEN_W-1:0]    s_axi_arlen,
    input  logic [2:0]               s_axi_arsize,
    input  logic [1:0]               s_axi_arburst,
    input  logic                     s_axi_arvalid,
    output logic                     s_axi_arready,
    output logic [AXI_ID_W-1:0]     s_axi_rid,
    output logic [AXI_DATA_W-1:0]   s_axi_rdata,
    output logic [1:0]               s_axi_rresp,
    output logic                     s_axi_rlast,
    output logic                     s_axi_rvalid,
    input  logic                     s_axi_rready
);
    // Xilinx BRAM inference with byte-enable writes
    // 4 separate byte arrays for byte-write enable inference
    logic [7:0] mem_b0 [0:(DMEM_SIZE/4)-1];  // Byte 0 [7:0]
    logic [7:0] mem_b1 [0:(DMEM_SIZE/4)-1];  // Byte 1 [15:8]
    logic [7:0] mem_b2 [0:(DMEM_SIZE/4)-1];  // Byte 2 [23:16]
    logic [7:0] mem_b3 [0:(DMEM_SIZE/4)-1];  // Byte 3 [31:24]

    // Internal: AXI4 slave FSM
    // Internal: Burst address generation (INCR/WRAP)
    // Internal: BRAM synchronous read/write with byte enables
endmodule : bram_dmem
```

---

## 9. hyperram_ctrl - HyperRAM Controller

AXI4 slave interface to external HyperRAM with DDR data transfer, configurable latency, and CS# timing control.

### 9.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| **AXI4 Slave Interface** ||||
| `s_axi_awid` | input | 4 | Write address ID |
| `s_axi_awaddr` | input | 32 | Write address |
| `s_axi_awlen` | input | 8 | Burst length |
| `s_axi_awsize` | input | 3 | Burst size |
| `s_axi_awburst` | input | 2 | Burst type |
| `s_axi_awvalid` | input | 1 | Write address valid |
| `s_axi_awready` | output | 1 | Write address ready |
| `s_axi_wdata` | input | 32 | Write data |
| `s_axi_wstrb` | input | 4 | Write strobes |
| `s_axi_wlast` | input | 1 | Write last beat |
| `s_axi_wvalid` | input | 1 | Write data valid |
| `s_axi_wready` | output | 1 | Write data ready |
| `s_axi_bid` | output | 4 | Write response ID |
| `s_axi_bresp` | output | 2 | Write response |
| `s_axi_bvalid` | output | 1 | Write response valid |
| `s_axi_bready` | input | 1 | Write response ready |
| `s_axi_arid` | input | 4 | Read address ID |
| `s_axi_araddr` | input | 32 | Read address |
| `s_axi_arlen` | input | 8 | Burst length |
| `s_axi_arsize` | input | 3 | Burst size |
| `s_axi_arburst` | input | 2 | Burst type |
| `s_axi_arvalid` | input | 1 | Read address valid |
| `s_axi_arready` | output | 1 | Read address ready |
| `s_axi_rid` | output | 4 | Read data ID |
| `s_axi_rdata` | output | 32 | Read data |
| `s_axi_rresp` | output | 2 | Read response |
| `s_axi_rlast` | output | 1 | Read last beat |
| `s_axi_rvalid` | output | 1 | Read data valid |
| `s_axi_rready` | input | 1 | Read data ready |
| **HyperRAM Physical Interface** ||||
| `hyper_cs_n` | output | 1 | Chip select (active-low) |
| `hyper_ck` | output | 1 | HyperRAM clock |
| `hyper_ck_n` | output | 1 | HyperRAM clock inverted (differential) |
| `hyper_rwds` | inout | 1 | Read-Write Data Strobe |
| `hyper_dq` | inout | 8 | Bidirectional data bus (DDR) |
| `hyper_rst_n` | output | 1 | HyperRAM reset (active-low) |

### 9.2 Module Skeleton

```systemverilog
module hyperram_ctrl
    import vsync_pkg::*;
#(
    parameter int LATENCY_CYCLES = 6,   // Initial latency (6 or 3 clocks)
    parameter int FIXED_LATENCY  = 1    // 1=fixed latency, 0=variable (RWDS-based)
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // AXI4 Slave Interface (same as bram_dmem)
    input  logic [AXI_ID_W-1:0]     s_axi_awid,
    input  logic [AXI_ADDR_W-1:0]   s_axi_awaddr,
    input  logic [AXI_LEN_W-1:0]    s_axi_awlen,
    input  logic [2:0]               s_axi_awsize,
    input  logic [1:0]               s_axi_awburst,
    input  logic                     s_axi_awvalid,
    output logic                     s_axi_awready,
    input  logic [AXI_DATA_W-1:0]   s_axi_wdata,
    input  logic [AXI_STRB_W-1:0]   s_axi_wstrb,
    input  logic                     s_axi_wlast,
    input  logic                     s_axi_wvalid,
    output logic                     s_axi_wready,
    output logic [AXI_ID_W-1:0]     s_axi_bid,
    output logic [1:0]               s_axi_bresp,
    output logic                     s_axi_bvalid,
    input  logic                     s_axi_bready,
    input  logic [AXI_ID_W-1:0]     s_axi_arid,
    input  logic [AXI_ADDR_W-1:0]   s_axi_araddr,
    input  logic [AXI_LEN_W-1:0]    s_axi_arlen,
    input  logic [2:0]               s_axi_arsize,
    input  logic [1:0]               s_axi_arburst,
    input  logic                     s_axi_arvalid,
    output logic                     s_axi_arready,
    output logic [AXI_ID_W-1:0]     s_axi_rid,
    output logic [AXI_DATA_W-1:0]   s_axi_rdata,
    output logic [1:0]               s_axi_rresp,
    output logic                     s_axi_rlast,
    output logic                     s_axi_rvalid,
    input  logic                     s_axi_rready,

    // HyperRAM Physical Interface
    output logic                     hyper_cs_n,
    output logic                     hyper_ck,
    output logic                     hyper_ck_n,
    inout  wire                      hyper_rwds,
    inout  wire  [7:0]               hyper_dq,
    output logic                     hyper_rst_n
);
    // Internal: CA (Command-Address) 48-bit generation
    // Internal: Latency counter with RWDS monitoring
    // Internal: DDR data serializer/deserializer (32-bit ↔ 8-bit DDR)
    // Internal: RWDS handling (input strobe for read, output mask for write)
    // Internal: CS# timing (tCSHI, tRWR, tCSS)
endmodule : hyperram_ctrl
```

---

## 10. uart_apb - UART Controller

APB slave UART with configurable baud rate, TX/RX FIFOs, and interrupt generation.

### 10.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| **APB Slave Interface** ||||
| `apb_paddr` | input | 8 | Register offset address [7:0] |
| `apb_psel` | input | 1 | Peripheral select |
| `apb_penable` | input | 1 | APB enable (2nd phase) |
| `apb_pwrite` | input | 1 | Write enable |
| `apb_pwdata` | input | 32 | Write data |
| `apb_pstrb` | input | 4 | Write strobes |
| `apb_prdata` | output | 32 | Read data |
| `apb_pready` | output | 1 | Slave ready |
| `apb_pslverr` | output | 1 | Slave error |
| **External UART Pins** ||||
| `uart_tx` | output | 1 | UART transmit data |
| `uart_rx` | input | 1 | UART receive data |
| **Interrupt Output** ||||
| `uart_irq` | output | 1 | Interrupt (TX empty/RX available/error) |

### 10.2 Module Skeleton

```systemverilog
module uart_apb
    import vsync_pkg::*;
#(
    parameter int TX_FIFO_DEPTH   = 16,
    parameter int RX_FIFO_DEPTH   = 16,
    parameter int DEFAULT_BAUD_DIV = 868  // sys_clk / baud_rate (e.g., 100MHz/115200)
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // APB Slave Interface
    input  logic [7:0]               apb_paddr,
    input  logic                     apb_psel,
    input  logic                     apb_penable,
    input  logic                     apb_pwrite,
    input  logic [AXI_DATA_W-1:0]   apb_pwdata,
    input  logic [AXI_STRB_W-1:0]   apb_pstrb,
    output logic [AXI_DATA_W-1:0]   apb_prdata,
    output logic                     apb_pready,
    output logic                     apb_pslverr,

    // External UART Pins
    output logic                     uart_tx,
    input  logic                     uart_rx,

    // Interrupt
    output logic                     uart_irq
);
    // Internal: TX FIFO, TX shift register, baud rate generator
    // Internal: RX FIFO, RX shift register, oversampling (16x)
    // Internal: Control/Status/Interrupt registers
endmodule : uart_apb
```

---

## 11. gpio_apb - GPIO Controller

APB slave GPIO with per-pin direction control, edge/level interrupt detection.

### 11.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| **APB Slave Interface** ||||
| `apb_paddr` | input | 8 | Register offset address [7:0] |
| `apb_psel` | input | 1 | Peripheral select |
| `apb_penable` | input | 1 | APB enable |
| `apb_pwrite` | input | 1 | Write enable |
| `apb_pwdata` | input | 32 | Write data |
| `apb_pstrb` | input | 4 | Write strobes |
| `apb_prdata` | output | 32 | Read data |
| `apb_pready` | output | 1 | Slave ready |
| `apb_pslverr` | output | 1 | Slave error |
| **GPIO Pins** ||||
| `gpio_i` | input | 16 | GPIO input data (from pads, synchronized) |
| `gpio_o` | output | 16 | GPIO output data (to pads) |
| `gpio_oe` | output | 16 | GPIO output enable (1=output, 0=hi-Z input) |
| **Interrupt Output** ||||
| `gpio_irq` | output | 1 | Combined GPIO interrupt |

### 11.2 Module Skeleton

```systemverilog
module gpio_apb
    import vsync_pkg::*;
#(
    parameter int GPIO_WIDTH = 16
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // APB Slave Interface
    input  logic [7:0]               apb_paddr,
    input  logic                     apb_psel,
    input  logic                     apb_penable,
    input  logic                     apb_pwrite,
    input  logic [AXI_DATA_W-1:0]   apb_pwdata,
    input  logic [AXI_STRB_W-1:0]   apb_pstrb,
    output logic [AXI_DATA_W-1:0]   apb_prdata,
    output logic                     apb_pready,
    output logic                     apb_pslverr,

    // GPIO Pins
    input  logic [GPIO_WIDTH-1:0]    gpio_i,
    output logic [GPIO_WIDTH-1:0]    gpio_o,
    output logic [GPIO_WIDTH-1:0]    gpio_oe,

    // Interrupt
    output logic                     gpio_irq
);
    // Internal: Direction register, Output data register
    // Internal: Input synchronizer (2-stage)
    // Internal: Interrupt enable, type (edge/level), polarity, pending
endmodule : gpio_apb
```

---

## 12. plic - Platform-Level Interrupt Controller

RISC-V compliant PLIC with configurable interrupt priorities, enable bits, threshold, and claim/complete mechanism.

### 12.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| **Interrupt Source Inputs** ||||
| `irq_sources` | input | 16 | Interrupt sources [15:0] (bit 0 reserved) |
| **CPU Interrupt Output** ||||
| `external_irq` | output | 1 | External interrupt to CPU (M-mode meip) |
| **APB Slave Interface** ||||
| `apb_paddr` | input | 12 | Register offset address [11:0] (4KB space) |
| `apb_psel` | input | 1 | Peripheral select |
| `apb_penable` | input | 1 | APB enable |
| `apb_pwrite` | input | 1 | Write enable |
| `apb_pwdata` | input | 32 | Write data |
| `apb_pstrb` | input | 4 | Write strobes |
| `apb_prdata` | output | 32 | Read data |
| `apb_pready` | output | 1 | Slave ready |
| `apb_pslverr` | output | 1 | Slave error |

### 12.2 Module Skeleton

```systemverilog
module plic
    import vsync_pkg::*;
#(
    parameter int NUM_SOURCES    = 16,  // Interrupt sources (0 reserved)
    parameter int NUM_PRIORITIES = 8,   // Priority levels (3-bit, 0=disabled)
    parameter int NUM_TARGETS    = 1    // Hart targets (single hart)
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // Interrupt Sources
    input  logic [NUM_SOURCES-1:0]   irq_sources,

    // CPU Interrupt Output
    output logic                     external_irq,

    // APB Slave Interface
    input  logic [11:0]              apb_paddr,
    input  logic                     apb_psel,
    input  logic                     apb_penable,
    input  logic                     apb_pwrite,
    input  logic [AXI_DATA_W-1:0]   apb_pwdata,
    input  logic [AXI_STRB_W-1:0]   apb_pstrb,
    output logic [AXI_DATA_W-1:0]   apb_prdata,
    output logic                     apb_pready,
    output logic                     apb_pslverr
);
    // Internal: Priority registers array [NUM_SOURCES]
    // Internal: Pending bits register [NUM_SOURCES]
    // Internal: Enable bits per target [NUM_TARGETS][NUM_SOURCES]
    // Internal: Threshold register per target [NUM_TARGETS]
    // Internal: Claim/complete logic (highest priority pending & enabled)
    // Internal: Gateway (edge-to-level conversion per source)
endmodule : plic
```

---

## 13. clint - Core Local Interruptor

RISC-V compliant CLINT providing 64-bit mtime counter, mtimecmp compare register, and software interrupt.

### 13.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| **CPU Interrupt Outputs** ||||
| `timer_irq` | output | 1 | Timer interrupt (mtip: mtime >= mtimecmp) |
| `software_irq` | output | 1 | Software interrupt (msip[0]) |
| **RTOS Timer Tick** ||||
| `timer_tick` | output | 1 | Periodic tick pulse (for RTOS scheduler time-slicing) |
| **APB Slave Interface** ||||
| `apb_paddr` | input | 16 | Register offset address [15:0] (64KB space) |
| `apb_psel` | input | 1 | Peripheral select |
| `apb_penable` | input | 1 | APB enable |
| `apb_pwrite` | input | 1 | Write enable |
| `apb_pwdata` | input | 32 | Write data |
| `apb_pstrb` | input | 4 | Write strobes |
| `apb_prdata` | output | 32 | Read data |
| `apb_pready` | output | 1 | Slave ready |
| `apb_pslverr` | output | 1 | Slave error |

### 13.2 Module Skeleton

```systemverilog
module clint
    import vsync_pkg::*;
(
    input  logic                     clk,
    input  logic                     rst_n,

    // CPU Interrupt Outputs
    output logic                     timer_irq,
    output logic                     software_irq,

    // RTOS Timer Tick
    output logic                     timer_tick,

    // APB Slave Interface
    input  logic [15:0]              apb_paddr,
    input  logic                     apb_psel,
    input  logic                     apb_penable,
    input  logic                     apb_pwrite,
    input  logic [AXI_DATA_W-1:0]   apb_pwdata,
    input  logic [AXI_STRB_W-1:0]   apb_pstrb,
    output logic [AXI_DATA_W-1:0]   apb_prdata,
    output logic                     apb_pready,
    output logic                     apb_pslverr
);
    // Internal: mtime[63:0] - free-running 64-bit counter
    // Internal: mtimecmp[63:0] - compare register
    // Internal: msip[0] - software interrupt pending bit
    // timer_irq = (mtime >= mtimecmp)
    // software_irq = msip[0]
    // timer_tick = configurable periodic pulse from mtime
endmodule : clint
```

---

## 14. vsync_top - Top Module

System top-level module instantiating all sub-modules and providing external I/O.

### 14.1 Port Table

| Port Name | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| **Clock & Reset** ||||
| `clk` | input | 1 | External clock input (e.g., 100MHz) |
| `rst_n` | input | 1 | External active-low reset |
| **UART External Pins** ||||
| `uart_tx` | output | 1 | UART transmit |
| `uart_rx` | input | 1 | UART receive |
| **GPIO External Pins** ||||
| `gpio_io` | inout | 16 | GPIO bidirectional I/O pins |
| **HyperRAM External Pins** ||||
| `hyper_cs_n` | output | 1 | HyperRAM chip select (active-low) |
| `hyper_ck` | output | 1 | HyperRAM clock |
| `hyper_ck_n` | output | 1 | HyperRAM clock inverted |
| `hyper_rwds` | inout | 1 | HyperRAM read-write data strobe |
| `hyper_dq` | inout | 8 | HyperRAM data bus |
| `hyper_rst_n` | output | 1 | HyperRAM reset (active-low) |
| **JTAG Debug (optional)** ||||
| `jtag_tck` | input | 1 | JTAG test clock |
| `jtag_tms` | input | 1 | JTAG test mode select |
| `jtag_tdi` | input | 1 | JTAG test data in |
| `jtag_tdo` | output | 1 | JTAG test data out |
| `jtag_trst_n` | input | 1 | JTAG test reset (active-low) |

### 14.2 Module Skeleton

```systemverilog
module vsync_top
    import vsync_pkg::*;
#(
    parameter string IMEM_INIT_FILE = "firmware.hex",
    parameter int    GPIO_WIDTH     = 16
)(
    // Clock & Reset
    input  logic                     clk,
    input  logic                     rst_n,

    // UART External Pins
    output logic                     uart_tx,
    input  logic                     uart_rx,

    // GPIO External Pins
    inout  wire  [GPIO_WIDTH-1:0]    gpio_io,

    // HyperRAM External Pins
    output logic                     hyper_cs_n,
    output logic                     hyper_ck,
    output logic                     hyper_ck_n,
    inout  wire                      hyper_rwds,
    inout  wire  [7:0]               hyper_dq,
    output logic                     hyper_rst_n,

    // JTAG Debug Interface (optional)
    input  logic                     jtag_tck,
    input  logic                     jtag_tms,
    input  logic                     jtag_tdi,
    output logic                     jtag_tdo,
    input  logic                     jtag_trst_n
);

    // =========================================================================
    // Internal Signals
    // =========================================================================

    // Synchronized reset
    logic sys_rst_n;

    // Instruction memory interface (rv32im_core ↔ bram_imem)
    logic [IMEM_ADDR_W-1:0]  imem_addr;
    logic [XLEN-1:0]         imem_rdata;
    logic                     imem_en;

    // Data memory interface (rv32im_core ↔ axi4_master)
    logic [XLEN-1:0]         cpu_mem_addr, cpu_mem_wdata, cpu_mem_rdata;
    logic                     cpu_mem_read, cpu_mem_write, cpu_mem_ready, cpu_mem_error;
    logic [2:0]               cpu_mem_size;

    // Interrupt signals
    logic external_irq, timer_irq, software_irq;
    logic uart_irq, gpio_irq, timer_tick;
    logic [15:0] plic_irq_sources;

    // Context switch (rv32im_core ↔ hw_rtos)
    logic ctx_switch_req, ctx_switch_ack;
    logic ctx_save_en, ctx_restore_en;
    logic [REG_ADDR_W-1:0] ctx_save_reg_idx, ctx_restore_reg_idx;
    logic [XLEN-1:0] ctx_save_reg_data, ctx_restore_reg_data;
    logic [XLEN-1:0] ctx_save_pc, ctx_restore_pc;
    logic [TASK_ID_W-1:0] current_task_id;
    logic task_active;

    // Syscall (rv32im_core ↔ posix_hw_layer)
    logic ecall_req, syscall_done;
    logic [7:0] syscall_num;
    logic [XLEN-1:0] syscall_arg0, syscall_arg1, syscall_arg2, syscall_ret;

    // RTOS control (posix_hw_layer ↔ hw_rtos)
    // ... (all task/sem/mutex/msgq signals)

    // GPIO tri-state
    logic [GPIO_WIDTH-1:0] gpio_i, gpio_o, gpio_oe;

    // AXI4 bus signals (all channels for master↔interconnect↔slaves)
    // ... (comprehensive signal declarations)

    // APB bus signals (bridge↔peripherals)
    // ... (PADDR, PSEL, PENABLE, PWRITE, PWDATA, PRDATA, PREADY, PSLVERR)

    // =========================================================================
    // Reset Synchronizer (async assert, sync de-assert)
    // =========================================================================
    logic [1:0] rst_sync;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rst_sync <= 2'b00;
        else        rst_sync <= {rst_sync[0], 1'b1};
    end
    assign sys_rst_n = rst_sync[1];

    // =========================================================================
    // GPIO Tri-State Buffers
    // =========================================================================
    genvar gi;
    generate
        for (gi = 0; gi < GPIO_WIDTH; gi++) begin : gen_gpio
            assign gpio_io[gi] = gpio_oe[gi] ? gpio_o[gi] : 1'bz;
            assign gpio_i[gi]  = gpio_io[gi];
        end
    endgenerate

    // =========================================================================
    // PLIC Interrupt Source Mapping
    // =========================================================================
    assign plic_irq_sources = {14'd0, gpio_irq, uart_irq};
    // Bit 0: reserved (no interrupt)
    // Bit 1: UART interrupt
    // Bit 2: GPIO interrupt
    // Bits 3-15: reserved for future (QSPI, I2C, etc.)

    // =========================================================================
    // Module Instantiations
    // =========================================================================
    // (1)  rv32im_core      u_cpu
    // (2)  hw_rtos           u_rtos
    // (3)  posix_hw_layer    u_posix
    // (4)  axi4_master       u_axi_master
    // (5)  axi4_interconnect u_axi_xbar
    // (6)  axi4_apb_bridge   u_apb_bridge
    // (7)  bram_imem         u_imem
    // (8)  bram_dmem         u_dmem
    // (9)  hyperram_ctrl     u_hyperram
    // (10) uart_apb          u_uart
    // (11) gpio_apb          u_gpio
    // (12) plic              u_plic
    // (13) clint             u_clint

endmodule : vsync_top
```

---

## Appendix A: Module Dependency Hierarchy

```
vsync_top
├── rv32im_core          (5-stage pipeline CPU)
├── hw_rtos              (Hardware RTOS engine)
├── posix_hw_layer       (POSIX hardware abstraction)
├── axi4_master          (CPU→AXI4 protocol converter)
├── axi4_interconnect    (1:5 AXI4 crossbar)
├── axi4_apb_bridge      (AXI4→APB protocol bridge)
├── bram_imem            (64KB instruction BRAM)
├── bram_dmem            (16KB data BRAM with AXI4 slave)
├── hyperram_ctrl        (External HyperRAM controller)
├── uart_apb             (UART with TX/RX FIFOs)
├── gpio_apb             (16-bit GPIO with interrupts)
├── plic                 (Interrupt priority controller)
└── clint                (Timer + software interrupt)
```

All modules import `vsync_pkg` for shared types, parameters, and constants.

## Appendix B: Interface Summary Matrix

| Module | AXI4 Master | AXI4 Slave | APB Slave | Direct CPU | IRQ Out | IRQ In |
|--------|:-----------:|:----------:|:---------:|:----------:|:-------:|:------:|
| rv32im_core | - | - | - | - | - | 3 in |
| hw_rtos | - | 1 | - | ctx_sw | - | tick |
| posix_hw_layer | - | 1 | - | syscall | - | - |
| axi4_master | 1 | - | - | cpu i/f | - | - |
| axi4_interconnect | 5 (out) | 1 (in) | - | - | - | - |
| axi4_apb_bridge | - | 1 | 4 (master) | - | - | - |
| bram_imem | - | - | - | imem i/f | - | - |
| bram_dmem | - | 1 | - | - | - | - |
| hyperram_ctrl | - | 1 | - | - | - | - |
| uart_apb | - | - | 1 | - | 1 | - |
| gpio_apb | - | - | 1 | - | 1 | - |
| plic | - | - | 1 | - | 1 | 16 in |
| clint | - | - | 1 | - | 2+tick | - |
| vsync_top | - | - | - | ext pins | - | - |
