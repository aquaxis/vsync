#!/bin/bash
# VSync Test Runner Script
# Compiles and runs all testbenches with iverilog
# Usage: ./tb/run_tests.sh [test_name]

set -e

PROJ_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RTL_DIR="$PROJ_ROOT/rtl"
TB_DIR="$PROJ_ROOT/tb"
OUT_DIR="/tmp/vsync_tests"
mkdir -p "$OUT_DIR"

# Common iverilog flags
IV_FLAGS="-g2012 -DIVERILOG -I${RTL_DIR}/core -I${TB_DIR}/common"

# Common RTL package
PKG="$RTL_DIR/core/vsync_pkg.sv"
CLK_RST="$TB_DIR/common/clk_rst_gen.sv"

# Results tracking
PASS_COUNT=0
FAIL_COUNT=0
COMPILE_FAIL=0
RUNTIME_FAIL=0
RESULTS=""
DETAIL_RESULTS=""

# Timeout settings (seconds)
DEFAULT_TIMEOUT=60
HEAVY_TIMEOUT=180  # For pipeline/integration tests

# Parse test log to extract PASS/FAIL counts
# Handles two output formats:
#   Format A (test_utils.sv): "Passed: N" / "Failed: N"
#   Format B (manual):        "PASS  : N" / "FAIL  : N"
parse_test_results() {
    local logfile="$1"
    local name="$2"

    # Extract pass/fail counts from summary section
    # Format A: "Passed: 179" / "Failed: 32" (test_utils.sv)
    local passed_a=$(grep -oP '(?i)Passed\s*:\s*\K[0-9]+' "$logfile" 2>/dev/null | tail -1)
    # Format B: "PASS  : 22" (manual testbenches)
    local passed_b=$(grep -oP '(?i)PASS\s*:\s*\K[0-9]+' "$logfile" 2>/dev/null | tail -1)

    local failed_a=$(grep -oP '(?i)Failed\s*:\s*\K[0-9]+' "$logfile" 2>/dev/null | tail -1)
    local failed_b=$(grep -oP '(?i)FAIL\s*:\s*\K[0-9]+' "$logfile" 2>/dev/null | tail -1)

    # Use whichever format matched (prefer Format A if both present)
    local pass_cnt="${passed_a:-${passed_b:-0}}"
    local fail_cnt="${failed_a:-${failed_b:-0}}"

    # Also check for "ALL TESTS PASSED" as a definitive pass indicator
    if grep -q "ALL TESTS PASSED" "$logfile" 2>/dev/null; then
        fail_cnt=0
    fi

    # Check for explicit failure markers
    # "RESULT: N TEST(S) FAILED" or "Result: *** N TEST(S) FAILED ***"
    local result_fail=$(grep -oP '(?i)RESULT:\s*\**\s*\K[0-9]+(?=\s+TEST\(S\)\s+FAILED)' "$logfile" 2>/dev/null | tail -1)
    if [ -n "$result_fail" ] && [ "$result_fail" -gt 0 ]; then
        fail_cnt="$result_fail"
    fi

    echo "${pass_cnt}:${fail_cnt}"
}

compile_and_run() {
    local name="$1"
    shift
    local timeout_val="$DEFAULT_TIMEOUT"

    # Check for --timeout=N option
    if [[ "$1" == --timeout=* ]]; then
        timeout_val="${1#--timeout=}"
        shift
    fi

    local files="$@"

    echo "================================================================"
    echo " Compiling: $name"
    echo "================================================================"

    local outfile="$OUT_DIR/${name}.out"
    local logfile="$OUT_DIR/${name}.log"

    if iverilog $IV_FLAGS -o "$outfile" $files 2>"$OUT_DIR/${name}_compile.log"; then
        echo " [COMPILE OK] $name"

        echo "----------------------------------------------------------------"
        echo " Running: $name (timeout: ${timeout_val}s)"
        echo "----------------------------------------------------------------"

        local vvp_exit=0
        timeout "$timeout_val" vvp "$outfile" > "$logfile" 2>&1 || vvp_exit=$?

        if [ "$vvp_exit" -eq 124 ]; then
            # timeout(1) returns 124 when command times out
            echo " [TIMEOUT] $name (exceeded ${timeout_val}s)"
            RUNTIME_FAIL=$((RUNTIME_FAIL + 1))
            RESULTS="$RESULTS\n[RUNTIME_FAIL] $name (timeout ${timeout_val}s)"
            DETAIL_RESULTS="$DETAIL_RESULTS\n  $name: RUNTIME_FAIL (timeout) P:- F:-"
        elif [ ! -s "$logfile" ]; then
            # Empty log = runtime crash before any output
            echo " [RUNTIME ERROR] $name (no output produced)"
            RUNTIME_FAIL=$((RUNTIME_FAIL + 1))
            RESULTS="$RESULTS\n[RUNTIME_FAIL] $name (crash)"
            DETAIL_RESULTS="$DETAIL_RESULTS\n  $name: RUNTIME_FAIL (crash) P:- F:-"
        else
            # Parse results from log (works for both exit=0 and exit!=0)
            # vvp returns non-zero when $fatal is called, but test results
            # are still valid in the log
            local counts
            counts=$(parse_test_results "$logfile" "$name")
            local pass_cnt="${counts%%:*}"
            local fail_cnt="${counts##*:}"

            local summary=$(grep -E "RESULT:|ALL TESTS|TEST SUITE SUMMARY|TEST SUMMARY" "$logfile" | tail -3)

            if [ "$fail_cnt" -gt 0 ]; then
                echo " [TEST_FAIL] $name (Pass:$pass_cnt Fail:$fail_cnt)"
                FAIL_COUNT=$((FAIL_COUNT + 1))
                RESULTS="$RESULTS\n[TEST_FAIL] $name (P:$pass_cnt F:$fail_cnt)"
                DETAIL_RESULTS="$DETAIL_RESULTS\n  $name: TEST_FAIL P:$pass_cnt F:$fail_cnt"
            else
                echo " [PASS] $name (Pass:$pass_cnt Fail:$fail_cnt)"
                PASS_COUNT=$((PASS_COUNT + 1))
                RESULTS="$RESULTS\n[PASS] $name (P:$pass_cnt)"
                DETAIL_RESULTS="$DETAIL_RESULTS\n  $name: PASS P:$pass_cnt F:0"
            fi

            if [ -n "$summary" ]; then
                echo "$summary"
            fi

            # Show vvp exit code if non-zero (informational)
            if [ "$vvp_exit" -ne 0 ]; then
                echo "  (vvp exit code: $vvp_exit - likely \$fatal in testbench)"
            fi
        fi
    else
        echo " [COMPILE FAILED] $name"
        cat "$OUT_DIR/${name}_compile.log" | head -20
        COMPILE_FAIL=$((COMPILE_FAIL + 1))
        RESULTS="$RESULTS\n[COMPILE_FAIL] $name"
        DETAIL_RESULTS="$DETAIL_RESULTS\n  $name: COMPILE_FAIL"
    fi
    echo ""
}

echo "============================================================"
echo " VSync Test Runner - $(date)"
echo "============================================================"
echo ""

# Priority 1: ALU
compile_and_run "tb_alu" \
    "$PKG" "$RTL_DIR/core/alu.sv" "$TB_DIR/core/tb_alu.sv"

# Priority 1b: RV32I ALU (pipeline-level)
compile_and_run "tb_rv32i_alu" \
    "$PKG" "$CLK_RST" \
    "$RTL_DIR/core/alu.sv" "$RTL_DIR/core/immediate_gen.sv" \
    "$RTL_DIR/core/register_file.sv" "$RTL_DIR/core/branch_unit.sv" \
    "$RTL_DIR/core/decode_stage.sv" "$RTL_DIR/core/execute_stage.sv" \
    "$RTL_DIR/core/fetch_stage.sv" "$RTL_DIR/core/memory_stage.sv" \
    "$RTL_DIR/core/writeback_stage.sv" "$RTL_DIR/core/hazard_unit.sv" \
    "$RTL_DIR/core/csr_unit.sv" "$RTL_DIR/core/exception_unit.sv" \
    "$RTL_DIR/core/multiplier_divider.sv" \
    "$TB_DIR/core/tb_rv32i_alu.sv"

# Priority 2: Register File
compile_and_run "tb_register_file" \
    "$PKG" "$CLK_RST" "$RTL_DIR/core/register_file.sv" \
    "$TB_DIR/core/tb_register_file.sv"

# Priority 3: Multiplier/Divider (needs extra time for division ops)
compile_and_run "tb_multiplier_divider" --timeout=120 \
    "$PKG" "$CLK_RST" "$RTL_DIR/core/multiplier_divider.sv" \
    "$TB_DIR/core/tb_multiplier_divider.sv"

# Priority 4: Pipeline (complex integration, needs extra time)
compile_and_run "tb_pipeline" --timeout=120 \
    "$PKG" "$CLK_RST" \
    "$RTL_DIR/core/alu.sv" "$RTL_DIR/core/immediate_gen.sv" \
    "$RTL_DIR/core/register_file.sv" "$RTL_DIR/core/branch_unit.sv" \
    "$RTL_DIR/core/decode_stage.sv" "$RTL_DIR/core/execute_stage.sv" \
    "$RTL_DIR/core/fetch_stage.sv" "$RTL_DIR/core/memory_stage.sv" \
    "$RTL_DIR/core/writeback_stage.sv" "$RTL_DIR/core/hazard_unit.sv" \
    "$RTL_DIR/core/csr_unit.sv" "$RTL_DIR/core/exception_unit.sv" \
    "$RTL_DIR/core/multiplier_divider.sv" \
    "$RTL_DIR/core/rv32im_core.sv" \
    "$TB_DIR/core/tb_pipeline.sv"

# Priority 5: CSR
compile_and_run "tb_csr" \
    "$PKG" "$CLK_RST" "$RTL_DIR/core/csr_unit.sv" \
    "$TB_DIR/core/tb_csr.sv"

# Priority 6: Exception
compile_and_run "tb_exception" \
    "$PKG" "$CLK_RST" "$RTL_DIR/core/exception_unit.sv" \
    "$TB_DIR/core/tb_exception.sv"

# Priority 7: AXI4 Protocol
compile_and_run "tb_axi4_protocol" \
    "$PKG" "$CLK_RST" "$RTL_DIR/bus/axi4_master.sv" \
    "$TB_DIR/bus/tb_axi4_protocol.sv"

# Priority 7b: AXI4-APB Bridge
compile_and_run "tb_axi4_apb_bridge" \
    "$PKG" "$CLK_RST" "$RTL_DIR/bus/axi4_apb_bridge.sv" \
    "$TB_DIR/common/axi4_bfm.sv" "$TB_DIR/common/apb_bfm.sv" \
    "$TB_DIR/bus/tb_axi4_apb_bridge.sv"

# Priority 8: BRAM
compile_and_run "tb_bram" \
    "$PKG" "$CLK_RST" \
    "$RTL_DIR/memory/bram_imem.sv" "$RTL_DIR/memory/bram_dmem.sv" \
    "$TB_DIR/memory/tb_bram.sv"

# Priority 8b: HyperRAM
compile_and_run "tb_hyperram" \
    "$PKG" "$CLK_RST" "$RTL_DIR/memory/hyperram_ctrl.sv" \
    "$TB_DIR/common/axi4_bfm.sv" \
    "$TB_DIR/memory/tb_hyperram.sv"

# Priority 9: Peripherals
compile_and_run "tb_uart" \
    "$PKG" "$CLK_RST" "$RTL_DIR/peripherals/uart_apb.sv" \
    "$TB_DIR/common/apb_bfm.sv" "$TB_DIR/peripherals/tb_uart.sv"

compile_and_run "tb_gpio" \
    "$PKG" "$CLK_RST" "$RTL_DIR/peripherals/gpio_apb.sv" \
    "$TB_DIR/common/apb_bfm.sv" "$TB_DIR/peripherals/tb_gpio.sv"

# Priority 10: RTOS
for rtos_tb in tb_task_mgmt tb_scheduler tb_context_switch tb_semaphore tb_mutex tb_msgqueue tb_pmp; do
    rtl_files="$PKG $CLK_RST"
    rtl_files="$rtl_files $RTL_DIR/rtos/task_scheduler.sv $RTL_DIR/rtos/tcb_array.sv"
    rtl_files="$rtl_files $RTL_DIR/rtos/context_switch.sv $RTL_DIR/rtos/hw_semaphore.sv"
    rtl_files="$rtl_files $RTL_DIR/rtos/hw_mutex.sv $RTL_DIR/rtos/hw_msgqueue.sv"
    rtl_files="$rtl_files $RTL_DIR/rtos/pmp_unit.sv $RTL_DIR/rtos/hw_rtos.sv"
    compile_and_run "$rtos_tb" \
        $rtl_files "$TB_DIR/rtos/${rtos_tb}.sv"
done

compile_and_run "test_hw_rtos" --timeout=120 \
    "$PKG" "$CLK_RST" \
    "$RTL_DIR/rtos/task_scheduler.sv" "$RTL_DIR/rtos/tcb_array.sv" \
    "$RTL_DIR/rtos/context_switch.sv" "$RTL_DIR/rtos/hw_semaphore.sv" \
    "$RTL_DIR/rtos/hw_mutex.sv" "$RTL_DIR/rtos/hw_msgqueue.sv" \
    "$RTL_DIR/rtos/pmp_unit.sv" "$RTL_DIR/rtos/hw_rtos.sv" \
    "$TB_DIR/rtos/test_hw_rtos.sv"

# Priority 11: POSIX
for posix_tb in tb_syscall tb_pthread tb_fd tb_timer; do
    compile_and_run "$posix_tb" \
        "$PKG" "$CLK_RST" "$RTL_DIR/posix/posix_hw_layer.sv" \
        "$TB_DIR/posix/${posix_tb}.sv"
done

# Priority 12: Interrupt
compile_and_run "tb_plic" \
    "$PKG" "$CLK_RST" "$RTL_DIR/interrupt/plic.sv" \
    "$TB_DIR/interrupt/tb_plic.sv"

compile_and_run "tb_clint" \
    "$PKG" "$CLK_RST" "$RTL_DIR/interrupt/clint.sv" \
    "$TB_DIR/interrupt/tb_clint.sv"

# Priority 13: Integration (full core, needs extra time)
compile_and_run "test_rv32im_core" --timeout=120 \
    "$PKG" "$CLK_RST" \
    "$RTL_DIR/core/alu.sv" "$RTL_DIR/core/immediate_gen.sv" \
    "$RTL_DIR/core/register_file.sv" "$RTL_DIR/core/branch_unit.sv" \
    "$RTL_DIR/core/decode_stage.sv" "$RTL_DIR/core/execute_stage.sv" \
    "$RTL_DIR/core/fetch_stage.sv" "$RTL_DIR/core/memory_stage.sv" \
    "$RTL_DIR/core/writeback_stage.sv" "$RTL_DIR/core/hazard_unit.sv" \
    "$RTL_DIR/core/csr_unit.sv" "$RTL_DIR/core/exception_unit.sv" \
    "$RTL_DIR/core/multiplier_divider.sv" \
    "$RTL_DIR/core/rv32im_core.sv" \
    "$RTL_DIR/memory/bram_imem.sv" "$RTL_DIR/memory/bram_dmem.sv" \
    "$TB_DIR/core/test_rv32im_core.sv"

# Priority 14: Integration - UART Shell Load/Go (CPU + IMEM + UART, needs extra time)
# Uses rv32im_core directly (bypasses vsync_top due to iverilog unpacked array limitation)
# Tests: CPU fetch from IMEM → execute → UART MMIO write → serial TX output
compile_and_run "tb_uart_shell_loadgo" --timeout=300 \
    "$PKG" "$CLK_RST" \
    "$RTL_DIR/core/alu.sv" "$RTL_DIR/core/immediate_gen.sv" \
    "$RTL_DIR/core/register_file.sv" "$RTL_DIR/core/branch_unit.sv" \
    "$RTL_DIR/core/decode_stage.sv" "$RTL_DIR/core/execute_stage.sv" \
    "$RTL_DIR/core/fetch_stage.sv" "$RTL_DIR/core/memory_stage.sv" \
    "$RTL_DIR/core/writeback_stage.sv" "$RTL_DIR/core/hazard_unit.sv" \
    "$RTL_DIR/core/csr_unit.sv" "$RTL_DIR/core/exception_unit.sv" \
    "$RTL_DIR/core/multiplier_divider.sv" \
    "$RTL_DIR/core/rv32im_core.sv" \
    "$RTL_DIR/memory/bram_imem.sv" \
    "$RTL_DIR/peripherals/uart_apb.sv" \
    "$TB_DIR/integration/tb_uart_shell_loadgo.sv"

# Priority 15: vsync_top Full SoC Integration Test
# Tests full SoC: CPU → AXI4 bus → APB bridge → UART TX
compile_and_run "tb_vsync_top_soc" --timeout=600 \
    "$PKG" "$CLK_RST" \
    "$RTL_DIR/core/alu.sv" "$RTL_DIR/core/immediate_gen.sv" \
    "$RTL_DIR/core/register_file.sv" "$RTL_DIR/core/branch_unit.sv" \
    "$RTL_DIR/core/decode_stage.sv" "$RTL_DIR/core/execute_stage.sv" \
    "$RTL_DIR/core/fetch_stage.sv" "$RTL_DIR/core/memory_stage.sv" \
    "$RTL_DIR/core/writeback_stage.sv" "$RTL_DIR/core/hazard_unit.sv" \
    "$RTL_DIR/core/csr_unit.sv" "$RTL_DIR/core/exception_unit.sv" \
    "$RTL_DIR/core/multiplier_divider.sv" \
    "$RTL_DIR/core/rv32im_core.sv" \
    "$RTL_DIR/memory/bram_imem.sv" "$RTL_DIR/memory/bram_dmem.sv" \
    "$RTL_DIR/memory/hyperram_ctrl.sv" \
    "$RTL_DIR/bus/axi4_master.sv" "$RTL_DIR/bus/axi4_interconnect.sv" \
    "$RTL_DIR/bus/axi4_apb_bridge.sv" \
    "$RTL_DIR/interrupt/clint.sv" "$RTL_DIR/interrupt/plic.sv" \
    "$RTL_DIR/peripherals/uart_apb.sv" "$RTL_DIR/peripherals/gpio_apb.sv" \
    "$RTL_DIR/rtos/tcb_array.sv" "$RTL_DIR/rtos/task_scheduler.sv" \
    "$RTL_DIR/rtos/context_switch.sv" "$RTL_DIR/rtos/hw_mutex.sv" \
    "$RTL_DIR/rtos/hw_semaphore.sv" "$RTL_DIR/rtos/hw_msgqueue.sv" \
    "$RTL_DIR/rtos/pmp_unit.sv" "$RTL_DIR/rtos/hw_rtos.sv" \
    "$RTL_DIR/posix/posix_hw_layer.sv" \
    "$RTL_DIR/top/vsync_top.sv" \
    "$TB_DIR/integration/tb_vsync_top_soc.sv"

echo ""
echo "============================================================"
echo " OVERALL RESULTS"
echo "============================================================"
echo -e "$RESULTS"
echo ""
echo "------------------------------------------------------------"
echo " DETAILED RESULTS (per test)"
echo "------------------------------------------------------------"
echo -e "$DETAIL_RESULTS"
echo ""
echo "------------------------------------------------------------"
echo " SUMMARY"
echo "------------------------------------------------------------"
echo " PASS:          $PASS_COUNT"
echo " TEST_FAIL:     $FAIL_COUNT"
echo " COMPILE_FAIL:  $COMPILE_FAIL"
echo " RUNTIME_FAIL:  $RUNTIME_FAIL"
echo " Total:         $((COMPILE_FAIL + PASS_COUNT + FAIL_COUNT + RUNTIME_FAIL))"
echo "============================================================"

# Generate JSON summary for automated reporting
JSON_FILE="$OUT_DIR/results_summary.json"
{
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"pass_count\": $PASS_COUNT,"
    echo "  \"test_fail_count\": $FAIL_COUNT,"
    echo "  \"compile_fail_count\": $COMPILE_FAIL,"
    echo "  \"runtime_fail_count\": $RUNTIME_FAIL,"
    echo "  \"total\": $((COMPILE_FAIL + PASS_COUNT + FAIL_COUNT + RUNTIME_FAIL))"
    echo "}"
} > "$JSON_FILE"
echo ""
echo " JSON summary saved to: $JSON_FILE"
echo "============================================================"
