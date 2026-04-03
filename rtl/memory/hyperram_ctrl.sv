// =============================================================================
// VSync - HyperRAM Controller
//
// File: hyperram_ctrl.sv
// Description: HyperBus DDR protocol controller with AXI4 slave interface.
//              Implements command/address phase (48-bit CA), configurable
//              initial latency, RWDS-based additional latency detection,
//              and DDR data transfer on HyperBus physical interface.
//              FSM: IDLE → CMD → LATENCY → DATA → DONE
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

module hyperram_ctrl
    import vsync_pkg::*;
#(
    parameter int LATENCY = 6,      // Initial latency in clock cycles
    parameter int ADDR_W  = 32,     // AXI address width
    parameter int DATA_W  = 32,     // AXI data width
    parameter int ID_W    = 4       // AXI ID width
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // =========================================================================
    // AXI4 Slave Port
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
    // HyperBus Physical Interface
    // =========================================================================
    output logic                   hb_ck,          // HyperBus clock (positive)
    output logic                   hb_ck_n,        // HyperBus clock (negative)
    output logic                   hb_cs_n,        // Chip select (active low)
    output logic                   hb_rwds_oe,     // RWDS output enable
    output logic                   hb_rwds_o,      // RWDS output
    input  logic                   hb_rwds_i,      // RWDS input
    output logic                   hb_dq_oe,       // DQ output enable
    output logic [7:0]            hb_dq_o,        // DQ output
    input  logic [7:0]            hb_dq_i         // DQ input
);

    // =========================================================================
    // FSM State Encoding
    // =========================================================================
    typedef enum logic [2:0] {
        ST_IDLE    = 3'b000,    // Waiting for AXI transaction
        ST_CMD     = 3'b001,    // Sending 48-bit command/address (6 bytes)
        ST_LATENCY = 3'b010,    // Waiting for initial + additional latency
        ST_DATA    = 3'b011,    // DDR data transfer phase
        ST_DONE    = 3'b100     // Transaction complete, send AXI response
    } state_t;

    state_t state, next_state;

    // =========================================================================
    // Command/Address (CA) Word Definition
    // =========================================================================
    // CA[47]: Read=1, Write=0
    // CA[46]: Register=1, Memory=0
    // CA[45]: Burst type: Linear=1, Wrapped=0
    // CA[44:16]: Row & upper column address
    // CA[15:3]: Reserved (set to 0)
    // CA[2:0]: Lower column address

    logic [47:0]    ca_word;            // 48-bit CA word
    logic           is_read;            // Current transaction is read
    logic [ID_W-1:0] txn_id;           // Transaction ID

    // =========================================================================
    // Counter & Control Registers
    // =========================================================================
    logic [3:0]     cmd_cnt;            // Command byte counter (0-5)
    logic [7:0]     lat_cnt;            // Latency cycle counter
    logic [3:0]     data_cnt;           // Data byte counter
    logic           additional_latency; // RWDS-indicated additional latency
    logic [7:0]     lat_total;          // Total latency cycles

    // =========================================================================
    // Data Registers
    // =========================================================================
    logic [DATA_W-1:0]  wr_data;        // Write data buffer
    logic [DATA_W-1:0]  rd_data;        // Read data accumulator
    logic [DATA_W/8-1:0] wr_strb;      // Write strobes
    logic               txn_error;      // Transaction error flag
    logic               hb_ck_en;       // Clock enable

    // Number of data bytes to transfer (DATA_W/8 bytes, DDR = 2 bytes per clk)
    localparam int DATA_BYTES  = DATA_W / 8;    // 4 bytes for 32-bit
    localparam int DDR_CYCLES  = DATA_BYTES / 2; // 2 clock cycles for 4 bytes

    // =========================================================================
    // CA Word Construction
    // =========================================================================
    logic [ADDR_W-1:0] txn_addr;

    always_comb begin
        // Memory space, linear burst
        ca_word[47]    = is_read;           // Read/Write
        ca_word[46]    = 1'b0;              // Memory space
        ca_word[45]    = 1'b1;              // Linear burst
        // HyperRAM uses half-word (16-bit) addressing
        // Row address in CA[44:16], column in CA[2:0]
        ca_word[44:16] = txn_addr[31:3];    // Row & upper column
        ca_word[15:3]  = 13'd0;             // Reserved
        ca_word[2:0]   = txn_addr[2:0];     // Lower column
    end

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
                    next_state = ST_CMD;
                end else if (s_axi_awvalid && s_axi_wvalid) begin
                    next_state = ST_CMD;
                end
            end

            ST_CMD: begin
                // 6 bytes of CA sent (DDR: 3 clock edges rising+falling = 3 clks)
                if (cmd_cnt == 4'd5) begin
                    next_state = ST_LATENCY;
                end
            end

            ST_LATENCY: begin
                if (lat_cnt >= lat_total - 1) begin
                    next_state = ST_DATA;
                end
            end

            ST_DATA: begin
                // DDR: 2 bytes per clock, DATA_BYTES total
                if (data_cnt >= DATA_BYTES[3:0] - 1) begin
                    next_state = ST_DONE;
                end
            end

            ST_DONE: begin
                // Wait for AXI response handshake
                if (is_read) begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        next_state = ST_IDLE;
                    end
                end else begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        next_state = ST_IDLE;
                    end
                end
            end

            default: begin
                next_state = ST_IDLE;
            end
        endcase
    end

    // =========================================================================
    // Data Path Logic
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_cnt            <= '0;
            lat_cnt            <= '0;
            data_cnt           <= '0;
            is_read            <= 1'b0;
            txn_id             <= '0;
            txn_addr           <= '0;
            wr_data            <= '0;
            wr_strb            <= '0;
            rd_data            <= '0;
            txn_error          <= 1'b0;
            additional_latency <= 1'b0;
            lat_total          <= '0;
            hb_ck_en           <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    cmd_cnt   <= '0;
                    lat_cnt   <= '0;
                    data_cnt  <= '0;
                    txn_error <= 1'b0;
                    rd_data   <= '0;
                    hb_ck_en  <= 1'b0;

                    if (s_axi_arvalid) begin
                        // Read transaction
                        is_read  <= 1'b1;
                        txn_id   <= s_axi_arid;
                        txn_addr <= s_axi_araddr;
                        hb_ck_en <= 1'b1;
                    end else if (s_axi_awvalid && s_axi_wvalid) begin
                        // Write transaction
                        is_read  <= 1'b0;
                        txn_id   <= s_axi_awid;
                        txn_addr <= s_axi_awaddr;
                        wr_data  <= s_axi_wdata;
                        wr_strb  <= s_axi_wstrb;
                        hb_ck_en <= 1'b1;
                    end
                end

                ST_CMD: begin
                    // Send CA bytes: 6 bytes total, one byte per half-clock (DDR)
                    // Simplified: send one byte per clock on rising edge
                    if (cmd_cnt < 4'd5) begin
                        cmd_cnt <= cmd_cnt + 1;
                    end
                end

                ST_LATENCY: begin
                    // Check RWDS for additional latency on first cycle
                    if (lat_cnt == '0) begin
                        additional_latency <= hb_rwds_i;
                        if (hb_rwds_i) begin
                            lat_total <= LATENCY[7:0] * 2;  // Double latency
                        end else begin
                            lat_total <= LATENCY[7:0];       // Normal latency
                        end
                    end
                    lat_cnt <= lat_cnt + 1;
                end

                ST_DATA: begin
                    if (is_read) begin
                        // DDR read: capture 8 bits on each edge
                        // Simplified: capture one byte per clock cycle
                        case (data_cnt[1:0])
                            2'd0: rd_data[ 7: 0] <= hb_dq_i;
                            2'd1: rd_data[15: 8] <= hb_dq_i;
                            2'd2: rd_data[23:16] <= hb_dq_i;
                            2'd3: rd_data[31:24] <= hb_dq_i;
                        endcase
                    end
                    data_cnt <= data_cnt + 1;
                end

                ST_DONE: begin
                    hb_ck_en <= 1'b0;
                end

                default: ;
            endcase
        end
    end

    // =========================================================================
    // HyperBus Output Signals
    // =========================================================================

    // Clock generation (active during transaction)
    assign hb_ck   =  clk & hb_ck_en;
    assign hb_ck_n = ~clk & hb_ck_en;

    // Chip select (active low during transaction)
    assign hb_cs_n = (state == ST_IDLE) || (state == ST_DONE &&
                      ((is_read && s_axi_rvalid && s_axi_rready) ||
                       (!is_read && s_axi_bvalid && s_axi_bready)));

    // DQ output: CA bytes during CMD, write data during DATA
    always_comb begin
        hb_dq_o  = 8'd0;
        hb_dq_oe = 1'b0;

        if (state == ST_CMD) begin
            hb_dq_oe = 1'b1;
            // Send CA bytes MSB first
            case (cmd_cnt)
                4'd0: hb_dq_o = ca_word[47:40];
                4'd1: hb_dq_o = ca_word[39:32];
                4'd2: hb_dq_o = ca_word[31:24];
                4'd3: hb_dq_o = ca_word[23:16];
                4'd4: hb_dq_o = ca_word[15: 8];
                4'd5: hb_dq_o = ca_word[ 7: 0];
                default: hb_dq_o = 8'd0;
            endcase
        end else if (state == ST_DATA && !is_read) begin
            hb_dq_oe = 1'b1;
            // Send write data bytes LSB first
            case (data_cnt[1:0])
                2'd0: hb_dq_o = wr_data[ 7: 0];
                2'd1: hb_dq_o = wr_data[15: 8];
                2'd2: hb_dq_o = wr_data[23:16];
                2'd3: hb_dq_o = wr_data[31:24];
            endcase
        end
    end

    // RWDS output: used as data mask during writes
    assign hb_rwds_oe = (state == ST_DATA) && !is_read;
    always_comb begin
        hb_rwds_o = 1'b0;
        if (state == ST_DATA && !is_read) begin
            // RWDS acts as byte-level write mask (inverted: 0 = write, 1 = mask)
            case (data_cnt[1:0])
                2'd0: hb_rwds_o = ~wr_strb[0];
                2'd1: hb_rwds_o = ~wr_strb[1];
                2'd2: hb_rwds_o = ~wr_strb[2];
                2'd3: hb_rwds_o = ~wr_strb[3];
            endcase
        end
    end

    // =========================================================================
    // AXI4 Slave Port Outputs
    // =========================================================================

    // AR ready: accept read address in IDLE
    assign s_axi_arready = (state == ST_IDLE) && s_axi_arvalid;

    // AW ready: accept write address in IDLE (no read pending)
    assign s_axi_awready = (state == ST_IDLE) && !s_axi_arvalid && s_axi_awvalid;

    // W ready: accept write data alongside AW
    assign s_axi_wready  = (state == ST_IDLE) && !s_axi_arvalid && s_axi_awvalid && s_axi_wvalid;

    // Read response
    assign s_axi_rid    = txn_id;
    assign s_axi_rdata  = rd_data;
    assign s_axi_rresp  = txn_error ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
    assign s_axi_rlast  = 1'b1;
    assign s_axi_rvalid = (state == ST_DONE) && is_read;

    // Write response
    assign s_axi_bid    = txn_id;
    assign s_axi_bresp  = txn_error ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
    assign s_axi_bvalid = (state == ST_DONE) && !is_read;

endmodule : hyperram_ctrl
