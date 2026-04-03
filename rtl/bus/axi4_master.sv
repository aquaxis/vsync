// =============================================================================
// VSync - AXI4 Master Interface
//
// File: axi4_master.sv
// Description: Converts CPU core memory access requests to AXI4 protocol.
//              FSM-based implementation with full VALID/READY handshake.
//              Supports single-beat read and write transactions.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

module axi4_master
    import vsync_pkg::*;
#(
    parameter int ADDR_W = 32,  // Address width
    parameter int DATA_W = 32,  // Data width
    parameter int ID_W   = 4    // Transaction ID width
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // =========================================================================
    // CPU Command Interface
    // =========================================================================
    input  logic                    cmd_read,       // Read request
    input  logic                    cmd_write,      // Write request
    input  logic [ADDR_W-1:0]      cmd_addr,       // Access address
    input  logic [DATA_W-1:0]      cmd_wdata,      // Write data
    input  logic [DATA_W/8-1:0]    cmd_wstrb,      // Write byte strobes
    output logic [DATA_W-1:0]      cmd_rdata,      // Read data output
    output logic                    cmd_done,       // Transaction complete
    output logic                    cmd_error,      // Transaction error

    // =========================================================================
    // AXI4 Master Port - Write Address Channel (AW)
    // =========================================================================
    output logic [ID_W-1:0]        m_axi_awid,
    output logic [ADDR_W-1:0]     m_axi_awaddr,
    output logic [7:0]            m_axi_awlen,    // Burst length (0 = single)
    output logic [2:0]            m_axi_awsize,   // Beat size
    output logic [1:0]            m_axi_awburst,  // Burst type
    output logic                   m_axi_awvalid,
    input  logic                   m_axi_awready,

    // =========================================================================
    // AXI4 Master Port - Write Data Channel (W)
    // =========================================================================
    output logic [DATA_W-1:0]     m_axi_wdata,
    output logic [DATA_W/8-1:0]  m_axi_wstrb,
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  logic                   m_axi_wready,

    // =========================================================================
    // AXI4 Master Port - Write Response Channel (B)
    // =========================================================================
    input  logic [ID_W-1:0]       m_axi_bid,
    input  logic [1:0]            m_axi_bresp,
    input  logic                   m_axi_bvalid,
    output logic                   m_axi_bready,

    // =========================================================================
    // AXI4 Master Port - Read Address Channel (AR)
    // =========================================================================
    output logic [ID_W-1:0]        m_axi_arid,
    output logic [ADDR_W-1:0]     m_axi_araddr,
    output logic [7:0]            m_axi_arlen,    // Burst length (0 = single)
    output logic [2:0]            m_axi_arsize,   // Beat size
    output logic [1:0]            m_axi_arburst,  // Burst type
    output logic                   m_axi_arvalid,
    input  logic                   m_axi_arready,

    // =========================================================================
    // AXI4 Master Port - Read Data Channel (R)
    // =========================================================================
    input  logic [ID_W-1:0]       m_axi_rid,
    input  logic [DATA_W-1:0]    m_axi_rdata,
    input  logic [1:0]            m_axi_rresp,
    input  logic                   m_axi_rlast,
    input  logic                   m_axi_rvalid,
    output logic                   m_axi_rready
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    typedef enum logic [2:0] {
        ST_IDLE      = 3'b000,
        ST_RD_ADDR   = 3'b001,  // Read: send address
        ST_RD_DATA   = 3'b010,  // Read: wait for data
        ST_WR_ADDR   = 3'b011,  // Write: send address + data
        ST_WR_DATA   = 3'b100,  // Write: send data (if addr accepted first)
        ST_WR_RESP   = 3'b101,  // Write: wait for response
        ST_DONE      = 3'b110   // Transaction complete
    } state_t;

    state_t state, next_state;

    // =========================================================================
    // Internal Registers
    // =========================================================================
    logic [ADDR_W-1:0]    addr_reg;
    logic [DATA_W-1:0]    wdata_reg;
    logic [DATA_W/8-1:0]  wstrb_reg;
    logic [DATA_W-1:0]    rdata_reg;
    logic                  error_reg;
    logic                  is_read_reg;
    logic                  aw_done;     // AW channel handshake completed
    logic                  w_done;      // W channel handshake completed

    // =========================================================================
    // Fixed AXI4 Signal Assignments (Single-beat transactions)
    // =========================================================================
    assign m_axi_awid    = '0;
    assign m_axi_awlen   = 8'd0;              // Single beat
    assign m_axi_awsize  = $clog2(DATA_W/8);  // Full data width per beat
    assign m_axi_awburst = 2'b01;             // INCR (don't care for single beat)

    assign m_axi_wlast   = 1'b1;              // Always last (single beat)

    assign m_axi_arid    = '0;
    assign m_axi_arlen   = 8'd0;              // Single beat
    assign m_axi_arsize  = $clog2(DATA_W/8);  // Full data width per beat
    assign m_axi_arburst = 2'b01;             // INCR

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
                if (cmd_read) begin
                    next_state = ST_RD_ADDR;
                end else if (cmd_write) begin
                    next_state = ST_WR_ADDR;
                end
            end

            ST_RD_ADDR: begin
                if (m_axi_arvalid && m_axi_arready) begin
                    next_state = ST_RD_DATA;
                end
            end

            ST_RD_DATA: begin
                if (m_axi_rvalid && m_axi_rready) begin
                    next_state = ST_DONE;
                end
            end

            ST_WR_ADDR: begin
                // AW and W can be accepted independently
                if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                    (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                    next_state = ST_WR_RESP;
                end else if (m_axi_awvalid && m_axi_awready && !(m_axi_wvalid && m_axi_wready)) begin
                    next_state = ST_WR_DATA;
                end
            end

            ST_WR_DATA: begin
                if (m_axi_wvalid && m_axi_wready) begin
                    next_state = ST_WR_RESP;
                end
            end

            ST_WR_RESP: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    next_state = ST_DONE;
                end
            end

            ST_DONE: begin
                next_state = ST_IDLE;
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
            addr_reg    <= '0;
            wdata_reg   <= '0;
            wstrb_reg   <= '0;
            rdata_reg   <= '0;
            error_reg   <= 1'b0;
            is_read_reg <= 1'b0;
            aw_done     <= 1'b0;
            w_done      <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    error_reg <= 1'b0;
                    aw_done   <= 1'b0;
                    w_done    <= 1'b0;
                    if (cmd_read) begin
                        addr_reg    <= cmd_addr;
                        is_read_reg <= 1'b1;
                    end else if (cmd_write) begin
                        addr_reg    <= cmd_addr;
                        wdata_reg   <= cmd_wdata;
                        wstrb_reg   <= cmd_wstrb;
                        is_read_reg <= 1'b0;
                    end
                end

                ST_RD_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        rdata_reg <= m_axi_rdata;
                        error_reg <= (m_axi_rresp != 2'b00);
                    end
                end

                ST_WR_ADDR: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        aw_done <= 1'b1;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        w_done <= 1'b1;
                    end
                end

                ST_WR_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        error_reg <= (m_axi_bresp != 2'b00);
                    end
                end

                ST_DONE: begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                end

                default: ;
            endcase
        end
    end

    // =========================================================================
    // AXI4 Output Signal Generation
    // =========================================================================

    // Read Address Channel (AR)
    assign m_axi_araddr  = addr_reg;
    assign m_axi_arvalid = (state == ST_RD_ADDR);

    // Read Data Channel (R)
    assign m_axi_rready  = (state == ST_RD_DATA);

    // Write Address Channel (AW)
    assign m_axi_awaddr  = addr_reg;
    assign m_axi_awvalid = (state == ST_WR_ADDR) && !aw_done;

    // Write Data Channel (W)
    assign m_axi_wdata   = wdata_reg;
    assign m_axi_wstrb   = wstrb_reg;
    assign m_axi_wvalid  = ((state == ST_WR_ADDR) && !w_done) ||
                            (state == ST_WR_DATA);

    // Write Response Channel (B)
    assign m_axi_bready  = (state == ST_WR_RESP);

    // =========================================================================
    // CPU Command Interface Outputs
    // =========================================================================
    assign cmd_rdata = rdata_reg;
    assign cmd_done  = (state == ST_DONE);
    assign cmd_error = (state == ST_DONE) && error_reg;

endmodule : axi4_master
