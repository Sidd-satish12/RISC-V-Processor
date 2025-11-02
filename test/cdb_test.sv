`include "sys_defs.svh"

// Basic testbench for cdb module
// Tests basic functionality for synthesis verification

module testbench;

    logic clock, reset;
    logic failed;

    // Inputs to cdb
    FU_REQUESTS requests;
    CDB_FU_OUTPUTS fu_outputs;

    // Outputs from cdb
    FU_GRANTS grants;
    logic [`N-1:0][`NUM_FU_TOTAL-1:0] gnt_bus_out;
    CDB_EARLY_TAG_ENTRY [`N-1:0] early_tags;
    CDB_ENTRY [`N-1:0] cdb_output;

    cdb dut (
        .clock(clock),
        .reset(reset),
        .requests(requests),
        .grants(grants),
        .gnt_bus_out(gnt_bus_out),
        .fu_outputs(fu_outputs),
        .early_tags(early_tags),
        .cdb_output(cdb_output)
    );

    always begin
        #(`CLOCK_PERIOD / 2.0);
        clock = ~clock;
    end

    // Helper function to create empty requests
    function FU_REQUESTS empty_requests;
        empty_requests.alu = '0;
        empty_requests.mult = '0;
        empty_requests.branch = '0;
        empty_requests.mem = '0;
    endfunction

    // Helper function to create empty fu_outputs
    function CDB_FU_OUTPUTS empty_fu_outputs;
        empty_fu_outputs.alu = '0;
        empty_fu_outputs.mult = '0;
        empty_fu_outputs.branch = '0;
        empty_fu_outputs.mem = '0;
    endfunction

    // Helper function to create a valid CDB entry
    function CDB_ENTRY valid_cdb_entry(input PHYS_TAG tag_val, input DATA data_val);
        valid_cdb_entry.valid = 1;
        valid_cdb_entry.tag   = tag_val;
        valid_cdb_entry.data  = data_val;
    endfunction

    // Helper function to create an invalid CDB entry
    function CDB_ENTRY invalid_cdb_entry;
        invalid_cdb_entry.valid = 0;
        invalid_cdb_entry.tag   = '0;
        invalid_cdb_entry.data  = '0;
    endfunction

    // Helper to print grant results
    task print_grant_results(input string label);
        $display("\n=== %s ===", label);
        $display("ALU grants: %b", grants.alu);
        $display("MULT grants: %b", grants.mult);
        $display("BRANCH grants: %b", grants.branch);
        $display("MEM grants: %b", grants.mem);
        $display("CDB output valid: %p", {cdb_output[2].valid, cdb_output[1].valid, cdb_output[0].valid});
        $display("Early tags valid: %p", {early_tags[2].valid, early_tags[1].valid, early_tags[0].valid});
    endtask

    // Helper to reset and wait for proper timing
    task reset_dut;
        reset = 1;
        @(negedge clock);
        @(negedge clock);
        reset = 0;
        @(negedge clock);
    endtask

    // Helper to check if any grants are set
    function logic any_grants;
        any_grants = |grants.alu || |grants.mult || |grants.branch || |grants.mem;
    endfunction

    initial begin
        int test_num = 1;
        clock = 0;
        reset = 1;
        failed = 0;

        // Initialize inputs
        requests = empty_requests();
        fu_outputs = empty_fu_outputs();

        reset_dut();

        // Test 1: No requests should produce no grants
        $display("\nTest %0d: No requests should produce no grants", test_num++);
        reset_dut();
        begin
            requests   = empty_requests();
            fu_outputs = empty_fu_outputs();

            @(negedge clock);
            @(negedge clock);

            if (!any_grants()) begin
                $display("  PASS: No grants when no requests");
            end else begin
                $display("  FAIL: Grants present when no requests");
                failed = 1;
            end
        end

        // Test 2: Single ALU request should get grant
        $display("\nTest %0d: Single ALU request should get grant", test_num++);
        reset_dut();
        begin
            requests = empty_requests();
            requests.alu[0] = 1;
            fu_outputs = empty_fu_outputs();
            fu_outputs.alu[0] = valid_cdb_entry(10, 32'hDEADBEEF);

            @(negedge clock);
            @(negedge clock);

            if (grants.alu[0] && !(|grants.mult) && !(|grants.branch) && !(|grants.mem)) begin
                $display("  PASS: Single ALU request granted");
            end else begin
                $display("  FAIL: ALU request not granted or other FUs granted (alu=%b, mult=%b, branch=%b, mem=%b)",
                         grants.alu[0], |grants.mult, |grants.branch, |grants.mem);
                failed = 1;
            end
        end

        // Test 3: Single MULT request should get grant
        $display("\nTest %0d: Single MULT request should get grant", test_num++);
        reset_dut();
        begin
            requests = empty_requests();
            requests.mult[0] = 1;
            fu_outputs = empty_fu_outputs();
            fu_outputs.mult[0] = valid_cdb_entry(15, 32'hCAFEBABE);

            @(negedge clock);
            @(negedge clock);

            if (grants.mult[0] && !(|grants.alu) && !(|grants.branch) && !(|grants.mem)) begin
                $display("  PASS: Single MULT request granted");
            end else begin
                $display("  FAIL: MULT request not granted or other FUs granted (mult=%b, alu=%b, branch=%b, mem=%b)",
                         grants.mult[0], |grants.alu, |grants.branch, |grants.mem);
                failed = 1;
            end
        end

        // Test 4: Single BRANCH request should get grant
        $display("\nTest %0d: Single BRANCH request should get grant", test_num++);
        reset_dut();
        begin
            requests = empty_requests();
            requests.branch[0] = 1;
            fu_outputs = empty_fu_outputs();
            fu_outputs.branch[0] = valid_cdb_entry(20, 32'h12345678);

            @(negedge clock);
            @(negedge clock);

            if (grants.branch[0] && !(|grants.alu) && !(|grants.mult) && !(|grants.mem)) begin
                $display("  PASS: Single BRANCH request granted");
            end else begin
                $display("  FAIL: BRANCH request not granted or other FUs granted (branch=%b, alu=%b, mult=%b, mem=%b)",
                         grants.branch[0], |grants.alu, |grants.mult, |grants.mem);
                failed = 1;
            end
        end

        // Test 5: Single MEM request should get grant
        $display("\nTest %0d: Single MEM request should get grant", test_num++);
        reset_dut();
        begin
            requests = empty_requests();
            requests.mem[0] = 1;
            fu_outputs = empty_fu_outputs();
            fu_outputs.mem[0] = valid_cdb_entry(25, 32'hABCDEF00);

            @(negedge clock);
            @(negedge clock);

            if (grants.mem[0] && !(|grants.alu) && !(|grants.mult) && !(|grants.branch)) begin
                $display("  PASS: Single MEM request granted");
            end else begin
                $display("  FAIL: MEM request not granted or other FUs granted (mem=%b, alu=%b, mult=%b, branch=%b)",
                         grants.mem[0], |grants.alu, |grants.mult, |grants.branch);
                failed = 1;
            end
        end

        // Test 6: Multiple ALU requests should grant up to N
        $display("\nTest %0d: Multiple ALU requests should grant up to N", test_num++);
        reset_dut();
        begin
            int granted_count;
            requests = empty_requests();
            requests.alu = '1;  // All ALU FUs requesting
            fu_outputs = empty_fu_outputs();
            for (int i = 0; i < `NUM_FU_ALU; i++) begin
                fu_outputs.alu[i] = valid_cdb_entry(i + 30, 32'hAAAA0000 + i);
            end

            @(negedge clock);
            @(negedge clock);

            granted_count = $countones(grants.alu);
            if (granted_count <= `N && granted_count > 0) begin
                $display("  PASS: Granted %0d ALU requests (up to N=%0d)", granted_count, `N);
            end else begin
                $display("  FAIL: Should grant between 1 and %0d ALU requests, got %0d", `N, granted_count);
                failed = 1;
            end
        end

        // Test 7: Reset clears grants and CDB output
        $display("\nTest %0d: Reset clears grants and CDB output", test_num++);
        reset_dut();
        begin
            requests = empty_requests();
            requests.alu[0] = 1;
            fu_outputs = empty_fu_outputs();
            fu_outputs.alu[0] = valid_cdb_entry(10, 32'hDEADBEEF);

            @(negedge clock);

            // Apply reset
            reset = 1;
            @(negedge clock);

            // Check that grants and cdb_output are cleared
            if (!any_grants() && !cdb_output[0].valid && !cdb_output[1].valid && !cdb_output[2].valid) begin
                $display("  PASS: Reset clears grants and CDB output");
            end else begin
                $display("  FAIL: Reset should clear grants and CDB output (grants=%b, cdb_valid=%p)", any_grants(), {
                         cdb_output[2].valid, cdb_output[1].valid, cdb_output[0].valid});
                failed = 1;
            end
        end

        // Test 8: CDB output reflects granted FU outputs
        $display("\nTest %0d: CDB output reflects granted FU outputs", test_num++);
        reset_dut();
        begin
            requests = empty_requests();
            requests.alu[0] = 1;
            fu_outputs = empty_fu_outputs();
            fu_outputs.alu[0] = valid_cdb_entry(42, 32'hFEDCBA98);

            @(negedge clock);
            @(negedge clock);

            // Check that CDB output contains the granted data
            if (cdb_output[0].valid && cdb_output[0].tag == 42 && cdb_output[0].data == 32'hFEDCBA98) begin
                $display("  PASS: CDB output reflects granted FU data");
            end else begin
                $display("  FAIL: CDB output mismatch (valid=%b, tag=%0d, data=%h)", cdb_output[0].valid, cdb_output[0].tag,
                         cdb_output[0].data);
                failed = 1;
            end
        end

        $display("\n");
        if (failed) begin
            $display("@@@ FAILED");
        end else begin
            $display("@@@ PASSED");
        end

        $finish;
    end

endmodule
