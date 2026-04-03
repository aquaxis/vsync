// =============================================================================
// VSync - UART with APB Slave Interface
//
// File: uart_apb.sv
// Description: UART 8N1 transceiver with TX/RX FIFOs, configurable baud rate,
//              16x oversampling RX, and APB slave interface.
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module uart_apb #(
    parameter int CLK_FREQ     = 100_000_000,
    parameter int DEFAULT_BAUD = 115200,
    parameter int FIFO_DEPTH   = 16
) (
    // Clock & Reset
    input  logic        clk,
    input  logic        rst_n,

    // APB Slave Interface
    input  logic        apb_psel,
    input  logic        apb_penable,
    input  logic        apb_pwrite,
    input  logic [7:0]  apb_paddr,
    input  logic [31:0] apb_pwdata,
    output logic [31:0] apb_prdata,
    output logic        apb_pready,
    output logic        apb_pslverr,

    // UART Signals
    input  logic        uart_rx,
    output logic        uart_tx,

    // Interrupt
    output logic        irq
);

    // =========================================================================
    // Register Address Offsets
    // =========================================================================
    localparam logic [7:0] REG_TX_DATA  = 8'h00;
    localparam logic [7:0] REG_RX_DATA  = 8'h04;
    localparam logic [7:0] REG_STATUS   = 8'h08;
    localparam logic [7:0] REG_CTRL     = 8'h0C;
    localparam logic [7:0] REG_BAUD_DIV = 8'h10;

    // =========================================================================
    // Baud Rate Divider
    // =========================================================================
    // Fractional baud rate divider (STM32 BRR equivalent):
    //   Value = round(CLK_FREQ / BAUD), packed as [31:4]=integer, [3:0]=fractional (1/16ths)
    //   25 MHz/115200 = 217 (int=13, frac=9)   10 MHz/115200 = 87 (int=5, frac=7)
    localparam int DEFAULT_BAUD_DIV = (CLK_FREQ + DEFAULT_BAUD / 2) / DEFAULT_BAUD;

    logic [31:0] baud_div_r;

    // =========================================================================
    // Control Register Fields
    // =========================================================================
    logic ctrl_tx_ie;   // bit0: TX interrupt enable
    logic ctrl_rx_ie;   // bit1: RX interrupt enable
    logic ctrl_tx_en;   // bit2: TX enable
    logic ctrl_rx_en;   // bit3: RX enable

    // =========================================================================
    // TX FIFO (Ring Buffer)
    // =========================================================================
    localparam int FIFO_ADDR_W = $clog2(FIFO_DEPTH);

    logic [7:0]             tx_fifo [FIFO_DEPTH];
    logic [FIFO_ADDR_W:0]   tx_wr_ptr;
    logic [FIFO_ADDR_W:0]   tx_rd_ptr;
    logic [FIFO_ADDR_W:0]   tx_count;

    logic tx_fifo_full;
    logic tx_fifo_empty;
    logic tx_fifo_push;
    logic tx_fifo_pop;

    assign tx_fifo_full  = (tx_count == FIFO_DEPTH[FIFO_ADDR_W:0]);
    assign tx_fifo_empty = (tx_count == '0);

    /** @brief TX FIFO write logic */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_wr_ptr <= '0;
        end else if (tx_fifo_push && !tx_fifo_full) begin
            tx_fifo[tx_wr_ptr[FIFO_ADDR_W-1:0]] <= apb_pwdata[7:0];
            tx_wr_ptr <= tx_wr_ptr + 1'b1;
        end
    end

    /** @brief TX FIFO read pointer logic */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_rd_ptr <= '0;
        end else if (tx_fifo_pop && !tx_fifo_empty) begin
            tx_rd_ptr <= tx_rd_ptr + 1'b1;
        end
    end

    /** @brief TX FIFO count logic */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_count <= '0;
        end else begin
            case ({tx_fifo_push && !tx_fifo_full, tx_fifo_pop && !tx_fifo_empty})
                2'b10:   tx_count <= tx_count + 1'b1;
                2'b01:   tx_count <= tx_count - 1'b1;
                default: tx_count <= tx_count;
            endcase
        end
    end

    // =========================================================================
    // RX FIFO (Ring Buffer)
    // =========================================================================
    logic [7:0]             rx_fifo [FIFO_DEPTH];
    logic [FIFO_ADDR_W:0]   rx_wr_ptr;
    logic [FIFO_ADDR_W:0]   rx_rd_ptr;
    logic [FIFO_ADDR_W:0]   rx_count;

    logic rx_fifo_full;
    logic rx_fifo_empty;
    logic rx_fifo_push;
    logic rx_fifo_pop;
    logic [7:0] rx_fifo_wdata;

    assign rx_fifo_full  = (rx_count == FIFO_DEPTH[FIFO_ADDR_W:0]);
    assign rx_fifo_empty = (rx_count == '0);

    /** @brief RX FIFO write logic */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_wr_ptr <= '0;
        end else if (rx_fifo_push && !rx_fifo_full) begin
            rx_fifo[rx_wr_ptr[FIFO_ADDR_W-1:0]] <= rx_fifo_wdata;
            rx_wr_ptr <= rx_wr_ptr + 1'b1;
        end
    end

    /** @brief RX FIFO read pointer logic */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_rd_ptr <= '0;
        end else if (rx_fifo_pop && !rx_fifo_empty) begin
            rx_rd_ptr <= rx_rd_ptr + 1'b1;
        end
    end

    /** @brief RX FIFO count logic */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_count <= '0;
        end else begin
            case ({rx_fifo_push && !rx_fifo_full, rx_fifo_pop && !rx_fifo_empty})
                2'b10:   rx_count <= rx_count + 1'b1;
                2'b01:   rx_count <= rx_count - 1'b1;
                default: rx_count <= rx_count;
            endcase
        end
    end

    // =========================================================================
    // TX FSM
    // =========================================================================
    typedef enum logic [3:0] {
        TX_IDLE,
        TX_START,
        TX_DATA0, TX_DATA1, TX_DATA2, TX_DATA3,
        TX_DATA4, TX_DATA5, TX_DATA6, TX_DATA7,
        TX_STOP
    } tx_state_t;

    tx_state_t tx_state, tx_state_next;
    logic [31:0] tx_baud_cnt;
    logic        tx_baud_tick;
    logic [7:0]  tx_shift_reg;
    logic        tx_busy;

    assign tx_busy = (tx_state != TX_IDLE);

    /** @brief TX baud counter: counts clocks per bit period
     *  baud_div_r = round(CLK_FREQ / BAUD) = total clocks per bit */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                                tx_baud_cnt <= 0;
        else if (tx_state == TX_IDLE)              tx_baud_cnt <= 0;
        else if (tx_baud_cnt >= (baud_div_r - 1))  tx_baud_cnt <= 0;
        else                                       tx_baud_cnt <= tx_baud_cnt + 1;
    end
    assign tx_baud_tick = (tx_state != TX_IDLE) && (tx_baud_cnt == (baud_div_r - 1));

    /** @brief TX FSM state register */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
        end else begin
            tx_state <= tx_state_next;
        end
    end

    /** @brief TX FSM next state logic */
    always_comb begin
        tx_state_next = tx_state;
        tx_fifo_pop   = 1'b0;

        case (tx_state)
            TX_IDLE: begin
                if (!tx_fifo_empty && ctrl_tx_en) begin
                    tx_state_next = TX_START;
                    tx_fifo_pop   = 1'b1;
                end
            end
            TX_START: if (tx_baud_tick) tx_state_next = TX_DATA0;
            TX_DATA0: if (tx_baud_tick) tx_state_next = TX_DATA1;
            TX_DATA1: if (tx_baud_tick) tx_state_next = TX_DATA2;
            TX_DATA2: if (tx_baud_tick) tx_state_next = TX_DATA3;
            TX_DATA3: if (tx_baud_tick) tx_state_next = TX_DATA4;
            TX_DATA4: if (tx_baud_tick) tx_state_next = TX_DATA5;
            TX_DATA5: if (tx_baud_tick) tx_state_next = TX_DATA6;
            TX_DATA6: if (tx_baud_tick) tx_state_next = TX_DATA7;
            TX_DATA7: if (tx_baud_tick) tx_state_next = TX_STOP;
            TX_STOP: begin
                if (tx_baud_tick) begin
                    tx_state_next = TX_IDLE;
                end
            end
            default: tx_state_next = TX_IDLE;
        endcase
    end

    /** @brief TX shift register and output */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_shift_reg <= 8'hFF;
            uart_tx      <= 1'b1;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    uart_tx <= 1'b1;
                    if (!tx_fifo_empty && ctrl_tx_en) begin
                        tx_shift_reg <= tx_fifo[tx_rd_ptr[FIFO_ADDR_W-1:0]];
                    end
                end
                TX_START: uart_tx <= 1'b0;             // Start bit
                TX_DATA0: uart_tx <= tx_shift_reg[0];
                TX_DATA1: uart_tx <= tx_shift_reg[1];
                TX_DATA2: uart_tx <= tx_shift_reg[2];
                TX_DATA3: uart_tx <= tx_shift_reg[3];
                TX_DATA4: uart_tx <= tx_shift_reg[4];
                TX_DATA5: uart_tx <= tx_shift_reg[5];
                TX_DATA6: uart_tx <= tx_shift_reg[6];
                TX_DATA7: uart_tx <= tx_shift_reg[7];
                TX_STOP:  uart_tx <= 1'b1;             // Stop bit
                default:  uart_tx <= 1'b1;
            endcase
        end
    end

    // =========================================================================
    // RX FSM with 16x Oversampling
    // =========================================================================
    typedef enum logic [3:0] {
        RX_IDLE,
        RX_START_DET,
        RX_SAMPLE0, RX_SAMPLE1, RX_SAMPLE2, RX_SAMPLE3,
        RX_SAMPLE4, RX_SAMPLE5, RX_SAMPLE6, RX_SAMPLE7,
        RX_STOP_CHECK
    } rx_state_t;

    rx_state_t rx_state, rx_state_next;
    logic [31:0] rx_baud_cnt;
    logic        rx_baud_tick;
    logic [3:0]  rx_sample_cnt;   // 16x oversampling counter
    logic [7:0]  rx_shift_reg;
    logic        rx_done;

    // Synchronize uart_rx (double-flop)
    logic uart_rx_sync1, uart_rx_sync2;

    /** @brief RX input synchronizer (metastability protection) */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_rx_sync1 <= 1'b1;
            uart_rx_sync2 <= 1'b1;
        end else begin
            uart_rx_sync1 <= uart_rx;
            uart_rx_sync2 <= uart_rx_sync1;
        end
    end

    /** @brief RX fractional baud rate divider for 16x oversampling
     *  baud_div_r packed: [31:4]=integer part, [3:0]=fractional part (1/16ths)
     *  Example: 217 = int=13, frac=9 → 9 of 16 ticks are 14clk, 7 are 13clk → 217clk/bit */
    logic [3:0]  rx_frac_acc;
    wire  [27:0] baud_int      = baud_div_r[31:4];   // integer part
    wire  [3:0]  baud_frac     = baud_div_r[3:0];    // fractional part (1/16ths)
    wire  [4:0]  rx_frac_sum   = {1'b0, rx_frac_acc} + {1'b0, baud_frac};
    // carry=1: tick period = baud_int+1 clocks, carry=0: baud_int clocks
    wire  [31:0] rx_tick_limit = rx_frac_sum[4] ? {4'b0, baud_int} : ({4'b0, baud_int} - 32'd1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_baud_cnt <= 0;
            rx_frac_acc <= 0;
        end else if (rx_state == RX_IDLE) begin
            rx_baud_cnt <= 0;
            rx_frac_acc <= 0;
        end else if (rx_baud_cnt >= rx_tick_limit) begin
            rx_baud_cnt <= 0;
            rx_frac_acc <= rx_frac_sum[3:0];  // update accumulator (mod 16)
        end else begin
            rx_baud_cnt <= rx_baud_cnt + 1;
        end
    end
    assign rx_baud_tick = (rx_state != RX_IDLE) && (rx_baud_cnt == rx_tick_limit);

    /** @brief RX 16x sample counter */
    // UART RX fix: Reset sample counter on START_DET→SAMPLE0 transition
    // to align mid-point sampling with correct SAMPLEx state.
    // Without this reset, sample_cnt is at 8 when entering SAMPLE0 (from
    // mid-sample at cnt=7), causing bit_done(cnt=15) to fire before
    // mid_sample(cnt=7), shifting all data samples one state late.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sample_cnt <= '0;
        end else if (rx_state == RX_IDLE) begin
            rx_sample_cnt <= '0;
        end else if (rx_state == RX_START_DET && rx_mid_sample && !uart_rx_sync2) begin
            // Valid start bit confirmed: reset counter for data bit 0 alignment
            rx_sample_cnt <= '0;
        end else if (rx_baud_tick) begin
            rx_sample_cnt <= rx_sample_cnt + 1'b1;
        end
    end

    // Mid-point sample (sample at count 7 of 16)
    logic rx_mid_sample;
    assign rx_mid_sample = rx_baud_tick && (rx_sample_cnt == 4'd7);

    // Bit period complete (16 ticks)
    logic rx_bit_done;
    assign rx_bit_done = rx_baud_tick && (rx_sample_cnt == 4'd15);

    /** @brief RX FSM state register */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
        end else begin
            rx_state <= rx_state_next;
        end
    end

    /** @brief RX FSM next state logic */
    always_comb begin
        rx_state_next = rx_state;
        rx_done       = 1'b0;

        case (rx_state)
            RX_IDLE: begin
                if (!uart_rx_sync2 && ctrl_rx_en) begin
                    rx_state_next = RX_START_DET;
                end
            end
            RX_START_DET: begin
                if (rx_mid_sample) begin
                    if (!uart_rx_sync2) begin
                        // Valid start bit confirmed at mid-point
                        rx_state_next = RX_SAMPLE0;
                    end else begin
                        // False start, go back to idle
                        rx_state_next = RX_IDLE;
                    end
                end
            end
            RX_SAMPLE0: if (rx_bit_done) rx_state_next = RX_SAMPLE1;
            RX_SAMPLE1: if (rx_bit_done) rx_state_next = RX_SAMPLE2;
            RX_SAMPLE2: if (rx_bit_done) rx_state_next = RX_SAMPLE3;
            RX_SAMPLE3: if (rx_bit_done) rx_state_next = RX_SAMPLE4;
            RX_SAMPLE4: if (rx_bit_done) rx_state_next = RX_SAMPLE5;
            RX_SAMPLE5: if (rx_bit_done) rx_state_next = RX_SAMPLE6;
            RX_SAMPLE6: if (rx_bit_done) rx_state_next = RX_SAMPLE7;
            RX_SAMPLE7: if (rx_bit_done) rx_state_next = RX_STOP_CHECK;
            RX_STOP_CHECK: begin
                if (rx_mid_sample) begin
                    rx_done       = 1'b1;
                    rx_state_next = RX_IDLE;
                end
            end
            default: rx_state_next = RX_IDLE;
        endcase
    end

    /** @brief RX shift register - samples data at mid-point */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_shift_reg <= '0;
        end else if (rx_mid_sample) begin
            case (rx_state)
                RX_SAMPLE0: rx_shift_reg[0] <= uart_rx_sync2;
                RX_SAMPLE1: rx_shift_reg[1] <= uart_rx_sync2;
                RX_SAMPLE2: rx_shift_reg[2] <= uart_rx_sync2;
                RX_SAMPLE3: rx_shift_reg[3] <= uart_rx_sync2;
                RX_SAMPLE4: rx_shift_reg[4] <= uart_rx_sync2;
                RX_SAMPLE5: rx_shift_reg[5] <= uart_rx_sync2;
                RX_SAMPLE6: rx_shift_reg[6] <= uart_rx_sync2;
                RX_SAMPLE7: rx_shift_reg[7] <= uart_rx_sync2;
                default: ; // No action
            endcase
        end
    end

    // Push received byte into RX FIFO
    assign rx_fifo_push  = rx_done;
    assign rx_fifo_wdata = rx_shift_reg;

    // =========================================================================
    // APB Slave Interface
    // =========================================================================
    logic apb_write_en;
    logic apb_read_en;

    assign apb_write_en = apb_psel && apb_penable && apb_pwrite;
    assign apb_read_en  = apb_psel && apb_penable && !apb_pwrite;
    assign apb_pready   = apb_psel && apb_penable;  // Always ready (no wait states)
    assign apb_pslverr  = 1'b0;                     // No slave errors

    // TX FIFO push on write to TX_DATA
    assign tx_fifo_push = apb_write_en && (apb_paddr == REG_TX_DATA);

    /** @brief APB register write logic */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_tx_ie  <= 1'b0;
            ctrl_rx_ie  <= 1'b0;
            ctrl_tx_en  <= 1'b1;   // TX enabled by default
            ctrl_rx_en  <= 1'b1;   // RX enabled by default
            baud_div_r  <= DEFAULT_BAUD_DIV[31:0];
        end else if (apb_write_en) begin
            case (apb_paddr)
                REG_CTRL: begin
                    ctrl_tx_ie <= apb_pwdata[0];
                    ctrl_rx_ie <= apb_pwdata[1];
                    ctrl_tx_en <= apb_pwdata[2];
                    ctrl_rx_en <= apb_pwdata[3];
                end
                REG_BAUD_DIV: begin
                    baud_div_r <= apb_pwdata;
                end
                default: ; // TX_DATA handled by FIFO push, others are read-only
            endcase
        end
    end

    /** @brief APB register read logic */
    always_comb begin
        apb_prdata = 32'h0;
        rx_fifo_pop = 1'b0;

        if (apb_read_en) begin
            case (apb_paddr)
                REG_TX_DATA: begin
                    apb_prdata = 32'h0; // TX_DATA is write-only
                end
                REG_RX_DATA: begin
                    apb_prdata  = {24'h0, rx_fifo[rx_rd_ptr[FIFO_ADDR_W-1:0]]};
                    rx_fifo_pop = 1'b1;
                end
                REG_STATUS: begin
                    apb_prdata = {27'h0,
                                  tx_busy,       // bit4: TX_BUSY
                                  rx_fifo_empty, // bit3: RX_EMPTY
                                  rx_fifo_full,  // bit2: RX_FULL
                                  tx_fifo_empty, // bit1: TX_EMPTY
                                  tx_fifo_full}; // bit0: TX_FULL
                end
                REG_CTRL: begin
                    apb_prdata = {28'h0, ctrl_rx_en, ctrl_tx_en, ctrl_rx_ie, ctrl_tx_ie};
                end
                REG_BAUD_DIV: begin
                    apb_prdata = baud_div_r;
                end
                default: begin
                    apb_prdata = 32'h0;
                end
            endcase
        end
    end

    // =========================================================================
    // Interrupt Generation
    // =========================================================================
    /** @brief IRQ: asserted when enabled TX empty or RX data available */
    assign irq = (tx_fifo_empty && ctrl_tx_ie) || (!rx_fifo_empty && ctrl_rx_ie);

endmodule : uart_apb
