// =============================================================================
// VSync - GPIO APB Controller Testbench
// =============================================================================
// Comprehensive testbench for the gpio_apb module.
// Tests output drive, input read, direction control, edge/level interrupts,
// interrupt clear (W1C), interrupt masking, and individual pin control.
//
// Uses GPIO_WIDTH=8 for simpler testing.
// =============================================================================

`timescale 1ns / 1ps

`include "../common/test_utils.sv"

import vsync_pkg::*;

module tb_gpio;

    import test_utils::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam int CLK_PERIOD  = 10;     // 100MHz clock
    localparam int RST_CYCLES  = 10;     // Reset duration
    localparam int GPIO_WIDTH  = 8;      // Narrower width for testing

    // Register address offsets
    localparam logic [7:0] REG_GPIO_OUT        = 8'h00;
    localparam logic [7:0] REG_GPIO_IN         = 8'h04;
    localparam logic [7:0] REG_GPIO_DIR        = 8'h08;
    localparam logic [7:0] REG_GPIO_INT_EN     = 8'h0C;
    localparam logic [7:0] REG_GPIO_INT_STATUS = 8'h10;
    localparam logic [7:0] REG_GPIO_INT_TYPE   = 8'h14;
    localparam logic [7:0] REG_GPIO_INT_POL    = 8'h18;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst;
    logic        rst_n;
    logic        init_done;

    // APB signals
    logic        apb_psel;
    logic        apb_penable;
    logic        apb_pwrite;
    logic [7:0]  apb_paddr;
    logic [31:0] apb_pwdata;
    logic [31:0] apb_prdata;
    logic        apb_pready;
    logic        apb_pslverr;

    // GPIO signals
    logic [GPIO_WIDTH-1:0] gpio_in;
    logic [GPIO_WIDTH-1:0] gpio_out;
    logic [GPIO_WIDTH-1:0] gpio_oe;
    logic                  irq;

    // =========================================================================
    // Clock and Reset Generation
    // =========================================================================
    clk_rst_gen #(
        .CLK_PERIOD_NS (CLK_PERIOD),
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
    gpio_apb #(
        .GPIO_WIDTH (GPIO_WIDTH)
    ) u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .apb_psel    (apb_psel),
        .apb_penable (apb_penable),
        .apb_pwrite  (apb_pwrite),
        .apb_paddr   (apb_paddr),
        .apb_pwdata  (apb_pwdata),
        .apb_prdata  (apb_prdata),
        .apb_pready  (apb_pready),
        .apb_pslverr (apb_pslverr),
        .gpio_in     (gpio_in),
        .gpio_out    (gpio_out),
        .gpio_oe     (gpio_oe),
        .irq         (irq)
    );

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_gpio.vcd");
        $dumpvars(0, tb_gpio);
    end

    // =========================================================================
    // Timeout Watchdog
    // =========================================================================
    initial begin
        #(CLK_PERIOD * 100000);
        $display("ERROR: Simulation timeout!");
        $fatal(1, "Simulation exceeded maximum time");
    end

    // =========================================================================
    // APB Bus Idle Initialization
    // =========================================================================
    initial begin
        apb_psel    = 1'b0;
        apb_penable = 1'b0;
        apb_pwrite  = 1'b0;
        apb_paddr   = 8'h00;
        apb_pwdata  = 32'h0;
        gpio_in     = '0;
    end

    // =========================================================================
    // APB Transaction Tasks
    // =========================================================================

    // APB write transaction (2-cycle protocol: setup + access)
    task automatic apb_write(
        input logic [7:0]  addr,
        input logic [31:0] data
    );
        // Setup phase
        @(posedge clk);
        apb_paddr   <= addr;
        apb_psel    <= 1'b1;
        apb_penable <= 1'b0;
        apb_pwrite  <= 1'b1;
        apb_pwdata  <= data;

        // Access phase
        @(posedge clk);
        apb_penable <= 1'b1;

        // Wait for PREADY
        while (!apb_pready) @(posedge clk);

        // Return to idle
        apb_psel    <= 1'b0;
        apb_penable <= 1'b0;
        apb_pwrite  <= 1'b0;
    endtask

    // APB read transaction
    task automatic apb_read(
        input  logic [7:0]  addr,
        output logic [31:0] data
    );
        // Setup phase
        @(posedge clk);
        apb_paddr   <= addr;
        apb_psel    <= 1'b1;
        apb_penable <= 1'b0;
        apb_pwrite  <= 1'b0;

        // Access phase
        @(posedge clk);
        apb_penable <= 1'b1;

        // Wait for PREADY
        while (!apb_pready) @(posedge clk);
        data = apb_prdata;

        // Return to idle
        apb_psel    <= 1'b0;
        apb_penable <= 1'b0;
    endtask

    // Wait for N clock cycles
    task automatic wait_clocks(int n);
        repeat (n) @(posedge clk);
    endtask

    // Wait enough cycles for gpio_in to propagate through the double-flop
    // synchronizer and become stable in gpio_in_sync2. The DUT has:
    //   cycle 1: gpio_in -> gpio_in_sync1
    //   cycle 2: gpio_in_sync1 -> gpio_in_sync2 (readable value)
    //   cycle 3: gpio_in_sync2 -> gpio_in_prev (edge detection reference)
    // We wait 4 cycles to be safe.
    task automatic wait_sync();
        wait_clocks(4);
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        @(posedge init_done);
        wait_clocks(5);

        test_main();
        test_finish();
    end

    // =========================================================================
    // Test Dispatcher
    // =========================================================================
    task automatic test_main();

        test_suite_begin("GPIO APB Controller Tests");

        test_output_drive();
        test_input_read();
        test_direction_control();
        test_rising_edge_interrupt();
        test_falling_edge_interrupt();
        test_level_high_interrupt();
        test_interrupt_clear();
        test_interrupt_mask();
        test_individual_pin_control();

    endtask

    // =========================================================================
    // Test 1: Output Drive
    // =========================================================================
    // Set DIR to output (1), write GPIO_OUT, verify gpio_out pins reflect
    // the written value.
    // =========================================================================
    task automatic test_output_drive();
        logic [31:0] rdata;

        test_begin("Output Drive");

        // Set all 8 pins as outputs
        apb_write(REG_GPIO_DIR, 32'h0000_00FF);
        wait_clocks(1);

        // Verify gpio_oe reflects direction register
        `ASSERT_EQ({24'h0, gpio_oe}, 32'h0000_00FF, "gpio_oe should be 0xFF for all outputs");

        // Write a known pattern to GPIO_OUT
        apb_write(REG_GPIO_OUT, 32'h0000_00A5);
        wait_clocks(1);

        // Verify gpio_out pins
        `ASSERT_EQ({24'h0, gpio_out}, 32'h0000_00A5, "gpio_out should be 0xA5");

        // Read back GPIO_OUT register
        apb_read(REG_GPIO_OUT, rdata);
        `ASSERT_EQ(rdata, 32'h0000_00A5, "GPIO_OUT readback should be 0xA5");

        // Write another pattern
        apb_write(REG_GPIO_OUT, 32'h0000_005A);
        wait_clocks(1);
        `ASSERT_EQ({24'h0, gpio_out}, 32'h0000_005A, "gpio_out should be 0x5A");

        // Write all zeros
        apb_write(REG_GPIO_OUT, 32'h0000_0000);
        wait_clocks(1);
        `ASSERT_EQ({24'h0, gpio_out}, 32'h0000_0000, "gpio_out should be 0x00");

        // Write all ones
        apb_write(REG_GPIO_OUT, 32'h0000_00FF);
        wait_clocks(1);
        `ASSERT_EQ({24'h0, gpio_out}, 32'h0000_00FF, "gpio_out should be 0xFF");

        // Clean up
        apb_write(REG_GPIO_OUT, 32'h0);
        apb_write(REG_GPIO_DIR, 32'h0);
        wait_clocks(2);
    endtask

    // =========================================================================
    // Test 2: Input Read
    // =========================================================================
    // Set DIR to input (0), drive gpio_in externally, read GPIO_IN register
    // and verify the value matches (after synchronizer latency).
    // =========================================================================
    task automatic test_input_read();
        logic [31:0] rdata;

        test_begin("Input Read");

        // Ensure all pins are inputs (DIR=0 is default after reset)
        apb_write(REG_GPIO_DIR, 32'h0);
        wait_clocks(1);

        // Drive gpio_in with a pattern
        gpio_in = 8'hC3;
        wait_sync();   // Wait for double-flop synchronizer

        // Read GPIO_IN register
        apb_read(REG_GPIO_IN, rdata);
        `ASSERT_EQ(rdata, 32'h0000_00C3, "GPIO_IN should read 0xC3");

        // Change input pattern
        gpio_in = 8'h3C;
        wait_sync();

        apb_read(REG_GPIO_IN, rdata);
        `ASSERT_EQ(rdata, 32'h0000_003C, "GPIO_IN should read 0x3C");

        // All zeros
        gpio_in = 8'h00;
        wait_sync();

        apb_read(REG_GPIO_IN, rdata);
        `ASSERT_EQ(rdata, 32'h0000_0000, "GPIO_IN should read 0x00");

        // All ones
        gpio_in = 8'hFF;
        wait_sync();

        apb_read(REG_GPIO_IN, rdata);
        `ASSERT_EQ(rdata, 32'h0000_00FF, "GPIO_IN should read 0xFF");

        // Clean up
        gpio_in = 8'h00;
        wait_clocks(2);
    endtask

    // =========================================================================
    // Test 3: Direction Control
    // =========================================================================
    // Verify that gpio_oe correctly reflects the DIR register. Each bit in
    // DIR individually controls whether the corresponding pin is an output.
    // =========================================================================
    task automatic test_direction_control();
        logic [31:0] rdata;

        test_begin("Direction Control");

        // All inputs
        apb_write(REG_GPIO_DIR, 32'h0);
        wait_clocks(1);
        `ASSERT_EQ({24'h0, gpio_oe}, 32'h0000_0000, "gpio_oe should be 0x00 (all inputs)");

        // All outputs
        apb_write(REG_GPIO_DIR, 32'h0000_00FF);
        wait_clocks(1);
        `ASSERT_EQ({24'h0, gpio_oe}, 32'h0000_00FF, "gpio_oe should be 0xFF (all outputs)");

        // Alternating pattern
        apb_write(REG_GPIO_DIR, 32'h0000_00AA);
        wait_clocks(1);
        `ASSERT_EQ({24'h0, gpio_oe}, 32'h0000_00AA, "gpio_oe should be 0xAA (alternating)");

        // Read DIR register back
        apb_read(REG_GPIO_DIR, rdata);
        `ASSERT_EQ(rdata, 32'h0000_00AA, "DIR readback should be 0xAA");

        // Single pin as output
        apb_write(REG_GPIO_DIR, 32'h0000_0001);
        wait_clocks(1);
        `ASSERT_EQ({24'h0, gpio_oe}, 32'h0000_0001, "gpio_oe should be 0x01 (pin 0 output)");

        // Clean up
        apb_write(REG_GPIO_DIR, 32'h0);
        wait_clocks(2);
    endtask

    // =========================================================================
    // Test 4: Rising Edge Interrupt
    // =========================================================================
    // Configure INT_TYPE=edge (1), INT_POL=rising (1), INT_EN=enabled.
    // Toggle gpio_in from low to high and verify INT_STATUS is set and
    // irq is asserted.
    // =========================================================================
    task automatic test_rising_edge_interrupt();
        logic [31:0] rdata;

        test_begin("Rising Edge Interrupt");

        // Ensure gpio_in is low and stable before configuring
        gpio_in = 8'h00;
        wait_sync();

        // Configure pin 0 for rising-edge interrupt
        apb_write(REG_GPIO_INT_TYPE, 32'h0000_0001);  // Pin 0: edge-triggered
        apb_write(REG_GPIO_INT_POL,  32'h0000_0001);  // Pin 0: rising edge
        apb_write(REG_GPIO_INT_EN,   32'h0000_0001);  // Pin 0: interrupt enabled

        // Clear any pending interrupts
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_00FF);
        wait_clocks(2);

        // Verify irq is deasserted
        `ASSERT_TRUE(irq === 1'b0, "IRQ should be deasserted before edge");

        // Create a rising edge on pin 0
        gpio_in = 8'h01;
        wait_sync();
        // After sync, the edge should have been detected
        // Need one more cycle for int_status_r to latch (it updates every clk)
        wait_clocks(1);

        // Check INT_STATUS
        apb_read(REG_GPIO_INT_STATUS, rdata);
        `ASSERT_TRUE(rdata[0] === 1'b1, "INT_STATUS[0] should be set on rising edge");

        // Check irq is asserted
        `ASSERT_TRUE(irq === 1'b1, "IRQ should be asserted after rising edge");

        // Verify no interrupt on other pins
        `ASSERT_TRUE(rdata[7:1] === 7'b0, "INT_STATUS[7:1] should be clear");

        // Clean up: clear interrupts, disable, reset gpio_in
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_00FF);
        apb_write(REG_GPIO_INT_EN,     32'h0);
        apb_write(REG_GPIO_INT_TYPE,   32'h0);
        apb_write(REG_GPIO_INT_POL,    32'h0);
        gpio_in = 8'h00;
        wait_sync();
    endtask

    // =========================================================================
    // Test 5: Falling Edge Interrupt
    // =========================================================================
    // Configure INT_TYPE=edge (1), INT_POL=falling (0), INT_EN=enabled.
    // Toggle gpio_in from high to low and verify INT_STATUS is set and
    // irq is asserted.
    // =========================================================================
    task automatic test_falling_edge_interrupt();
        logic [31:0] rdata;

        test_begin("Falling Edge Interrupt");

        // Start with gpio_in high and let it stabilize through synchronizer
        gpio_in = 8'h04;  // Pin 2 high
        wait_sync();

        // Configure pin 2 for falling-edge interrupt
        apb_write(REG_GPIO_INT_TYPE, 32'h0000_0004);  // Pin 2: edge-triggered
        apb_write(REG_GPIO_INT_POL,  32'h0000_0000);  // Pin 2: falling edge (pol=0)
        apb_write(REG_GPIO_INT_EN,   32'h0000_0004);  // Pin 2: enabled

        // Clear any pending interrupts
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_00FF);
        wait_clocks(2);

        // Verify irq is deasserted
        `ASSERT_TRUE(irq === 1'b0, "IRQ should be deasserted before falling edge");

        // Create a falling edge on pin 2
        gpio_in = 8'h00;
        wait_sync();
        wait_clocks(1);

        // Check INT_STATUS
        apb_read(REG_GPIO_INT_STATUS, rdata);
        `ASSERT_TRUE(rdata[2] === 1'b1, "INT_STATUS[2] should be set on falling edge");

        // Check irq
        `ASSERT_TRUE(irq === 1'b1, "IRQ should be asserted after falling edge");

        // Clean up
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_00FF);
        apb_write(REG_GPIO_INT_EN,     32'h0);
        apb_write(REG_GPIO_INT_TYPE,   32'h0);
        apb_write(REG_GPIO_INT_POL,    32'h0);
        gpio_in = 8'h00;
        wait_sync();
    endtask

    // =========================================================================
    // Test 6: Level-Triggered Interrupt (High Level)
    // =========================================================================
    // Configure INT_TYPE=level (0), INT_POL=high (1), INT_EN=enabled.
    // Drive gpio_in high, verify irq asserts. Drive low, clear status,
    // verify irq deasserts.
    // =========================================================================
    task automatic test_level_high_interrupt();
        logic [31:0] rdata;

        test_begin("Level High Interrupt");

        // Start with gpio_in low
        gpio_in = 8'h00;
        wait_sync();

        // Configure pin 3 for level-high interrupt
        apb_write(REG_GPIO_INT_TYPE, 32'h0000_0000);  // Pin 3: level-triggered
        apb_write(REG_GPIO_INT_POL,  32'h0000_0008);  // Pin 3: high level
        apb_write(REG_GPIO_INT_EN,   32'h0000_0008);  // Pin 3: enabled

        // Clear any pending interrupts
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_00FF);
        wait_clocks(2);

        // Verify irq is deasserted (gpio_in[3] is low)
        `ASSERT_TRUE(irq === 1'b0, "IRQ should be deasserted when gpio_in[3] is low");

        // Drive pin 3 high
        gpio_in = 8'h08;
        wait_sync();
        // For level interrupts, int_detect is continuously active while the
        // level is present, so int_status_r gets set on each clock.
        wait_clocks(2);

        // Check INT_STATUS
        apb_read(REG_GPIO_INT_STATUS, rdata);
        `ASSERT_TRUE(rdata[3] === 1'b1, "INT_STATUS[3] should be set for high level");

        // Check irq asserted
        `ASSERT_TRUE(irq === 1'b1, "IRQ should be asserted when gpio_in[3] is high");

        // For level-triggered: even after clearing status, if the level
        // is still present, the status will be re-set on the next clock.
        // First remove the stimulus, then clear.
        gpio_in = 8'h00;
        wait_sync();

        // Now clear the interrupt status
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_0008);
        wait_clocks(2);

        // IRQ should now be deasserted (source removed + status cleared)
        `ASSERT_TRUE(irq === 1'b0, "IRQ should deassert after level removed and status cleared");

        // Clean up
        apb_write(REG_GPIO_INT_EN,   32'h0);
        apb_write(REG_GPIO_INT_TYPE, 32'h0);
        apb_write(REG_GPIO_INT_POL,  32'h0);
        wait_clocks(2);
    endtask

    // =========================================================================
    // Test 7: Interrupt Clear (Write-1-to-Clear)
    // =========================================================================
    // Trigger multiple interrupts, then clear them selectively using the
    // W1C mechanism. Verify individual bits can be cleared independently.
    // =========================================================================
    task automatic test_interrupt_clear();
        logic [31:0] rdata;

        test_begin("Interrupt Clear (W1C)");

        // Start with all gpio_in low
        gpio_in = 8'h00;
        wait_sync();

        // Configure pins 0 and 1 for rising-edge interrupt
        apb_write(REG_GPIO_INT_TYPE, 32'h0000_0003);  // Pins 0,1: edge
        apb_write(REG_GPIO_INT_POL,  32'h0000_0003);  // Pins 0,1: rising
        apb_write(REG_GPIO_INT_EN,   32'h0000_0003);  // Pins 0,1: enabled

        // Clear any pending
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_00FF);
        wait_clocks(2);

        // Trigger rising edges on both pin 0 and pin 1
        gpio_in = 8'h03;
        wait_sync();
        wait_clocks(1);

        // Verify both interrupts are pending
        apb_read(REG_GPIO_INT_STATUS, rdata);
        `ASSERT_TRUE(rdata[0] === 1'b1, "INT_STATUS[0] should be set");
        `ASSERT_TRUE(rdata[1] === 1'b1, "INT_STATUS[1] should be set");
        `ASSERT_TRUE(irq === 1'b1, "IRQ should be asserted with both pending");

        // Clear only pin 0 interrupt (write 1 to bit 0 only)
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_0001);
        wait_clocks(1);

        apb_read(REG_GPIO_INT_STATUS, rdata);
        `ASSERT_TRUE(rdata[0] === 1'b0, "INT_STATUS[0] should be cleared after W1C");
        `ASSERT_TRUE(rdata[1] === 1'b1, "INT_STATUS[1] should still be set");
        `ASSERT_TRUE(irq === 1'b1, "IRQ should still be asserted (pin 1 still pending)");

        // Clear pin 1 interrupt
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_0002);
        wait_clocks(1);

        apb_read(REG_GPIO_INT_STATUS, rdata);
        `ASSERT_TRUE(rdata[1] === 1'b0, "INT_STATUS[1] should be cleared after W1C");

        // IRQ should now be deasserted (edge-triggered, so no re-trigger from
        // steady-state high)
        `ASSERT_TRUE(irq === 1'b0, "IRQ should deassert after all interrupts cleared");

        // Clean up
        apb_write(REG_GPIO_INT_EN,   32'h0);
        apb_write(REG_GPIO_INT_TYPE, 32'h0);
        apb_write(REG_GPIO_INT_POL,  32'h0);
        gpio_in = 8'h00;
        wait_sync();
    endtask

    // =========================================================================
    // Test 8: Interrupt Mask (Disabled Interrupts)
    // =========================================================================
    // Verify that when INT_EN is cleared for a pin, an interrupt event does
    // not set INT_STATUS and does not assert irq.
    // =========================================================================
    task automatic test_interrupt_mask();
        logic [31:0] rdata;

        test_begin("Interrupt Mask");

        // Start with gpio_in low
        gpio_in = 8'h00;
        wait_sync();

        // Configure pin 5 for rising-edge interrupt but leave it DISABLED
        apb_write(REG_GPIO_INT_TYPE, 32'h0000_0020);  // Pin 5: edge
        apb_write(REG_GPIO_INT_POL,  32'h0000_0020);  // Pin 5: rising
        apb_write(REG_GPIO_INT_EN,   32'h0000_0000);  // Pin 5: DISABLED

        // Clear any pending
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_00FF);
        wait_clocks(2);

        // Create a rising edge on pin 5
        gpio_in = 8'h20;
        wait_sync();
        wait_clocks(2);

        // INT_STATUS should NOT be set because INT_EN is 0 for this pin.
        // The RTL gates int_detect with gpio_int_en_r before OR'ing into status.
        apb_read(REG_GPIO_INT_STATUS, rdata);
        `ASSERT_TRUE(rdata[5] === 1'b0, "INT_STATUS[5] should NOT be set when masked");

        // IRQ should remain deasserted
        `ASSERT_TRUE(irq === 1'b0, "IRQ should not assert for masked interrupt");

        // Now enable the interrupt for pin 5 and create another edge
        gpio_in = 8'h00;
        wait_sync();  // Return to low first

        apb_write(REG_GPIO_INT_EN, 32'h0000_0020);  // Enable pin 5
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_00FF);  // Clear stale
        wait_clocks(2);

        // Create rising edge
        gpio_in = 8'h20;
        wait_sync();
        wait_clocks(1);

        // Now INT_STATUS should be set
        apb_read(REG_GPIO_INT_STATUS, rdata);
        `ASSERT_TRUE(rdata[5] === 1'b1, "INT_STATUS[5] should be set when enabled");
        `ASSERT_TRUE(irq === 1'b1, "IRQ should assert for enabled interrupt");

        // Clean up
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_00FF);
        apb_write(REG_GPIO_INT_EN,   32'h0);
        apb_write(REG_GPIO_INT_TYPE, 32'h0);
        apb_write(REG_GPIO_INT_POL,  32'h0);
        gpio_in = 8'h00;
        wait_sync();
    endtask

    // =========================================================================
    // Test 9: Individual Pin Control
    // =========================================================================
    // Verify that each pin can be independently controlled for output drive,
    // input read, and direction, without affecting adjacent pins.
    // =========================================================================
    task automatic test_individual_pin_control();
        logic [31:0] rdata;

        test_begin("Individual Pin Control");

        // -- Part A: Individual output pins --
        // Set all pins as outputs
        apb_write(REG_GPIO_DIR, 32'h0000_00FF);
        wait_clocks(1);

        // Walk a '1' through each output pin
        for (int i = 0; i < GPIO_WIDTH; i++) begin
            apb_write(REG_GPIO_OUT, 32'(1 << i));
            wait_clocks(1);
            `ASSERT_EQ({24'h0, gpio_out}, 32'(1 << i),
                $sformatf("gpio_out should be 0x%02h (pin %0d only)", 1 << i, i));
        end

        // -- Part B: Individual input pins --
        // Set all pins as inputs
        apb_write(REG_GPIO_DIR, 32'h0);
        wait_clocks(1);

        // Walk a '1' through each input pin
        for (int i = 0; i < GPIO_WIDTH; i++) begin
            gpio_in = 8'(1 << i);
            wait_sync();
            apb_read(REG_GPIO_IN, rdata);
            `ASSERT_EQ(rdata, 32'(1 << i),
                $sformatf("GPIO_IN should be 0x%02h (pin %0d only)", 1 << i, i));
        end

        // -- Part C: Individual direction per pin --
        // Set only even pins as outputs, odd pins as inputs
        apb_write(REG_GPIO_DIR, 32'h0000_0055);  // 0b01010101
        wait_clocks(1);
        `ASSERT_EQ({24'h0, gpio_oe}, 32'h0000_0055,
            "gpio_oe should be 0x55 (even pins output, odd pins input)");

        // Write to GPIO_OUT -- only even pins should drive
        apb_write(REG_GPIO_OUT, 32'h0000_00FF);
        wait_clocks(1);
        // gpio_out reflects the register value regardless of direction
        `ASSERT_EQ({24'h0, gpio_out}, 32'h0000_00FF,
            "gpio_out register value should be 0xFF");

        // Verify direction readback
        apb_read(REG_GPIO_DIR, rdata);
        `ASSERT_EQ(rdata, 32'h0000_0055, "DIR readback should be 0x55");

        // -- Part D: Individual pin interrupt (per-pin edge detection) --
        // Configure only pin 7 for rising-edge interrupt, ensure pin 6 does not trigger
        apb_write(REG_GPIO_DIR, 32'h0);  // All inputs
        gpio_in = 8'h00;
        wait_sync();

        apb_write(REG_GPIO_INT_TYPE, 32'h0000_00C0);  // Pins 7,6: edge
        apb_write(REG_GPIO_INT_POL,  32'h0000_00C0);  // Pins 7,6: rising
        apb_write(REG_GPIO_INT_EN,   32'h0000_0080);  // Only pin 7 enabled
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_00FF);
        wait_clocks(2);

        // Trigger rising edge on pin 6 only (should not cause IRQ)
        gpio_in = 8'h40;  // Pin 6 high
        wait_sync();
        wait_clocks(1);

        `ASSERT_TRUE(irq === 1'b0, "IRQ should not assert for pin 6 (masked)");

        // Now trigger rising edge on pin 7 (should cause IRQ)
        gpio_in = 8'hC0;  // Pin 7 also high
        wait_sync();
        wait_clocks(1);

        apb_read(REG_GPIO_INT_STATUS, rdata);
        `ASSERT_TRUE(rdata[7] === 1'b1, "INT_STATUS[7] should be set (pin 7 enabled)");
        `ASSERT_TRUE(irq === 1'b1, "IRQ should assert for pin 7");

        // Clean up
        apb_write(REG_GPIO_INT_STATUS, 32'h0000_00FF);
        apb_write(REG_GPIO_INT_EN,   32'h0);
        apb_write(REG_GPIO_INT_TYPE, 32'h0);
        apb_write(REG_GPIO_INT_POL,  32'h0);
        apb_write(REG_GPIO_DIR,      32'h0);
        apb_write(REG_GPIO_OUT,      32'h0);
        gpio_in = 8'h00;
        wait_sync();
    endtask

endmodule : tb_gpio
