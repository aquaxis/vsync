// =============================================================================
// VSync - Hello UART Full SoC Testbench
//
// Loads hello_uart firmware into vsync_top and verifies "Hello VSync!\n"
// is transmitted via UART TX.
//
// Simulation:
//   iverilog -g2012 -DIVERILOG -I rtl/core -I tb/common -o tb_hello_uart_sim \
//       <all_rtl_files> tb/debug/tb_hello_uart.sv
//   vvp tb_hello_uart_sim
// =============================================================================

`timescale 1ns / 1ps

`include "test_utils.sv"

module tb_hello_uart;

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

    // Expected message: "Hello VSync!\n" (13 chars) + null byte (14 total)
    // We capture up to 14 bytes
    localparam int  MAX_CAPTURE  = 14;

    // Timeout: 200 ms simulation time (14 bytes * 83.2us = ~1.16ms, plenty of margin)
    localparam int  TIMEOUT_NS   = 200_000_000;

    // Expected UART output
    localparam string EXPECTED_MSG = "Hello VSync!\n";

    // =========================================================================
    // Signals
    // =========================================================================
    logic        clk;
    logic        rst_n;

    // UART
    logic        uart_tx;
    logic        uart_rx;

    // GPIO (active tristate)
    wire  [15:0] gpio_io;

    // HyperRAM (active tristate)
    wire         hyper_rwds;
    wire  [7:0]  hyper_dq;

    // Captured UART bytes
    logic [7:0]  captured_bytes [0:MAX_CAPTURE-1];
    int          byte_count;

    // =========================================================================
    // Clock Generation (25 MHz)
    // =========================================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // =========================================================================
    // VCD Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_hello_uart.vcd");
        $dumpvars(0, tb_hello_uart);
    end

    // =========================================================================
    // Signal Tieoffs
    // =========================================================================
    assign uart_rx  = 1'b1;       // UART idle = high
    assign gpio_io  = 16'bz;      // Tri-state
    assign hyper_rwds = 1'bz;     // Tri-state
    assign hyper_dq   = 8'bz;     // Tri-state

    // =========================================================================
    // DUT Instantiation - vsync_top (Full SoC)
    // =========================================================================
    vsync_top #(
        .IMEM_INIT_FILE ("sw/tools/build/hello_uart_i.hex"),
        .DMEM_INIT_FILE ("sw/tools/build/hello_uart_d.hex")
    ) u_dut (
        .clk            (clk),
        .rst_n          (rst_n),

        // UART
        .uart_tx        (uart_tx),
        .uart_rx        (uart_rx),

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
    // UART Capture Process (runs in background)
    // =========================================================================
    initial begin
        byte_count = 0;
        for (int i = 0; i < MAX_CAPTURE; i++)
            captured_bytes[i] = 8'h00;

        // Wait for reset to deassert
        @(negedge rst_n);
        #100;

        // Capture bytes from UART TX
        for (int b = 0; b < MAX_CAPTURE; b++) begin
            logic [7:0] rx_byte;
            uart_capture_byte(rx_byte);
            captured_bytes[b] = rx_byte;
            byte_count++;
            if (rx_byte >= 8'h20 && rx_byte < 8'h7F)
                $display("[TB] UART TX byte %0d captured: 0x%02h ('%c') at %0t",
                         b, rx_byte, rx_byte, $time);
            else
                $display("[TB] UART TX byte %0d captured: 0x%02h (ctrl) at %0t",
                         b, rx_byte, $time);
        end
    end

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        // -----------------------------------------------------------------
        // Reset (vsync_top uses active-high rst_n: 1=reset, 0=run)
        // -----------------------------------------------------------------
        rst_n = 1'b1;  // Assert reset (active high)
        repeat (RST_CYCLES) @(posedge clk);
        rst_n = 1'b0;  // Release reset
        $display("[TB] Reset released at %0t", $time);
        $display("[TB] Waiting for UART TX output: \"Hello VSync!\\n\"");

        // -----------------------------------------------------------------
        // Wait for all bytes or timeout
        // -----------------------------------------------------------------
        fork
            begin
                // Wait for capture to finish (at least 13 meaningful bytes)
                wait (byte_count >= 13);
                $display("[TB] All expected UART bytes captured at %0t", $time);
                // Small extra wait for any trailing byte
                #(CLKS_PER_BIT * CLK_PERIOD * 12);
            end
            begin
                // Timeout watchdog
                #(TIMEOUT_NS);
                $display("[TB] ERROR: Timeout after %0d ns, captured %0d bytes",
                         TIMEOUT_NS, byte_count);
            end
        join_any
        disable fork;

        // Small delay to settle
        #1000;

        // -----------------------------------------------------------------
        // Build captured string for display
        // -----------------------------------------------------------------
        begin
            string captured_str;
            captured_str = "";
            for (int i = 0; i < byte_count && i < MAX_CAPTURE; i++) begin
                if (captured_bytes[i] >= 8'h20 && captured_bytes[i] < 8'h7F)
                    captured_str = {captured_str, string'(captured_bytes[i])};
                else if (captured_bytes[i] == 8'h0A)
                    captured_str = {captured_str, "\\n"};
                else if (captured_bytes[i] == 8'h00)
                    captured_str = {captured_str, "\\0"};
                else
                    captured_str = {captured_str, "?"};
            end
            $display("[TB] Captured string: \"%s\"", captured_str);
            $display("[TB] Captured %0d bytes total", byte_count);
        end

        // -----------------------------------------------------------------
        // Test Verification
        // -----------------------------------------------------------------
        test_suite_begin("Hello UART SoC Test");

        // Verify byte count
        test_begin("Captured at least 13 bytes");
        check(byte_count >= 13, "byte_count >= 13");

        // Verify each character of "Hello VSync!\n"
        test_begin("Byte 0 = 'H' (0x48)");
        check_eq({24'b0, captured_bytes[0]}, 32'h48, "byte 0");

        test_begin("Byte 1 = 'e' (0x65)");
        check_eq({24'b0, captured_bytes[1]}, 32'h65, "byte 1");

        test_begin("Byte 2 = 'l' (0x6C)");
        check_eq({24'b0, captured_bytes[2]}, 32'h6C, "byte 2");

        test_begin("Byte 3 = 'l' (0x6C)");
        check_eq({24'b0, captured_bytes[3]}, 32'h6C, "byte 3");

        test_begin("Byte 4 = 'o' (0x6F)");
        check_eq({24'b0, captured_bytes[4]}, 32'h6F, "byte 4");

        test_begin("Byte 5 = ' ' (0x20)");
        check_eq({24'b0, captured_bytes[5]}, 32'h20, "byte 5");

        test_begin("Byte 6 = 'V' (0x56)");
        check_eq({24'b0, captured_bytes[6]}, 32'h56, "byte 6");

        test_begin("Byte 7 = 'S' (0x53)");
        check_eq({24'b0, captured_bytes[7]}, 32'h53, "byte 7");

        test_begin("Byte 8 = 'y' (0x79)");
        check_eq({24'b0, captured_bytes[8]}, 32'h79, "byte 8");

        test_begin("Byte 9 = 'n' (0x6E)");
        check_eq({24'b0, captured_bytes[9]}, 32'h6E, "byte 9");

        test_begin("Byte 10 = 'c' (0x63)");
        check_eq({24'b0, captured_bytes[10]}, 32'h63, "byte 10");

        test_begin("Byte 11 = '!' (0x21)");
        check_eq({24'b0, captured_bytes[11]}, 32'h21, "byte 11");

        test_begin("Byte 12 = '\\n' (0x0A)");
        check_eq({24'b0, captured_bytes[12]}, 32'h0A, "byte 12");

        test_finish();
    end

    // =========================================================================
    // Debug: Trace UART TX FIFO writes and posix_hw_layer writes
    // =========================================================================
    wire        dbg_tx_push   = u_dut.u_uart.tx_fifo_push;
    wire [31:0] dbg_apb_pwdata = u_dut.u_uart.apb_pwdata;
    wire        dbg_apb_pwrite = u_dut.u_uart.apb_pwrite;
    wire        dbg_apb_psel   = u_dut.u_uart.apb_psel;
    wire        dbg_apb_pen    = u_dut.u_uart.apb_penable;
    wire [7:0]  dbg_apb_paddr  = u_dut.u_uart.apb_paddr;

    wire [31:0] dbg_periph_addr  = u_dut.periph_addr;
    wire [31:0] dbg_periph_wdata = u_dut.periph_wdata;
    wire        dbg_periph_write = u_dut.periph_write;
    wire        dbg_periph_ready = u_dut.periph_ready;
    wire [2:0]  dbg_periph_state = u_dut.periph_state;

    // Trace posix_hw_layer state
    wire [3:0]  dbg_phl_state = u_dut.u_posix.state_r;
    wire        dbg_ecall_req = u_dut.u_posix.ecall_req;
    wire [7:0]  dbg_syscall_num = u_dut.u_posix.syscall_num;
    wire [31:0] dbg_arg0 = u_dut.u_posix.latched_arg0;
    wire [31:0] dbg_arg1 = u_dut.u_posix.latched_arg1;
    wire [31:0] dbg_arg2 = u_dut.u_posix.latched_arg2;

    // Debug: verify BRAM contents at string location
    initial begin
        #100;
        $display("[DBG] BRAM check: word[196]=0x%08h (expect 0x6c6c6548 = 'Hell')",
                 u_dut.u_imem.mem[196]);
        $display("[DBG] BRAM check: word[197]=0x%08h (expect 0x5356206f = 'o VS')",
                 u_dut.u_imem.mem[197]);
        $display("[DBG] BRAM check: word[198]=0x%08h (expect 0x21636e79 = 'ync!')",
                 u_dut.u_imem.mem[198]);
        $display("[DBG] BRAM check: word[199]=0x%08h (expect 0x0000000a = '\\n')",
                 u_dut.u_imem.mem[199]);
    end

    // Debug: trace IMEM Port B reads
    wire        dbg_imem_b_en    = u_dut.imem_b_en;
    wire [15:0] dbg_imem_b_addr  = u_dut.imem_b_addr;
    wire [31:0] dbg_imem_b_rdata = u_dut.imem_b_rdata;
    wire [2:0]  dbg_imem_state   = u_dut.imem_state;

    // Debug: trace AXI master read channel
    wire [31:0] dbg_axi_araddr  = u_dut.axi_m_araddr;
    wire        dbg_axi_arvalid = u_dut.axi_m_arvalid;
    wire        dbg_axi_arready = u_dut.axi_m_arready;
    wire [31:0] dbg_axi_rdata   = u_dut.axi_m_rdata;
    wire        dbg_axi_rvalid  = u_dut.axi_m_rvalid;

    // Debug: trace CPU data memory interface
    wire [31:0] dbg_cpu_mem_addr  = u_dut.cpu_mem_addr;
    wire        dbg_cpu_mem_read  = u_dut.cpu_mem_read;
    wire [31:0] dbg_cpu_mem_rdata = u_dut.cpu_mem_rdata;
    wire        dbg_cpu_mem_ready = u_dut.cpu_mem_ready;

    always @(posedge clk) begin
        // Trace IMEM reads (around string address 0x310 = word 196)
        if (dbg_imem_b_en && dbg_imem_b_addr[15:2] >= 14'd194 && dbg_imem_b_addr[15:2] <= 14'd200)
            $display("[DBG] t=%0t IMEM_B read: addr=0x%04h word_idx=%0d rdata=0x%08h state=%0d",
                     $time, dbg_imem_b_addr, dbg_imem_b_addr[15:2], dbg_imem_b_rdata, dbg_imem_state);

        // Trace AXI reads in IMEM address range
        if (dbg_axi_arvalid && dbg_axi_araddr < 32'h10000)
            $display("[DBG] t=%0t AXI_AR: addr=0x%08h valid=%b ready=%b",
                     $time, dbg_axi_araddr, dbg_axi_arvalid, dbg_axi_arready);

        // Trace CPU mem reads in IMEM range
        if (dbg_cpu_mem_read && dbg_cpu_mem_addr < 32'h10000)
            $display("[DBG] t=%0t CPU_MEM_RD: addr=0x%08h rdata=0x%08h ready=%b",
                     $time, dbg_cpu_mem_addr, dbg_cpu_mem_rdata, dbg_cpu_mem_ready);

        if (dbg_ecall_req)
            $display("[DBG] t=%0t ecall_req: num=%0d a0=0x%08h a1=0x%08h a2=0x%08h",
                     $time, dbg_syscall_num, u_dut.u_posix.syscall_arg0,
                     u_dut.u_posix.syscall_arg1, u_dut.u_posix.syscall_arg2);

        if (dbg_periph_write)
            $display("[DBG] t=%0t periph_write: addr=0x%08h wdata=0x%08h state=%0d",
                     $time, dbg_periph_addr, dbg_periph_wdata, dbg_periph_state);

        if (dbg_tx_push)
            $display("[DBG] t=%0t TX_PUSH: pwdata=0x%08h paddr=0x%02h",
                     $time, dbg_apb_pwdata, dbg_apb_paddr);
    end

    // =========================================================================
    // Absolute Timeout (safety net)
    // =========================================================================
    initial begin
        #(TIMEOUT_NS + 1_000_000);  // safety
        $display("[TB] FATAL: Absolute timeout reached");
        $finish(1);
    end

endmodule : tb_hello_uart
