// =============================================================================
// VSync - System Top Module
// RISC-V RV32IM Processor with Hardware RTOS
//
// File: vsync_top.sv
// Description: Top-level integration of all VSync SoC modules
//              Connects CPU core, memory subsystem, bus infrastructure,
//              peripherals, RTOS engine, and POSIX hardware layer.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

module vsync_top
  import vsync_pkg::*;
#(
    parameter string IMEM_INIT_FILE = "firmware_i.hex",
    parameter string DMEM_INIT_FILE = "firmware_d.hex",
    parameter int    GPIO_WIDTH     = 16
) (
    // Clock & Reset
    input logic clk,
    input logic rst_n,

    // BTN
    input logic [3:0] btn,

    // LED
    output logic [3:0] led,
    output logic [3:0] led_r,

    // UART
    output logic uart_tx,
    input  logic uart_rx,

    // GPIO
    inout wire [GPIO_WIDTH-1:0] gpio_io,

    // HyperRAM
    output logic       hyper_cs_n,
    output logic       hyper_ck,
    output logic       hyper_ck_n,
    inout  wire        hyper_rwds,
    inout  wire  [7:0] hyper_dq,
    output logic       hyper_rst_n,

    // JTAG Debug
    input  logic jtag_tck,
    input  logic jtag_tms,
    input  logic jtag_tdi,
    output logic jtag_tdo,
    input  logic jtag_trst_n
);

  // =========================================================================
  // Clock Generation: 100 MHz -> 25 MHz via MMCME2_BASE
  // =========================================================================
  logic clk_sys;  // 25 MHz system clock
  logic mmcm_locked;  // MMCM lock indicator

`ifndef IVERILOG
  logic clk_fb;
  logic clk_25m_unbuf;

  MMCME2_BASE #(
      .CLKIN1_PERIOD(10.0),  // 100 MHz input
      .CLKFBOUT_MULT_F(10.0),  // VCO = 1000 MHz
      .CLKOUT0_DIVIDE_F(40.0),  // 1000/40 = 25 MHz
      .DIVCLK_DIVIDE(1)
  ) u_mmcm (
      .CLKIN1   (clk),
      .CLKOUT0  (clk_25m_unbuf),
      .CLKFBOUT (clk_fb),
      .CLKFBIN  (clk_fb),
      .RST      (1'b0),
      .PWRDWN   (1'b0),
      .LOCKED   (mmcm_locked),
      .CLKOUT0B (),
      .CLKOUT1  (),
      .CLKOUT1B (),
      .CLKOUT2  (),
      .CLKOUT2B (),
      .CLKOUT3  (),
      .CLKOUT3B (),
      .CLKOUT4  (),
      .CLKOUT5  (),
      .CLKOUT6  (),
      .CLKFBOUTB()
  );

  BUFG u_bufg_clk (
      .I(clk_25m_unbuf),
      .O(clk_sys)
  );
`else
  // Simulation: testbench provides 25 MHz clock directly
  assign clk_sys = clk;
  assign mmcm_locked = 1'b1;
`endif

  // =========================================================================
  // Stage 1: Infrastructure - Signal Declarations, Reset Sync, GPIO,
  //          Interrupt Mapping, AXI4/APB Bus Signals, Control Signals
  // =========================================================================

  logic [31:0] led_count;
  always_ff @(posedge clk_sys) begin
    if (rst_n) begin
      led_count <= 0;
    end else if (led_count < 10000000) begin
      led_count <= led_count + 1;
    end else begin
      led_count <= 0;
      led_r[0]  <= ~led_r[0];
    end
  end
  logic [31:0] led2_count;
  always_ff @(posedge clk_sys) begin
    if (led2_count < 10000000) begin
      led2_count <= led2_count + 1;
    end else begin
      led2_count <= 0;
      led_r[1]   <= ~led_r[1];
    end
  end

  //assign led = btn;
  assign led_r[3] = mmcm_locked;

  // -------------------------------------------------------------------------
  // 1.1 Synchronized Reset
  // -------------------------------------------------------------------------
  logic [2:0] rst_sync_ff;
  logic       sys_rst_n;

  // Asynchronous assert, synchronous de-assert reset synchronizer
  // Reset held active until MMCM is locked
  always_ff @(posedge clk_sys) begin
    if (rst_n || !mmcm_locked) begin
      rst_sync_ff <= 3'b000;
    end else begin
      rst_sync_ff <= {rst_sync_ff[1:0], 1'b1};
    end
  end

  assign sys_rst_n = rst_sync_ff[2];

  // -------------------------------------------------------------------------
  // 1.2 CPU <-> Instruction Memory Signals
  // -------------------------------------------------------------------------
  logic [    IMEM_ADDR_W-1:0] cpu_imem_addr;
  logic [           XLEN-1:0] cpu_imem_rdata;
  logic                       cpu_imem_en;

  // IMEM Port B Signals (for AXI-to-BRAM bridge, data bus R/W access)
  logic [    IMEM_ADDR_W-1:0] imem_b_addr;
  logic [               31:0] imem_b_wdata;
  logic                       imem_b_we;
  logic [                3:0] imem_b_be;
  logic                       imem_b_en;
  logic [               31:0] imem_b_rdata;

  // -------------------------------------------------------------------------
  // 1.3 CPU <-> AXI4 Master Signals (Data Memory Interface)
  // -------------------------------------------------------------------------
  logic [           XLEN-1:0] cpu_mem_addr;
  logic [           XLEN-1:0] cpu_mem_wdata;
  logic                       cpu_mem_read;
  logic                       cpu_mem_write;
  logic [                2:0] cpu_mem_size;
  logic [           XLEN-1:0] cpu_mem_rdata;
  logic                       cpu_mem_ready;
  logic                       cpu_mem_error;

  // AXI4 Master command interface signals (adapted from CPU mem interface)
  logic                       axi_cmd_read;
  logic                       axi_cmd_write;
  logic [               31:0] axi_cmd_addr;
  logic [               31:0] axi_cmd_wdata;
  logic [                3:0] axi_cmd_wstrb;
  logic [               31:0] axi_cmd_rdata;
  logic                       axi_cmd_done;
  logic                       axi_cmd_error;

  // -------------------------------------------------------------------------
  // 1.4 Interrupt Signals
  // -------------------------------------------------------------------------
  logic                       plic_ext_irq;
  logic                       clint_timer_irq;
  logic                       clint_sw_irq;
  logic                       uart_irq;
  logic                       gpio_irq;
  logic [               15:0] plic_irq_sources;

  // -------------------------------------------------------------------------
  // 1.5 Context Switch / RTOS Control Signals (CPU <-> hw_rtos)
  // -------------------------------------------------------------------------
  logic                       ctx_switch_req;
  logic                       ctx_switch_ack;
  logic                       ctx_save_en;
  logic [     REG_ADDR_W-1:0] ctx_save_reg_idx;
  logic [           XLEN-1:0] ctx_save_reg_data;
  logic [           XLEN-1:0] ctx_save_pc;
  logic                       ctx_restore_en;
  logic [     REG_ADDR_W-1:0] ctx_restore_reg_idx;
  logic [           XLEN-1:0] ctx_restore_reg_data;
  logic [           XLEN-1:0] ctx_restore_pc;
  logic [      TASK_ID_W-1:0] current_task_id;
  logic [      TASK_ID_W-1:0] next_task_id;
  logic                       task_active;

  // RTOS scheduler control
  logic                       scheduler_en;
  logic [                1:0] schedule_policy;

  // -------------------------------------------------------------------------
  // 1.6 POSIX Syscall Signals (CPU <-> posix_hw_layer)
  // -------------------------------------------------------------------------
  logic                       ecall_req;
  logic [                7:0] syscall_num;
  logic [           XLEN-1:0] syscall_arg0;
  logic [           XLEN-1:0] syscall_arg1;
  logic [           XLEN-1:0] syscall_arg2;
  logic [           XLEN-1:0] syscall_ret;
  logic                       syscall_done;

  // -------------------------------------------------------------------------
  // 1.7 POSIX <-> RTOS Control Signals
  // -------------------------------------------------------------------------
  logic                       rtos_task_create;
  logic [           XLEN-1:0] rtos_task_create_pc;
  logic [           XLEN-1:0] rtos_task_create_sp;
  logic [TASK_PRIORITY_W-1:0] rtos_task_create_prio;
  logic                       rtos_task_create_done;
  logic [      TASK_ID_W-1:0] rtos_task_create_id;
  logic                       rtos_task_exit;
  logic                       rtos_task_join;
  logic [      TASK_ID_W-1:0] rtos_task_target_id;
  logic                       rtos_task_join_done;
  logic                       rtos_task_yield;
  logic [                1:0] rtos_sem_op;
  logic [                2:0] rtos_sem_id;
  logic [                7:0] rtos_sem_value;
  logic                       rtos_sem_done;
  logic                       rtos_sem_result;
  logic [                1:0] rtos_mutex_op;
  logic [                2:0] rtos_mutex_id;
  logic                       rtos_mutex_done;
  logic                       rtos_mutex_result;
  logic [                1:0] rtos_msgq_op;
  logic [                1:0] rtos_msgq_id;
  logic [           XLEN-1:0] rtos_msgq_data;
  logic                       rtos_msgq_done;
  logic [           XLEN-1:0] rtos_msgq_result;
  logic                       rtos_msgq_success;

  // -------------------------------------------------------------------------
  // 1.8 POSIX Peripheral Access Signals
  // -------------------------------------------------------------------------
  logic [           XLEN-1:0] periph_addr;
  logic [           XLEN-1:0] periph_wdata;
  logic                       periph_read;
  logic                       periph_write;
  logic [           XLEN-1:0] periph_rdata;
  logic                       periph_ready;

  // -------------------------------------------------------------------------
  // 1.9 CPU Debug Signals
  // -------------------------------------------------------------------------
  logic                       debug_halt_req;
  logic                       debug_halted;
  logic [           XLEN-1:0] debug_pc;
  logic [           XLEN-1:0] debug_instr;
  logic [     REG_ADDR_W-1:0] debug_reg_addr;
  logic [           XLEN-1:0] debug_reg_data;

  // -------------------------------------------------------------------------
  // 1.10 AXI4 Master <-> Interconnect Signals
  // -------------------------------------------------------------------------
  // AXI4 Master output (from axi4_master) -> Interconnect slave port
  logic [                3:0] axi_m_awid;
  logic [               31:0] axi_m_awaddr;
  logic [                7:0] axi_m_awlen;
  logic [                2:0] axi_m_awsize;
  logic [                1:0] axi_m_awburst;
  logic                       axi_m_awvalid;
  logic                       axi_m_awready;

  logic [               31:0] axi_m_wdata;
  logic [                3:0] axi_m_wstrb;
  logic                       axi_m_wlast;
  logic                       axi_m_wvalid;
  logic                       axi_m_wready;

  logic [                3:0] axi_m_bid;
  logic [                1:0] axi_m_bresp;
  logic                       axi_m_bvalid;
  logic                       axi_m_bready;

  logic [                3:0] axi_m_arid;
  logic [               31:0] axi_m_araddr;
  logic [                7:0] axi_m_arlen;
  logic [                2:0] axi_m_arsize;
  logic [                1:0] axi_m_arburst;
  logic                       axi_m_arvalid;
  logic                       axi_m_arready;

  logic [                3:0] axi_m_rid;
  logic [               31:0] axi_m_rdata;
  logic [                1:0] axi_m_rresp;
  logic                       axi_m_rlast;
  logic                       axi_m_rvalid;
  logic                       axi_m_rready;

  // -------------------------------------------------------------------------
  // 1.11 Interconnect <-> Slave AXI4 Signals (Array-based, NUM_SLAVES=6)
  // -------------------------------------------------------------------------
  // Slave Index Mapping:
  //   [0] = bram_dmem (via AXI-to-BRAM bridge)
  //   [1] = hyperram_ctrl
  //   [2] = axi4_apb_bridge (CLINT/PLIC/UART/GPIO)
  //   [3] = hw_rtos
  //   [4] = posix_hw_layer
  //   [5] = bram_imem (via AXI-to-BRAM bridge)
  localparam int NUM_AXI_SLAVES = 6;

  // Write Address Channel
  logic [ 3:0] xbar_m_awid   [NUM_AXI_SLAVES];
  logic [31:0] xbar_m_awaddr [NUM_AXI_SLAVES];
  logic [ 7:0] xbar_m_awlen  [NUM_AXI_SLAVES];
  logic [ 2:0] xbar_m_awsize [NUM_AXI_SLAVES];
  logic [ 1:0] xbar_m_awburst[NUM_AXI_SLAVES];
  logic        xbar_m_awvalid[NUM_AXI_SLAVES];
  logic        xbar_m_awready[NUM_AXI_SLAVES];

  // Write Data Channel
  logic [31:0] xbar_m_wdata  [NUM_AXI_SLAVES];
  logic [ 3:0] xbar_m_wstrb  [NUM_AXI_SLAVES];
  logic        xbar_m_wlast  [NUM_AXI_SLAVES];
  logic        xbar_m_wvalid [NUM_AXI_SLAVES];
  logic        xbar_m_wready [NUM_AXI_SLAVES];

  // Write Response Channel
  logic [ 3:0] xbar_m_bid    [NUM_AXI_SLAVES];
  logic [ 1:0] xbar_m_bresp  [NUM_AXI_SLAVES];
  logic        xbar_m_bvalid [NUM_AXI_SLAVES];
  logic        xbar_m_bready [NUM_AXI_SLAVES];

  // Read Address Channel
  logic [ 3:0] xbar_m_arid   [NUM_AXI_SLAVES];
  logic [31:0] xbar_m_araddr [NUM_AXI_SLAVES];
  logic [ 7:0] xbar_m_arlen  [NUM_AXI_SLAVES];
  logic [ 2:0] xbar_m_arsize [NUM_AXI_SLAVES];
  logic [ 1:0] xbar_m_arburst[NUM_AXI_SLAVES];
  logic        xbar_m_arvalid[NUM_AXI_SLAVES];
  logic        xbar_m_arready[NUM_AXI_SLAVES];

  // Read Data Channel
  logic [ 3:0] xbar_m_rid    [NUM_AXI_SLAVES];
  logic [31:0] xbar_m_rdata  [NUM_AXI_SLAVES];
  logic [ 1:0] xbar_m_rresp  [NUM_AXI_SLAVES];
  logic        xbar_m_rlast  [NUM_AXI_SLAVES];
  logic        xbar_m_rvalid [NUM_AXI_SLAVES];
  logic        xbar_m_rready [NUM_AXI_SLAVES];

  // -------------------------------------------------------------------------
  // 1.11a iverilog workaround: dummy signals for broken unpacked array
  //       output ports + assigns to drive real xbar_m_* signals
  // -------------------------------------------------------------------------
`ifdef IVERILOG
  // Dummy signals to absorb broken interconnect output ports
  logic [ 3:0] xbar_m_dummy_awid   [NUM_AXI_SLAVES];
  logic [31:0] xbar_m_dummy_awaddr [NUM_AXI_SLAVES];
  logic [ 7:0] xbar_m_dummy_awlen  [NUM_AXI_SLAVES];
  logic [ 2:0] xbar_m_dummy_awsize [NUM_AXI_SLAVES];
  logic [ 1:0] xbar_m_dummy_awburst[NUM_AXI_SLAVES];
  logic        xbar_m_dummy_awvalid[NUM_AXI_SLAVES];
  logic [31:0] xbar_m_dummy_wdata  [NUM_AXI_SLAVES];
  logic [ 3:0] xbar_m_dummy_wstrb  [NUM_AXI_SLAVES];
  logic        xbar_m_dummy_wlast  [NUM_AXI_SLAVES];
  logic        xbar_m_dummy_wvalid [NUM_AXI_SLAVES];
  logic        xbar_m_dummy_bready [NUM_AXI_SLAVES];
  logic [ 3:0] xbar_m_dummy_arid   [NUM_AXI_SLAVES];
  logic [31:0] xbar_m_dummy_araddr [NUM_AXI_SLAVES];
  logic [ 7:0] xbar_m_dummy_arlen  [NUM_AXI_SLAVES];
  logic [ 2:0] xbar_m_dummy_arsize [NUM_AXI_SLAVES];
  logic [ 1:0] xbar_m_dummy_arburst[NUM_AXI_SLAVES];
  logic        xbar_m_dummy_arvalid[NUM_AXI_SLAVES];
  logic        xbar_m_dummy_rready [NUM_AXI_SLAVES];

  // Drive real xbar_m_* from interconnect internal packed vectors (gated)
  // and AXI master signals (broadcast). Uses constant-index assigns which
  // work correctly in iverilog for local unpacked arrays.

  // Gated: awvalid (from awvalid_vec)
  assign xbar_m_awvalid[0] = u_axi_xbar.awvalid_vec[0];
  assign xbar_m_awvalid[1] = u_axi_xbar.awvalid_vec[1];
  assign xbar_m_awvalid[2] = u_axi_xbar.awvalid_vec[2];
  assign xbar_m_awvalid[3] = u_axi_xbar.awvalid_vec[3];
  assign xbar_m_awvalid[4] = u_axi_xbar.awvalid_vec[4];
  assign xbar_m_awvalid[5] = u_axi_xbar.awvalid_vec[5];
  // Gated: arvalid (from arvalid_vec)
  assign xbar_m_arvalid[0] = u_axi_xbar.arvalid_vec[0];
  assign xbar_m_arvalid[1] = u_axi_xbar.arvalid_vec[1];
  assign xbar_m_arvalid[2] = u_axi_xbar.arvalid_vec[2];
  assign xbar_m_arvalid[3] = u_axi_xbar.arvalid_vec[3];
  assign xbar_m_arvalid[4] = u_axi_xbar.arvalid_vec[4];
  assign xbar_m_arvalid[5] = u_axi_xbar.arvalid_vec[5];
  // Gated: wvalid (from wvalid_vec)
  assign xbar_m_wvalid[0] = u_axi_xbar.wvalid_vec[0];
  assign xbar_m_wvalid[1] = u_axi_xbar.wvalid_vec[1];
  assign xbar_m_wvalid[2] = u_axi_xbar.wvalid_vec[2];
  assign xbar_m_wvalid[3] = u_axi_xbar.wvalid_vec[3];
  assign xbar_m_wvalid[4] = u_axi_xbar.wvalid_vec[4];
  assign xbar_m_wvalid[5] = u_axi_xbar.wvalid_vec[5];
  // Gated: bready (from bready_vec)
  assign xbar_m_bready[0] = u_axi_xbar.bready_vec[0];
  assign xbar_m_bready[1] = u_axi_xbar.bready_vec[1];
  assign xbar_m_bready[2] = u_axi_xbar.bready_vec[2];
  assign xbar_m_bready[3] = u_axi_xbar.bready_vec[3];
  assign xbar_m_bready[4] = u_axi_xbar.bready_vec[4];
  assign xbar_m_bready[5] = u_axi_xbar.bready_vec[5];
  // Gated: rready (from rready_vec)
  assign xbar_m_rready[0] = u_axi_xbar.rready_vec[0];
  assign xbar_m_rready[1] = u_axi_xbar.rready_vec[1];
  assign xbar_m_rready[2] = u_axi_xbar.rready_vec[2];
  assign xbar_m_rready[3] = u_axi_xbar.rready_vec[3];
  assign xbar_m_rready[4] = u_axi_xbar.rready_vec[4];
  assign xbar_m_rready[5] = u_axi_xbar.rready_vec[5];

  // Broadcast: AW channel (passthrough from AXI master)
  assign xbar_m_awid[0] = axi_m_awid;
  assign xbar_m_awid[1] = axi_m_awid;
  assign xbar_m_awid[2] = axi_m_awid;
  assign xbar_m_awid[3] = axi_m_awid;
  assign xbar_m_awid[4] = axi_m_awid;
  assign xbar_m_awid[5] = axi_m_awid;
  assign xbar_m_awaddr[0] = axi_m_awaddr;
  assign xbar_m_awaddr[1] = axi_m_awaddr;
  assign xbar_m_awaddr[2] = axi_m_awaddr;
  assign xbar_m_awaddr[3] = axi_m_awaddr;
  assign xbar_m_awaddr[4] = axi_m_awaddr;
  assign xbar_m_awaddr[5] = axi_m_awaddr;
  assign xbar_m_awlen[0] = axi_m_awlen;
  assign xbar_m_awlen[1] = axi_m_awlen;
  assign xbar_m_awlen[2] = axi_m_awlen;
  assign xbar_m_awlen[3] = axi_m_awlen;
  assign xbar_m_awlen[4] = axi_m_awlen;
  assign xbar_m_awlen[5] = axi_m_awlen;
  assign xbar_m_awsize[0] = axi_m_awsize;
  assign xbar_m_awsize[1] = axi_m_awsize;
  assign xbar_m_awsize[2] = axi_m_awsize;
  assign xbar_m_awsize[3] = axi_m_awsize;
  assign xbar_m_awsize[4] = axi_m_awsize;
  assign xbar_m_awsize[5] = axi_m_awsize;
  assign xbar_m_awburst[0] = axi_m_awburst;
  assign xbar_m_awburst[1] = axi_m_awburst;
  assign xbar_m_awburst[2] = axi_m_awburst;
  assign xbar_m_awburst[3] = axi_m_awburst;
  assign xbar_m_awburst[4] = axi_m_awburst;
  assign xbar_m_awburst[5] = axi_m_awburst;

  // Broadcast: AR channel (passthrough from AXI master)
  assign xbar_m_arid[0] = axi_m_arid;
  assign xbar_m_arid[1] = axi_m_arid;
  assign xbar_m_arid[2] = axi_m_arid;
  assign xbar_m_arid[3] = axi_m_arid;
  assign xbar_m_arid[4] = axi_m_arid;
  assign xbar_m_arid[5] = axi_m_arid;
  assign xbar_m_araddr[0] = axi_m_araddr;
  assign xbar_m_araddr[1] = axi_m_araddr;
  assign xbar_m_araddr[2] = axi_m_araddr;
  assign xbar_m_araddr[3] = axi_m_araddr;
  assign xbar_m_araddr[4] = axi_m_araddr;
  assign xbar_m_araddr[5] = axi_m_araddr;
  assign xbar_m_arlen[0] = axi_m_arlen;
  assign xbar_m_arlen[1] = axi_m_arlen;
  assign xbar_m_arlen[2] = axi_m_arlen;
  assign xbar_m_arlen[3] = axi_m_arlen;
  assign xbar_m_arlen[4] = axi_m_arlen;
  assign xbar_m_arlen[5] = axi_m_arlen;
  assign xbar_m_arsize[0] = axi_m_arsize;
  assign xbar_m_arsize[1] = axi_m_arsize;
  assign xbar_m_arsize[2] = axi_m_arsize;
  assign xbar_m_arsize[3] = axi_m_arsize;
  assign xbar_m_arsize[4] = axi_m_arsize;
  assign xbar_m_arsize[5] = axi_m_arsize;
  assign xbar_m_arburst[0] = axi_m_arburst;
  assign xbar_m_arburst[1] = axi_m_arburst;
  assign xbar_m_arburst[2] = axi_m_arburst;
  assign xbar_m_arburst[3] = axi_m_arburst;
  assign xbar_m_arburst[4] = axi_m_arburst;
  assign xbar_m_arburst[5] = axi_m_arburst;

  // Broadcast: W channel (passthrough from AXI master)
  assign xbar_m_wdata[0] = axi_m_wdata;
  assign xbar_m_wdata[1] = axi_m_wdata;
  assign xbar_m_wdata[2] = axi_m_wdata;
  assign xbar_m_wdata[3] = axi_m_wdata;
  assign xbar_m_wdata[4] = axi_m_wdata;
  assign xbar_m_wdata[5] = axi_m_wdata;
  assign xbar_m_wstrb[0] = axi_m_wstrb;
  assign xbar_m_wstrb[1] = axi_m_wstrb;
  assign xbar_m_wstrb[2] = axi_m_wstrb;
  assign xbar_m_wstrb[3] = axi_m_wstrb;
  assign xbar_m_wstrb[4] = axi_m_wstrb;
  assign xbar_m_wstrb[5] = axi_m_wstrb;
  assign xbar_m_wlast[0] = axi_m_wlast;
  assign xbar_m_wlast[1] = axi_m_wlast;
  assign xbar_m_wlast[2] = axi_m_wlast;
  assign xbar_m_wlast[3] = axi_m_wlast;
  assign xbar_m_wlast[4] = axi_m_wlast;
  assign xbar_m_wlast[5] = axi_m_wlast;
`endif

  // -------------------------------------------------------------------------
  // 1.11b Intermediate signals for DMEM/IMEM bridge FSMs (iverilog compat)
  // -------------------------------------------------------------------------
  // iverilog cannot assign to unpacked array elements in always_comb.
  // Use intermediate signals in always_comb, then connect via assign.

  // DMEM bridge (slave[0]) intermediate output signals
  logic        dmem_s_awready;
  logic        dmem_s_wready;
  logic [ 3:0] dmem_s_bid;
  logic [ 1:0] dmem_s_bresp;
  logic        dmem_s_bvalid;
  logic        dmem_s_arready;
  logic [ 3:0] dmem_s_rid;
  logic [31:0] dmem_s_rdata;
  logic [ 1:0] dmem_s_rresp;
  logic        dmem_s_rlast;
  logic        dmem_s_rvalid;

  assign xbar_m_awready[0] = dmem_s_awready;
  assign xbar_m_wready[0]  = dmem_s_wready;
  assign xbar_m_bid[0]     = dmem_s_bid;
  assign xbar_m_bresp[0]   = dmem_s_bresp;
  assign xbar_m_bvalid[0]  = dmem_s_bvalid;
  assign xbar_m_arready[0] = dmem_s_arready;
  assign xbar_m_rid[0]     = dmem_s_rid;
  assign xbar_m_rdata[0]   = dmem_s_rdata;
  assign xbar_m_rresp[0]   = dmem_s_rresp;
  assign xbar_m_rlast[0]   = dmem_s_rlast;
  assign xbar_m_rvalid[0]  = dmem_s_rvalid;

  // IMEM bridge (slave[5]) intermediate output signals
  logic        imem_s_awready;
  logic        imem_s_wready;
  logic [ 3:0] imem_s_bid;
  logic [ 1:0] imem_s_bresp;
  logic        imem_s_bvalid;
  logic        imem_s_arready;
  logic [ 3:0] imem_s_rid;
  logic [31:0] imem_s_rdata;
  logic [ 1:0] imem_s_rresp;
  logic        imem_s_rlast;
  logic        imem_s_rvalid;

  assign xbar_m_awready[5] = imem_s_awready;
  assign xbar_m_wready[5]  = imem_s_wready;
  assign xbar_m_bid[5]     = imem_s_bid;
  assign xbar_m_bresp[5]   = imem_s_bresp;
  assign xbar_m_bvalid[5]  = imem_s_bvalid;
  assign xbar_m_arready[5] = imem_s_arready;
  assign xbar_m_rid[5]     = imem_s_rid;
  assign xbar_m_rdata[5]   = imem_s_rdata;
  assign xbar_m_rresp[5]   = imem_s_rresp;
  assign xbar_m_rlast[5]   = imem_s_rlast;
  assign xbar_m_rvalid[5]  = imem_s_rvalid;

  // -------------------------------------------------------------------------
  // 1.12 APB Bridge <-> Peripheral Signals
  // -------------------------------------------------------------------------
  logic                   apb_psel_bridge;
  logic                   apb_penable;
  logic                   apb_pwrite;
  logic [           31:0] apb_paddr;
  logic [           31:0] apb_pwdata;
  logic [           31:0] apb_prdata_bridge;
  logic                   apb_pready_bridge;
  logic                   apb_pslverr_bridge;

  // Per-peripheral APB select signals
  logic                   apb_psel_uart;
  logic                   apb_psel_gpio;
  logic                   apb_psel_plic;
  logic                   apb_psel_clint;

  // Per-peripheral APB response signals
  logic [           31:0] apb_prdata_uart;
  logic                   apb_pready_uart;
  logic                   apb_pslverr_uart;

  logic [           31:0] apb_prdata_gpio;
  logic                   apb_pready_gpio;
  logic                   apb_pslverr_gpio;

  logic [           31:0] apb_prdata_plic;
  logic                   apb_pready_plic;
  logic                   apb_pslverr_plic;

  logic [           31:0] apb_prdata_clint;
  logic                   apb_pready_clint;
  logic                   apb_pslverr_clint;

  // -------------------------------------------------------------------------
  // 1.13 HyperRAM Tri-state Signals
  // -------------------------------------------------------------------------
  logic                   hb_ck;
  logic                   hb_ck_n;
  logic                   hb_cs_n;
  logic                   hb_rwds_oe;
  logic                   hb_rwds_o;
  logic                   hb_rwds_i;
  logic                   hb_dq_oe;
  logic [            7:0] hb_dq_o;
  logic [            7:0] hb_dq_i;

  // -------------------------------------------------------------------------
  // 1.14 GPIO Tri-state Signals
  // -------------------------------------------------------------------------
  logic [ GPIO_WIDTH-1:0] gpio_in;
  logic [ GPIO_WIDTH-1:0] gpio_out;
  logic [ GPIO_WIDTH-1:0] gpio_oe;

  // -------------------------------------------------------------------------
  // 1.15 BRAM DMEM Signals (for AXI-to-BRAM bridge)
  // -------------------------------------------------------------------------
  logic [DMEM_ADDR_W-3:0] dmem_addr;  // Word address (12-bit for 4096 words)
  logic [           31:0] dmem_wdata;
  logic                   dmem_we;
  logic [            3:0] dmem_be;
  logic                   dmem_re;
  logic [           31:0] dmem_rdata;

  // -------------------------------------------------------------------------
  // 1.16 Timer Tick for hw_rtos
  // -------------------------------------------------------------------------
  // Since CLINT has no timer_tick output, generate one from timer_irq
  // rising edge detection
  logic                   timer_tick;
  logic                   timer_irq_prev;

  always_ff @(posedge clk_sys or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      timer_irq_prev <= 1'b0;
    end else begin
      timer_irq_prev <= clint_timer_irq;
    end
  end

  assign timer_tick = clint_timer_irq & ~timer_irq_prev;

  // -------------------------------------------------------------------------
  // 1.17 CPU mem_size -> cmd_wstrb Conversion
  // -------------------------------------------------------------------------
  // Convert funct3-based mem_size to AXI byte strobes
  always_comb begin
    axi_cmd_read  = cpu_mem_read;
    axi_cmd_write = cpu_mem_write;
    axi_cmd_addr  = cpu_mem_addr;
    axi_cmd_wdata = cpu_mem_wdata;

    case (cpu_mem_size)
      3'b000:  axi_cmd_wstrb = 4'b0001 << cpu_mem_addr[1:0];  // Byte
      3'b001:  axi_cmd_wstrb = 4'b0011 << cpu_mem_addr[1:0];  // Halfword
      3'b010:  axi_cmd_wstrb = 4'b1111;  // Word
      default: axi_cmd_wstrb = 4'b1111;
    endcase
  end

  assign cpu_mem_rdata = axi_cmd_rdata;
  assign cpu_mem_ready = axi_cmd_done;
  assign cpu_mem_error = axi_cmd_error;

  // -------------------------------------------------------------------------
  // 1.18 GPIO Tri-state Buffers
  // -------------------------------------------------------------------------
  genvar gi;
  generate
    for (gi = 0; gi < GPIO_WIDTH; gi++) begin : gen_gpio_tristate
      assign gpio_io[gi] = gpio_oe[gi] ? gpio_out[gi] : 1'bz;
      assign gpio_in[gi] = gpio_io[gi];
    end
  endgenerate

  // -------------------------------------------------------------------------
  // 1.19 HyperRAM Tri-state Buffers
  // -------------------------------------------------------------------------
  assign hyper_dq   = hb_dq_oe   ? hb_dq_o   : 8'bz;
  assign hb_dq_i    = hyper_dq;
  assign hyper_rwds = hb_rwds_oe ? hb_rwds_o  : 1'bz;
  assign hb_rwds_i  = hyper_rwds;
  assign hyper_cs_n = hb_cs_n;
  assign hyper_ck   = hb_ck;
  assign hyper_ck_n = hb_ck_n;
  assign hyper_rst_n = sys_rst_n;

  // -------------------------------------------------------------------------
  // 1.20 PLIC Interrupt Source Mapping
  // -------------------------------------------------------------------------
  // irq_sources[0] = reserved, [1] = uart_irq, [2] = gpio_irq, [15:3] = reserved
  // Per module_io_spec.md §14: Bit 0 reserved, Bit 1 UART, Bit 2 GPIO
  assign plic_irq_sources = {13'd0, gpio_irq, uart_irq, 1'b0};

  // -------------------------------------------------------------------------
  // 1.21 APB Address Decode Logic
  // -------------------------------------------------------------------------
  // REVIEW-005 fix: Merge APB access from both paths:
  //   Path A: AXI-APB bridge (CPU direct memory-mapped access)
  //   Path B: POSIX peripheral access (posix_hw_layer file I/O)
  // Arbitration: periph APB takes priority when active (posix_hw_layer
  // stalls CPU via ecall, so no contention expected)
  logic        apb_mux_psel;
  logic        apb_mux_penable;
  logic        apb_mux_pwrite;
  logic [31:0] apb_mux_paddr;
  logic [31:0] apb_mux_pwdata;

  always_comb begin
    if (periph_apb_psel) begin
      // POSIX peripheral path active
      apb_mux_psel    = periph_apb_psel;
      apb_mux_penable = periph_apb_penable;
      apb_mux_pwrite  = periph_apb_pwrite;
      apb_mux_paddr   = periph_apb_paddr;
      apb_mux_pwdata  = periph_apb_pwdata;
    end else begin
      // Normal AXI-APB bridge path
      apb_mux_psel    = apb_psel_bridge;
      apb_mux_penable = apb_penable;
      apb_mux_pwrite  = apb_pwrite;
      apb_mux_paddr   = apb_paddr;
      apb_mux_pwdata  = apb_pwdata;
    end
  end

  assign apb_psel_uart  = apb_mux_psel &&
                            (apb_mux_paddr >= ADDR_UART_BASE) &&
                            (apb_mux_paddr <= ADDR_UART_END);

  assign apb_psel_gpio  = apb_mux_psel &&
                            (apb_mux_paddr >= ADDR_GPIO_BASE) &&
                            (apb_mux_paddr <= ADDR_GPIO_END);

  assign apb_psel_plic  = apb_mux_psel &&
                            (apb_mux_paddr >= ADDR_PLIC_BASE) &&
                            (apb_mux_paddr <= ADDR_PLIC_END);

  assign apb_psel_clint = apb_mux_psel &&
                            (apb_mux_paddr >= ADDR_CLINT_BASE) &&
                            (apb_mux_paddr <= ADDR_CLINT_END);

  // APB response MUX: route prdata/pready/pslverr from selected peripheral
  always_comb begin
    if (apb_psel_uart) begin
      apb_prdata_bridge  = apb_prdata_uart;
      apb_pready_bridge  = apb_pready_uart;
      apb_pslverr_bridge = apb_pslverr_uart;
    end else if (apb_psel_gpio) begin
      apb_prdata_bridge  = apb_prdata_gpio;
      apb_pready_bridge  = apb_pready_gpio;
      apb_pslverr_bridge = apb_pslverr_gpio;
    end else if (apb_psel_plic) begin
      apb_prdata_bridge  = apb_prdata_plic;
      apb_pready_bridge  = apb_pready_plic;
      apb_pslverr_bridge = apb_pslverr_plic;
    end else if (apb_psel_clint) begin
      apb_prdata_bridge  = apb_prdata_clint;
      apb_pready_bridge  = apb_pready_clint;
      apb_pslverr_bridge = apb_pslverr_clint;
    end else begin
      apb_prdata_bridge  = 32'h0;
      apb_pready_bridge  = 1'b1;
      apb_pslverr_bridge = 1'b1;  // Decode error for unmapped address
    end
  end

  // -------------------------------------------------------------------------
  // 1.22 AXI4-to-BRAM Bridge Logic (for bram_dmem via interconnect slave 0)
  // -------------------------------------------------------------------------
  // Simple AXI4 slave handshake to BRAM interface conversion
  // Supports single-beat read/write transactions

  // FSM for AXI-to-BRAM bridge
  typedef enum logic [2:0] {
    DMEM_IDLE,
    DMEM_WRITE_DATA,
    DMEM_WRITE_RESP,
    DMEM_READ_WAIT,
    DMEM_READ_DATA
  } dmem_bridge_state_t;

  dmem_bridge_state_t dmem_state, dmem_state_next;
  logic [ 3:0] dmem_axi_id_reg;
  logic [31:0] dmem_axi_addr_reg;

  always_ff @(posedge clk_sys or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      dmem_state        <= DMEM_IDLE;
      dmem_axi_id_reg   <= '0;
      dmem_axi_addr_reg <= '0;
    end else begin
      dmem_state <= dmem_state_next;
      // Capture AXI ID and address on handshake
      if (dmem_state == DMEM_IDLE) begin
        if (xbar_m_awvalid[0] && dmem_s_awready) begin
          dmem_axi_id_reg   <= xbar_m_awid[0];
          dmem_axi_addr_reg <= xbar_m_awaddr[0];
        end else if (xbar_m_arvalid[0] && dmem_s_arready) begin
          dmem_axi_id_reg   <= xbar_m_arid[0];
          dmem_axi_addr_reg <= xbar_m_araddr[0];
        end
      end
    end
  end

  always_comb begin
    dmem_state_next = dmem_state;
    // Default BRAM signals
    dmem_addr       = dmem_axi_addr_reg[DMEM_ADDR_W-1:2];  // Word address (byte >> 2)
    dmem_wdata      = '0;
    dmem_we         = 1'b0;
    dmem_be         = 4'b0;
    dmem_re         = 1'b0;
    // Default AXI slave responses (via intermediate signals)
    dmem_s_awready  = 1'b0;
    dmem_s_wready   = 1'b0;
    dmem_s_bid      = dmem_axi_id_reg;
    dmem_s_bresp    = 2'b00;  // OKAY
    dmem_s_bvalid   = 1'b0;
    dmem_s_arready  = 1'b0;
    dmem_s_rid      = dmem_axi_id_reg;
    dmem_s_rdata    = dmem_rdata;
    dmem_s_rresp    = 2'b00;  // OKAY
    dmem_s_rlast    = 1'b0;
    dmem_s_rvalid   = 1'b0;

    case (dmem_state)
      DMEM_IDLE: begin
        // Accept write address or read address
        if (xbar_m_awvalid[0]) begin
          dmem_s_awready  = 1'b1;
          dmem_state_next = DMEM_WRITE_DATA;
        end else if (xbar_m_arvalid[0]) begin
          dmem_s_arready  = 1'b1;
          dmem_state_next = DMEM_READ_WAIT;
        end
      end

      DMEM_WRITE_DATA: begin
        dmem_s_wready = 1'b1;
        if (xbar_m_wvalid[0]) begin
          dmem_addr  = dmem_axi_addr_reg[DMEM_ADDR_W-1:2];  // Word address
          dmem_wdata = xbar_m_wdata[0];
          dmem_we    = 1'b1;
          dmem_be    = xbar_m_wstrb[0];
          dmem_state_next = DMEM_WRITE_RESP;
        end
      end

      DMEM_WRITE_RESP: begin
        dmem_s_bvalid = 1'b1;
        if (xbar_m_bready[0]) begin
          dmem_state_next = DMEM_IDLE;
        end
      end

      DMEM_READ_WAIT: begin
        // Issue read to BRAM (1 cycle latency)
        dmem_addr = dmem_axi_addr_reg[DMEM_ADDR_W-1:2];  // Word address
        dmem_re = 1'b1;
        dmem_state_next = DMEM_READ_DATA;
      end

      DMEM_READ_DATA: begin
        dmem_s_rvalid = 1'b1;
        dmem_s_rlast  = 1'b1;
        dmem_s_rdata  = dmem_rdata;
        if (xbar_m_rready[0]) begin
          dmem_state_next = DMEM_IDLE;
        end
      end

      default: dmem_state_next = DMEM_IDLE;
    endcase
  end

  // -------------------------------------------------------------------------
  // 1.23 AXI4-to-BRAM Bridge Logic (for bram_imem via interconnect slave [5])
  // -------------------------------------------------------------------------
  // Same FSM pattern as DMEM bridge (section 1.22)
  // Supports single-beat read/write transactions to IMEM Port B

  typedef enum logic [2:0] {
    IMEM_IDLE,
    IMEM_WRITE_DATA,
    IMEM_WRITE_RESP,
    IMEM_READ_WAIT,
    IMEM_READ_DATA
  } imem_bridge_state_t;

  imem_bridge_state_t imem_state, imem_state_next;
  logic [ 3:0] imem_axi_id_reg;
  logic [31:0] imem_axi_addr_reg;

  always_ff @(posedge clk_sys or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      imem_state        <= IMEM_IDLE;
      imem_axi_id_reg   <= '0;
      imem_axi_addr_reg <= '0;
    end else begin
      imem_state <= imem_state_next;
      // Capture AXI ID and address on handshake
      if (imem_state == IMEM_IDLE) begin
        if (xbar_m_awvalid[5] && imem_s_awready) begin
          imem_axi_id_reg   <= xbar_m_awid[5];
          imem_axi_addr_reg <= xbar_m_awaddr[5];
        end else if (xbar_m_arvalid[5] && imem_s_arready) begin
          imem_axi_id_reg   <= xbar_m_arid[5];
          imem_axi_addr_reg <= xbar_m_araddr[5];
        end
      end
    end
  end

  always_comb begin
    imem_state_next = imem_state;
    // Default BRAM Port B signals
    imem_b_addr     = imem_axi_addr_reg[IMEM_ADDR_W-1:0];
    imem_b_wdata    = '0;
    imem_b_we       = 1'b0;
    imem_b_be       = 4'b0;
    imem_b_en       = 1'b0;
    // Default AXI slave responses (via intermediate signals)
    imem_s_awready  = 1'b0;
    imem_s_wready   = 1'b0;
    imem_s_bid      = imem_axi_id_reg;
    imem_s_bresp    = 2'b00;  // OKAY
    imem_s_bvalid   = 1'b0;
    imem_s_arready  = 1'b0;
    imem_s_rid      = imem_axi_id_reg;
    imem_s_rdata    = imem_b_rdata;
    imem_s_rresp    = 2'b00;  // OKAY
    imem_s_rlast    = 1'b0;
    imem_s_rvalid   = 1'b0;

    case (imem_state)
      IMEM_IDLE: begin
        // Accept write address or read address
        if (xbar_m_awvalid[5]) begin
          imem_s_awready  = 1'b1;
          imem_state_next = IMEM_WRITE_DATA;
        end else if (xbar_m_arvalid[5]) begin
          imem_s_arready  = 1'b1;
          imem_state_next = IMEM_READ_WAIT;
        end
      end

      IMEM_WRITE_DATA: begin
        imem_s_wready = 1'b1;
        if (xbar_m_wvalid[5]) begin
          imem_b_addr     = imem_axi_addr_reg[IMEM_ADDR_W-1:0];
          imem_b_wdata    = xbar_m_wdata[5];
          imem_b_we       = 1'b1;
          imem_b_be       = xbar_m_wstrb[5];
          imem_b_en       = 1'b1;
          imem_state_next = IMEM_WRITE_RESP;
        end
      end

      IMEM_WRITE_RESP: begin
        imem_s_bvalid = 1'b1;
        if (xbar_m_bready[5]) begin
          imem_state_next = IMEM_IDLE;
        end
      end

      IMEM_READ_WAIT: begin
        // Issue read to BRAM Port B (1 cycle latency)
        imem_b_addr     = imem_axi_addr_reg[IMEM_ADDR_W-1:0];
        imem_b_en       = 1'b1;
        imem_state_next = IMEM_READ_DATA;
      end

      IMEM_READ_DATA: begin
        imem_s_rvalid = 1'b1;
        imem_s_rlast  = 1'b1;
        imem_s_rdata  = imem_b_rdata;
        if (xbar_m_rready[5]) begin
          imem_state_next = IMEM_IDLE;
        end
      end

      default: imem_state_next = IMEM_IDLE;
    endcase
  end

  // -------------------------------------------------------------------------
  // 1.24 RTOS Default Control Signals
  // -------------------------------------------------------------------------
  assign scheduler_en    = 1'b1;  // Scheduler always enabled
  assign schedule_policy = 2'b10;  // Priority + Round-Robin

  // -------------------------------------------------------------------------
  // 1.25 Debug Interface Default Tie-offs (JTAG stub)
  // -------------------------------------------------------------------------
  assign debug_halt_req  = 1'b0;
  assign debug_reg_addr  = '0;
  assign jtag_tdo        = 1'b0;  // JTAG not implemented yet

  // -------------------------------------------------------------------------
  // 1.26 POSIX Peripheral Access - APB Bridge
  // REVIEW-005 fix: Connect posix_hw_layer periph signals to APB bus
  // This enables POSIX File I/O to access UART/GPIO/etc. via peripherals
  // -------------------------------------------------------------------------
  // Peripheral access APB master interface signals
  logic        periph_apb_psel;
  logic        periph_apb_penable;
  logic        periph_apb_pwrite;
  logic [31:0] periph_apb_paddr;
  logic [31:0] periph_apb_pwdata;
  logic [31:0] periph_apb_prdata;
  logic        periph_apb_pready;

  // Peripheral access FSM: converts periph_read/periph_write to APB transactions
  typedef enum logic [2:0] {
    PERIPH_IDLE,
    PERIPH_SETUP,
    PERIPH_ACCESS,
    PERIPH_DONE
  } periph_bridge_state_t;

  periph_bridge_state_t periph_state, periph_state_next;
  logic [31:0] periph_addr_r;
  logic [31:0] periph_wdata_r;
  logic        periph_is_write_r;

  always_ff @(posedge clk_sys or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      periph_state      <= PERIPH_IDLE;
      periph_addr_r     <= '0;
      periph_wdata_r    <= '0;
      periph_is_write_r <= 1'b0;
    end else begin
      periph_state <= periph_state_next;
      if (periph_state == PERIPH_IDLE && (periph_read || periph_write)) begin
        periph_addr_r     <= periph_addr;
        periph_wdata_r    <= periph_wdata;
        periph_is_write_r <= periph_write;
      end
    end
  end

  always_comb begin
    periph_state_next  = periph_state;
    periph_apb_psel    = 1'b0;
    periph_apb_penable = 1'b0;
    periph_apb_pwrite  = 1'b0;
    periph_apb_paddr   = periph_addr_r;
    periph_apb_pwdata  = periph_wdata_r;

    case (periph_state)
      PERIPH_IDLE: begin
        if (periph_read || periph_write) begin
          periph_state_next = PERIPH_SETUP;
        end
      end
      PERIPH_SETUP: begin
        // APB setup phase: assert psel, pwrite
        periph_apb_psel   = 1'b1;
        periph_apb_pwrite = periph_is_write_r;
        periph_apb_paddr  = periph_addr_r;
        periph_apb_pwdata = periph_wdata_r;
        periph_state_next = PERIPH_ACCESS;
      end
      PERIPH_ACCESS: begin
        // APB access phase: assert psel + penable, wait for pready
        periph_apb_psel    = 1'b1;
        periph_apb_penable = 1'b1;
        periph_apb_pwrite  = periph_is_write_r;
        periph_apb_paddr   = periph_addr_r;
        periph_apb_pwdata  = periph_wdata_r;
        if (periph_apb_pready) begin
          periph_state_next = PERIPH_DONE;
        end
      end
      PERIPH_DONE: begin
        periph_state_next = PERIPH_IDLE;
      end
      default: periph_state_next = PERIPH_IDLE;
    endcase
  end

  // Map APB responses back to posix_hw_layer periph interface
  assign periph_rdata = periph_apb_prdata;
  assign periph_ready = (periph_state == PERIPH_DONE);

  // Route peripheral APB to the existing APB bus via address decode
  // The periph_apb signals share the APB bus with the main AXI-APB bridge
  // Per-peripheral select signals for periph access path
  logic apb_periph_sel_uart;
  logic apb_periph_sel_gpio;
  logic apb_periph_sel_clint;

  assign apb_periph_sel_uart  = periph_apb_psel &&
                                  (periph_apb_paddr >= ADDR_UART_BASE) &&
                                  (periph_apb_paddr <= ADDR_UART_END);
  assign apb_periph_sel_gpio  = periph_apb_psel &&
                                  (periph_apb_paddr >= ADDR_GPIO_BASE) &&
                                  (periph_apb_paddr <= ADDR_GPIO_END);
  assign apb_periph_sel_clint = periph_apb_psel &&
                                  (periph_apb_paddr >= ADDR_CLINT_BASE) &&
                                  (periph_apb_paddr <= ADDR_CLINT_END);

  // APB response mux for peripheral access path
  always_comb begin
    if (apb_periph_sel_uart) begin
      periph_apb_prdata = apb_prdata_uart;
      periph_apb_pready = apb_pready_uart;
    end else if (apb_periph_sel_gpio) begin
      periph_apb_prdata = apb_prdata_gpio;
      periph_apb_pready = apb_pready_gpio;
    end else if (apb_periph_sel_clint) begin
      periph_apb_prdata = apb_prdata_clint;
      periph_apb_pready = apb_pready_clint;
    end else begin
      periph_apb_prdata = 32'h0;
      periph_apb_pready = 1'b1;  // Default ready for unmapped
    end
  end

  // =========================================================================
  // Stage 2: Completed Module Instantiations
  // =========================================================================

  // -------------------------------------------------------------------------
  // 2.1 Instruction Memory (bram_imem)
  // -------------------------------------------------------------------------
  bram_imem #(
      .DEPTH     (IMEM_SIZE / 4),    // 16384 words
      .ADDR_WIDTH(IMEM_ADDR_W - 2),  // 14 (word address width)
      .DATA_WIDTH(XLEN),             // 32
      .INIT_FILE (IMEM_INIT_FILE)
  ) u_imem (
      .clk    (clk_sys),
      // Port A - Instruction Fetch (read-only, byte→word addr conversion)
      .a_en   (cpu_imem_en),
      .a_addr (cpu_imem_addr[IMEM_ADDR_W-1:2]),
      .a_rdata(cpu_imem_rdata),
      // Port B - Data Bus Access (read/write via AXI bridge, byte→word addr)
      .b_en   (imem_b_en),
      .b_we   (imem_b_we),
      .b_be   (imem_b_be),
      .b_addr (imem_b_addr[IMEM_ADDR_W-1:2]),
      .b_wdata(imem_b_wdata),
      .b_rdata(imem_b_rdata)
  );

  // -------------------------------------------------------------------------
  // 2.2 Data Memory (bram_dmem)
  // -------------------------------------------------------------------------
  bram_dmem #(
      .DEPTH     (DMEM_SIZE / 4),      // 4096 words
      .ADDR_WIDTH(DMEM_ADDR_W - 2),    // 12-bit word address (byte addr >> 2)
      .DATA_WIDTH(XLEN),               // 32
      .INIT_FILE (DMEM_INIT_FILE)
  ) u_dmem (
      .clk  (clk_sys),
      .addr (dmem_addr),
      .wdata(dmem_wdata),
      .we   (dmem_we),
      .be   (dmem_be),
      .re   (dmem_re),
      .rdata(dmem_rdata)
  );

  // -------------------------------------------------------------------------
  // 2.3 AXI4 Master (axi4_master)
  // -------------------------------------------------------------------------
  axi4_master #(
      .ADDR_W(AXI_ADDR_W),
      .DATA_W(AXI_DATA_W),
      .ID_W  (AXI_ID_W)
  ) u_axi_master (
      .clk          (clk_sys),
      .rst_n        (sys_rst_n),
      // CPU command interface
      .cmd_read     (axi_cmd_read),
      .cmd_write    (axi_cmd_write),
      .cmd_addr     (axi_cmd_addr),
      .cmd_wdata    (axi_cmd_wdata),
      .cmd_wstrb    (axi_cmd_wstrb),
      .cmd_rdata    (axi_cmd_rdata),
      .cmd_done     (axi_cmd_done),
      .cmd_error    (axi_cmd_error),
      // AXI4 Write Address Channel
      .m_axi_awid   (axi_m_awid),
      .m_axi_awaddr (axi_m_awaddr),
      .m_axi_awlen  (axi_m_awlen),
      .m_axi_awsize (axi_m_awsize),
      .m_axi_awburst(axi_m_awburst),
      .m_axi_awvalid(axi_m_awvalid),
      .m_axi_awready(axi_m_awready),
      // AXI4 Write Data Channel
      .m_axi_wdata  (axi_m_wdata),
      .m_axi_wstrb  (axi_m_wstrb),
      .m_axi_wlast  (axi_m_wlast),
      .m_axi_wvalid (axi_m_wvalid),
      .m_axi_wready (axi_m_wready),
      // AXI4 Write Response Channel
      .m_axi_bid    (axi_m_bid),
      .m_axi_bresp  (axi_m_bresp),
      .m_axi_bvalid (axi_m_bvalid),
      .m_axi_bready (axi_m_bready),
      // AXI4 Read Address Channel
      .m_axi_arid   (axi_m_arid),
      .m_axi_araddr (axi_m_araddr),
      .m_axi_arlen  (axi_m_arlen),
      .m_axi_arsize (axi_m_arsize),
      .m_axi_arburst(axi_m_arburst),
      .m_axi_arvalid(axi_m_arvalid),
      .m_axi_arready(axi_m_arready),
      // AXI4 Read Data Channel
      .m_axi_rid    (axi_m_rid),
      .m_axi_rdata  (axi_m_rdata),
      .m_axi_rresp  (axi_m_rresp),
      .m_axi_rlast  (axi_m_rlast),
      .m_axi_rvalid (axi_m_rvalid),
      .m_axi_rready (axi_m_rready)
  );

  // -------------------------------------------------------------------------
  // 2.4 AXI4 Interconnect (axi4_interconnect)
  // -------------------------------------------------------------------------
  axi4_interconnect #(
      .NUM_SLAVES(NUM_AXI_SLAVES),
      .ADDR_W    (AXI_ADDR_W),
      .DATA_W    (AXI_DATA_W),
      .ID_W      (AXI_ID_W)
  ) u_axi_xbar (
      .clk          (clk_sys),
      .rst_n        (sys_rst_n),
      // Slave port (from axi4_master)
      .s_axi_awid   (axi_m_awid),
      .s_axi_awaddr (axi_m_awaddr),
      .s_axi_awlen  (axi_m_awlen),
      .s_axi_awsize (axi_m_awsize),
      .s_axi_awburst(axi_m_awburst),
      .s_axi_awvalid(axi_m_awvalid),
      .s_axi_awready(axi_m_awready),
      .s_axi_wdata  (axi_m_wdata),
      .s_axi_wstrb  (axi_m_wstrb),
      .s_axi_wlast  (axi_m_wlast),
      .s_axi_wvalid (axi_m_wvalid),
      .s_axi_wready (axi_m_wready),
      .s_axi_bid    (axi_m_bid),
      .s_axi_bresp  (axi_m_bresp),
      .s_axi_bvalid (axi_m_bvalid),
      .s_axi_bready (axi_m_bready),
      .s_axi_arid   (axi_m_arid),
      .s_axi_araddr (axi_m_araddr),
      .s_axi_arlen  (axi_m_arlen),
      .s_axi_arsize (axi_m_arsize),
      .s_axi_arburst(axi_m_arburst),
      .s_axi_arvalid(axi_m_arvalid),
      .s_axi_arready(axi_m_arready),
      .s_axi_rid    (axi_m_rid),
      .s_axi_rdata  (axi_m_rdata),
      .s_axi_rresp  (axi_m_rresp),
      .s_axi_rlast  (axi_m_rlast),
      .s_axi_rvalid (axi_m_rvalid),
      .s_axi_rready (axi_m_rready),
      // Master ports (array-based, to slaves)
`ifdef IVERILOG
      // iverilog workaround: unpacked array output ports produce X values
      // at module boundaries. Route to dummy signals; real xbar_m_* driven
      // below via hierarchical access to internal packed vectors.
      .m_axi_awid   (xbar_m_dummy_awid),
      .m_axi_awaddr (xbar_m_dummy_awaddr),
      .m_axi_awlen  (xbar_m_dummy_awlen),
      .m_axi_awsize (xbar_m_dummy_awsize),
      .m_axi_awburst(xbar_m_dummy_awburst),
      .m_axi_awvalid(xbar_m_dummy_awvalid),
      .m_axi_awready(xbar_m_awready),
      .m_axi_wdata  (xbar_m_dummy_wdata),
      .m_axi_wstrb  (xbar_m_dummy_wstrb),
      .m_axi_wlast  (xbar_m_dummy_wlast),
      .m_axi_wvalid (xbar_m_dummy_wvalid),
      .m_axi_wready (xbar_m_wready),
      .m_axi_bid    (xbar_m_bid),
      .m_axi_bresp  (xbar_m_bresp),
      .m_axi_bvalid (xbar_m_bvalid),
      .m_axi_bready (xbar_m_dummy_bready),
      .m_axi_arid   (xbar_m_dummy_arid),
      .m_axi_araddr (xbar_m_dummy_araddr),
      .m_axi_arlen  (xbar_m_dummy_arlen),
      .m_axi_arsize (xbar_m_dummy_arsize),
      .m_axi_arburst(xbar_m_dummy_arburst),
      .m_axi_arvalid(xbar_m_dummy_arvalid),
      .m_axi_arready(xbar_m_arready),
      .m_axi_rid    (xbar_m_rid),
      .m_axi_rdata  (xbar_m_rdata),
      .m_axi_rresp  (xbar_m_rresp),
      .m_axi_rlast  (xbar_m_rlast),
      .m_axi_rvalid (xbar_m_rvalid),
      .m_axi_rready (xbar_m_dummy_rready)
`else
      .m_axi_awid   (xbar_m_awid),
      .m_axi_awaddr (xbar_m_awaddr),
      .m_axi_awlen  (xbar_m_awlen),
      .m_axi_awsize (xbar_m_awsize),
      .m_axi_awburst(xbar_m_awburst),
      .m_axi_awvalid(xbar_m_awvalid),
      .m_axi_awready(xbar_m_awready),
      .m_axi_wdata  (xbar_m_wdata),
      .m_axi_wstrb  (xbar_m_wstrb),
      .m_axi_wlast  (xbar_m_wlast),
      .m_axi_wvalid (xbar_m_wvalid),
      .m_axi_wready (xbar_m_wready),
      .m_axi_bid    (xbar_m_bid),
      .m_axi_bresp  (xbar_m_bresp),
      .m_axi_bvalid (xbar_m_bvalid),
      .m_axi_bready (xbar_m_bready),
      .m_axi_arid   (xbar_m_arid),
      .m_axi_araddr (xbar_m_araddr),
      .m_axi_arlen  (xbar_m_arlen),
      .m_axi_arsize (xbar_m_arsize),
      .m_axi_arburst(xbar_m_arburst),
      .m_axi_arvalid(xbar_m_arvalid),
      .m_axi_arready(xbar_m_arready),
      .m_axi_rid    (xbar_m_rid),
      .m_axi_rdata  (xbar_m_rdata),
      .m_axi_rresp  (xbar_m_rresp),
      .m_axi_rlast  (xbar_m_rlast),
      .m_axi_rvalid (xbar_m_rvalid),
      .m_axi_rready (xbar_m_rready)
`endif
  );

  // -------------------------------------------------------------------------
  // 2.5 AXI4-to-APB Bridge (axi4_apb_bridge) - Slave Index [2]
  // -------------------------------------------------------------------------
  axi4_apb_bridge #(
      .AXI_ADDR_W(AXI_ADDR_W),
      .AXI_DATA_W(AXI_DATA_W),
      .APB_ADDR_W(32),
      .APB_DATA_W(32),
      .AXI_ID_W  (AXI_ID_W)
  ) u_apb_bridge (
      .clk          (clk_sys),
      .rst_n        (sys_rst_n),
      // AXI4 Slave (from interconnect slave port [2])
      .s_axi_awid   (xbar_m_awid[2]),
      .s_axi_awaddr (xbar_m_awaddr[2]),
      .s_axi_awlen  (xbar_m_awlen[2]),
      .s_axi_awsize (xbar_m_awsize[2]),
      .s_axi_awburst(xbar_m_awburst[2]),
      .s_axi_awvalid(xbar_m_awvalid[2]),
      .s_axi_awready(xbar_m_awready[2]),
      .s_axi_wdata  (xbar_m_wdata[2]),
      .s_axi_wstrb  (xbar_m_wstrb[2]),
      .s_axi_wlast  (xbar_m_wlast[2]),
      .s_axi_wvalid (xbar_m_wvalid[2]),
      .s_axi_wready (xbar_m_wready[2]),
      .s_axi_bid    (xbar_m_bid[2]),
      .s_axi_bresp  (xbar_m_bresp[2]),
      .s_axi_bvalid (xbar_m_bvalid[2]),
      .s_axi_bready (xbar_m_bready[2]),
      .s_axi_arid   (xbar_m_arid[2]),
      .s_axi_araddr (xbar_m_araddr[2]),
      .s_axi_arlen  (xbar_m_arlen[2]),
      .s_axi_arsize (xbar_m_arsize[2]),
      .s_axi_arburst(xbar_m_arburst[2]),
      .s_axi_arvalid(xbar_m_arvalid[2]),
      .s_axi_arready(xbar_m_arready[2]),
      .s_axi_rid    (xbar_m_rid[2]),
      .s_axi_rdata  (xbar_m_rdata[2]),
      .s_axi_rresp  (xbar_m_rresp[2]),
      .s_axi_rlast  (xbar_m_rlast[2]),
      .s_axi_rvalid (xbar_m_rvalid[2]),
      .s_axi_rready (xbar_m_rready[2]),
      // APB Master
      .apb_psel     (apb_psel_bridge),
      .apb_penable  (apb_penable),
      .apb_pwrite   (apb_pwrite),
      .apb_paddr    (apb_paddr),
      .apb_pwdata   (apb_pwdata),
      .apb_prdata   (apb_prdata_bridge),
      .apb_pready   (apb_pready_bridge),
      .apb_pslverr  (apb_pslverr_bridge)
  );

  // -------------------------------------------------------------------------
  // 2.6 HyperRAM Controller (hyperram_ctrl) - Slave Index [1]
  // -------------------------------------------------------------------------
  hyperram_ctrl #(
      .LATENCY(6),
      .ADDR_W (AXI_ADDR_W),
      .DATA_W (AXI_DATA_W),
      .ID_W   (AXI_ID_W)
  ) u_hyperram (
      .clk          (clk_sys),
      .rst_n        (sys_rst_n),
      // AXI4 Slave (from interconnect slave port [1])
      .s_axi_awid   (xbar_m_awid[1]),
      .s_axi_awaddr (xbar_m_awaddr[1]),
      .s_axi_awlen  (xbar_m_awlen[1]),
      .s_axi_awsize (xbar_m_awsize[1]),
      .s_axi_awburst(xbar_m_awburst[1]),
      .s_axi_awvalid(xbar_m_awvalid[1]),
      .s_axi_awready(xbar_m_awready[1]),
      .s_axi_wdata  (xbar_m_wdata[1]),
      .s_axi_wstrb  (xbar_m_wstrb[1]),
      .s_axi_wlast  (xbar_m_wlast[1]),
      .s_axi_wvalid (xbar_m_wvalid[1]),
      .s_axi_wready (xbar_m_wready[1]),
      .s_axi_bid    (xbar_m_bid[1]),
      .s_axi_bresp  (xbar_m_bresp[1]),
      .s_axi_bvalid (xbar_m_bvalid[1]),
      .s_axi_bready (xbar_m_bready[1]),
      .s_axi_arid   (xbar_m_arid[1]),
      .s_axi_araddr (xbar_m_araddr[1]),
      .s_axi_arlen  (xbar_m_arlen[1]),
      .s_axi_arsize (xbar_m_arsize[1]),
      .s_axi_arburst(xbar_m_arburst[1]),
      .s_axi_arvalid(xbar_m_arvalid[1]),
      .s_axi_arready(xbar_m_arready[1]),
      .s_axi_rid    (xbar_m_rid[1]),
      .s_axi_rdata  (xbar_m_rdata[1]),
      .s_axi_rresp  (xbar_m_rresp[1]),
      .s_axi_rlast  (xbar_m_rlast[1]),
      .s_axi_rvalid (xbar_m_rvalid[1]),
      .s_axi_rready (xbar_m_rready[1]),
      // HyperBus physical pins (tri-state handled in top)
      .hb_ck        (hb_ck),
      .hb_ck_n      (hb_ck_n),
      .hb_cs_n      (hb_cs_n),
      .hb_rwds_oe   (hb_rwds_oe),
      .hb_rwds_o    (hb_rwds_o),
      .hb_rwds_i    (hb_rwds_i),
      .hb_dq_oe     (hb_dq_oe),
      .hb_dq_o      (hb_dq_o),
      .hb_dq_i      (hb_dq_i)
  );

  // -------------------------------------------------------------------------
  // 2.7 UART Controller (uart_apb)
  // -------------------------------------------------------------------------
  uart_apb #(
      .CLK_FREQ    (25_000_000),
      .DEFAULT_BAUD(115200),
      .FIFO_DEPTH  (16)
  ) u_uart (
      .clk        (clk_sys),
      .rst_n      (sys_rst_n),
      .apb_psel   (apb_psel_uart),
      .apb_penable(apb_mux_penable),
      .apb_pwrite (apb_mux_pwrite),
      .apb_paddr  (apb_mux_paddr[7:0]),
      .apb_pwdata (apb_mux_pwdata),
      .apb_prdata (apb_prdata_uart),
      .apb_pready (apb_pready_uart),
      .apb_pslverr(apb_pslverr_uart),
      .uart_rx    (uart_rx),
      .uart_tx    (uart_tx),
      .irq        (uart_irq)
  );

  // -------------------------------------------------------------------------
  // 2.8 GPIO Controller (gpio_apb)
  // -------------------------------------------------------------------------
  gpio_apb #(
      .GPIO_WIDTH(GPIO_WIDTH)
  ) u_gpio (
      .clk        (clk_sys),
      .rst_n      (sys_rst_n),
      .apb_psel   (apb_psel_gpio),
      .apb_penable(apb_mux_penable),
      .apb_pwrite (apb_mux_pwrite),
      .apb_paddr  (apb_mux_paddr[7:0]),
      .apb_pwdata (apb_mux_pwdata),
      .apb_prdata (apb_prdata_gpio),
      .apb_pready (apb_pready_gpio),
      .apb_pslverr(apb_pslverr_gpio),
      .gpio_in    (gpio_in),
      .gpio_out   (gpio_out),
      .gpio_oe    (gpio_oe),
      .irq        (gpio_irq)
  );

  // -------------------------------------------------------------------------
  // 2.9 PLIC - Platform-Level Interrupt Controller
  // -------------------------------------------------------------------------
  plic #(
      .NUM_SOURCES  (16),
      .NUM_TARGETS  (1),
      .PRIORITY_BITS(3)
  ) u_plic (
      .clk        (clk_sys),
      .rst_n      (sys_rst_n),
      .apb_psel   (apb_psel_plic),
      .apb_penable(apb_mux_penable),
      .apb_pwrite (apb_mux_pwrite),
      .apb_paddr  (apb_mux_paddr[15:0]),
      .apb_pwdata (apb_mux_pwdata),
      .apb_prdata (apb_prdata_plic),
      .apb_pready (apb_pready_plic),
      .apb_pslverr(apb_pslverr_plic),
      .irq_sources(plic_irq_sources),
      .ext_irq    (plic_ext_irq)
  );

  // -------------------------------------------------------------------------
  // 2.10 CLINT - Core Local Interruptor
  // -------------------------------------------------------------------------
  clint #(
      .TIMER_WIDTH(64)
  ) u_clint (
      .clk        (clk_sys),
      .rst_n      (sys_rst_n),
      .apb_psel   (apb_psel_clint),
      .apb_penable(apb_mux_penable),
      .apb_pwrite (apb_mux_pwrite),
      .apb_paddr  (apb_mux_paddr[15:0]),
      .apb_pwdata (apb_mux_pwdata),
      .apb_prdata (apb_prdata_clint),
      .apb_pready (apb_pready_clint),
      .apb_pslverr(apb_pslverr_clint),
      .timer_irq  (clint_timer_irq),
      .sw_irq     (clint_sw_irq)
  );

  // =========================================================================
  // Stage 3: Top-Level Module Instantiations (rv32im_core, hw_rtos,
  //          posix_hw_layer)
  // =========================================================================

  // -------------------------------------------------------------------------
  // 3.1 RISC-V CPU Core (rv32im_core)
  // -------------------------------------------------------------------------
  rv32im_core u_cpu (
      .clk  (clk_sys),
      .rst_n(sys_rst_n),

      // Instruction Memory Interface (direct to bram_imem)
      .imem_addr (cpu_imem_addr),
      .imem_rdata(cpu_imem_rdata),
      .imem_en   (cpu_imem_en),

      // Data Memory Interface (to axi4_master via adaptor logic)
      .mem_addr (cpu_mem_addr),
      .mem_wdata(cpu_mem_wdata),
      .mem_read (cpu_mem_read),
      .mem_write(cpu_mem_write),
      .mem_size (cpu_mem_size),
      .mem_rdata(cpu_mem_rdata),
      .mem_ready(cpu_mem_ready),
      .mem_error(cpu_mem_error),

      // Interrupt Inputs
      .external_irq(plic_ext_irq),
      .timer_irq   (clint_timer_irq),
      .software_irq(clint_sw_irq),

      // RTOS Control Interface (to/from hw_rtos)
      .ctx_switch_req      (ctx_switch_req),
      .ctx_switch_ack      (ctx_switch_ack),
      .ctx_save_en         (ctx_save_en),
      .ctx_save_reg_idx    (ctx_save_reg_idx),
      .ctx_save_reg_data   (ctx_save_reg_data),
      .ctx_save_pc         (ctx_save_pc),
      .ctx_restore_en      (ctx_restore_en),
      .ctx_restore_reg_idx (ctx_restore_reg_idx),
      .ctx_restore_reg_data(ctx_restore_reg_data),
      .ctx_restore_pc      (ctx_restore_pc),
      .current_task_id     (current_task_id),
      .task_active         (task_active),

      // POSIX Syscall Interface (to/from posix_hw_layer)
      .ecall_req   (ecall_req),
      .syscall_num (syscall_num),
      .syscall_arg0(syscall_arg0),
      .syscall_arg1(syscall_arg1),
      .syscall_arg2(syscall_arg2),
      .syscall_ret (syscall_ret),
      .syscall_done(syscall_done),

      // Debug Interface
      .debug_halt_req(debug_halt_req),
      .debug_halted  (debug_halted),
      .debug_pc      (debug_pc),
      .debug_instr   (debug_instr),
      .debug_reg_addr(debug_reg_addr),
      .debug_reg_data(debug_reg_data)
  );

  // -------------------------------------------------------------------------
  // 3.2 Hardware RTOS Engine (hw_rtos) - Slave Index [3]
  // -------------------------------------------------------------------------
  hw_rtos u_rtos (
      .clk  (clk_sys),
      .rst_n(sys_rst_n),

      // Task Scheduler Control
      .scheduler_en   (scheduler_en),
      .schedule_policy(schedule_policy),
      .current_task_id(current_task_id),
      .next_task_id   (next_task_id),
      .task_active    (task_active),

      // Context Switch Control (to/from rv32im_core)
      .ctx_switch_req      (ctx_switch_req),
      .ctx_switch_ack      (ctx_switch_ack),
      .ctx_save_en         (ctx_save_en),
      .ctx_save_reg_idx    (ctx_save_reg_idx),
      .ctx_save_reg_data   (ctx_save_reg_data),
      .ctx_save_pc         (ctx_save_pc),
      .ctx_restore_en      (ctx_restore_en),
      .ctx_restore_reg_idx (ctx_restore_reg_idx),
      .ctx_restore_reg_data(ctx_restore_reg_data),
      .ctx_restore_pc      (ctx_restore_pc),

      // Timer Input (generated from CLINT timer_irq)
      .timer_tick(timer_tick),

      // POSIX Layer Control Input (from posix_hw_layer)
      .rtos_task_create     (rtos_task_create),
      .rtos_task_create_pc  (rtos_task_create_pc),
      .rtos_task_create_sp  (rtos_task_create_sp),
      .rtos_task_create_prio(rtos_task_create_prio),
      .rtos_task_create_done(rtos_task_create_done),
      .rtos_task_create_id  (rtos_task_create_id),
      .rtos_task_exit       (rtos_task_exit),
      .rtos_task_join       (rtos_task_join),
      .rtos_task_target_id  (rtos_task_target_id),
      .rtos_task_join_done  (rtos_task_join_done),
      .rtos_task_yield      (rtos_task_yield),
      .rtos_sem_op          (rtos_sem_op),
      .rtos_sem_id          (rtos_sem_id),
      .rtos_sem_value       (rtos_sem_value),
      .rtos_sem_done        (rtos_sem_done),
      .rtos_sem_result      (rtos_sem_result),
      .rtos_mutex_op        (rtos_mutex_op),
      .rtos_mutex_id        (rtos_mutex_id),
      .rtos_mutex_done      (rtos_mutex_done),
      .rtos_mutex_result    (rtos_mutex_result),
      .rtos_msgq_op         (rtos_msgq_op),
      .rtos_msgq_id         (rtos_msgq_id),
      .rtos_msgq_data       (rtos_msgq_data),
      .rtos_msgq_done       (rtos_msgq_done),
      .rtos_msgq_result     (rtos_msgq_result),
      .rtos_msgq_success    (rtos_msgq_success),

      // AXI4 Slave Interface (from interconnect slave port [3])
      .s_axi_awaddr (xbar_m_awaddr[3]),
      .s_axi_awprot (3'b000),
      .s_axi_awvalid(xbar_m_awvalid[3]),
      .s_axi_awready(xbar_m_awready[3]),
      .s_axi_wdata  (xbar_m_wdata[3]),
      .s_axi_wstrb  (xbar_m_wstrb[3]),
      .s_axi_wvalid (xbar_m_wvalid[3]),
      .s_axi_wready (xbar_m_wready[3]),
      .s_axi_bresp  (xbar_m_bresp[3]),
      .s_axi_bvalid (xbar_m_bvalid[3]),
      .s_axi_bready (xbar_m_bready[3]),
      .s_axi_araddr (xbar_m_araddr[3]),
      .s_axi_arprot (3'b000),
      .s_axi_arvalid(xbar_m_arvalid[3]),
      .s_axi_arready(xbar_m_arready[3]),
      .s_axi_rdata  (xbar_m_rdata[3]),
      .s_axi_rresp  (xbar_m_rresp[3]),
      .s_axi_rvalid (xbar_m_rvalid[3]),
      .s_axi_rready (xbar_m_rready[3])
  );

  // hw_rtos uses AXI4-Lite (no burst). Tie off burst-related signals for port [3]
  assign xbar_m_bid[3]   = xbar_m_awid[3];  // Echo back ID
  assign xbar_m_rid[3]   = xbar_m_arid[3];  // Echo back ID
  assign xbar_m_rlast[3] = xbar_m_rvalid[3];  // Single-beat always last

  // -------------------------------------------------------------------------
  // 3.3 POSIX Hardware Layer (posix_hw_layer) - Slave Index [4]
  // -------------------------------------------------------------------------
  posix_hw_layer u_posix (
      .clk  (clk_sys),
      .rst_n(sys_rst_n),

      // Syscall Dispatcher Interface (from rv32im_core)
      .ecall_req   (ecall_req),
      .syscall_num (syscall_num),
      .syscall_arg0(syscall_arg0),
      .syscall_arg1(syscall_arg1),
      .syscall_arg2(syscall_arg2),
      .syscall_ret (syscall_ret),
      .syscall_done(syscall_done),

      // RTOS Control Output (to hw_rtos)
      .rtos_task_create     (rtos_task_create),
      .rtos_task_create_pc  (rtos_task_create_pc),
      .rtos_task_create_sp  (rtos_task_create_sp),
      .rtos_task_create_prio(rtos_task_create_prio),
      .rtos_task_create_done(rtos_task_create_done),
      .rtos_task_create_id  (rtos_task_create_id),
      .rtos_task_exit       (rtos_task_exit),
      .rtos_task_join       (rtos_task_join),
      .rtos_task_target_id  (rtos_task_target_id),
      .rtos_task_join_done  (rtos_task_join_done),
      .rtos_task_yield      (rtos_task_yield),
      .rtos_sem_op          (rtos_sem_op),
      .rtos_sem_id          (rtos_sem_id),
      .rtos_sem_value       (rtos_sem_value),
      .rtos_sem_done        (rtos_sem_done),
      .rtos_sem_result      (rtos_sem_result),
      .rtos_mutex_op        (rtos_mutex_op),
      .rtos_mutex_id        (rtos_mutex_id),
      .rtos_mutex_done      (rtos_mutex_done),
      .rtos_mutex_result    (rtos_mutex_result),
      .rtos_msgq_op         (rtos_msgq_op),
      .rtos_msgq_id         (rtos_msgq_id),
      .rtos_msgq_data       (rtos_msgq_data),
      .rtos_msgq_done       (rtos_msgq_done),
      .rtos_msgq_result     (rtos_msgq_result),
      .rtos_msgq_success    (rtos_msgq_success),

      // RTOS current task ID (REVIEW-008 fix)
      .rtos_current_tid(current_task_id),

      // Peripheral Access Control
      .periph_addr (periph_addr),
      .periph_wdata(periph_wdata),
      .periph_read (periph_read),
      .periph_write(periph_write),
      .periph_rdata(periph_rdata),
      .periph_ready(periph_ready),

      // AXI4 Slave Interface (from interconnect slave port [4])
      .s_axi_awaddr (xbar_m_awaddr[4]),
      .s_axi_awprot (3'b000),
      .s_axi_awvalid(xbar_m_awvalid[4]),
      .s_axi_awready(xbar_m_awready[4]),
      .s_axi_wdata  (xbar_m_wdata[4]),
      .s_axi_wstrb  (xbar_m_wstrb[4]),
      .s_axi_wvalid (xbar_m_wvalid[4]),
      .s_axi_wready (xbar_m_wready[4]),
      .s_axi_bresp  (xbar_m_bresp[4]),
      .s_axi_bvalid (xbar_m_bvalid[4]),
      .s_axi_bready (xbar_m_bready[4]),
      .s_axi_araddr (xbar_m_araddr[4]),
      .s_axi_arprot (3'b000),
      .s_axi_arvalid(xbar_m_arvalid[4]),
      .s_axi_arready(xbar_m_arready[4]),
      .s_axi_rdata  (xbar_m_rdata[4]),
      .s_axi_rresp  (xbar_m_rresp[4]),
      .s_axi_rvalid (xbar_m_rvalid[4]),
      .s_axi_rready (xbar_m_rready[4])
  );

  // posix_hw_layer uses AXI4-Lite. Tie off burst-related signals for port [4]
  assign xbar_m_bid[4] = xbar_m_awid[4];  // Echo back ID
  assign xbar_m_rid[4] = xbar_m_arid[4];  // Echo back ID
  assign xbar_m_rlast[4] = xbar_m_rvalid[4];  // Single-beat always last

  assign led = gpio_out[3:0];

endmodule : vsync_top
