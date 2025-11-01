`include "sys_defs.svh"

// Basic testbench for reg_file module
// Tests basic functionality for synthesis verification

module testbench;

    logic clock, reset;
    logic                       failed;

    // Temporary variables for test logic
    int                         all_match;
    int                         pattern_ok;
    int                         stress_failed;
    int                         boundary_ok;
    DATA                        test_val;
    PHYS_TAG                    reg_addr;

    // Inputs to regfile
    PRF_READ_TAGS               read_tags;
    CDB_ENTRY     [`CDB_SZ-1:0] cdb_writes;

    // Outputs from regfile
    PRF_READ_DATA               read_data;

    regfile dut (
        .clock(clock),
        .reset(reset),
        .read_tags(read_tags),
        .read_data(read_data),
        .cdb_writes(cdb_writes)
    );

    always begin
        #(`CLOCK_PERIOD / 2.0);
        clock = ~clock;
    end

    // Helper function to create test data
    function DATA create_test_data(input int value);
        return DATA'(value);
    endfunction

    // Helper to print read results (using ALU ports for testing)
    task print_read_results(input string label);
        $display("\n=== %s ===", label);
        for (int i = 0; i < `NUM_FU_ALU; i++) begin
            $display("  ALU Port %0d: tag=%0d -> data=0x%h", i, read_tags.alu[i], read_data.alu[i]);
        end
        for (int i = 0; i < `NUM_FU_MULT; i++) begin
            $display("  MULT Port %0d: tag=%0d -> data=0x%h", i, read_tags.mult[i], read_data.mult[i]);
        end
        for (int i = 0; i < `NUM_FU_BRANCH; i++) begin
            $display("  BRANCH Port %0d: tag=%0d -> data=0x%h", i, read_tags.branch[i], read_data.branch[i]);
        end
        for (int i = 0; i < `NUM_FU_MEM; i++) begin
            $display("  MEM Port %0d: tag=%0d -> data=0x%h", i, read_tags.mem[i], read_data.mem[i]);
        end
    endtask

    // Helper to print write inputs
    task print_write_inputs(input string label);
        $display("\n=== %s ===", label);
        for (int i = 0; i < `CDB_SZ; i++) begin
            if (cdb_writes[i].valid) begin
                $display("  Write %0d: tag=%0d <- data=0x%h", i, cdb_writes[i].tag, cdb_writes[i].data);
            end else begin
                $display("  Write %0d: disabled", i);
            end
        end
    endtask

    // Helper to reset and wait for proper timing
    task reset_dut;
        reset = 1;
        @(negedge clock);
        @(negedge clock);
        reset = 0;
        @(negedge clock);
    endtask

    initial begin
        int test_num = 1;
        clock = 0;
        reset = 1;
        failed = 0;

        // Initialize inputs
        read_tags = '0;
        cdb_writes = '0;

        reset_dut();

        // Test 1: Basic read from zero register
        $display("\nTest %0d: Basic read from zero register", test_num++);
        reset_dut();
        begin
            read_tags.alu[0] = 0;  // Read zero register
            read_tags.alu[1] = 0;  // Read zero register again
            @(negedge clock);

            if (read_data.alu[0] == 0 && read_data.alu[1] == 0) begin
                $display("  PASS: Zero register reads return 0");
            end else begin
                $display("  FAIL: Zero register should return 0, got 0x%h and 0x%h", read_data.alu[0], read_data.alu[1]);
                failed = 1;
            end
        end

        // Test 2: Write and read back
        $display("\nTest %0d: Write and read back", test_num++);
        reset_dut();
        begin
            DATA test_val = create_test_data(32'hDEADBEEF);

            // Write to register 5 via CDB
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag   = 5;
            cdb_writes[0].data  = test_val;
            @(negedge clock);

            // Clear write inputs
            cdb_writes[0].valid = 0;

            // Read back from register 5
            read_tags.alu[0] = 5;
            @(negedge clock);

            if (read_data.alu[0] == test_val) begin
                $display("  PASS: Write and read back successful (0x%h)", test_val);
            end else begin
                $display("  FAIL: Expected 0x%h, got 0x%h", test_val, read_data.alu[0]);
                failed = 1;
            end
        end

        // Test 3: Forwarding - read same cycle as write
        $display("\nTest %0d: Forwarding - read same cycle as write", test_num++);
        reset_dut();
        begin
            DATA test_val = create_test_data(32'hCAFEBABE);

            // Write to register 10 via CDB
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag = 10;
            cdb_writes[0].data = test_val;

            // Read from register 10 in same cycle
            read_tags.alu[0] = 10;

            @(negedge clock);

            if (read_data.alu[0] == test_val) begin
                $display("  PASS: Forwarding works - got 0x%h", test_val);
            end else begin
                $display("  FAIL: Forwarding failed, expected 0x%h, got 0x%h", test_val, read_data.alu[0]);
                failed = 1;
            end

            // Clear write inputs
            cdb_writes[0].valid = 0;
        end

        // Test 4: Multiple writes and reads
        $display("\nTest %0d: Multiple writes and reads", test_num++);
        reset_dut();
        begin
            // Write to multiple registers via CDB
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag   = 15;
            cdb_writes[0].data  = 32'h11111111;
            cdb_writes[1].valid = 1;
            cdb_writes[1].tag   = 20;
            cdb_writes[1].data  = 32'h22222222;
            cdb_writes[2].valid = 1;
            cdb_writes[2].tag   = 25;
            cdb_writes[2].data  = 32'h33333333;
            @(negedge clock);

            // Clear write inputs
            cdb_writes = '0;

            // Read back all three
            read_tags.alu[0] = 15;
            read_tags.alu[1] = 20;
            read_tags.alu[2] = 25;
            @(negedge clock);

            if (read_data.alu[0] == 32'h11111111 && read_data.alu[1] == 32'h22222222 && read_data.alu[2] == 32'h33333333) begin
                $display("  PASS: Multiple writes and reads successful");
            end else begin
                $display("  FAIL: Expected 11111111, 22222222, 33333333, got %h, %h, %h", read_data.alu[0], read_data.alu[1],
                         read_data.alu[2]);
                failed = 1;
            end
        end

        // Test 5: Forwarding with multiple ports
        $display("\nTest %0d: Forwarding with multiple ports", test_num++);
        reset_dut();
        begin
            // Write to registers 30, 31, 32
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag = 30;
            cdb_writes[0].data = 32'hAAAAAAAA;
            cdb_writes[1].valid = 1;
            cdb_writes[1].tag = 31;
            cdb_writes[1].data = 32'hBBBBBBBB;
            cdb_writes[2].valid = 1;
            cdb_writes[2].tag = 32;
            cdb_writes[2].data = 32'hCCCCCCCC;

            // Read from same registers in same cycle
            read_tags.alu[0] = 30;
            read_tags.alu[1] = 31;
            read_tags.alu[2] = 32;

            @(negedge clock);

            if (read_data.alu[0] == 32'hAAAAAAAA && read_data.alu[1] == 32'hBBBBBBBB && read_data.alu[2] == 32'hCCCCCCCC) begin
                $display("  PASS: Multiple forwarding works");
            end else begin
                $display("  FAIL: Multiple forwarding failed, got %h, %h, %h", read_data.alu[0], read_data.alu[1],
                         read_data.alu[2]);
                failed = 1;
            end

            // Clear write inputs
            cdb_writes = '0;
        end

        // Test 6: Mix of forwarding and register reads
        $display("\nTest %0d: Mix of forwarding and register reads", test_num++);
        reset_dut();
        begin
            // First write some values to registers
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag   = 40;
            cdb_writes[0].data  = 32'h44444444;
            cdb_writes[1].valid = 1;
            cdb_writes[1].tag   = 41;
            cdb_writes[1].data  = 32'h55555555;
            @(negedge clock);

            // Clear write inputs
            cdb_writes = '0;

            // Now write to register 42 and read from 40, 41 (old), and 42 (forwarding)
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag = 42;
            cdb_writes[0].data = 32'h66666666;
            read_tags.alu[0] = 40;  // Should read from register
            read_tags.alu[1] = 41;  // Should read from register
            read_tags.alu[2] = 42;  // Should forward from write
            read_tags.mult[0] = 0;  // Zero register

            @(negedge clock);

            if (read_data.alu[0] == 32'h44444444 &&
                read_data.alu[1] == 32'h55555555 &&
                read_data.alu[2] == 32'h66666666 &&
                read_data.mult[0] == 0) begin
                $display("  PASS: Mix of register reads and forwarding works");
            end else begin
                $display("  FAIL: Mixed reads failed, got %h, %h, %h, %h", read_data.alu[0], read_data.alu[1], read_data.alu[2],
                         read_data.mult[0]);
                failed = 1;
            end

            // Clear write inputs
            cdb_writes = '0;
        end

        // Test 7: Reset clears register file
        $display("\nTest %0d: Reset clears register file", test_num++);
        reset_dut();
        begin
            // Write some values
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag   = 50;
            cdb_writes[0].data  = 32'h77777777;
            cdb_writes[1].valid = 1;
            cdb_writes[1].tag   = 51;
            cdb_writes[1].data  = 32'h88888888;
            @(negedge clock);

            // Clear write inputs
            cdb_writes = '0;

            // Read back to verify writes
            read_tags.alu[0] = 50;
            read_tags.alu[1] = 51;
            @(negedge clock);

            // Apply reset
            reset = 1;
            @(negedge clock);
            @(negedge clock);
            reset = 0;
            @(negedge clock);

            // Read again - should be zero
            if (read_data.alu[0] == 0 && read_data.alu[1] == 0) begin
                $display("  PASS: Reset clears register file");
            end else begin
                $display("  FAIL: Reset should clear registers, got %h, %h", read_data.alu[0], read_data.alu[1]);
                failed = 1;
            end
        end

        // Test 8: Large register indices
        $display("\nTest %0d: Large register indices", test_num++);
        reset_dut();
        begin
            // Test with higher register numbers (close to PHYS_REG_SZ_R10K = 64)
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag   = 60;
            cdb_writes[0].data  = 32'h99999999;
            cdb_writes[1].valid = 1;
            cdb_writes[1].tag   = 63;
            cdb_writes[1].data  = 32'hAAAAAAAA;
            @(negedge clock);

            // Clear write inputs
            cdb_writes = '0;

            // Read back
            read_tags.alu[0] = 60;
            read_tags.alu[1] = 63;
            @(negedge clock);

            if (read_data.alu[0] == 32'h99999999 && read_data.alu[1] == 32'hAAAAAAAA) begin
                $display("  PASS: Large register indices work");
            end else begin
                $display("  FAIL: Large register indices failed, got %h, %h", read_data.alu[0], read_data.alu[1]);
                failed = 1;
            end
        end

        // Test 9: Multiple read ports reading same register
        $display("\nTest %0d: Multiple read ports reading same register", test_num++);
        reset_dut();
        begin
            // Write a value
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag   = 55;
            cdb_writes[0].data  = 32'hBBBBBBBB;
            @(negedge clock);

            // Clear write inputs
            cdb_writes = '0;

            // Multiple ALU ports read same register
            read_tags.alu[0] = 55;
            read_tags.alu[1] = 55;
            read_tags.alu[2] = 55;
            @(negedge clock);

            // All should return same value
            all_match = 1;
            for (int i = 1; i < `NUM_FU_ALU; i++) begin
                if (read_data.alu[i] != read_data.alu[0]) all_match = 0;
            end

            if (all_match && read_data.alu[0] == 32'hBBBBBBBB) begin
                $display("  PASS: Multiple ports reading same register work");
            end else begin
                $display("  FAIL: Multiple ports reading same register failed");
                for (int i = 0; i < `NUM_FU_ALU; i++) begin
                    $display("    Port %0d: %h", i, read_data.alu[i]);
                end
                failed = 1;
            end
        end

        // Test 10: Write conflicts - multiple writes to same register
        $display("\nTest %0d: Write conflicts - multiple writes to same register", test_num++);
        reset_dut();
        begin
            // All three write ports write to same register with different values
            // Last write should win (cdb_writes[2] is the highest index)
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag   = 40;
            cdb_writes[0].data  = 32'h11111111;
            cdb_writes[1].valid = 1;
            cdb_writes[1].tag   = 40;
            cdb_writes[1].data  = 32'h22222222;
            cdb_writes[2].valid = 1;
            cdb_writes[2].tag   = 40;
            cdb_writes[2].data  = 32'h33333333;
            @(negedge clock);

            // Clear write inputs
            cdb_writes = '0;

            // Read back - should get the last write value
            read_tags.alu[0] = 40;
            @(negedge clock);

            if (read_data.alu[0] == 32'h33333333) begin
                $display("  PASS: Write conflicts resolved correctly (last write wins)");
            end else begin
                $display("  FAIL: Write conflict not resolved correctly, expected 33333333, got %h", read_data.alu[0]);
                failed = 1;
            end
        end

        // Test 11: Complex forwarding scenario
        $display("\nTest %0d: Complex forwarding scenario", test_num++);
        reset_dut();
        begin
            // Write to multiple registers first
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag   = 45;
            cdb_writes[0].data  = 32'hAAAAAAAA;
            cdb_writes[1].valid = 1;
            cdb_writes[1].tag   = 46;
            cdb_writes[1].data  = 32'hBBBBBBBB;
            cdb_writes[2].valid = 1;
            cdb_writes[2].tag   = 47;
            cdb_writes[2].data  = 32'hCCCCCCCC;
            @(negedge clock);

            // Clear write inputs
            cdb_writes = '0;

            // Now do mixed reads: some from registers, some forwarding
            read_tags.alu[0] = 45;  // From register
            read_tags.alu[1] = 46;  // From register
            read_tags.alu[2] = 47;  // From register

            // New writes in same cycle
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag = 48;
            cdb_writes[0].data = 32'hDDDDDDDD;
            cdb_writes[1].valid = 1;
            cdb_writes[1].tag = 49;
            cdb_writes[1].data = 32'hEEEEEEEE;
            cdb_writes[2].valid = 1;
            cdb_writes[2].tag = 45;
            cdb_writes[2].data = 32'hFFFFFFFF;  // Overwrite reg 45

            // Use mult and branch ports for additional reads since ALU only has 3 ports
            read_tags.mult[0] = 48;  // Forward from cdb_writes[0]
            read_tags.branch[0] = 49;  // Forward from cdb_writes[1]
            read_tags.mem[0] = 45;  // Forward from cdb_writes[2] (overwrites register value)

            @(negedge clock);

            // Due to aggressive forwarding: any read of a register being written gets forwarded
            if (read_data.alu[0] == 32'hFFFFFFFF &&  // Port 0 reading reg 45 -> forwarded from write port 2
                read_data.alu[1] == 32'hBBBBBBBB &&  // Port 1 reading reg 46 -> old value (no write to 46)
                read_data.alu[2] == 32'hCCCCCCCC &&  // Port 2 reading reg 47 -> old value (no write to 47)
                read_data.mult[0] == 32'hDDDDDDDD &&  // Port 3 reading reg 48 -> forwarded from write port 0
                read_data.branch[0] == 32'hEEEEEEEE &&  // Port 4 reading reg 49 -> forwarded from write port 1
                read_data.mem[0] == 32'hFFFFFFFF) begin  // Port 5 reading reg 45 -> forwarded from write port 2
                $display("  PASS: Complex forwarding scenario works");
            end else begin
                $display("  FAIL: Complex forwarding failed");
                $display("    ALU Port 0: expected FFFFFFFF (forwarded), got %h", read_data.alu[0]);
                $display("    ALU Port 1: expected BBBBBBBB (old), got %h", read_data.alu[1]);
                $display("    ALU Port 2: expected CCCCCCCC (old), got %h", read_data.alu[2]);
                $display("    MULT Port 0: expected DDDDDDDD (forwarded), got %h", read_data.mult[0]);
                $display("    BRANCH Port 0: expected EEEEEEEE (forwarded), got %h", read_data.branch[0]);
                $display("    MEM Port 0: expected FFFFFFFF (forwarded), got %h", read_data.mem[0]);
                failed = 1;
            end

            // Clear write inputs
            cdb_writes = '0;
        end

        // Test 12: Data pattern integrity test
        $display("\nTest %0d: Data pattern integrity test", test_num++);
        reset_dut();
        begin
            DATA patterns[4];
            patterns[0] = 32'h00000000;
            patterns[1] = 32'hFFFFFFFF;
            patterns[2] = 32'hAAAAAAAA;
            patterns[3] = 32'h55555555;

            // Write all patterns to different registers
            for (int p = 0; p < 4; p++) begin
                cdb_writes[p%3].valid = 1;
                cdb_writes[p%3].tag   = 50 + p;
                cdb_writes[p%3].data  = patterns[p];
                if ((p % 3) == 2 || p == 3) begin  // Write every 3 ports or at the end
                    @(negedge clock);
                    cdb_writes = '0;
                end
            end

            // Read back all patterns using available ALU ports
            for (int i = 0; i < `NUM_FU_ALU; i++) begin
                read_tags.alu[i] = 50 + i;
            end
            // Use mult ports for the remaining reads
            for (int i = `NUM_FU_ALU; i < 4; i++) begin
                read_tags.mult[i-`NUM_FU_ALU] = 50 + i;
            end
            @(negedge clock);

            // Check all patterns are correct
            pattern_ok = 1;
            for (int i = 0; i < `NUM_FU_ALU; i++) begin
                if (read_data.alu[i] != patterns[i]) pattern_ok = 0;
            end
            for (int i = `NUM_FU_ALU; i < 4; i++) begin
                if (read_data.mult[i-`NUM_FU_ALU] != patterns[i]) pattern_ok = 0;
            end

            if (!pattern_ok) begin
                $display("  FAIL: Data pattern integrity failed");
                for (int i = 0; i < `NUM_FU_ALU; i++) begin
                    $display("    Reg %0d: expected %h, got %h", 50 + i, patterns[i], read_data.alu[i]);
                end
                for (int i = `NUM_FU_ALU; i < 4; i++) begin
                    $display("    Reg %0d: expected %h, got %h", 50 + i, patterns[i], read_data.mult[i-`NUM_FU_ALU]);
                end
                failed = 1;
            end

            if (!failed) begin
                $display("  PASS: Data pattern integrity maintained");
            end
        end

        // Test 13: Stress test - many sequential operations
        $display("\nTest %0d: Stress test - sequential operations", test_num++);
        reset_dut();
        begin
            stress_failed = 0;

            // Perform 16 sequential write/read operations
            for (int i = 0; i < 16; i++) begin
                test_val = {8'hAA, 8'hBB, 8'hCC, 8'hDD} + i;  // Vary the data
                reg_addr = 32 + i;  // Use registers 32-47

                // Write
                cdb_writes[0].valid = 1;
                cdb_writes[0].tag = reg_addr;
                cdb_writes[0].data = test_val;
                @(negedge clock);

                // Clear write inputs
                cdb_writes = '0;

                // Read back
                read_tags.alu[0] = reg_addr;
                @(negedge clock);

                if (read_data.alu[0] != test_val) begin
                    $display("  FAIL: Stress test failed at iteration %0d, expected %h, got %h", i, test_val, read_data.alu[0]);
                    stress_failed = 1;
                    failed = 1;
                    break;
                end
            end

            if (!stress_failed) begin
                $display("  PASS: Stress test passed - 16 sequential operations successful");
            end
        end

        // Test 14: Boundary register testing (highest registers)
        $display("\nTest %0d: Boundary register testing", test_num++);
        reset_dut();
        begin
            // Test the highest register numbers (PHYS_REG_SZ_R10K = 64, so indices 0-63)
            PHYS_TAG high_regs[6];
            DATA high_vals[6];
            high_regs[0] = 58;
            high_regs[1] = 59;
            high_regs[2] = 60;
            high_regs[3] = 61;
            high_regs[4] = 62;
            high_regs[5] = 63;
            high_vals[0] = 32'h11111111;
            high_vals[1] = 32'h22222222;
            high_vals[2] = 32'h33333333;
            high_vals[3] = 32'h44444444;
            high_vals[4] = 32'h55555555;
            high_vals[5] = 32'h66666666;

            // Write to high registers
            for (int i = 0; i < 6; i++) begin
                cdb_writes[i%3].valid = 1;
                cdb_writes[i%3].tag   = high_regs[i];
                cdb_writes[i%3].data  = high_vals[i];
                if ((i % 3) == 2 || i == 5) begin  // Write every 3 ports or at the end
                    @(negedge clock);
                    cdb_writes = '0;
                end
            end

            // Read back all high registers using available ports
            for (int i = 0; i < `NUM_FU_ALU; i++) begin
                read_tags.alu[i] = high_regs[i];
            end
            // Use mult ports for remaining reads
            for (int i = `NUM_FU_ALU; i < 6; i++) begin
                read_tags.mult[i-`NUM_FU_ALU] = high_regs[i];
            end
            @(negedge clock);

            // Verify all values
            boundary_ok = 1;
            for (int i = 0; i < `NUM_FU_ALU; i++) begin
                if (read_data.alu[i] != high_vals[i]) begin
                    boundary_ok = 0;
                    $display("  FAIL: Boundary test failed for reg %0d, expected %h, got %h", high_regs[i], high_vals[i],
                             read_data.alu[i]);
                end
            end
            for (int i = `NUM_FU_ALU; i < 6; i++) begin
                if (read_data.mult[i-`NUM_FU_ALU] != high_vals[i]) begin
                    boundary_ok = 0;
                    $display("  FAIL: Boundary test failed for reg %0d, expected %h, got %h", high_regs[i], high_vals[i],
                             read_data.mult[i-`NUM_FU_ALU]);
                end
            end

            if (boundary_ok) begin
                $display("  PASS: Boundary register testing successful");
            end else begin
                failed = 1;
            end
        end

        // Test 15: Mixed read/write timing test
        $display("\nTest %0d: Mixed read/write timing test", test_num++);
        reset_dut();
        begin
            // Initialize some registers
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag   = 10;
            cdb_writes[0].data  = 32'hDEAD0000;
            cdb_writes[1].valid = 1;
            cdb_writes[1].tag   = 11;
            cdb_writes[1].data  = 32'hBEEF0000;
            @(negedge clock);
            cdb_writes = '0;

            // Cycle 1: Read existing values and write new ones
            read_tags.alu[0] = 10;  // Read old value
            read_tags.alu[1] = 11;  // Read old value
            cdb_writes[0].valid = 1;
            cdb_writes[0].tag = 12;
            cdb_writes[0].data = 32'h11110000;  // New write
            read_tags.alu[2] = 12;  // Should forward
            @(negedge clock);

            // Verify cycle 1 results
            if (read_data.alu[0] != 32'hDEAD0000 || read_data.alu[1] != 32'hBEEF0000 || read_data.alu[2] != 32'h11110000) begin
                $display("  FAIL: Cycle 1 timing failed");
                failed = 1;
            end else begin
                // Cycle 2: Read the values that were just written
                cdb_writes = '0;
                read_tags.alu[0] = 12;  // Should read from register now
                read_tags.alu[1] = 10;  // Still old value
                read_tags.alu[2] = 11;  // Still old value
                @(negedge clock);

                if (read_data.alu[0] != 32'h11110000 || read_data.alu[1] != 32'hDEAD0000 || read_data.alu[2] != 32'hBEEF0000) begin
                    $display("  FAIL: Cycle 2 timing failed");
                    failed = 1;
                end else begin
                    $display("  PASS: Mixed read/write timing test successful");
                end
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
