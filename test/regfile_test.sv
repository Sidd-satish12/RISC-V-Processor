`include "sys_defs.svh"

// Basic testbench for reg_file module
// Tests basic functionality for synthesis verification

module testbench;

    logic clock, reset;
    logic          failed;

    // Temporary variables for test logic
    int            all_match;

    // Inputs to reg_file
    PHYS_TAG [5:0] read_tags;  // 6 read ports (NUM_FU_TOTAL)

    // Outputs from reg_file
    DATA     [5:0] read_outputs;  // 6 read ports

    // Write inputs
    logic    [2:0] write_en;  // 3 write ports (CDB_SZ)
    PHYS_TAG [2:0] write_tags;  // 3 write ports
    DATA     [2:0] write_data;  // 3 write ports

    reg_file dut (
        .clock(clock),
        .reset(reset),
        .read_tags(read_tags),
        .read_outputs(read_outputs),
        .write_en(write_en),
        .write_tags(write_tags),
        .write_data(write_data)
    );

    always begin
        #(`CLOCK_PERIOD / 2.0);
        clock = ~clock;
    end

    // Helper function to create test data
    function DATA create_test_data(input int value);
        return DATA'(value);
    endfunction

    // Helper to print read results
    task print_read_results(input string label);
        $display("\n=== %s ===", label);
        for (int i = 0; i < 6; i++) begin
            $display("  Port %0d: tag=%0d -> data=0x%h", i, read_tags[i], read_outputs[i]);
        end
    endtask

    // Helper to print write inputs
    task print_write_inputs(input string label);
        $display("\n=== %s ===", label);
        for (int i = 0; i < 3; i++) begin
            if (write_en[i]) begin
                $display("  Write %0d: tag=%0d <- data=0x%h", i, write_tags[i], write_data[i]);
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
        write_en = '0;
        write_tags = '0;
        write_data = '0;

        reset_dut();

        // Test 1: Basic read from zero register
        $display("\nTest %0d: Basic read from zero register", test_num++);
        reset_dut();
        begin
            read_tags[0] = 0;  // Read zero register
            read_tags[1] = 0;  // Read zero register again
            @(negedge clock);

            if (read_outputs[0] == 0 && read_outputs[1] == 0) begin
                $display("  PASS: Zero register reads return 0");
            end else begin
                $display("  FAIL: Zero register should return 0, got 0x%h and 0x%h", read_outputs[0], read_outputs[1]);
                failed = 1;
            end
        end

        // Test 2: Write and read back
        $display("\nTest %0d: Write and read back", test_num++);
        reset_dut();
        begin
            DATA test_val = create_test_data(32'hDEADBEEF);

            // Write to register 5
            write_en[0]   = 1;
            write_tags[0] = 5;
            write_data[0] = test_val;
            @(negedge clock);

            // Clear write inputs
            write_en[0]  = 0;

            // Read back from register 5
            read_tags[0] = 5;
            @(negedge clock);

            if (read_outputs[0] == test_val) begin
                $display("  PASS: Write and read back successful (0x%h)", test_val);
            end else begin
                $display("  FAIL: Expected 0x%h, got 0x%h", test_val, read_outputs[0]);
                failed = 1;
            end
        end

        // Test 3: Forwarding - read same cycle as write
        $display("\nTest %0d: Forwarding - read same cycle as write", test_num++);
        reset_dut();
        begin
            DATA test_val = create_test_data(32'hCAFEBABE);

            // Write to register 10
            write_en[0]   = 1;
            write_tags[0] = 10;
            write_data[0] = test_val;

            // Read from register 10 in same cycle
            read_tags[0]  = 10;

            @(negedge clock);

            if (read_outputs[0] == test_val) begin
                $display("  PASS: Forwarding works - got 0x%h", test_val);
            end else begin
                $display("  FAIL: Forwarding failed, expected 0x%h, got 0x%h", test_val, read_outputs[0]);
                failed = 1;
            end

            // Clear write inputs
            write_en[0] = 0;
        end

        // Test 4: Multiple writes and reads
        $display("\nTest %0d: Multiple writes and reads", test_num++);
        reset_dut();
        begin
            // Write to multiple registers
            write_en[0]   = 1;
            write_tags[0] = 15;
            write_data[0] = 32'h11111111;
            write_en[1]   = 1;
            write_tags[1] = 20;
            write_data[1] = 32'h22222222;
            write_en[2]   = 1;
            write_tags[2] = 25;
            write_data[2] = 32'h33333333;
            @(negedge clock);

            // Clear write inputs
            write_en = '0;

            // Read back all three
            read_tags[0] = 15;
            read_tags[1] = 20;
            read_tags[2] = 25;
            @(negedge clock);

            if (read_outputs[0] == 32'h11111111 && read_outputs[1] == 32'h22222222 && read_outputs[2] == 32'h33333333) begin
                $display("  PASS: Multiple writes and reads successful");
            end else begin
                $display("  FAIL: Expected 11111111, 22222222, 33333333, got %h, %h, %h", read_outputs[0], read_outputs[1],
                         read_outputs[2]);
                failed = 1;
            end
        end

        // Test 5: Forwarding with multiple ports
        $display("\nTest %0d: Forwarding with multiple ports", test_num++);
        reset_dut();
        begin
            // Write to registers 30, 31, 32
            write_en[0]   = 1;
            write_tags[0] = 30;
            write_data[0] = 32'hAAAAAAAA;
            write_en[1]   = 1;
            write_tags[1] = 31;
            write_data[1] = 32'hBBBBBBBB;
            write_en[2]   = 1;
            write_tags[2] = 32;
            write_data[2] = 32'hCCCCCCCC;

            // Read from same registers in same cycle
            read_tags[0]  = 30;
            read_tags[1]  = 31;
            read_tags[2]  = 32;

            @(negedge clock);

            if (read_outputs[0] == 32'hAAAAAAAA && read_outputs[1] == 32'hBBBBBBBB && read_outputs[2] == 32'hCCCCCCCC) begin
                $display("  PASS: Multiple forwarding works");
            end else begin
                $display("  FAIL: Multiple forwarding failed, got %h, %h, %h", read_outputs[0], read_outputs[1], read_outputs[2]);
                failed = 1;
            end

            // Clear write inputs
            write_en = '0;
        end

        // Test 6: Mix of forwarding and register reads
        $display("\nTest %0d: Mix of forwarding and register reads", test_num++);
        reset_dut();
        begin
            // First write some values to registers
            write_en[0]   = 1;
            write_tags[0] = 40;
            write_data[0] = 32'h44444444;
            write_en[1]   = 1;
            write_tags[1] = 41;
            write_data[1] = 32'h55555555;
            @(negedge clock);

            // Clear write inputs
            write_en = '0;

            // Now write to register 42 and read from 40, 41 (old), and 42 (forwarding)
            write_en[0] = 1;
            write_tags[0] = 42;
            write_data[0] = 32'h66666666;
            read_tags[0] = 40;  // Should read from register
            read_tags[1] = 41;  // Should read from register
            read_tags[2] = 42;  // Should forward from write
            read_tags[3] = 0;  // Zero register

            @(negedge clock);

            if (read_outputs[0] == 32'h44444444 &&
                read_outputs[1] == 32'h55555555 &&
                read_outputs[2] == 32'h66666666 &&
                read_outputs[3] == 0) begin
                $display("  PASS: Mix of register reads and forwarding works");
            end else begin
                $display("  FAIL: Mixed reads failed, got %h, %h, %h, %h", read_outputs[0], read_outputs[1], read_outputs[2],
                         read_outputs[3]);
                failed = 1;
            end

            // Clear write inputs
            write_en = '0;
        end

        // Test 7: Reset clears register file
        $display("\nTest %0d: Reset clears register file", test_num++);
        reset_dut();
        begin
            // Write some values
            write_en[0]   = 1;
            write_tags[0] = 50;
            write_data[0] = 32'h77777777;
            write_en[1]   = 1;
            write_tags[1] = 51;
            write_data[1] = 32'h88888888;
            @(negedge clock);

            // Clear write inputs
            write_en = '0;

            // Read back to verify writes
            read_tags[0] = 50;
            read_tags[1] = 51;
            @(negedge clock);

            // Apply reset
            reset = 1;
            @(negedge clock);
            @(negedge clock);
            reset = 0;
            @(negedge clock);

            // Read again - should be zero
            if (read_outputs[0] == 0 && read_outputs[1] == 0) begin
                $display("  PASS: Reset clears register file");
            end else begin
                $display("  FAIL: Reset should clear registers, got %h, %h", read_outputs[0], read_outputs[1]);
                failed = 1;
            end
        end

        // Test 8: Large register indices
        $display("\nTest %0d: Large register indices", test_num++);
        reset_dut();
        begin
            // Test with higher register numbers (close to PHYS_REG_SZ_R10K = 64)
            write_en[0]   = 1;
            write_tags[0] = 60;
            write_data[0] = 32'h99999999;
            write_en[1]   = 1;
            write_tags[1] = 63;
            write_data[1] = 32'hAAAAAAAA;
            @(negedge clock);

            // Clear write inputs
            write_en = '0;

            // Read back
            read_tags[0] = 60;
            read_tags[1] = 63;
            @(negedge clock);

            if (read_outputs[0] == 32'h99999999 && read_outputs[1] == 32'hAAAAAAAA) begin
                $display("  PASS: Large register indices work");
            end else begin
                $display("  FAIL: Large register indices failed, got %h, %h", read_outputs[0], read_outputs[1]);
                failed = 1;
            end
        end

        // Test 9: Multiple read ports reading same register
        $display("\nTest %0d: Multiple read ports reading same register", test_num++);
        reset_dut();
        begin
            // Write a value
            write_en[0]   = 1;
            write_tags[0] = 55;
            write_data[0] = 32'hBBBBBBBB;
            @(negedge clock);

            // Clear write inputs
            write_en = '0;

            // Multiple ports read same register
            read_tags[0] = 55;
            read_tags[1] = 55;
            read_tags[2] = 55;
            read_tags[3] = 55;
            read_tags[4] = 55;
            read_tags[5] = 55;
            @(negedge clock);

            // All should return same value
            all_match = 1;
            for (int i = 1; i < 6; i++) begin
                if (read_outputs[i] != read_outputs[0]) all_match = 0;
            end

            if (all_match && read_outputs[0] == 32'hBBBBBBBB) begin
                $display("  PASS: Multiple ports reading same register work");
            end else begin
                $display("  FAIL: Multiple ports reading same register failed");
                for (int i = 0; i < 6; i++) begin
                    $display("    Port %0d: %h", i, read_outputs[i]);
                end
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
