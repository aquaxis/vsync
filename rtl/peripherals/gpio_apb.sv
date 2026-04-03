// =============================================================================
// VSync - GPIO Controller with APB Slave Interface
//
// File: gpio_apb.sv
// Description: General Purpose I/O controller with configurable width,
//              direction control, and interrupt support (edge/level).
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

module gpio_apb #(
    parameter int GPIO_WIDTH = 32
) (
    // Clock & Reset
    input  logic                    clk,
    input  logic                    rst_n,

    // APB Slave Interface
    input  logic                    apb_psel,
    input  logic                    apb_penable,
    input  logic                    apb_pwrite,
    input  logic [7:0]              apb_paddr,
    input  logic [31:0]             apb_pwdata,
    output logic [31:0]             apb_prdata,
    output logic                    apb_pready,
    output logic                    apb_pslverr,

    // GPIO Pins
    input  logic [GPIO_WIDTH-1:0]   gpio_in,
    output logic [GPIO_WIDTH-1:0]   gpio_out,
    output logic [GPIO_WIDTH-1:0]   gpio_oe,

    // Interrupt
    output logic                    irq
);

    // =========================================================================
    // Register Address Offsets
    // =========================================================================
    localparam logic [7:0] REG_GPIO_OUT        = 8'h00;
    localparam logic [7:0] REG_GPIO_IN         = 8'h04;
    localparam logic [7:0] REG_GPIO_DIR        = 8'h08;
    localparam logic [7:0] REG_GPIO_INT_EN     = 8'h0C;
    localparam logic [7:0] REG_GPIO_INT_STATUS = 8'h10;
    localparam logic [7:0] REG_GPIO_INT_TYPE   = 8'h14;
    localparam logic [7:0] REG_GPIO_INT_POL    = 8'h18;

    // =========================================================================
    // Register Declarations
    // =========================================================================
    logic [GPIO_WIDTH-1:0] gpio_out_r;
    logic [GPIO_WIDTH-1:0] gpio_dir_r;        // 0=input, 1=output
    logic [GPIO_WIDTH-1:0] gpio_int_en_r;
    logic [GPIO_WIDTH-1:0] gpio_int_status_r;
    logic [GPIO_WIDTH-1:0] gpio_int_type_r;   // 0=level, 1=edge
    logic [GPIO_WIDTH-1:0] gpio_int_pol_r;    // 0=Low/Falling, 1=High/Rising

    // =========================================================================
    // Input Synchronization (double-flop)
    // =========================================================================
    logic [GPIO_WIDTH-1:0] gpio_in_sync1;
    logic [GPIO_WIDTH-1:0] gpio_in_sync2;
    logic [GPIO_WIDTH-1:0] gpio_in_prev;

    /** @brief GPIO input synchronizer (metastability protection) */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_in_sync1 <= '0;
            gpio_in_sync2 <= '0;
            gpio_in_prev  <= '0;
        end else begin
            gpio_in_sync1 <= gpio_in;
            gpio_in_sync2 <= gpio_in_sync1;
            gpio_in_prev  <= gpio_in_sync2;
        end
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign gpio_out = gpio_out_r;
    assign gpio_oe  = gpio_dir_r;

    // =========================================================================
    // Edge Detection
    // =========================================================================
    logic [GPIO_WIDTH-1:0] rising_edge;
    logic [GPIO_WIDTH-1:0] falling_edge;

    assign rising_edge  = gpio_in_sync2 & ~gpio_in_prev;
    assign falling_edge = ~gpio_in_sync2 & gpio_in_prev;

    // =========================================================================
    // Interrupt Detection
    // =========================================================================
    logic [GPIO_WIDTH-1:0] int_detect;

    /** @brief Interrupt detection: edge or level based on configuration */
    always_comb begin
        for (int i = 0; i < GPIO_WIDTH; i++) begin
            if (gpio_int_type_r[i]) begin
                // Edge-triggered
                if (gpio_int_pol_r[i])
                    int_detect[i] = rising_edge[i];   // Rising edge
                else
                    int_detect[i] = falling_edge[i];  // Falling edge
            end else begin
                // Level-triggered
                if (gpio_int_pol_r[i])
                    int_detect[i] = gpio_in_sync2[i];  // High level
                else
                    int_detect[i] = ~gpio_in_sync2[i]; // Low level
            end
        end
    end

    // =========================================================================
    // APB Slave Interface
    // =========================================================================
    logic apb_write_en;
    logic apb_read_en;

    assign apb_write_en = apb_psel && apb_penable && apb_pwrite;
    assign apb_read_en  = apb_psel && apb_penable && !apb_pwrite;
    assign apb_pready   = apb_psel && apb_penable;  // Always ready
    assign apb_pslverr  = 1'b0;

    /** @brief APB register write and interrupt status update logic */
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_out_r        <= '0;
            gpio_dir_r        <= '0;   // All inputs by default
            gpio_int_en_r     <= '0;
            gpio_int_status_r <= '0;
            gpio_int_type_r   <= '0;
            gpio_int_pol_r    <= '0;
        end else begin
            // Update interrupt status (set on detection)
            gpio_int_status_r <= gpio_int_status_r | (int_detect & gpio_int_en_r);

            // APB writes
            if (apb_write_en) begin
                case (apb_paddr)
                    REG_GPIO_OUT: begin
                        gpio_out_r <= apb_pwdata[GPIO_WIDTH-1:0];
                    end
                    REG_GPIO_DIR: begin
                        gpio_dir_r <= apb_pwdata[GPIO_WIDTH-1:0];
                    end
                    REG_GPIO_INT_EN: begin
                        gpio_int_en_r <= apb_pwdata[GPIO_WIDTH-1:0];
                    end
                    REG_GPIO_INT_STATUS: begin
                        // Write-1-to-Clear (W1C)
                        gpio_int_status_r <= gpio_int_status_r & ~apb_pwdata[GPIO_WIDTH-1:0];
                    end
                    REG_GPIO_INT_TYPE: begin
                        gpio_int_type_r <= apb_pwdata[GPIO_WIDTH-1:0];
                    end
                    REG_GPIO_INT_POL: begin
                        gpio_int_pol_r <= apb_pwdata[GPIO_WIDTH-1:0];
                    end
                    default: ; // REG_GPIO_IN is read-only
                endcase
            end
        end
    end

    /** @brief APB register read logic */
    always_comb begin
        apb_prdata = 32'h0;

        if (apb_read_en) begin
            case (apb_paddr)
                REG_GPIO_OUT:        apb_prdata = {{(32-GPIO_WIDTH){1'b0}}, gpio_out_r};
                REG_GPIO_IN:         apb_prdata = {{(32-GPIO_WIDTH){1'b0}}, gpio_in_sync2};
                REG_GPIO_DIR:        apb_prdata = {{(32-GPIO_WIDTH){1'b0}}, gpio_dir_r};
                REG_GPIO_INT_EN:     apb_prdata = {{(32-GPIO_WIDTH){1'b0}}, gpio_int_en_r};
                REG_GPIO_INT_STATUS: apb_prdata = {{(32-GPIO_WIDTH){1'b0}}, gpio_int_status_r};
                REG_GPIO_INT_TYPE:   apb_prdata = {{(32-GPIO_WIDTH){1'b0}}, gpio_int_type_r};
                REG_GPIO_INT_POL:    apb_prdata = {{(32-GPIO_WIDTH){1'b0}}, gpio_int_pol_r};
                default:             apb_prdata = 32'h0;
            endcase
        end
    end

    // =========================================================================
    // IRQ Output
    // =========================================================================
    /** @brief IRQ: OR of all enabled and active interrupt status bits */
    assign irq = |(gpio_int_status_r & gpio_int_en_r);

endmodule : gpio_apb
