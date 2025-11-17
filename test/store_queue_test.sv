`include "sys_defs.svh"

// Basic testbench for Store Queue module

module testbench;

    logic clock, reset;
    logic failed;

    STOREQ_ENTRY [`N-1:0] sq_dispatch_packet;
    logic [$clog2(`LSQ_SZ+1)-1:0] free_slots;
    STOREQ_IDX [`N-1:0] sq_alloc_idxs;

    logic mispredict;
    logic [$clog2(`N+1)-1:0] free_count;

    // Instantiate DUT
    store_queue dut (
        .clock(clock),
        .reset(reset),

        .sq_dispatch_packet(sq_dispatch_packet),
        .free_slots(free_slots),
        .sq_alloc_idxs(sq_alloc_idxs),

        .mispredict(mispredict),
        .free_count(free_count)
    );

    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end

    // -------------------------------------------------------------------------
    // Helper constructors
    // -------------------------------------------------------------------------
    function STOREQ_ENTRY make_entry(input int idx);
        make_entry = '0;
        make_entry.valid = 1;
        make_entry.address  = 32'h1000 + idx;
        make_entry.data  = 32'hABCD0000 + idx;
        make_entry.rob_idx = ROB_IDX'(idx); 
    endfunction

    function STOREQ_ENTRY empty_entry();
        empty_entry = '0;
        empty_entry.valid = 0;
    endfunction

    // -------------------------------------------------------------------------
    // Print Store Queue state
    // -------------------------------------------------------------------------
    task print_sq_state(input string label);
        $display("\n=== %s ===", label);
        $display("Free slots: %0d", free_slots);
        for (int i = 0; i < `LSQ_SZ; i++) begin
            $display("SQ[%0d]: valid=%b addr=%h data=%h",
                     i,
                     dut.sq_entries[i].valid,
                     dut.sq_entries[i].address,
                     dut.sq_entries[i].data);
        end
        $display("");
    endtask

    // -------------------------------------------------------------------------
    // Reset task
    // -------------------------------------------------------------------------
    task reset_dut;
        reset = 0;
        @(negedge clock);
        reset = 1;
        @(negedge clock);
        @(negedge clock);
        reset = 0;
        @(negedge clock);
    endtask

    int test_num;
    initial begin
        test_num = 1;
        failed = 0;
        clock  = 0;
        reset  = 0;

        sq_dispatch_packet = '{default:empty_entry()};

        // ----------------------------------------------------
        // Test 1: Reset clears store queue
        // ----------------------------------------------------
        $display("\nTest %0d: Reset initializes state", test_num++);
        reset_dut();
        @(negedge clock);
        print_sq_state("After reset");

        if (free_slots == `LSQ_SZ) begin
            $display("  PASS: All slots free");
        end else begin
            $display("  FAIL: Free slots=%0d expected=%0d",
                     free_slots, `LSQ_SZ);
            failed = 1;
        end

        // ----------------------------------------------------
        // Test 2: Dispatch one store entry
        // ----------------------------------------------------
        $display("\nTest %0d: Dispatch one store", test_num++);
        reset_dut();

        sq_dispatch_packet = '{default:empty_entry()};
        sq_dispatch_packet[0] = make_entry(0);

        @(negedge clock);
        print_sq_state("After dispatching 1 store");

        if (free_slots == `LSQ_SZ - 1) begin
            $display("  PASS: Free slots decreased");
        end else begin
            $display("  FAIL: free_slots=%0d expected=%0d",
                    free_slots, `LSQ_SZ - 1);
            failed = 1;
        end

        // ----------------------------------------------------
        // Final
        // ----------------------------------------------------
        if (!failed) $display("\nALL SQ TESTS PASSED\n");
        else         $display("\nSOME SQ TESTS FAILED\n");

        $finish;
    end


endmodule