// =============================================================================
// VSync - Shell Quick Test (periph_write capture, no UART serial timing)
//
// Captures shell output by monitoring posix_hw_layer periph_write events
// directly, bypassing UART TX serial timing for ~100x faster simulation.
// =============================================================================

`timescale 1ns / 1ps

module tb_shell_fast;

    import vsync_pkg::*;

    localparam real CLK_PERIOD = 40.0;  // 25 MHz
    localparam int  RST_CYCLES = 20;
    localparam int  MAX_CAPTURE = 4096;

    logic clk, rst_n;
    logic uart_tx;
    reg   uart_rx_drv;
    wire [15:0] gpio_io;
    wire hyper_rwds;
    wire [7:0] hyper_dq;

    // Clock
    initial begin clk = 0; forever #(CLK_PERIOD/2) clk = ~clk; end

    // Tieoffs
    assign gpio_io = 16'bz;
    assign hyper_rwds = 1'bz;
    assign hyper_dq = 8'bz;

    // Disable RTOS and timer interrupts
    initial begin
        force u_dut.scheduler_en = 1'b0;
        force u_dut.clint_timer_irq = 1'b0;
    end

    // =========================================================================
    // IMEM BRAM diagnostic: verify string data is correct
    // =========================================================================
    initial begin
        repeat(RST_CYCLES + 5) @(posedge clk);
        // Address 0x167C -> word 1439: should be "\r\n\0\0" = 0x00000A0D
        $display("[DIAG] IMEM[1439] (0x167C '\\r\\n') = 0x%08x (expect 0x00000a0d)",
                 u_dut.u_imem.mem[1439]);
        // Address 0x1680 -> word 1440: should be "    " = 0x20202020
        $display("[DIAG] IMEM[1440] (0x1680 '    ') = 0x%08x (expect 0x20202020)",
                 u_dut.u_imem.mem[1440]);
        // Address 0x1F28 -> word 1994: should be "====" = 0x3D3D3D3D
        $display("[DIAG] IMEM[1994] (0x1F28 '====') = 0x%08x (expect 0x3d3d3d3d)",
                 u_dut.u_imem.mem[1994]);
        // Address 0x1F54 -> word 2005: should be "  VS" = start of "  VSync..."
        $display("[DIAG] IMEM[2005] (0x1F54 'VSync') = 0x%08x",
                 u_dut.u_imem.mem[2005]);
        // Check .rodata start: 0x15B0 -> word 1388: "0x\0\0"
        $display("[DIAG] IMEM[1388] (0x15B0 '0x\\0\\0') = 0x%08x (expect 0x00007830)",
                 u_dut.u_imem.mem[1388]);
    end

    // =========================================================================
    // Capture first 20 bytes with hex values for debugging
    // =========================================================================
    integer diag_byte_idx;
    initial diag_byte_idx = 0;
    always @(posedge clk) begin
        if (u_dut.u_posix.periph_write &&
            u_dut.u_posix.periph_addr == 32'h10000000 &&
            diag_byte_idx < 20) begin
            $display("[BYTE] #%0d: 0x%02x '%s' at t=%0t",
                     diag_byte_idx, u_dut.u_posix.periph_wdata[7:0],
                     (u_dut.u_posix.periph_wdata[7:0] >= 8'h20 &&
                      u_dut.u_posix.periph_wdata[7:0] < 8'h7f) ?
                         string'(u_dut.u_posix.periph_wdata[7:0]) : ".",
                     $time);
            diag_byte_idx = diag_byte_idx + 1;
        end
    end

    // =========================================================================
    // Pipeline Debug Probes (focused on LBU→BNEZ in shell_puts)
    // =========================================================================
    // Uses dbg_* probe wires defined in rv32im_core.sv / execute_stage.sv /
    // hazard_unit.sv (IVERILOG ifdef) to access packed struct fields.
    integer bnez_probe_count;
    initial bnez_probe_count = 0;
    always @(posedge clk) begin
        // Probe 1: When BNEZ (PC=0x3E8) is in ID/EX, only on stall_ex=0 (decisive cycle)
        if (u_dut.u_cpu.dbg_id_ex_pc == 32'h000003E8 &&
            u_dut.u_cpu.dbg_id_ex_valid &&
            !u_dut.u_cpu.stall_ex &&
            bnez_probe_count < 20) begin
            $display("[BNEZ-EX] t=%0t pc=0x%08x fwd_a=%0b rs1_fwd=0x%08x branch_taken=%0b stall_ex=%0b",
                     $time,
                     u_dut.u_cpu.dbg_id_ex_pc,
                     u_dut.u_cpu.dbg_fwd_a,
                     u_dut.u_cpu.u_execute_stage.dbg_rs1_forwarded,
                     u_dut.u_cpu.ex_branch_taken,
                     u_dut.u_cpu.stall_ex);
            $display("[BNEZ-EX]   id_ex.rs1_data=0x%08x wb_data=0x%08x exmem_alu=0x%08x",
                     u_dut.u_cpu.dbg_id_ex_rs1_data,
                     u_dut.u_cpu.u_execute_stage.dbg_wb_data,
                     u_dut.u_cpu.dbg_ex_mem_alu);
            $display("[BNEZ-EX]   exmem: pc=0x%08x rd=%0d rw=%0b memrd=%0b valid=%0b",
                     u_dut.u_cpu.dbg_ex_mem_pc,
                     u_dut.u_cpu.dbg_ex_mem_rd,
                     u_dut.u_cpu.dbg_ex_mem_rw,
                     u_dut.u_cpu.dbg_ex_mem_memrd,
                     u_dut.u_cpu.dbg_ex_mem_valid);
            $display("[BNEZ-EX]   memwb: pc=0x%08x rd=%0d rw=%0b wb_sel=%0b mem_rdata=0x%08x alu=0x%08x valid=%0b",
                     u_dut.u_cpu.dbg_mem_wb_pc,
                     u_dut.u_cpu.dbg_mem_wb_rd,
                     u_dut.u_cpu.dbg_mem_wb_rw,
                     u_dut.u_cpu.dbg_mem_wb_wbsel,
                     u_dut.u_cpu.dbg_mem_wb_memrdata,
                     u_dut.u_cpu.dbg_mem_wb_alu,
                     u_dut.u_cpu.dbg_mem_wb_valid);
            $display("[BNEZ-EX]   hazard: luh_id=%0b luh_ex=%0b flush_if=%0b flush_id=%0b flush_ex=%0b mem_stall=%0b",
                     u_dut.u_cpu.u_hazard_unit.dbg_luh_id,
                     u_dut.u_cpu.u_hazard_unit.dbg_luh_ex,
                     u_dut.u_cpu.dbg_flush_if_h,
                     u_dut.u_cpu.dbg_flush_id_h,
                     u_dut.u_cpu.dbg_flush_ex_h,
                     u_dut.u_cpu.mem_stall);
            bnez_probe_count = bnez_probe_count + 1;
        end
    end

    // Probe 2: When LBU (PC=0x3E4) is in MEM stage (EX/MEM register)
    integer lbu_probe_count;
    initial lbu_probe_count = 0;
    always @(posedge clk) begin
        if (u_dut.u_cpu.dbg_ex_mem_pc == 32'h000003E4 &&
            u_dut.u_cpu.dbg_ex_mem_valid &&
            lbu_probe_count < 10) begin
            $display("[LBU-MEM] t=%0t addr=0x%08x dmem_rdata=0x%08x load_data=0x%08x byte_off=%0b funct3=%0b mem_stall=%0b mem_ready=%0b",
                     $time,
                     u_dut.u_cpu.dbg_ex_mem_alu,
                     u_dut.u_cpu.mem_rdata,
                     u_dut.u_cpu.u_memory_stage.load_data,
                     u_dut.u_cpu.u_memory_stage.byte_offset,
                     u_dut.u_cpu.dbg_ex_mem_funct3,
                     u_dut.u_cpu.mem_stall,
                     u_dut.u_cpu.mem_ready);
            lbu_probe_count = lbu_probe_count + 1;
        end
    end

    // Probe 3: wb_rd_data (writeback output) when LBU result enters MEM/WB
    integer wb_probe_count;
    initial wb_probe_count = 0;
    always @(posedge clk) begin
        if (u_dut.u_cpu.dbg_mem_wb_pc == 32'h000003E4 &&
            u_dut.u_cpu.dbg_mem_wb_valid &&
            wb_probe_count < 10) begin
            $display("[LBU-WB] t=%0t memwb_pc=0x%08x wb_sel=%0b wb_rd_data=0x%08x mem_rdata=0x%08x alu=0x%08x",
                     $time,
                     u_dut.u_cpu.dbg_mem_wb_pc,
                     u_dut.u_cpu.dbg_mem_wb_wbsel,
                     u_dut.u_cpu.wb_rd_data,
                     u_dut.u_cpu.dbg_mem_wb_memrdata,
                     u_dut.u_cpu.dbg_mem_wb_alu);
            wb_probe_count = wb_probe_count + 1;
        end
    end

    // DUT
    vsync_top #(
        .IMEM_INIT_FILE("sw/tools/build/shell_i.hex"),
        .DMEM_INIT_FILE("")
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .uart_tx(uart_tx), .uart_rx(uart_rx_drv),
        .gpio_io(gpio_io),
        .hyper_cs_n(), .hyper_ck(), .hyper_ck_n(),
        .hyper_rwds(hyper_rwds), .hyper_dq(hyper_dq), .hyper_rst_n(),
        .jtag_tck(1'b0), .jtag_tms(1'b0), .jtag_tdi(1'b0), .jtag_tdo(), .jtag_trst_n(1'b0)
    );

    // =========================================================================
    // Capture shell output via periph_write to UART TX (addr 0x10000000)
    // =========================================================================
    logic [7:0] captured_bytes [0:MAX_CAPTURE-1];
    integer byte_count;
    integer prompt_count;

    initial begin
        byte_count = 0;
        prompt_count = 0;
        for (integer i = 0; i < MAX_CAPTURE; i++) captured_bytes[i] = 8'h00;
    end

    // Progress tracking
    integer last_report_count;
    initial last_report_count = 0;

    always @(posedge clk) begin
        if (u_dut.u_posix.periph_write &&
            u_dut.u_posix.periph_addr == 32'h10000000 &&
            byte_count < MAX_CAPTURE) begin

            captured_bytes[byte_count] = u_dut.u_posix.periph_wdata[7:0];
            byte_count = byte_count + 1;

            // Progress report every 200 bytes
            if (byte_count - last_report_count >= 200) begin
                $display("[TB] Progress: %0d bytes captured at t=%0t", byte_count, $time);
                last_report_count = byte_count;
            end

            // Check for "vsync> " prompt
            if (byte_count >= 7 &&
                captured_bytes[byte_count-7] == 8'h76 &&  // 'v'
                captured_bytes[byte_count-6] == 8'h73 &&  // 's'
                captured_bytes[byte_count-5] == 8'h79 &&  // 'y'
                captured_bytes[byte_count-4] == 8'h6E &&  // 'n'
                captured_bytes[byte_count-3] == 8'h63 &&  // 'c'
                captured_bytes[byte_count-2] == 8'h3E &&  // '>'
                captured_bytes[byte_count-1] == 8'h20) begin // ' '
                prompt_count = prompt_count + 1;
                $display("[TB] Prompt #%0d detected at byte %0d, t=%0t", prompt_count, byte_count, $time);
            end
        end
    end

    // Monitor UART RX FIFO activity (edge-triggered to avoid simulation slowdown)
    integer prev_rx_count;
    initial prev_rx_count = 0;
    always @(posedge clk) begin
        if (u_dut.u_uart.rx_count != prev_rx_count) begin
            if (prompt_count >= 1)
                $display("[TB] UART RX FIFO count: %0d -> %0d at t=%0t",
                         prev_rx_count, u_dut.u_uart.rx_count, $time);
            prev_rx_count <= u_dut.u_uart.rx_count;
        end
    end

    // =========================================================================
    // UART RX injection: send "help\r" directly via UART serial when prompted
    // =========================================================================
    // BAUD_DIV = round(25M / 115200) = 217 (fractional divider)
    localparam int BAUD_DIV = 217;
    localparam int CLKS_PER_BIT = BAUD_DIV;           // 217 clocks per bit

    task automatic uart_send_byte(input logic [7:0] data);
        integer i;
        uart_rx_drv = 1'b0;  // Start bit
        repeat(CLKS_PER_BIT) @(posedge clk);
        for (i = 0; i < 8; i = i + 1) begin
            uart_rx_drv = data[i];
            repeat(CLKS_PER_BIT) @(posedge clk);
        end
        uart_rx_drv = 1'b1;  // Stop bit
        repeat(CLKS_PER_BIT) @(posedge clk);
        repeat(CLKS_PER_BIT) @(posedge clk);  // Inter-character gap
    endtask

    // =========================================================================
    // Main test
    // =========================================================================
    initial begin
        rst_n = 1'b1;
        uart_rx_drv = 1'b1;
        repeat(RST_CYCLES) @(posedge clk);
        rst_n = 1'b0;
        $display("[TB] Reset released at %0t", $time);

        // Wait for first prompt
        fork
            begin
                wait(prompt_count >= 1);
                $display("[TB] First prompt at byte %0d, t=%0t", byte_count, $time);
            end
            begin
                #200_000_000;  // 200ms timeout (in ns - but $time will be ps)
                // Actually this is 200ms of sim time
            end
        join_any
        disable fork;

        if (prompt_count < 1) begin
            $display("[TB] WARN: No prompt after 200ms, captured %0d bytes", byte_count);
            // Continue anyway - dump what we have
        end

        // Send "help\r" if prompt was received
        if (prompt_count >= 1) begin
            repeat(CLKS_PER_BIT * 5) @(posedge clk);
            $display("[TB] Sending 'help' at %0t", $time);
            uart_send_byte(8'h68);  // 'h'
            $display("[TB] Sent 'h' at %0t, rx_count=%0d", $time, u_dut.u_uart.rx_count);
            uart_send_byte(8'h65);  // 'e'
            $display("[TB] Sent 'e' at %0t, rx_count=%0d", $time, u_dut.u_uart.rx_count);
            uart_send_byte(8'h6C);  // 'l'
            $display("[TB] Sent 'l' at %0t, rx_count=%0d", $time, u_dut.u_uart.rx_count);
            uart_send_byte(8'h70);  // 'p'
            $display("[TB] Sent 'p' at %0t, rx_count=%0d", $time, u_dut.u_uart.rx_count);
            uart_send_byte(8'h0D);  // '\r'
            $display("[TB] Sent CR at %0t, rx_count=%0d, bytes=%0d", $time, u_dut.u_uart.rx_count, byte_count);

            // Wait for second prompt (50ms should be plenty for help output)
            fork
                begin
                    wait(prompt_count >= 2);
                    $display("[TB] Second prompt at byte %0d, t=%0t", byte_count, $time);
                end
                begin
                    #50_000_000;  // 50ms timeout
                    $display("[TB] Prompt #2 timeout, bytes=%0d, prompts=%0d", byte_count, prompt_count);
                end
            join_any
            disable fork;
        end

        // Extra wait for trailing bytes
        repeat(1000) @(posedge clk);

        // =====================================================================
        // Display captured output
        // =====================================================================
        $display("");
        $display("============================================================");
        $display("[TB] Total bytes captured: %0d", byte_count);
        $display("[TB] Prompts detected: %0d", prompt_count);
        $display("============================================================");

        // Print all captured output as text
        $display("[TB] --- Captured Output ---");
        begin
            string line;
            line = "";
            for (integer i = 0; i < byte_count && i < MAX_CAPTURE; i = i + 1) begin
                if (captured_bytes[i] >= 8'h20 && captured_bytes[i] < 8'h7F)
                    line = {line, string'(captured_bytes[i])};
                else if (captured_bytes[i] == 8'h0D)
                    ;  // skip CR
                else if (captured_bytes[i] == 8'h0A) begin
                    $display("%s", line);
                    line = "";
                end else if (captured_bytes[i] == 8'h00)
                    line = {line, "\\0"};
            end
            if (line != "")
                $display("%s", line);
        end

        $display("============================================================");
        $display("[TB] Simulation complete at %0t", $time);
        $finish;
    end

    // Safety timeout
    initial begin
        #300_000_000;  // 300 ms
        $display("[TB] TIMEOUT at %0t, captured %0d bytes, prompts=%0d", $time, byte_count, prompt_count);
        // Dump what we have before finishing
        $display("[TB] --- Partial Output ---");
        begin
            string line;
            line = "";
            for (integer i = 0; i < byte_count && i < MAX_CAPTURE; i = i + 1) begin
                if (captured_bytes[i] >= 8'h20 && captured_bytes[i] < 8'h7F)
                    line = {line, string'(captured_bytes[i])};
                else if (captured_bytes[i] == 8'h0A) begin
                    $display("%s", line);
                    line = "";
                end else if (captured_bytes[i] == 8'h00)
                    line = {line, "\\0"};
                else if (captured_bytes[i] != 8'h0D)
                    line = {line, "."};
            end
            if (line != "") $display("%s", line);
        end
        $finish;
    end

endmodule
