// =============================================================================
// VSync - Shell UART Command Test Testbench
//
// Loads shell firmware into vsync_top, waits for banner + prompt,
// sends "help" command via UART RX, and verifies the response on UART TX.
//
// Simulation:
//   iverilog -g2012 -DIVERILOG -I rtl/core -I tb/common -o tb_shell_sim \
//       <all_rtl_files> tb/debug/tb_shell.sv
//   vvp tb_shell_sim
// =============================================================================

`timescale 1ns / 1ps

`include "test_utils.sv"

module tb_shell;

    import vsync_pkg::*;
    import test_utils::*;

    // =========================================================================
    // Parameters
    // =========================================================================
    // Clock: 25 MHz (MMCM bypassed in iverilog: clk_sys = clk)
    localparam real CLK_PERIOD   = 40.0;            // 25 MHz = 40 ns period
    localparam int  RST_CYCLES   = 20;              // Reset hold cycles

    // UART timing (must match vsync_top uart_apb: CLK_FREQ=25MHz, BAUD=115200)
    // BAUD_DIV = round(25M / 115200) = 217 (int=13, frac=9)
    localparam int  BAUD_DIV     = 217;
    localparam int  CLKS_PER_BIT = BAUD_DIV;         // 217 clocks per bit
    // One byte (8N1): start + 8 data + stop = 10 bits = 2170 clocks = 86800 ns

    // Large capture buffer for banner + help output
    localparam int  MAX_CAPTURE  = 2048;

    // Timeout: 500 ms simulation time (shell with flow control: ~70ms expected)
    localparam int  TIMEOUT_NS   = 500_000_000;

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst_n;

    // UART
    logic        uart_tx;
    reg          uart_rx_drv;

    // GPIO (active tristate)
    wire  [15:0] gpio_io;

    // HyperRAM (active tristate)
    wire         hyper_rwds;
    wire  [7:0]  hyper_dq;

    // Captured UART TX bytes
    logic [7:0]  captured_bytes [0:MAX_CAPTURE-1];
    integer      byte_count;
    integer      prompt_count;
    integer      pre_help_bytes;

    // =========================================================================
    // Clock Generation (25 MHz)
    // =========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // =========================================================================
    // VCD Dump (disabled for performance)
    // =========================================================================
    // initial begin
    //     $dumpfile("tb_shell.vcd");
    //     $dumpvars(0, tb_shell);
    // end

    // =========================================================================
    // Signal Tieoffs
    // =========================================================================
    assign gpio_io  = 16'bz;
    assign hyper_rwds = 1'bz;
    assign hyper_dq   = 8'bz;

    // =========================================================================
    // RTOS Scheduler & Timer/Interrupt Disable (bare-metal shell test)
    // =========================================================================
    initial begin
        // Disable RTOS scheduler (hardwired 1'b1 in vsync_top; force overrides)
        force u_dut.scheduler_en = 1'b0;
        // Suppress CLINT timer IRQ to prevent interrupt storm
        // (mtimecmp=0 by default → timer_irq asserted immediately → continuous
        //  re-trapping after each mret since MIE=1 after start.S)
        force u_dut.clint_timer_irq = 1'b0;
    end

    // (Diagnostics removed for speed - ecall path verified working correctly)

    // =========================================================================
    // DUT Instantiation - vsync_top (Full SoC)
    // =========================================================================
    vsync_top #(
        .IMEM_INIT_FILE ("sw/tools/build/shell_i.hex"),
        .DMEM_INIT_FILE ("")
    ) u_dut (
        .clk            (clk),
        .rst_n          (rst_n),

        // UART
        .uart_tx        (uart_tx),
        .uart_rx        (uart_rx_drv),

        // GPIO
        .gpio_io        (gpio_io),

        // HyperRAM
        .hyper_cs_n     (),
        .hyper_ck       (),
        .hyper_ck_n     (),
        .hyper_rwds     (hyper_rwds),
        .hyper_dq       (hyper_dq),
        .hyper_rst_n    (),

        // JTAG (disabled)
        .jtag_tck       (1'b0),
        .jtag_tms       (1'b0),
        .jtag_tdi       (1'b0),
        .jtag_tdo       (),
        .jtag_trst_n    (1'b0)
    );

    // =========================================================================
    // UART TX Capture Task
    // =========================================================================
    task automatic uart_capture_byte(output logic [7:0] data);
        // Wait for start bit (falling edge on uart_tx)
        @(negedge uart_tx);

        // Move to center of start bit
        #(CLKS_PER_BIT * CLK_PERIOD / 2);

        // Sample 8 data bits (LSB first)
        for (int i = 0; i < 8; i++) begin
            #(CLKS_PER_BIT * CLK_PERIOD);
            data[i] = uart_tx;
        end

        // Wait through stop bit
        #(CLKS_PER_BIT * CLK_PERIOD);
    endtask

    // =========================================================================
    // UART RX Send Task (sends serial data TO shell)
    // =========================================================================
    task automatic uart_send_byte(input logic [7:0] data);
        integer i;
        // Start bit (low)
        uart_rx_drv = 1'b0;
        repeat(CLKS_PER_BIT) @(posedge clk);

        // Data bits (LSB first)
        for (i = 0; i < 8; i = i + 1) begin
            uart_rx_drv = data[i];
            repeat(CLKS_PER_BIT) @(posedge clk);
        end

        // Stop bit (high)
        uart_rx_drv = 1'b1;
        repeat(CLKS_PER_BIT) @(posedge clk);

        // Inter-character gap (1 bit time)
        repeat(CLKS_PER_BIT) @(posedge clk);
    endtask

    // =========================================================================
    // Prompt Detection Logic
    // =========================================================================
    // Check if last 7 captured bytes match "vsync> "
    function automatic integer check_prompt;
        input integer bc;
        begin
            if (bc >= 7 &&
                captured_bytes[bc-7] == 8'h76 &&  // 'v'
                captured_bytes[bc-6] == 8'h73 &&  // 's'
                captured_bytes[bc-5] == 8'h79 &&  // 'y'
                captured_bytes[bc-4] == 8'h6E &&  // 'n'
                captured_bytes[bc-3] == 8'h63 &&  // 'c'
                captured_bytes[bc-2] == 8'h3E &&  // '>'
                captured_bytes[bc-1] == 8'h20)    // ' '
                check_prompt = 1;
            else
                check_prompt = 0;
        end
    endfunction

    // =========================================================================
    // Background UART TX Capture Process
    // =========================================================================
    initial begin
        byte_count = 0;
        prompt_count = 0;
        pre_help_bytes = 0;

        for (integer i = 0; i < MAX_CAPTURE; i = i + 1)
            captured_bytes[i] = 8'h00;

        // Wait for reset to deassert
        @(negedge rst_n);
        #100;

        // Capture bytes from UART TX forever
        forever begin
            logic [7:0] rx_byte;
            uart_capture_byte(rx_byte);

            if (byte_count < MAX_CAPTURE) begin
                captured_bytes[byte_count] = rx_byte;
                byte_count = byte_count + 1;

                // Reduced logging: only every 100th byte or prompt detection
                if (byte_count <= 5 || byte_count % 100 == 0)
                    $display("[TX] byte %0d: 0x%02h at %0t", byte_count-1, rx_byte, $time);

                // Detect "vsync> " prompt
                if (check_prompt(byte_count)) begin
                    prompt_count = prompt_count + 1;
                    $display("[TB] === Prompt #%0d detected at byte %0d, t=%0t ===",
                             prompt_count, byte_count, $time);
                end
            end
        end
    end

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // -----------------------------------------------------------------
        // Reset (vsync_top uses active-high rst_n: 1=reset, 0=run)
        // -----------------------------------------------------------------
        rst_n = 1'b1;          // Assert reset (active high)
        uart_rx_drv = 1'b1;   // UART idle = high
        repeat (RST_CYCLES) @(posedge clk);
        rst_n = 1'b0;         // Release reset
        $display("[TB] Reset released at %0t", $time);

        // IMEM diagnostic: verify banner strings are loaded correctly
        $display("[TB] IMEM[1994] (0x1F28 '====') = 0x%08h", u_dut.u_imem.mem[1994]);
        $display("[TB] IMEM[2005] (0x1F54 'VSync') = 0x%08h", u_dut.u_imem.mem[2005]);
        $display("[TB] IMEM[2038] (0x1FD8 'vsync>') = 0x%08h", u_dut.u_imem.mem[2038]);
        $display("[TB] scheduler_en = %b (should be 0)", u_dut.scheduler_en);

        $display("[TB] Waiting for shell banner and first prompt...");

        // -----------------------------------------------------------------
        // Wait for first "vsync> " prompt (after banner)
        // -----------------------------------------------------------------
        fork
            begin
                wait (prompt_count >= 1);
                $display("[TB] First prompt received at %0t, captured %0d bytes",
                         $time, byte_count);
            end
            begin
                #(TIMEOUT_NS);
                $display("[TB] ERROR: Timeout waiting for first prompt after %0d ns",
                         TIMEOUT_NS);
            end
        join_any
        disable fork;

        if (prompt_count < 1) begin
            $display("[TB] FATAL: No prompt received, aborting");
            $finish(1);
        end

        // Record byte count before sending command
        pre_help_bytes = byte_count;

        // -----------------------------------------------------------------
        // Send "help\r" command via UART RX
        // -----------------------------------------------------------------
        // Small delay after prompt
        repeat(CLKS_PER_BIT * 5) @(posedge clk);

        $display("[TB] Sending 'help' command at %0t", $time);
        uart_send_byte(8'h68);  // 'h'
        uart_send_byte(8'h65);  // 'e'
        uart_send_byte(8'h6C);  // 'l'
        uart_send_byte(8'h70);  // 'p'
        uart_send_byte(8'h0D);  // '\r'

        // -----------------------------------------------------------------
        // Wait for help response and second prompt
        // -----------------------------------------------------------------
        $display("[TB] Waiting for help response and second prompt...");
        fork
            begin
                wait (prompt_count >= 2);
                $display("[TB] Second prompt received at %0t, captured %0d bytes",
                         $time, byte_count);
            end
            begin
                #(TIMEOUT_NS);
                $display("[TB] ERROR: Timeout waiting for help response after %0d ns",
                         TIMEOUT_NS);
            end
        join_any
        disable fork;

        // Extra wait for any trailing bytes
        repeat(CLKS_PER_BIT * 20) @(posedge clk);

        // -----------------------------------------------------------------
        // Display Captured Output
        // -----------------------------------------------------------------
        $display("");
        $display("============================================================");
        $display("[TB] Total bytes captured: %0d", byte_count);
        $display("[TB] Prompts detected: %0d", prompt_count);
        $display("[TB] Banner bytes: %0d, Help response bytes: %0d",
                 pre_help_bytes, byte_count - pre_help_bytes);
        $display("============================================================");

        // Display banner section
        $display("[TB] --- Banner Output (first %0d bytes) ---", pre_help_bytes);
        begin
            string s;
            s = "";
            for (integer i = 0; i < pre_help_bytes && i < MAX_CAPTURE; i = i + 1) begin
                if (captured_bytes[i] >= 8'h20 && captured_bytes[i] < 8'h7F)
                    s = {s, string'(captured_bytes[i])};
                else if (captured_bytes[i] == 8'h0D)
                    ; // skip CR for display
                else if (captured_bytes[i] == 8'h0A)
                    s = {s, "\n"};
            end
            $display("%s", s);
        end

        // Display help response
        $display("[TB] --- Help Response (bytes %0d to %0d) ---",
                 pre_help_bytes, byte_count-1);
        begin
            string s;
            s = "";
            for (integer i = pre_help_bytes; i < byte_count && i < MAX_CAPTURE; i = i + 1) begin
                if (captured_bytes[i] >= 8'h20 && captured_bytes[i] < 8'h7F)
                    s = {s, string'(captured_bytes[i])};
                else if (captured_bytes[i] == 8'h0D)
                    ; // skip CR for display
                else if (captured_bytes[i] == 8'h0A)
                    s = {s, "\n"};
            end
            $display("%s", s);
        end

        // -----------------------------------------------------------------
        // Test Verification
        // -----------------------------------------------------------------
        test_suite_begin("Shell UART Command Test");

        // Test 1: First prompt received
        test_begin("First 'vsync> ' prompt received");
        check(prompt_count >= 1, "prompt_count >= 1");

        // Test 2: Banner contains "VSync Monitor Shell"
        test_begin("Banner contains 'VSync Monitor'");
        begin
            integer found;
            found = 0;
            for (integer i = 0; i <= pre_help_bytes - 13; i = i + 1) begin
                if (captured_bytes[i]    == 8'h56 &&  // 'V'
                    captured_bytes[i+1]  == 8'h53 &&  // 'S'
                    captured_bytes[i+2]  == 8'h79 &&  // 'y'
                    captured_bytes[i+3]  == 8'h6E &&  // 'n'
                    captured_bytes[i+4]  == 8'h63 &&  // 'c'
                    captured_bytes[i+5]  == 8'h20 &&  // ' '
                    captured_bytes[i+6]  == 8'h4D &&  // 'M'
                    captured_bytes[i+7]  == 8'h6F &&  // 'o'
                    captured_bytes[i+8]  == 8'h6E &&  // 'n'
                    captured_bytes[i+9]  == 8'h69 &&  // 'i'
                    captured_bytes[i+10] == 8'h74 &&  // 't'
                    captured_bytes[i+11] == 8'h6F &&  // 'o'
                    captured_bytes[i+12] == 8'h72)    // 'r'
                    found = 1;
            end
            check(found == 1, "Banner has 'VSync Monitor'");
        end

        // Test 3: Help command echoed back
        test_begin("Help command echoed ('help')");
        begin
            integer found;
            found = 0;
            for (integer i = pre_help_bytes; i <= byte_count - 4; i = i + 1) begin
                if (captured_bytes[i]   == 8'h68 &&  // 'h'
                    captured_bytes[i+1] == 8'h65 &&  // 'e'
                    captured_bytes[i+2] == 8'h6C &&  // 'l'
                    captured_bytes[i+3] == 8'h70)    // 'p'
                    found = 1;
            end
            check(found == 1, "Echo contains 'help'");
        end

        // Test 4: Help response contains "Shell Commands"
        test_begin("Response contains 'Shell Commands'");
        begin
            integer found;
            found = 0;
            for (integer i = pre_help_bytes; i <= byte_count - 8; i = i + 1) begin
                if (captured_bytes[i]   == 8'h53 &&  // 'S'
                    captured_bytes[i+1] == 8'h68 &&  // 'h'
                    captured_bytes[i+2] == 8'h65 &&  // 'e'
                    captured_bytes[i+3] == 8'h6C &&  // 'l'
                    captured_bytes[i+4] == 8'h6C &&  // 'l'
                    captured_bytes[i+5] == 8'h20 &&  // ' '
                    captured_bytes[i+6] == 8'h43 &&  // 'C'
                    captured_bytes[i+7] == 8'h6F)    // 'o'
                    found = 1;
            end
            check(found == 1, "Response has 'Shell Co'");
        end

        // Test 5: Help response contains "peek"
        test_begin("Response contains 'peek'");
        begin
            integer found;
            found = 0;
            for (integer i = pre_help_bytes; i <= byte_count - 4; i = i + 1) begin
                if (captured_bytes[i]   == 8'h70 &&  // 'p'
                    captured_bytes[i+1] == 8'h65 &&  // 'e'
                    captured_bytes[i+2] == 8'h65 &&  // 'e'
                    captured_bytes[i+3] == 8'h6B)    // 'k'
                    found = 1;
            end
            check(found == 1, "Response has 'peek'");
        end

        // Test 6: Help response contains "info"
        test_begin("Response contains 'info'");
        begin
            integer found;
            found = 0;
            for (integer i = pre_help_bytes; i <= byte_count - 4; i = i + 1) begin
                if (captured_bytes[i]   == 8'h69 &&  // 'i'
                    captured_bytes[i+1] == 8'h6E &&  // 'n'
                    captured_bytes[i+2] == 8'h66 &&  // 'f'
                    captured_bytes[i+3] == 8'h6F)    // 'o'
                    found = 1;
            end
            check(found == 1, "Response has 'info'");
        end

        // Test 7: Second prompt received (after help output)
        test_begin("Second 'vsync> ' prompt after help");
        check(prompt_count >= 2, "prompt_count >= 2");

        test_finish();
    end

    // =========================================================================
    // Absolute Timeout (safety net)
    // =========================================================================
    initial begin
        #(TIMEOUT_NS * 2 + 1_000_000);
        $display("[TB] FATAL: Absolute timeout reached");
        $finish(1);
    end

endmodule : tb_shell
