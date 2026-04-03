// =============================================================================
// VSync - UART APB Testbench
// =============================================================================
// Comprehensive testbench for the uart_apb module.
// Tests APB register access, TX/RX data paths, loopback, FIFO status,
// and interrupt generation.
//
// Simulation:
//   iverilog -g2012 -o sim.vvp tb_uart.sv ../common/*.sv \
//       ../../rtl/core/vsync_pkg.sv ../../rtl/peripherals/uart_apb.sv
//   vvp sim.vvp
//   gtkwave dump.vcd
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

module tb_uart;

    import test_utils::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int CLK_FREQ     = 10_000_000;   // 10 MHz for faster sim
    localparam int DEFAULT_BAUD = 115200;
    localparam int FIFO_DEPTH   = 4;            // Small FIFO for faster test

    localparam real CLK_PERIOD_NS = 100.0;      // 10 MHz => 100 ns period
    localparam int  RST_CYCLES    = 10;

    // Derived timing constants (fractional baud rate divider)
    // baud_div = round(CLK_FREQ / BAUD) = (10M + 57600) / 115200 = 87
    // baud_div IS the clocks-per-bit (no *16 needed)
    localparam int BAUD_DIV          = (CLK_FREQ + DEFAULT_BAUD / 2) / DEFAULT_BAUD;
    localparam int CLKS_PER_BIT      = BAUD_DIV;
    // Full 8N1 frame: 1 start + 8 data + 1 stop = 10 bits
    localparam int CLKS_PER_FRAME    = CLKS_PER_BIT * 10;

    // Register address offsets
    localparam logic [7:0] REG_TX_DATA  = 8'h00;
    localparam logic [7:0] REG_RX_DATA  = 8'h04;
    localparam logic [7:0] REG_STATUS   = 8'h08;
    localparam logic [7:0] REG_CTRL     = 8'h0C;
    localparam logic [7:0] REG_BAUD_DIV = 8'h10;

    // Status register bit positions
    localparam int STATUS_TX_FULL  = 0;
    localparam int STATUS_TX_EMPTY = 1;
    localparam int STATUS_RX_FULL  = 2;
    localparam int STATUS_RX_EMPTY = 3;
    localparam int STATUS_TX_BUSY  = 4;

    // Control register bit positions
    localparam int CTRL_TX_IE = 0;
    localparam int CTRL_RX_IE = 1;
    localparam int CTRL_TX_EN = 2;
    localparam int CTRL_RX_EN = 3;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // APB interface
    logic        apb_psel;
    logic        apb_penable;
    logic        apb_pwrite;
    logic [7:0]  apb_paddr;
    logic [31:0] apb_pwdata;
    logic [31:0] apb_prdata;
    logic        apb_pready;
    logic        apb_pslverr;

    // UART signals
    logic        uart_rx;
    logic        uart_tx;
    logic        irq;

    // Loopback wire: connect TX output back to RX input
    logic        loopback_en;
    logic        uart_rx_drive;   // Externally driven RX stimulus

    // When loopback is enabled, uart_rx follows uart_tx;
    // otherwise, uart_rx follows the external stimulus driver.
    assign uart_rx = loopback_en ? uart_tx : uart_rx_drive;

    // =========================================================================
    // Clock and Reset Generation
    // =========================================================================
    clk_rst_gen #(
        .CLK_PERIOD_NS (CLK_PERIOD_NS),
        .RST_CYCLES    (RST_CYCLES)
    ) u_clk_rst (
        .clk       (clk),
        .rst       (rst),
        .rst_n     (rst_n),
        .init_done (init_done)
    );

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    uart_apb #(
        .CLK_FREQ     (CLK_FREQ),
        .DEFAULT_BAUD (DEFAULT_BAUD),
        .FIFO_DEPTH   (FIFO_DEPTH)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .apb_psel     (apb_psel),
        .apb_penable  (apb_penable),
        .apb_pwrite   (apb_pwrite),
        .apb_paddr    (apb_paddr),
        .apb_pwdata   (apb_pwdata),
        .apb_prdata   (apb_prdata),
        .apb_pready   (apb_pready),
        .apb_pslverr  (apb_pslverr),
        .uart_rx      (uart_rx),
        .uart_tx      (uart_tx),
        .irq          (irq)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_uart);
    end

    // =========================================================================
    // Timeout Watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD_NS * 500000);
        $display("ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded maximum time");
    end

    // =========================================================================
    // Signal Initialization
    // =========================================================================
    initial begin
        apb_psel     = 1'b0;
        apb_penable  = 1'b0;
        apb_pwrite   = 1'b0;
        apb_paddr    = 8'h0;
        apb_pwdata   = 32'h0;
        uart_rx_drive = 1'b1;   // Idle high
        loopback_en  = 1'b0;
    end

    // =========================================================================
    // APB Helper Tasks
    // =========================================================================

    // APB write transaction (2-cycle protocol: setup + access)
    task automatic apb_write(input logic [7:0] addr, input logic [31:0] wdata);
        // Setup phase
        @(posedge clk);
        apb_psel    <= 1'b1;
        apb_penable <= 1'b0;
        apb_pwrite  <= 1'b1;
        apb_paddr   <= addr;
        apb_pwdata  <= wdata;

        // Access phase
        @(posedge clk);
        apb_penable <= 1'b1;

        // Wait for ready
        @(posedge clk);
        apb_psel    <= 1'b0;
        apb_penable <= 1'b0;
        apb_pwrite  <= 1'b0;
    endtask

    // APB read transaction (2-cycle protocol: setup + access)
    task automatic apb_read(input logic [7:0] addr, output logic [31:0] rdata);
        // Setup phase
        @(posedge clk);
        apb_psel    <= 1'b1;
        apb_penable <= 1'b0;
        apb_pwrite  <= 1'b0;
        apb_paddr   <= addr;

        // Access phase
        @(posedge clk);
        apb_penable <= 1'b1;

        // Capture read data at the end of access phase
        @(posedge clk);
        rdata = apb_prdata;
        apb_psel    <= 1'b0;
        apb_penable <= 1'b0;
    endtask

    // =========================================================================
    // UART RX Stimulus Task
    // =========================================================================
    // Drives uart_rx_drive with a full 8N1 frame at the configured baud rate.
    // bit_period is in clock cycles: CLKS_PER_BIT
    task automatic uart_send_byte(input logic [7:0] data);
        integer i;

        // Start bit (low)
        uart_rx_drive <= 1'b0;
        repeat (CLKS_PER_BIT) @(posedge clk);

        // Data bits (LSB first)
        for (i = 0; i < 8; i++) begin
            uart_rx_drive <= data[i];
            repeat (CLKS_PER_BIT) @(posedge clk);
        end

        // Stop bit (high)
        uart_rx_drive <= 1'b1;
        repeat (CLKS_PER_BIT) @(posedge clk);
    endtask

    // =========================================================================
    // UART TX Capture Task
    // =========================================================================
    // Monitors uart_tx and captures a full 8N1 frame.
    // Waits for the start bit falling edge, samples each data bit at mid-bit,
    // and returns the received byte.
    task automatic uart_capture_tx(output logic [7:0] data);
        integer i;

        // Wait for start bit (falling edge on uart_tx)
        @(negedge uart_tx);

        // Advance to the middle of the start bit
        repeat (CLKS_PER_BIT / 2) @(posedge clk);

        // Verify start bit is still low
        if (uart_tx !== 1'b0) begin
            $display("WARNING: Start bit not stable at mid-point");
        end

        // Sample each data bit at the middle of the bit period
        for (i = 0; i < 8; i++) begin
            repeat (CLKS_PER_BIT) @(posedge clk);
            data[i] = uart_tx;
        end

        // Advance to middle of stop bit and verify
        repeat (CLKS_PER_BIT) @(posedge clk);
        if (uart_tx !== 1'b1) begin
            $display("WARNING: Stop bit not high");
        end

        // Wait for stop bit to finish
        repeat (CLKS_PER_BIT / 2) @(posedge clk);
    endtask

    // =========================================================================
    // Convenience: wait for TX to become idle (not busy)
    // =========================================================================
    task automatic wait_tx_idle();
        logic [31:0] status;
        int timeout;
        logic done;
        timeout = 0;
        done = 0;
        while (!done) begin
            apb_read(REG_STATUS, status);
            if (!status[STATUS_TX_BUSY] && status[STATUS_TX_EMPTY])
                done = 1;
            else begin
                timeout++;
                if (timeout > CLKS_PER_FRAME * 4) begin
                    $display("WARNING: wait_tx_idle timeout");
                    done = 1;
                end
            end
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        @(posedge init_done);
        repeat (5) @(posedge clk);

        test_main();

        test_finish();
    end

    // =========================================================================
    // Test Cases
    // =========================================================================
    task automatic test_main();

        test_suite_begin("UART APB Test Suite");

        test_reg_read_write();
        test_tx_single_byte();
        test_rx_single_byte();
        test_loopback();
        test_tx_fifo_full();
        test_rx_fifo_empty();
        test_status_register();
        test_irq_tx_empty();
        test_irq_rx_data();

    endtask

    // -------------------------------------------------------------------------
    // Test 1: Register Read/Write (CTRL, BAUD_DIV)
    // -------------------------------------------------------------------------
    task automatic test_reg_read_write();
        logic [31:0] rdata;

        test_begin("Register Read/Write");

        // -- Read default CTRL: TX_EN=1 (bit2), RX_EN=1 (bit3), IE bits=0
        // Default CTRL = 4'b1100 = 0x0C
        apb_read(REG_CTRL, rdata);
        check_eq(rdata, 32'h0000_000C, "CTRL default value (TX_EN=1, RX_EN=1)");

        // -- Write a new CTRL value: TX_IE=1, RX_IE=1, TX_EN=1, RX_EN=1 => 0x0F
        apb_write(REG_CTRL, 32'h0000_000F);
        apb_read(REG_CTRL, rdata);
        check_eq(rdata, 32'h0000_000F, "CTRL write-back (all bits set)");

        // -- Restore CTRL to defaults (TX_EN=1, RX_EN=1, IEs off)
        apb_write(REG_CTRL, 32'h0000_000C);
        apb_read(REG_CTRL, rdata);
        check_eq(rdata, 32'h0000_000C, "CTRL restored to defaults");

        // -- Read default BAUD_DIV
        apb_read(REG_BAUD_DIV, rdata);
        check_eq(rdata, BAUD_DIV[31:0], "BAUD_DIV default value");

        // -- Write a custom baud divisor and read back
        apb_write(REG_BAUD_DIV, 32'h0000_00AA);
        apb_read(REG_BAUD_DIV, rdata);
        check_eq(rdata, 32'h0000_00AA, "BAUD_DIV custom write-back");

        // -- Restore original baud divisor
        apb_write(REG_BAUD_DIV, BAUD_DIV[31:0]);
        apb_read(REG_BAUD_DIV, rdata);
        check_eq(rdata, BAUD_DIV[31:0], "BAUD_DIV restored to default");

    endtask

    // -------------------------------------------------------------------------
    // Test 2: TX Single Byte - write to TX_DATA, verify waveform
    // -------------------------------------------------------------------------
    task automatic test_tx_single_byte();
        logic [7:0] tx_byte;
        logic [7:0] captured;

        test_begin("TX Single Byte");

        loopback_en <= 1'b0;
        uart_rx_drive <= 1'b1;

        tx_byte = 8'hA5;

        // Ensure TX is enabled (default) and FIFO is empty
        wait_tx_idle();

        // Write byte to TX_DATA - this pushes into the TX FIFO
        apb_write(REG_TX_DATA, {24'h0, tx_byte});

        // Capture the transmitted byte by monitoring uart_tx
        uart_capture_tx(captured);

        check_eq({24'h0, captured}, {24'h0, tx_byte}, "TX waveform byte match");

        // Wait for transmitter to return to idle
        wait_tx_idle();

    endtask

    // -------------------------------------------------------------------------
    // Test 3: RX Single Byte - drive uart_rx, read from RX_DATA
    // -------------------------------------------------------------------------
    task automatic test_rx_single_byte();
        logic [7:0] rx_byte;
        logic [31:0] rdata;
        logic [31:0] status;
        int timeout;

        test_begin("RX Single Byte");

        loopback_en <= 1'b0;
        uart_rx_drive <= 1'b1;
        rx_byte = 8'h3C;

        // Allow a few idle cycles
        repeat (10) @(posedge clk);

        // Send a byte into the RX path
        uart_send_byte(rx_byte);

        // Wait for the RX FSM to complete and data to appear in FIFO.
        // The RX uses 16x oversampling, so after the frame plus some margin
        // the byte should be in the FIFO.
        // Additional margin for the double-flop synchronizer (2 cycles)
        // and the stop-bit mid-sample completion.
        repeat (CLKS_PER_BIT * 2) @(posedge clk);

        // Poll status until RX_EMPTY clears (data available)
        timeout = 0;
        begin
            logic poll_done;
            logic timed_out;
            poll_done = 0;
            timed_out = 0;
            while (!poll_done) begin
                apb_read(REG_STATUS, status);
                if (!status[STATUS_RX_EMPTY])
                    poll_done = 1;
                else begin
                    timeout++;
                    if (timeout > 100) begin
                        test_fail("RX data did not appear in FIFO (timeout)");
                        poll_done = 1;
                        timed_out = 1;
                    end
                end
            end

            if (!timed_out) begin
                // Read the received byte
                apb_read(REG_RX_DATA, rdata);
                begin
                    logic [31:0] actual_val;
                    logic [31:0] expected_val;
                    actual_val = {24'h0, rdata[7:0]};
                    expected_val = {24'h0, rx_byte};
                    check_eq(actual_val, expected_val, "RX data byte match");
                end
            end
        end

    endtask

    // -------------------------------------------------------------------------
    // Test 4: Loopback Test - TX a byte, capture on RX
    // -------------------------------------------------------------------------
    task automatic test_loopback();
        logic [7:0] lb_byte;
        logic [31:0] rdata;
        logic [31:0] status;
        int timeout;

        test_begin("Loopback Test");

        // Enable loopback: uart_tx feeds directly into uart_rx
        loopback_en <= 1'b1;
        repeat (5) @(posedge clk);

        lb_byte = 8'h5A;

        // Ensure TX is idle
        wait_tx_idle();

        // Write byte to TX_DATA
        apb_write(REG_TX_DATA, {24'h0, lb_byte});

        // Wait for the full frame to transmit and loop back through RX.
        // TX frame duration + RX frame duration (overlapped in loopback,
        // but RX needs to complete its own 16x oversampling).
        // Allow generous margin.
        repeat (CLKS_PER_FRAME + CLKS_PER_BIT * 4) @(posedge clk);

        // Poll for RX data available
        timeout = 0;
        begin
            logic poll_done;
            logic timed_out;
            poll_done = 0;
            timed_out = 0;
            while (!poll_done) begin
                apb_read(REG_STATUS, status);
                if (!status[STATUS_RX_EMPTY])
                    poll_done = 1;
                else begin
                    timeout++;
                    if (timeout > 200) begin
                        test_fail("Loopback RX data did not arrive (timeout)");
                        poll_done = 1;
                        timed_out = 1;
                    end
                end
            end

            if (!timed_out) begin
                // Read the looped-back byte
                apb_read(REG_RX_DATA, rdata);
                begin
                    logic [31:0] actual_val;
                    logic [31:0] expected_val;
                    actual_val = {24'h0, rdata[7:0]};
                    expected_val = {24'h0, lb_byte};
                    check_eq(actual_val, expected_val, "Loopback data match");
                end
            end
        end

        // Disable loopback
        loopback_en <= 1'b0;
        uart_rx_drive <= 1'b1;
        repeat (5) @(posedge clk);

    endtask

    // -------------------------------------------------------------------------
    // Test 5: TX FIFO Full Detection
    // -------------------------------------------------------------------------
    task automatic test_tx_fifo_full();
        logic [31:0] status;
        int i;

        test_begin("TX FIFO Full Detection");

        // Disable TX so bytes stay in the FIFO and don't drain
        apb_write(REG_CTRL, 32'h0000_0008);  // RX_EN=1, TX_EN=0, IEs=0
        repeat (5) @(posedge clk);

        // Fill the TX FIFO to capacity
        for (i = 0; i < FIFO_DEPTH; i++) begin
            apb_write(REG_TX_DATA, {24'h0, 8'(i)});
        end

        // Check that TX_FULL is asserted
        apb_read(REG_STATUS, status);
        check(status[STATUS_TX_FULL] === 1'b1, "TX_FULL asserted after filling FIFO");
        check(status[STATUS_TX_EMPTY] === 1'b0, "TX_EMPTY deasserted when FIFO is full");

        // Write one more byte (should be ignored since FIFO is full)
        apb_write(REG_TX_DATA, 32'h0000_00FF);

        // TX_FULL should still be asserted
        apb_read(REG_STATUS, status);
        check(status[STATUS_TX_FULL] === 1'b1, "TX_FULL still asserted after overflow write");

        // Re-enable TX so the FIFO drains for subsequent tests
        apb_write(REG_CTRL, 32'h0000_000C);  // TX_EN=1, RX_EN=1

        // Wait for FIFO to drain completely
        wait_tx_idle();

    endtask

    // -------------------------------------------------------------------------
    // Test 6: RX FIFO Empty Detection
    // -------------------------------------------------------------------------
    task automatic test_rx_fifo_empty();
        logic [31:0] status;
        logic [31:0] rdata;

        test_begin("RX FIFO Empty Detection");

        loopback_en <= 1'b0;
        uart_rx_drive <= 1'b1;

        // At this point the RX FIFO should be empty (we've read everything)
        apb_read(REG_STATUS, status);
        check(status[STATUS_RX_EMPTY] === 1'b1, "RX_EMPTY asserted when FIFO is empty");
        check(status[STATUS_RX_FULL] === 1'b0, "RX_FULL deasserted when FIFO is empty");

        // Reading from an empty RX FIFO should return stale/zero data without error
        // (apb_pslverr is always 0 in this design)
        apb_read(REG_RX_DATA, rdata);
        // Just verify no hang occurred; the value is undefined but should not cause errors
        check(apb_pslverr === 1'b0, "No slave error on empty RX FIFO read");

    endtask

    // -------------------------------------------------------------------------
    // Test 7: Status Register Checks
    // -------------------------------------------------------------------------
    task automatic test_status_register();
        logic [31:0] status;

        test_begin("Status Register Checks");

        loopback_en <= 1'b0;
        uart_rx_drive <= 1'b1;

        // After all previous tests have drained, TX should be idle and empty
        wait_tx_idle();

        apb_read(REG_STATUS, status);
        check(status[STATUS_TX_EMPTY] === 1'b1, "TX_EMPTY when idle");
        check(status[STATUS_TX_FULL] === 1'b0, "TX_FULL deasserted when idle");
        check(status[STATUS_RX_EMPTY] === 1'b1, "RX_EMPTY when no data received");
        check(status[STATUS_TX_BUSY] === 1'b0, "TX_BUSY deasserted when idle");

        // Write a byte and immediately check TX_BUSY / TX_EMPTY
        apb_write(REG_TX_DATA, 32'h0000_0042);

        // Give a few cycles for the TX FSM to start
        repeat (5) @(posedge clk);

        apb_read(REG_STATUS, status);
        // TX FSM should have popped the byte and started transmitting
        check(status[STATUS_TX_BUSY] === 1'b1, "TX_BUSY asserted during transmission");

        // Wait for transmission to complete
        wait_tx_idle();

        apb_read(REG_STATUS, status);
        check(status[STATUS_TX_BUSY] === 1'b0, "TX_BUSY deasserted after completion");
        check(status[STATUS_TX_EMPTY] === 1'b1, "TX_EMPTY after transmission complete");

    endtask

    // -------------------------------------------------------------------------
    // Test 8: IRQ Generation - TX Empty with TX_IE
    // -------------------------------------------------------------------------
    task automatic test_irq_tx_empty();
        logic [31:0] status;

        test_begin("IRQ - TX Empty with TX_IE");

        loopback_en <= 1'b0;
        uart_rx_drive <= 1'b1;

        // Ensure TX FIFO is empty and idle
        wait_tx_idle();

        // Initially, TX_IE is disabled, so IRQ should be low
        apb_write(REG_CTRL, 32'h0000_000C);  // TX_EN=1, RX_EN=1, IEs=0
        repeat (3) @(posedge clk);
        check(irq === 1'b0, "IRQ deasserted when TX_IE=0");

        // Enable TX_IE. Since TX FIFO is empty, IRQ should assert immediately.
        // CTRL: TX_IE=1, RX_IE=0, TX_EN=1, RX_EN=1 => 0x0D
        apb_write(REG_CTRL, 32'h0000_000D);
        repeat (3) @(posedge clk);
        check(irq === 1'b1, "IRQ asserted when TX_IE=1 and TX FIFO empty");

        // Write a byte to TX FIFO so it is no longer empty
        apb_write(REG_TX_DATA, 32'h0000_0055);
        repeat (3) @(posedge clk);

        // TX FIFO is not empty now (byte may be in-flight or still in FIFO),
        // but the FSM pops immediately so it may already be empty again.
        // Instead, disable TX first so the byte stays in FIFO.
        // Re-do: disable TX, then write.
        apb_write(REG_CTRL, 32'h0000_0009);  // TX_IE=1, RX_EN=1, TX_EN=0, RX_IE=0
        repeat (3) @(posedge clk);

        // Wait for any in-flight TX to complete
        repeat (CLKS_PER_FRAME + 50) @(posedge clk);

        apb_write(REG_TX_DATA, 32'h0000_0055);
        repeat (3) @(posedge clk);

        // TX FIFO has data but TX is disabled, so tx_fifo_empty=0 => IRQ should deassert
        check(irq === 1'b0, "IRQ deasserted when TX FIFO not empty (TX_IE=1)");

        // Re-enable TX to drain, then IRQ should re-assert after FIFO empties
        apb_write(REG_CTRL, 32'h0000_000D);  // TX_IE=1, TX_EN=1, RX_EN=1
        wait_tx_idle();
        repeat (3) @(posedge clk);
        check(irq === 1'b1, "IRQ re-asserted after TX FIFO drained");

        // Disable TX_IE to clean up
        apb_write(REG_CTRL, 32'h0000_000C);
        repeat (3) @(posedge clk);
        check(irq === 1'b0, "IRQ deasserted after disabling TX_IE");

    endtask

    // -------------------------------------------------------------------------
    // Test 9: IRQ Generation - RX Data Available with RX_IE
    // -------------------------------------------------------------------------
    task automatic test_irq_rx_data();
        logic [31:0] rdata;
        logic [31:0] status;
        int timeout;

        test_begin("IRQ - RX Data Available with RX_IE");

        loopback_en <= 1'b0;
        uart_rx_drive <= 1'b1;

        // Enable RX_IE: CTRL = TX_EN=1, RX_EN=1, RX_IE=1, TX_IE=0 => 0x0E
        apb_write(REG_CTRL, 32'h0000_000E);
        repeat (3) @(posedge clk);

        // RX FIFO should be empty, so IRQ should be low
        check(irq === 1'b0, "IRQ deasserted when RX FIFO empty (RX_IE=1)");

        // Send a byte into the RX path
        uart_send_byte(8'hBE);

        // Wait for the byte to be received
        repeat (CLKS_PER_BIT * 3) @(posedge clk);

        // Poll for data arrival
        timeout = 0;
        begin
            logic poll_done;
            logic timed_out;
            poll_done = 0;
            timed_out = 0;
            while (!poll_done) begin
                apb_read(REG_STATUS, status);
                if (!status[STATUS_RX_EMPTY])
                    poll_done = 1;
                else begin
                    timeout++;
                    if (timeout > 200) begin
                        test_fail("RX byte did not arrive for IRQ test (timeout)");
                        apb_write(REG_CTRL, 32'h0000_000C);
                        poll_done = 1;
                        timed_out = 1;
                    end
                end
            end

            if (!timed_out) begin
                // IRQ should now be asserted (RX FIFO not empty and RX_IE=1)
                check(irq === 1'b1, "IRQ asserted when RX data available (RX_IE=1)");

                // Read the byte to empty the FIFO
                apb_read(REG_RX_DATA, rdata);
                begin
                    logic [31:0] actual_val;
                    actual_val = {24'h0, rdata[7:0]};
                    check_eq(actual_val, 32'h0000_00BE, "RX data correct in IRQ test");
                end

                // After reading, RX FIFO should be empty again, IRQ should deassert
                repeat (3) @(posedge clk);
                check(irq === 1'b0, "IRQ deasserted after reading RX data");
            end
        end

        // Disable RX_IE to clean up
        apb_write(REG_CTRL, 32'h0000_000C);
        repeat (3) @(posedge clk);

    endtask

endmodule : tb_uart
