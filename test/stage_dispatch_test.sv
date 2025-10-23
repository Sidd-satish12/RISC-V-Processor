`include "sys_defs.svh"

module stage_dispatch_tb;

    // ============================================================
    // Clock & Reset
    // ============================================================
    logic clock;
    logic reset;

    initial clock = 0;
    always #5 clock = ~clock;

    // Reset logic
    initial begin
        reset = 1;
        #20;
        reset = 0;
    end

    // ============================================================
    // DUT Inputs & Outputs
    // ============================================================
    FETCH_DISP_PACKET fetch_packet;
    logic [`N-1:0] fetch_valid;
    logic [$clog2(`ROB_SZ+1)-1:0] free_slots_rob;
    logic [$clog2(`RS_SZ+1)-1:0] free_slots_rs;
    logic [$clog2(`PHYS_REG_SZ_R10K+1)-1:0] free_slots_freelst;

    logic stall_fetch;
    logic [$clog2(`N)-1:0] dispatch_count;

    logic [`N-1:0] rob_alloc_valid;
    ROB_ENTRY [`N-1:0] rob_alloc_entries;

    logic [`N-1:0] rs_alloc_valid;
    RS_ENTRY [`N-1:0] rs_alloc_entries;

    logic [`N-1:0] free_alloc_valid;
    PHYS_TAG [`N-1:0] allocated_phys;

    // PRF dummy signals
    logic [2*`N-1:0] prf_read_valid;
    PHYS_TAG [2*`N-1:0] prf_read_tags;
    DATA [2*`N-1:0] prf_read_values;

    // ============================================================
    // DUT Instance
    // ============================================================
    stage_dispatch dut (
        .clock(clock),
        .reset(reset),
        .fetch_packet(fetch_packet),
        .fetch_valid(fetch_valid),
        .free_slots_rob(free_slots_rob),
        .free_slots_rs(free_slots_rs),
        .free_slots_freelst(free_slots_freelst),
        .stall_fetch(stall_fetch),
        .dispatch_count(dispatch_count),
        .rob_alloc_valid(rob_alloc_valid),
        .rob_alloc_entries(rob_alloc_entries),
        .rs_alloc_valid(rs_alloc_valid),
        .rs_alloc_entries(rs_alloc_entries),
        .free_alloc_valid(free_alloc_valid),
        .allocated_phys(allocated_phys)
        // ADD below once implemented in stage_dispatch.sv 
        
        // .prf_read_valid(prf_read_valid),
        // .prf_read_tags(prf_read_tags),
        // .prf_read_values(prf_read_values)
    );

    // ============================================================
    // Test Procedure
    // ============================================================

    initial begin
        // Wait for reset release
        @(negedge reset);
        @(posedge clock);

        // -------------------------------
        // Test 1: Basic Dispatch
        // -------------------------------
        $display("\n=== TEST 1: Basic Dispatch ===");

        // Initialize signals
        fetch_valid = '0;
        fetch_packet = '0;
        free_slots_rob = `N;
        free_slots_rs = `N;
        free_slots_freelst = `N;

        // Dummy physical register allocation tags
        for (int i = 0; i < `N; i++) begin
            allocated_phys[i] = i;
        end

        // Create a bundle of valid fetched instructions
        for (int i = 0; i < `N; i++) begin
            fetch_valid[i] = 1'b1;
            fetch_packet.valid[i] = 1'b1;
            fetch_packet.uses_rd[i] = 1'b1;  // all use dest reg
            fetch_packet.rs1_idx[i] = i;
            fetch_packet.rs2_idx[i] = i+1;
            fetch_packet.rd_idx[i]  = i+2;
        end

        @(posedge clock);

        // Check the results
        $display("Dispatch count: %0d", dispatch_count);
        $display("Stall Fetch: %b", stall_fetch);
        $display("ROB Alloc Valid: %b", rob_alloc_valid);
        $display("RS Alloc Valid:  %b", rs_alloc_valid);
        $display("num_valid_from_fetch:  %b", dut.num_valid_from_fetch);
        $display("max_dispatch:  %b", dut.max_dispatch);

        // Expect all N instructions to be dispatched
        if (dispatch_count == `N)
            $display("[PASS] Dispatched %0d instructions.", dispatch_count);
        else
            $display("[FAIL] Unexpected dispatch behavior.");

        // -------------------------------
        // Add more tests
        // -------------------------------
        

        #20;
        $finish;
    end

endmodule
