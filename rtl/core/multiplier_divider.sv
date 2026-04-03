// =============================================================================
// VSync - Multiplier / Divider Unit (M-Extension)
// RISC-V RV32IM Processor
//
// File: multiplier_divider.sv
// Description: Multi-cycle multiplier and divider for RV32M extension
//              Supports MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
// Standard: IEEE 1800-2017 (SystemVerilog)
// =============================================================================

import vsync_pkg::*;

/**
 * @brief M-Extension multiplier/divider unit
 *
 * Multiplication: single-cycle 32x32 -> 64-bit result.
 * Division: multi-cycle (32-cycle) restoring divider.
 * Handles RISC-V specified corner cases:
 *   - Division by zero: DIV/DIVU -> all-ones, REM/REMU -> dividend
 *   - Signed overflow (MIN_INT / -1): DIV -> MIN_INT, REM -> 0
 */
module multiplier_divider (
    input  logic             clk,
    input  logic             rst_n,

    // Control interface
    input  logic             start,        // Start operation pulse
    input  mext_op_t         op,           // M-extension operation type
    input  logic [XLEN-1:0]  operand_a,    // Source operand A (rs1)
    input  logic [XLEN-1:0]  operand_b,    // Source operand B (rs2)

    // Result interface
    output logic [XLEN-1:0]  result,       // Operation result
    output logic             done,         // Result valid (single-cycle pulse)
    output logic             busy          // Unit is busy (cannot accept new op)
);

    // =========================================================================
    // Internal signals
    // =========================================================================

    // Division state machine
    typedef enum logic [1:0] {
        DIV_IDLE  = 2'b00,
        DIV_CALC  = 2'b01,
        DIV_DONE  = 2'b10,
        DIV_HOLD  = 2'b11
    } div_state_t;

    div_state_t              div_state, div_state_next;
    logic [4:0]              div_count;        // Division cycle counter (0-31)

    // Latched operation info
    mext_op_t                op_latched;
    logic [XLEN-1:0]         operand_a_latched;
    logic [XLEN-1:0]         operand_b_latched;

    // Multiplication signals
    logic signed   [XLEN-1:0] a_signed;
    logic signed   [XLEN-1:0] b_signed;
    logic unsigned [XLEN-1:0] a_unsigned;
    logic unsigned [XLEN-1:0] b_unsigned;

    logic signed   [2*XLEN-1:0] mul_ss;     // signed * signed
    logic signed   [2*XLEN:0]   mul_su;     // signed * unsigned (extra bit)
    logic unsigned [2*XLEN-1:0] mul_uu;     // unsigned * unsigned

    logic [XLEN-1:0]         mul_result;
    logic                    is_mul_op;

    // Division signals
    logic                    is_div_op;
    logic                    div_by_zero;
    logic                    div_overflow;
    logic                    a_neg, b_neg;
    logic [XLEN-1:0]         abs_a, abs_b;
    logic [XLEN-1:0]         quotient, remainder;
    logic [XLEN-1:0]         div_result;
    logic                    is_signed_div;

    // Restoring divider registers
    logic [XLEN-1:0]         div_quotient;
    logic [XLEN:0]           div_remainder;   // 33-bit for subtraction overflow detection
    logic [XLEN-1:0]         div_divisor;

    // =========================================================================
    // Operation type classification
    // =========================================================================
    assign is_mul_op = (op == MEXT_MUL) || (op == MEXT_MULH) ||
                       (op == MEXT_MULHSU) || (op == MEXT_MULHU);
    assign is_div_op = (op == MEXT_DIV) || (op == MEXT_DIVU) ||
                       (op == MEXT_REM) || (op == MEXT_REMU);

    assign is_signed_div = (op_latched == MEXT_DIV) || (op_latched == MEXT_REM);

    // =========================================================================
    // Multiplication (combinational, single-cycle)
    // =========================================================================
    assign a_signed   = $signed(operand_a);
    assign b_signed   = $signed(operand_b);
    assign a_unsigned = operand_a;
    assign b_unsigned = operand_b;

    // Full 64-bit multiplication results
    assign mul_ss = a_signed * b_signed;
    assign mul_su = a_signed * $signed({1'b0, b_unsigned});
    assign mul_uu = a_unsigned * b_unsigned;

    // Select multiplication result
    always_comb begin
        case (op)
            MEXT_MUL:    mul_result = mul_ss[XLEN-1:0];         // Lower 32 bits
            MEXT_MULH:   mul_result = mul_ss[2*XLEN-1:XLEN];   // Upper 32 bits (s*s)
            MEXT_MULHSU: mul_result = mul_su[2*XLEN-1:XLEN];   // Upper 32 bits (s*u)
            MEXT_MULHU:  mul_result = mul_uu[2*XLEN-1:XLEN];   // Upper 32 bits (u*u)
            default:     mul_result = '0;
        endcase
    end

    // =========================================================================
    // Division corner case detection
    // =========================================================================
    assign div_by_zero = (operand_b == '0);

    // Overflow: signed minimum / -1  (e.g., -2^31 / -1)
    assign div_overflow = (op == MEXT_DIV || op == MEXT_REM) &&
                          (operand_a == {1'b1, {(XLEN-1){1'b0}}}) &&  // MIN_INT
                          (operand_b == '1);                             // -1

    // =========================================================================
    // Division: absolute value computation for signed operations
    // =========================================================================
    assign a_neg = operand_a[XLEN-1];
    assign b_neg = operand_b[XLEN-1];

    always_comb begin
        if ((op == MEXT_DIV || op == MEXT_REM) && a_neg)
            abs_a = ~operand_a + 1'b1;
        else
            abs_a = operand_a;

        if ((op == MEXT_DIV || op == MEXT_REM) && b_neg)
            abs_b = ~operand_b + 1'b1;
        else
            abs_b = operand_b;
    end

    // =========================================================================
    // Division result with sign correction (combinational)
    // =========================================================================
    always_comb begin
        quotient  = div_quotient;
        remainder = div_remainder[XLEN-1:0];

        // Apply sign correction for signed division
        if (is_signed_div) begin
            // Quotient sign: negative if operands have different signs
            if (operand_a_latched[XLEN-1] ^ operand_b_latched[XLEN-1])
                quotient = ~div_quotient + 1'b1;

            // Remainder sign: same as dividend
            if (operand_a_latched[XLEN-1])
                remainder = ~div_remainder[XLEN-1:0] + 1'b1;
        end
    end

    // =========================================================================
    // Division state machine
    // =========================================================================
    // Standard restoring division: N iterations for N-bit dividend.
    // Each iteration: shift {R, Q} left, compare R with D, update.
    // Initialization: R=0, Q=abs_dividend (no pre-shift).
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_state       <= DIV_IDLE;
            div_count       <= '0;
            div_quotient    <= '0;
            div_remainder   <= '0;
            div_divisor     <= '0;
            op_latched      <= MEXT_MUL;
            operand_a_latched <= '0;
            operand_b_latched <= '0;
        end else begin
            case (div_state)
                DIV_IDLE: begin
                    if (start && is_div_op && !div_by_zero && !div_overflow) begin
                        div_state       <= DIV_CALC;
                        div_count       <= '0;
                        div_divisor     <= abs_b;
                        op_latched      <= op;
                        operand_a_latched <= operand_a;
                        operand_b_latched <= operand_b;

                        // Initialize: R=0, Q=dividend (standard restoring division)
                        div_remainder   <= '0;
                        div_quotient    <= abs_a;
                    end
                end

                DIV_CALC: begin
                    // Standard restoring division step:
                    // 1. Left-shift {R, Q}: R gets Q's MSB, Q shifts left
                    // 2. Compare shifted R with divisor
                    // 3. If R >= D: subtract and set quotient bit to 1
                    //    Else: keep R, set quotient bit to 0
                    if ({div_remainder[XLEN-1:0], div_quotient[XLEN-1]} >= {1'b0, div_divisor}) begin
                        // Subtraction succeeds
                        div_remainder <= {div_remainder[XLEN-1:0], div_quotient[XLEN-1]} - {1'b0, div_divisor};
                        div_quotient  <= {div_quotient[XLEN-2:0], 1'b1};
                    end else begin
                        // Restore (keep remainder, shift in 0)
                        div_remainder <= {div_remainder[XLEN-1:0], div_quotient[XLEN-1]};
                        div_quotient  <= {div_quotient[XLEN-2:0], 1'b0};
                    end

                    div_count <= div_count + 5'd1;

                    if (div_count == 5'd31) begin
                        // 32 iterations complete (0 through 31)
                        div_state <= DIV_DONE;
                    end
                end

                DIV_DONE: begin
                    // Result visible via combinational output MUX.
                    // Transition to HOLD so result remains stable on outputs
                    // after non-blocking assignments settle (for testbench sampling).
                    div_state <= DIV_HOLD;
                end

                DIV_HOLD: begin
                    // Return to idle
                    div_state <= DIV_IDLE;
                end

                default: begin
                    div_state <= DIV_IDLE;
                end
            endcase
        end
    end

    // =========================================================================
    // Result MUX and output control
    // =========================================================================
    always_comb begin
        result = '0;
        done   = 1'b0;
        busy   = 1'b0;

        if (start && is_mul_op) begin
            // Multiplication: single-cycle, result available immediately
            result = mul_result;
            done   = 1'b1;
        end else if (start && is_div_op && div_by_zero) begin
            // Division by zero: immediate result per RISC-V spec
            case (op)
                MEXT_DIV,
                MEXT_DIVU:  result = {XLEN{1'b1}};  // All ones (-1 unsigned)
                MEXT_REM,
                MEXT_REMU:  result = operand_a;       // Dividend
                default:    result = '0;
            endcase
            done = 1'b1;
        end else if (start && is_div_op && div_overflow) begin
            // Signed overflow (MIN_INT / -1): immediate result per RISC-V spec
            case (op)
                MEXT_DIV: result = {1'b1, {(XLEN-1){1'b0}}};  // MIN_INT
                MEXT_REM: result = '0;                           // 0
                default:  result = '0;
            endcase
            done = 1'b1;
        end else if (div_state == DIV_DONE || div_state == DIV_HOLD) begin
            // Division result available in both DONE and HOLD states.
            // HOLD ensures result stays stable after NBA settles.
            case (op_latched)
                MEXT_DIV,
                MEXT_DIVU:  result = quotient;
                MEXT_REM,
                MEXT_REMU:  result = remainder;
                default:    result = '0;
            endcase
            done = 1'b1;
        end else if (div_state == DIV_CALC) begin
            busy = 1'b1;
        end
    end

endmodule : multiplier_divider
