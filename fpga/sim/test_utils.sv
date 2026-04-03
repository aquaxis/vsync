// =============================================================================
// VSync - Test Utilities Package
// =============================================================================
// Common test utility functions, macros, and definitions used across all
// testbenches in the VSync project.
// =============================================================================

`ifndef TEST_UTILS_SV
`define TEST_UTILS_SV

package test_utils;

    // =========================================================================
    // Test result tracking
    // =========================================================================
    int unsigned test_pass_count = 0;
    int unsigned test_fail_count = 0;
    int unsigned test_total_count = 0;
    string       current_test_name = "";

    // =========================================================================
    // Assertion severity levels
    // =========================================================================
    typedef enum {
        SEV_INFO,
        SEV_WARNING,
        SEV_ERROR,
        SEV_FATAL
    } severity_t;

    // =========================================================================
    // Test lifecycle functions
    // =========================================================================

    // Initialize test suite
    function void test_suite_begin(string suite_name);
        $display("=============================================================");
        $display(" TEST SUITE: %s", suite_name);
        $display(" Timestamp: %0t", $time);
        $display("=============================================================");
        test_pass_count  = 0;
        test_fail_count  = 0;
        test_total_count = 0;
    endfunction

    // Begin individual test case
    function void test_begin(string test_name);
        current_test_name = test_name;
        test_total_count++;
        $display("-------------------------------------------------------------");
        $display(" [TEST %0d] %s - START", test_total_count, test_name);
        $display("-------------------------------------------------------------");
    endfunction

    // Report test pass
    function void test_pass(string msg = "");
        test_pass_count++;
        if (msg != "")
            $display(" [PASS] %s: %s", current_test_name, msg);
        else
            $display(" [PASS] %s", current_test_name);
    endfunction

    // Report test fail
    function void test_fail(string msg = "");
        test_fail_count++;
        if (msg != "")
            $display(" [FAIL] %s: %s", current_test_name, msg);
        else
            $display(" [FAIL] %s", current_test_name);
    endfunction

    // Check condition and report pass/fail
    function void check(bit condition, string msg = "");
        if (condition)
            test_pass(msg);
        else
            test_fail(msg);
    endfunction

    // Check equality
    function void check_eq(logic [31:0] actual, logic [31:0] expected, string msg = "");
        if (actual === expected) begin
            test_pass($sformatf("%s (expected=0x%08h, actual=0x%08h)", msg, expected, actual));
        end else begin
            test_fail($sformatf("%s (expected=0x%08h, actual=0x%08h)", msg, expected, actual));
        end
    endfunction

    // Check not equal
    function void check_neq(logic [31:0] actual, logic [31:0] not_expected, string msg = "");
        if (actual !== not_expected) begin
            test_pass($sformatf("%s (not_expected=0x%08h, actual=0x%08h)", msg, not_expected, actual));
        end else begin
            test_fail($sformatf("%s (should not be 0x%08h but got 0x%08h)", msg, not_expected, actual));
        end
    endfunction

    // End test suite and print summary
    function void test_suite_end();
        $display("");
        $display("=============================================================");
        $display(" TEST SUITE SUMMARY");
        $display("=============================================================");
        $display(" Total:  %0d", test_total_count);
        $display(" Passed: %0d", test_pass_count);
        $display(" Failed: %0d", test_fail_count);
        $display("=============================================================");
        if (test_fail_count == 0) begin
            $display(" RESULT: ALL TESTS PASSED");
        end else begin
            $display(" RESULT: %0d TEST(S) FAILED", test_fail_count);
        end
        $display("=============================================================");
        $display("");
    endfunction

    // Finish simulation with appropriate exit code
    function void test_finish();
        test_suite_end();
        if (test_fail_count > 0)
            $fatal(1, "Test suite failed with %0d failures", test_fail_count);
        else
            $finish(0);
    endfunction

    // =========================================================================
    // Utility functions
    // =========================================================================

    // Sign-extend from bit width to 32 bits
    function logic [31:0] sign_extend(logic [31:0] value, int width);
        logic [31:0] mask;
        if (value[width-1]) begin
            mask = 32'hFFFFFFFF << width;
            return value | mask;
        end else begin
            mask = (32'h1 << width) - 1;
            return value & mask;
        end
    endfunction

    // Generate random data
    function logic [31:0] random_data();
        return $urandom();
    endfunction

    // Generate random address aligned to specified boundary
    function logic [31:0] random_aligned_addr(int alignment, logic [31:0] max_addr);
        logic [31:0] addr;
        addr = $urandom_range(0, max_addr);
        addr = addr & ~(alignment - 1);  // Align
        return addr;
    endfunction

endpackage

// =============================================================================
// Convenience macros
// =============================================================================

// Assert with automatic message
// iverilog does not support package::function() qualified calls in macros
`ifdef IVERILOG
`define ASSERT_EQ(actual, expected, msg) \
    check_eq(actual, expected, msg)

`define ASSERT_NEQ(actual, not_expected, msg) \
    check_neq(actual, not_expected, msg)

`define ASSERT_TRUE(condition, msg) \
    check(condition, msg)

`define ASSERT_FALSE(condition, msg) \
    check(!condition, msg)
`else
`define ASSERT_EQ(actual, expected, msg) \
    test_utils::check_eq(actual, expected, msg)

`define ASSERT_NEQ(actual, not_expected, msg) \
    test_utils::check_neq(actual, not_expected, msg)

`define ASSERT_TRUE(condition, msg) \
    test_utils::check(condition, msg)

`define ASSERT_FALSE(condition, msg) \
    test_utils::check(!condition, msg)
`endif

// Wait for condition with timeout
`ifdef IVERILOG
`define WAIT_FOR(condition, timeout_cycles, msg) \
    begin \
        int __timeout_cnt = 0; \
        while (!(condition) && __timeout_cnt < timeout_cycles) begin \
            @(posedge clk); \
            __timeout_cnt++; \
        end \
        if (__timeout_cnt >= timeout_cycles) begin \
            $display("  Timeout: %s (after %0d cycles)", msg, timeout_cycles); \
            test_fail(msg); \
        end \
    end
`else
`define WAIT_FOR(condition, timeout_cycles, msg) \
    begin \
        int __timeout_cnt = 0; \
        while (!(condition) && __timeout_cnt < timeout_cycles) begin \
            @(posedge clk); \
            __timeout_cnt++; \
        end \
        if (__timeout_cnt >= timeout_cycles) \
            test_utils::test_fail($sformatf("Timeout: %s (after %0d cycles)", msg, timeout_cycles)); \
    end
`endif

`endif // TEST_UTILS_SV
