// =============================================================================
// VSync - AXI4 Interconnect (1-to-N Address Decoder & Router)
//
// File: axi4_interconnect.sv
// Description: Routes AXI4 transactions from a single master to multiple slaves
//              based on address decoding. Supports 6 slave ports with
//              configurable address map. Returns DECERR for invalid addresses.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

module axi4_interconnect
    import vsync_pkg::*;
#(
    parameter int NUM_SLAVES = 6,       // Number of slave ports
    parameter int ADDR_W     = 32,      // Address width
    parameter int DATA_W     = 32,      // Data width
    parameter int ID_W       = 4        // Transaction ID width
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // =========================================================================
    // AXI4 Slave Port (Master-side: CPU connects here)
    // =========================================================================
    // Write Address Channel
    input  logic [ID_W-1:0]        s_axi_awid,
    input  logic [ADDR_W-1:0]     s_axi_awaddr,
    input  logic [7:0]            s_axi_awlen,
    input  logic [2:0]            s_axi_awsize,
    input  logic [1:0]            s_axi_awburst,
    input  logic                   s_axi_awvalid,
    output logic                   s_axi_awready,

    // Write Data Channel
    input  logic [DATA_W-1:0]     s_axi_wdata,
    input  logic [DATA_W/8-1:0]  s_axi_wstrb,
    input  logic                   s_axi_wlast,
    input  logic                   s_axi_wvalid,
    output logic                   s_axi_wready,

    // Write Response Channel
    output logic [ID_W-1:0]       s_axi_bid,
    output logic [1:0]            s_axi_bresp,
    output logic                   s_axi_bvalid,
    input  logic                   s_axi_bready,

    // Read Address Channel
    input  logic [ID_W-1:0]        s_axi_arid,
    input  logic [ADDR_W-1:0]     s_axi_araddr,
    input  logic [7:0]            s_axi_arlen,
    input  logic [2:0]            s_axi_arsize,
    input  logic [1:0]            s_axi_arburst,
    input  logic                   s_axi_arvalid,
    output logic                   s_axi_arready,

    // Read Data Channel
    output logic [ID_W-1:0]       s_axi_rid,
    output logic [DATA_W-1:0]    s_axi_rdata,
    output logic [1:0]            s_axi_rresp,
    output logic                   s_axi_rlast,
    output logic                   s_axi_rvalid,
    input  logic                   s_axi_rready,

    // =========================================================================
    // AXI4 Master Ports (Slave-side: peripherals connect here)
    // =========================================================================
    // Write Address Channel
    output logic [ID_W-1:0]        m_axi_awid    [NUM_SLAVES],
    output logic [ADDR_W-1:0]     m_axi_awaddr  [NUM_SLAVES],
    output logic [7:0]            m_axi_awlen   [NUM_SLAVES],
    output logic [2:0]            m_axi_awsize  [NUM_SLAVES],
    output logic [1:0]            m_axi_awburst [NUM_SLAVES],
    output logic                   m_axi_awvalid [NUM_SLAVES],
    input  logic                   m_axi_awready [NUM_SLAVES],

    // Write Data Channel
    output logic [DATA_W-1:0]     m_axi_wdata   [NUM_SLAVES],
    output logic [DATA_W/8-1:0]  m_axi_wstrb   [NUM_SLAVES],
    output logic                   m_axi_wlast   [NUM_SLAVES],
    output logic                   m_axi_wvalid  [NUM_SLAVES],
    input  logic                   m_axi_wready  [NUM_SLAVES],

    // Write Response Channel
    input  logic [ID_W-1:0]       m_axi_bid     [NUM_SLAVES],
    input  logic [1:0]            m_axi_bresp   [NUM_SLAVES],
    input  logic                   m_axi_bvalid  [NUM_SLAVES],
    output logic                   m_axi_bready  [NUM_SLAVES],

    // Read Address Channel
    output logic [ID_W-1:0]        m_axi_arid    [NUM_SLAVES],
    output logic [ADDR_W-1:0]     m_axi_araddr  [NUM_SLAVES],
    output logic [7:0]            m_axi_arlen   [NUM_SLAVES],
    output logic [2:0]            m_axi_arsize  [NUM_SLAVES],
    output logic [1:0]            m_axi_arburst [NUM_SLAVES],
    output logic                   m_axi_arvalid [NUM_SLAVES],
    input  logic                   m_axi_arready [NUM_SLAVES],

    // Read Data Channel
    input  logic [ID_W-1:0]       m_axi_rid     [NUM_SLAVES],
    input  logic [DATA_W-1:0]    m_axi_rdata   [NUM_SLAVES],
    input  logic [1:0]            m_axi_rresp   [NUM_SLAVES],
    input  logic                   m_axi_rlast   [NUM_SLAVES],
    input  logic                   m_axi_rvalid  [NUM_SLAVES],
    output logic                   m_axi_rready  [NUM_SLAVES]
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    typedef enum logic [2:0] {
        ST_IDLE     = 3'b000,
        ST_READ     = 3'b001,   // Read transaction in progress
        ST_WRITE_AW = 3'b010,   // Write address phase
        ST_WRITE_W  = 3'b011,   // Write data phase
        ST_WRITE_B  = 3'b100,   // Write response phase
        ST_DECERR_R = 3'b101,   // Decode error read response
        ST_DECERR_B = 3'b110    // Decode error write response
    } state_t;

    state_t state, next_state;

    // =========================================================================
    // Address Decode Logic
    // =========================================================================
    logic [$clog2(NUM_SLAVES)-1:0] wr_slave_sel;
    logic [$clog2(NUM_SLAVES)-1:0] rd_slave_sel;
    logic [$clog2(NUM_SLAVES)-1:0] active_slave;
    logic                           wr_decode_valid;
    logic                           rd_decode_valid;
    logic                           active_is_read;

    // Registered transaction info
    logic [ID_W-1:0]               txn_id;
    logic                          aw_accepted;  // AW handshake done

    /**
     * @brief Decode address to slave index
     * @param addr Input address
     * @param slave_idx Output slave index
     * @param valid Output decode valid flag
     */
    // Address decode - inlined for iverilog compatibility
    // (iverilog does not support function with output ports)
    //
    // Slave Index Mapping (matches vsync_top.sv wiring):
    //   [0] = bram_dmem (via AXI-to-BRAM bridge)   0x00010000 - 0x00013FFF
    //   [1] = hyperram_ctrl                         0x20000000 - 0x2FFFFFFF
    //   [2] = axi4_apb_bridge (CLINT/PLIC/UART/GPIO)
    //   [3] = hw_rtos                               0x11000000 - 0x1100FFFF
    //   [4] = posix_hw_layer                        0x12000000 - 0x1200FFFF
    //   [5] = bram_imem (via AXI-to-BRAM bridge)   0x00000000 - 0x0000FFFF
    always_comb begin
        // Write address decode
        wr_decode_valid = 1'b1;
        wr_slave_sel    = '0;
        if (s_axi_awaddr >= ADDR_DMEM_BASE && s_axi_awaddr <= ADDR_DMEM_END) begin
            wr_slave_sel = 3'd0;   // DMEM bridge
        end else if (s_axi_awaddr >= ADDR_HYPERRAM_BASE && s_axi_awaddr <= ADDR_HYPERRAM_END) begin
            wr_slave_sel = 3'd1;   // HyperRAM
        end else if ((s_axi_awaddr >= ADDR_CLINT_BASE && s_axi_awaddr <= ADDR_CLINT_END) ||
                     (s_axi_awaddr >= ADDR_PLIC_BASE  && s_axi_awaddr <= ADDR_PLIC_END)  ||
                     (s_axi_awaddr >= ADDR_UART_BASE  && s_axi_awaddr <= ADDR_UART_END)  ||
                     (s_axi_awaddr >= ADDR_GPIO_BASE  && s_axi_awaddr <= ADDR_GPIO_END)) begin
            wr_slave_sel = 3'd2;   // APB Bridge (CLINT/PLIC/UART/GPIO)
        end else if (s_axi_awaddr >= ADDR_RTOS_BASE && s_axi_awaddr <= ADDR_RTOS_END) begin
            wr_slave_sel = 3'd3;   // hw_rtos
        end else if (s_axi_awaddr >= ADDR_POSIX_BASE && s_axi_awaddr <= ADDR_POSIX_END) begin
            wr_slave_sel = 3'd4;   // posix_hw_layer
        end else if (s_axi_awaddr >= ADDR_IMEM_BASE && s_axi_awaddr <= ADDR_IMEM_END) begin
            wr_slave_sel = 3'd5;   // IMEM bridge
        end else begin
            wr_decode_valid = 1'b0;  // Decode error
        end

        // Read address decode
        rd_decode_valid = 1'b1;
        rd_slave_sel    = '0;
        if (s_axi_araddr >= ADDR_DMEM_BASE && s_axi_araddr <= ADDR_DMEM_END) begin
            rd_slave_sel = 3'd0;   // DMEM bridge
        end else if (s_axi_araddr >= ADDR_HYPERRAM_BASE && s_axi_araddr <= ADDR_HYPERRAM_END) begin
            rd_slave_sel = 3'd1;   // HyperRAM
        end else if ((s_axi_araddr >= ADDR_CLINT_BASE && s_axi_araddr <= ADDR_CLINT_END) ||
                     (s_axi_araddr >= ADDR_PLIC_BASE  && s_axi_araddr <= ADDR_PLIC_END)  ||
                     (s_axi_araddr >= ADDR_UART_BASE  && s_axi_araddr <= ADDR_UART_END)  ||
                     (s_axi_araddr >= ADDR_GPIO_BASE  && s_axi_araddr <= ADDR_GPIO_END)) begin
            rd_slave_sel = 3'd2;   // APB Bridge (CLINT/PLIC/UART/GPIO)
        end else if (s_axi_araddr >= ADDR_RTOS_BASE && s_axi_araddr <= ADDR_RTOS_END) begin
            rd_slave_sel = 3'd3;   // hw_rtos
        end else if (s_axi_araddr >= ADDR_POSIX_BASE && s_axi_araddr <= ADDR_POSIX_END) begin
            rd_slave_sel = 3'd4;   // posix_hw_layer
        end else if (s_axi_araddr >= ADDR_IMEM_BASE && s_axi_araddr <= ADDR_IMEM_END) begin
            rd_slave_sel = 3'd5;   // IMEM bridge
        end else begin
            rd_decode_valid = 1'b0;  // Decode error
        end
    end

    // =========================================================================
    // FSM State Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            active_slave <= '0;
            active_is_read <= 1'b0;
            txn_id       <= '0;
            aw_accepted  <= 1'b0;
        end else begin
            state <= next_state;

            case (state)
                ST_IDLE: begin
                    aw_accepted <= 1'b0;
                    // Read has priority (simpler: check read first)
                    if (s_axi_arvalid) begin
                        active_slave   <= rd_slave_sel;
                        active_is_read <= 1'b1;
                        txn_id         <= s_axi_arid;
                    end else if (s_axi_awvalid) begin
                        active_slave   <= wr_slave_sel;
                        active_is_read <= 1'b0;
                        txn_id         <= s_axi_awid;
                    end
                end

                ST_WRITE_AW: begin
                    if (m_axi_awvalid[active_slave] && m_axi_awready[active_slave]) begin
                        aw_accepted <= 1'b1;
                    end
                end

                ST_WRITE_B, ST_DECERR_B, ST_DECERR_R: begin
                    // Reset for next transaction
                end

                default: ;
            endcase
        end
    end

    // =========================================================================
    // FSM Next State Logic
    // =========================================================================
    always_comb begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (s_axi_arvalid) begin
                    if (rd_decode_valid) begin
                        next_state = ST_READ;
                    end else begin
                        next_state = ST_DECERR_R;
                    end
                end else if (s_axi_awvalid) begin
                    if (wr_decode_valid) begin
                        next_state = ST_WRITE_AW;
                    end else begin
                        next_state = ST_DECERR_B;
                    end
                end
            end

            ST_READ: begin
                // Wait for read data response from slave
                if (m_axi_rvalid[active_slave] && s_axi_rready) begin
                    next_state = ST_IDLE;
                end
            end

            ST_WRITE_AW: begin
                // Wait for AW to be accepted, then forward W
                if (aw_accepted || (m_axi_awvalid[active_slave] && m_axi_awready[active_slave])) begin
                    next_state = ST_WRITE_W;
                end
            end

            ST_WRITE_W: begin
                // Wait for W data to be accepted
                if (m_axi_wvalid[active_slave] && m_axi_wready[active_slave]) begin
                    next_state = ST_WRITE_B;
                end
            end

            ST_WRITE_B: begin
                // Wait for write response
                if (m_axi_bvalid[active_slave] && s_axi_bready) begin
                    next_state = ST_IDLE;
                end
            end

            ST_DECERR_R: begin
                // Generate decode error read response
                if (s_axi_rready) begin
                    next_state = ST_IDLE;
                end
            end

            ST_DECERR_B: begin
                // Consume write data first if present, then error response
                if (s_axi_bready) begin
                    next_state = ST_IDLE;
                end
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // =========================================================================
    // Master Port Signal Routing (to slaves)
    // =========================================================================
`ifdef IVERILOG
    // -------------------------------------------------------------------------
    // iverilog workaround: generate-block continuous assigns to unpacked array
    // output ports produce X values in iverilog. Use packed vectors for gated
    // signals and explicit constant-index assigns for all output connections.
    // -------------------------------------------------------------------------

    // Packed vectors for gated per-slave signals (one-hot decoded)
    logic [NUM_SLAVES-1:0] arvalid_vec, awvalid_vec, wvalid_vec, bready_vec, rready_vec;

    always_comb begin
        arvalid_vec = '0;
        awvalid_vec = '0;
        wvalid_vec  = '0;
        bready_vec  = '0;
        rready_vec  = '0;
        if (state == ST_IDLE && s_axi_arvalid && rd_decode_valid)
            arvalid_vec[rd_slave_sel] = 1'b1;
        if (state == ST_WRITE_AW && !aw_accepted)
            awvalid_vec[active_slave] = 1'b1;
        if (state == ST_WRITE_W && s_axi_wvalid)
            wvalid_vec[active_slave] = 1'b1;
        if (state == ST_WRITE_B && s_axi_bready)
            bready_vec[active_slave] = 1'b1;
        if (state == ST_READ && s_axi_rready)
            rready_vec[active_slave] = 1'b1;
    end

    // Gated signals: packed vector bit -> unpacked array output
    assign m_axi_arvalid[0] = arvalid_vec[0]; assign m_axi_arvalid[1] = arvalid_vec[1];
    assign m_axi_arvalid[2] = arvalid_vec[2]; assign m_axi_arvalid[3] = arvalid_vec[3];
    assign m_axi_arvalid[4] = arvalid_vec[4]; assign m_axi_arvalid[5] = arvalid_vec[5];

    assign m_axi_awvalid[0] = awvalid_vec[0]; assign m_axi_awvalid[1] = awvalid_vec[1];
    assign m_axi_awvalid[2] = awvalid_vec[2]; assign m_axi_awvalid[3] = awvalid_vec[3];
    assign m_axi_awvalid[4] = awvalid_vec[4]; assign m_axi_awvalid[5] = awvalid_vec[5];

    assign m_axi_wvalid[0] = wvalid_vec[0]; assign m_axi_wvalid[1] = wvalid_vec[1];
    assign m_axi_wvalid[2] = wvalid_vec[2]; assign m_axi_wvalid[3] = wvalid_vec[3];
    assign m_axi_wvalid[4] = wvalid_vec[4]; assign m_axi_wvalid[5] = wvalid_vec[5];

    assign m_axi_bready[0] = bready_vec[0]; assign m_axi_bready[1] = bready_vec[1];
    assign m_axi_bready[2] = bready_vec[2]; assign m_axi_bready[3] = bready_vec[3];
    assign m_axi_bready[4] = bready_vec[4]; assign m_axi_bready[5] = bready_vec[5];

    assign m_axi_rready[0] = rready_vec[0]; assign m_axi_rready[1] = rready_vec[1];
    assign m_axi_rready[2] = rready_vec[2]; assign m_axi_rready[3] = rready_vec[3];
    assign m_axi_rready[4] = rready_vec[4]; assign m_axi_rready[5] = rready_vec[5];

    // Broadcast signals: same source to all slave ports
    // AR channel
    assign m_axi_arid[0] = s_axi_arid; assign m_axi_arid[1] = s_axi_arid;
    assign m_axi_arid[2] = s_axi_arid; assign m_axi_arid[3] = s_axi_arid;
    assign m_axi_arid[4] = s_axi_arid; assign m_axi_arid[5] = s_axi_arid;

    assign m_axi_araddr[0] = s_axi_araddr; assign m_axi_araddr[1] = s_axi_araddr;
    assign m_axi_araddr[2] = s_axi_araddr; assign m_axi_araddr[3] = s_axi_araddr;
    assign m_axi_araddr[4] = s_axi_araddr; assign m_axi_araddr[5] = s_axi_araddr;

    assign m_axi_arlen[0] = s_axi_arlen; assign m_axi_arlen[1] = s_axi_arlen;
    assign m_axi_arlen[2] = s_axi_arlen; assign m_axi_arlen[3] = s_axi_arlen;
    assign m_axi_arlen[4] = s_axi_arlen; assign m_axi_arlen[5] = s_axi_arlen;

    assign m_axi_arsize[0] = s_axi_arsize; assign m_axi_arsize[1] = s_axi_arsize;
    assign m_axi_arsize[2] = s_axi_arsize; assign m_axi_arsize[3] = s_axi_arsize;
    assign m_axi_arsize[4] = s_axi_arsize; assign m_axi_arsize[5] = s_axi_arsize;

    assign m_axi_arburst[0] = s_axi_arburst; assign m_axi_arburst[1] = s_axi_arburst;
    assign m_axi_arburst[2] = s_axi_arburst; assign m_axi_arburst[3] = s_axi_arburst;
    assign m_axi_arburst[4] = s_axi_arburst; assign m_axi_arburst[5] = s_axi_arburst;

    // AW channel
    assign m_axi_awid[0] = s_axi_awid; assign m_axi_awid[1] = s_axi_awid;
    assign m_axi_awid[2] = s_axi_awid; assign m_axi_awid[3] = s_axi_awid;
    assign m_axi_awid[4] = s_axi_awid; assign m_axi_awid[5] = s_axi_awid;

    assign m_axi_awaddr[0] = s_axi_awaddr; assign m_axi_awaddr[1] = s_axi_awaddr;
    assign m_axi_awaddr[2] = s_axi_awaddr; assign m_axi_awaddr[3] = s_axi_awaddr;
    assign m_axi_awaddr[4] = s_axi_awaddr; assign m_axi_awaddr[5] = s_axi_awaddr;

    assign m_axi_awlen[0] = s_axi_awlen; assign m_axi_awlen[1] = s_axi_awlen;
    assign m_axi_awlen[2] = s_axi_awlen; assign m_axi_awlen[3] = s_axi_awlen;
    assign m_axi_awlen[4] = s_axi_awlen; assign m_axi_awlen[5] = s_axi_awlen;

    assign m_axi_awsize[0] = s_axi_awsize; assign m_axi_awsize[1] = s_axi_awsize;
    assign m_axi_awsize[2] = s_axi_awsize; assign m_axi_awsize[3] = s_axi_awsize;
    assign m_axi_awsize[4] = s_axi_awsize; assign m_axi_awsize[5] = s_axi_awsize;

    assign m_axi_awburst[0] = s_axi_awburst; assign m_axi_awburst[1] = s_axi_awburst;
    assign m_axi_awburst[2] = s_axi_awburst; assign m_axi_awburst[3] = s_axi_awburst;
    assign m_axi_awburst[4] = s_axi_awburst; assign m_axi_awburst[5] = s_axi_awburst;

    // W channel
    assign m_axi_wdata[0] = s_axi_wdata; assign m_axi_wdata[1] = s_axi_wdata;
    assign m_axi_wdata[2] = s_axi_wdata; assign m_axi_wdata[3] = s_axi_wdata;
    assign m_axi_wdata[4] = s_axi_wdata; assign m_axi_wdata[5] = s_axi_wdata;

    assign m_axi_wstrb[0] = s_axi_wstrb; assign m_axi_wstrb[1] = s_axi_wstrb;
    assign m_axi_wstrb[2] = s_axi_wstrb; assign m_axi_wstrb[3] = s_axi_wstrb;
    assign m_axi_wstrb[4] = s_axi_wstrb; assign m_axi_wstrb[5] = s_axi_wstrb;

    assign m_axi_wlast[0] = s_axi_wlast; assign m_axi_wlast[1] = s_axi_wlast;
    assign m_axi_wlast[2] = s_axi_wlast; assign m_axi_wlast[3] = s_axi_wlast;
    assign m_axi_wlast[4] = s_axi_wlast; assign m_axi_wlast[5] = s_axi_wlast;

`else
    genvar i;
    generate
        for (i = 0; i < NUM_SLAVES; i++) begin : gen_slave_routing
            // AR channel: forward to selected slave only
            assign m_axi_arid[i]    = s_axi_arid;
            assign m_axi_araddr[i]  = s_axi_araddr;
            assign m_axi_arlen[i]   = s_axi_arlen;
            assign m_axi_arsize[i]  = s_axi_arsize;
            assign m_axi_arburst[i] = s_axi_arburst;
            assign m_axi_arvalid[i] = (state == ST_IDLE) && s_axi_arvalid &&
                                       rd_decode_valid && (rd_slave_sel == i[$clog2(NUM_SLAVES)-1:0]);

            // AW channel: forward to selected slave only
            assign m_axi_awid[i]    = s_axi_awid;
            assign m_axi_awaddr[i]  = s_axi_awaddr;
            assign m_axi_awlen[i]   = s_axi_awlen;
            assign m_axi_awsize[i]  = s_axi_awsize;
            assign m_axi_awburst[i] = s_axi_awburst;
            assign m_axi_awvalid[i] = (state == ST_WRITE_AW) && !aw_accepted &&
                                       (active_slave == i[$clog2(NUM_SLAVES)-1:0]);

            // W channel: forward to selected slave only
            assign m_axi_wdata[i]   = s_axi_wdata;
            assign m_axi_wstrb[i]   = s_axi_wstrb;
            assign m_axi_wlast[i]   = s_axi_wlast;
            assign m_axi_wvalid[i]  = (state == ST_WRITE_W) &&
                                       (active_slave == i[$clog2(NUM_SLAVES)-1:0]) &&
                                       s_axi_wvalid;

            // B channel: accept from selected slave only
            assign m_axi_bready[i]  = (state == ST_WRITE_B) &&
                                       (active_slave == i[$clog2(NUM_SLAVES)-1:0]) &&
                                       s_axi_bready;

            // R channel: accept from selected slave only
            assign m_axi_rready[i]  = (state == ST_READ) &&
                                       (active_slave == i[$clog2(NUM_SLAVES)-1:0]) &&
                                       s_axi_rready;
        end
    endgenerate
`endif

    // =========================================================================
    // Slave Port Signal Routing (back to master)
    // =========================================================================

    // AR ready: from selected slave or decode error
    always_comb begin
        if (state == ST_IDLE && s_axi_arvalid) begin
            if (rd_decode_valid) begin
                s_axi_arready = m_axi_arready[rd_slave_sel];
            end else begin
                s_axi_arready = 1'b1;  // Accept for decode error
            end
        end else begin
            s_axi_arready = 1'b0;
        end
    end

    // AW ready: from selected slave or decode error
    always_comb begin
        if (state == ST_WRITE_AW && !aw_accepted) begin
            s_axi_awready = m_axi_awready[active_slave];
        end else if (state == ST_IDLE && !s_axi_arvalid && s_axi_awvalid && !wr_decode_valid) begin
            s_axi_awready = 1'b1;  // Accept for decode error
        end else begin
            s_axi_awready = 1'b0;
        end
    end

    // W ready: from selected slave or decode error
    always_comb begin
        if (state == ST_WRITE_W) begin
            s_axi_wready = m_axi_wready[active_slave];
        end else if (state == ST_DECERR_B && s_axi_wvalid) begin
            s_axi_wready = 1'b1;  // Consume write data for decode error
        end else begin
            s_axi_wready = 1'b0;
        end
    end

    // R channel mux: from selected slave or decode error
    always_comb begin
        if (state == ST_DECERR_R) begin
            s_axi_rid   = txn_id;
            s_axi_rdata = '0;
            s_axi_rresp = AXI_RESP_DECERR;
            s_axi_rlast = 1'b1;
            s_axi_rvalid = 1'b1;
        end else if (state == ST_READ) begin
            s_axi_rid    = m_axi_rid[active_slave];
            s_axi_rdata  = m_axi_rdata[active_slave];
            s_axi_rresp  = m_axi_rresp[active_slave];
            s_axi_rlast  = m_axi_rlast[active_slave];
            s_axi_rvalid = m_axi_rvalid[active_slave];
        end else begin
            s_axi_rid    = '0;
            s_axi_rdata  = '0;
            s_axi_rresp  = '0;
            s_axi_rlast  = 1'b0;
            s_axi_rvalid = 1'b0;
        end
    end

    // B channel mux: from selected slave or decode error
    always_comb begin
        if (state == ST_DECERR_B) begin
            s_axi_bid    = txn_id;
            s_axi_bresp  = AXI_RESP_DECERR;
            s_axi_bvalid = 1'b1;
        end else if (state == ST_WRITE_B) begin
            s_axi_bid    = m_axi_bid[active_slave];
            s_axi_bresp  = m_axi_bresp[active_slave];
            s_axi_bvalid = m_axi_bvalid[active_slave];
        end else begin
            s_axi_bid    = '0;
            s_axi_bresp  = '0;
            s_axi_bvalid = 1'b0;
        end
    end

endmodule : axi4_interconnect
