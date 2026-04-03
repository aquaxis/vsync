// =============================================================================
// VSync - AXI4 to APB Bridge
//
// File: axi4_apb_bridge.sv
// Description: Protocol bridge converting AXI4 slave transactions to APB
//              master transactions. Supports single-beat transfers only
//              (no burst support, AWLEN must be 0).
//              FSM: IDLE → SETUP → ACCESS → RESP
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

module axi4_apb_bridge
    import vsync_pkg::*;
#(
    parameter int AXI_ADDR_W = 32,  // AXI4 address width
    parameter int AXI_DATA_W = 32,  // AXI4 data width
    parameter int APB_ADDR_W = 32,  // APB address width
    parameter int APB_DATA_W = 32,  // APB data width
    parameter int AXI_ID_W   = 4    // AXI4 ID width
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // =========================================================================
    // AXI4 Slave Port (connects to interconnect master port)
    // =========================================================================
    // Write Address Channel
    input  logic [AXI_ID_W-1:0]        s_axi_awid,
    input  logic [AXI_ADDR_W-1:0]     s_axi_awaddr,
    input  logic [7:0]                s_axi_awlen,
    input  logic [2:0]                s_axi_awsize,
    input  logic [1:0]                s_axi_awburst,
    input  logic                       s_axi_awvalid,
    output logic                       s_axi_awready,

    // Write Data Channel
    input  logic [AXI_DATA_W-1:0]     s_axi_wdata,
    input  logic [AXI_DATA_W/8-1:0]  s_axi_wstrb,
    input  logic                       s_axi_wlast,
    input  logic                       s_axi_wvalid,
    output logic                       s_axi_wready,

    // Write Response Channel
    output logic [AXI_ID_W-1:0]       s_axi_bid,
    output logic [1:0]                s_axi_bresp,
    output logic                       s_axi_bvalid,
    input  logic                       s_axi_bready,

    // Read Address Channel
    input  logic [AXI_ID_W-1:0]        s_axi_arid,
    input  logic [AXI_ADDR_W-1:0]     s_axi_araddr,
    input  logic [7:0]                s_axi_arlen,
    input  logic [2:0]                s_axi_arsize,
    input  logic [1:0]                s_axi_arburst,
    input  logic                       s_axi_arvalid,
    output logic                       s_axi_arready,

    // Read Data Channel
    output logic [AXI_ID_W-1:0]       s_axi_rid,
    output logic [AXI_DATA_W-1:0]    s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                       s_axi_rlast,
    output logic                       s_axi_rvalid,
    input  logic                       s_axi_rready,

    // =========================================================================
    // APB Master Port (connects to APB peripherals)
    // =========================================================================
    output logic                       apb_psel,       // Peripheral select
    output logic                       apb_penable,    // Enable phase
    output logic                       apb_pwrite,     // Write transfer
    output logic [APB_ADDR_W-1:0]     apb_paddr,      // Address
    output logic [APB_DATA_W-1:0]     apb_pwdata,     // Write data
    input  logic [APB_DATA_W-1:0]     apb_prdata,     // Read data
    input  logic                       apb_pready,     // Slave ready
    input  logic                       apb_pslverr     // Slave error
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    typedef enum logic [2:0] {
        ST_IDLE   = 3'b000,     // Waiting for AXI transaction
        ST_SETUP  = 3'b001,     // APB setup phase (PSEL=1, PENABLE=0)
        ST_ACCESS = 3'b010,     // APB access phase (PSEL=1, PENABLE=1)
        ST_WR_RESP = 3'b011,    // AXI write response phase
        ST_RD_RESP = 3'b100,    // AXI read response phase
        ST_WR_WAIT = 3'b101     // Wait for write data
    } state_t;

    state_t state, next_state;

    // =========================================================================
    // Internal Registers
    // =========================================================================
    logic [AXI_ID_W-1:0]        txn_id;         // Transaction ID
    logic [AXI_ADDR_W-1:0]     txn_addr;       // Transaction address
    logic [AXI_DATA_W-1:0]     txn_wdata;      // Write data
    logic                       txn_is_write;   // Write transaction flag
    logic [APB_DATA_W-1:0]     txn_rdata;      // Captured read data
    logic                       txn_error;      // Captured error flag
    logic                       aw_received;    // AW already received
    logic                       w_received;     // W data already received

    // =========================================================================
    // FSM State Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= next_state;
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
                    // Read has priority
                    next_state = ST_SETUP;
                end else if (s_axi_awvalid && s_axi_wvalid) begin
                    // Write with both AW and W available
                    next_state = ST_SETUP;
                end else if (s_axi_awvalid) begin
                    // AW available but waiting for W data
                    next_state = ST_WR_WAIT;
                end
            end

            ST_WR_WAIT: begin
                if (s_axi_wvalid) begin
                    next_state = ST_SETUP;
                end
            end

            ST_SETUP: begin
                // APB setup phase always takes 1 cycle
                next_state = ST_ACCESS;
            end

            ST_ACCESS: begin
                // Wait for APB slave ready
                if (apb_pready) begin
                    if (txn_is_write) begin
                        next_state = ST_WR_RESP;
                    end else begin
                        next_state = ST_RD_RESP;
                    end
                end
            end

            ST_WR_RESP: begin
                // Wait for AXI write response acceptance
                if (s_axi_bvalid && s_axi_bready) begin
                    next_state = ST_IDLE;
                end
            end

            ST_RD_RESP: begin
                // Wait for AXI read response acceptance
                if (s_axi_rvalid && s_axi_rready) begin
                    next_state = ST_IDLE;
                end
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // =========================================================================
    // Data Path Registers
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            txn_id       <= '0;
            txn_addr     <= '0;
            txn_wdata    <= '0;
            txn_is_write <= 1'b0;
            txn_rdata    <= '0;
            txn_error    <= 1'b0;
            aw_received  <= 1'b0;
            w_received   <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    aw_received <= 1'b0;
                    w_received  <= 1'b0;
                    if (s_axi_arvalid) begin
                        // Capture read transaction
                        txn_id       <= s_axi_arid;
                        txn_addr     <= s_axi_araddr;
                        txn_is_write <= 1'b0;
                    end else if (s_axi_awvalid && s_axi_wvalid) begin
                        // Capture write transaction (both channels ready)
                        txn_id       <= s_axi_awid;
                        txn_addr     <= s_axi_awaddr;
                        txn_wdata    <= s_axi_wdata;
                        txn_is_write <= 1'b1;
                        aw_received  <= 1'b1;
                        w_received   <= 1'b1;
                    end else if (s_axi_awvalid) begin
                        // Capture AW, wait for W
                        txn_id       <= s_axi_awid;
                        txn_addr     <= s_axi_awaddr;
                        txn_is_write <= 1'b1;
                        aw_received  <= 1'b1;
                    end
                end

                ST_WR_WAIT: begin
                    if (s_axi_wvalid) begin
                        txn_wdata   <= s_axi_wdata;
                        w_received  <= 1'b1;
                    end
                end

                ST_ACCESS: begin
                    if (apb_pready) begin
                        txn_rdata <= apb_prdata;
                        txn_error <= apb_pslverr;
                    end
                end

                default: ;
            endcase
        end
    end

    // =========================================================================
    // APB Master Port Outputs
    // =========================================================================
    assign apb_psel    = (state == ST_SETUP) || (state == ST_ACCESS);
    assign apb_penable = (state == ST_ACCESS);
    assign apb_pwrite  = txn_is_write;
    assign apb_paddr   = txn_addr[APB_ADDR_W-1:0];
    assign apb_pwdata  = txn_wdata[APB_DATA_W-1:0];

    // =========================================================================
    // AXI4 Slave Port Outputs
    // =========================================================================

    // AR ready: accept in IDLE when read arrives
    assign s_axi_arready = (state == ST_IDLE) && s_axi_arvalid;

    // AW ready: accept in IDLE when no read pending
    assign s_axi_awready = ((state == ST_IDLE) && !s_axi_arvalid && s_axi_awvalid);

    // W ready: accept alongside AW in IDLE, or in WR_WAIT state
    assign s_axi_wready  = ((state == ST_IDLE) && !s_axi_arvalid && s_axi_awvalid && s_axi_wvalid) ||
                            (state == ST_WR_WAIT);

    // Write response
    assign s_axi_bid    = txn_id;
    assign s_axi_bresp  = txn_error ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
    assign s_axi_bvalid = (state == ST_WR_RESP);

    // Read response
    assign s_axi_rid    = txn_id;
    assign s_axi_rdata  = txn_rdata;
    assign s_axi_rresp  = txn_error ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
    assign s_axi_rlast  = 1'b1;     // Always last (single beat)
    assign s_axi_rvalid = (state == ST_RD_RESP);

endmodule : axi4_apb_bridge
