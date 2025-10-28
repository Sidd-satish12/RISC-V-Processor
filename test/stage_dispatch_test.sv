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
        .rob_entry_packet(rob_alloc_entries),
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

    localparam n = 4;


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
            $display("allocated physical reg: %b", allocated_phys[i]);
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
        $display("ROB Alloc Valid: %b", rob_alloc_valid); // TODO: check this later, for now since it's initialized, it's displayed as xxx
        $display("RS Alloc Valid:  %b", rs_alloc_valid); // check this later
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
        

        // -------------------------------
        // Test 2: Invalid fetch bundle
        // -------------------------------
        $display("\n=== TEST 2: Inst from Fetch are not all valid ===");

        // Initialize signals
        fetch_valid = '0;
        fetch_packet = '0;
        free_slots_rob = `N;
        free_slots_rs = `N;
        free_slots_freelst = `N;

        for (int i = 0; i < `N; i++) begin
            allocated_phys[i] = i;
            $display("allocated physical reg: %b", allocated_phys[i]);
        end

        for (int i = 0; i < `N - 1; i++) begin
            fetch_valid[i] = 1'b1;
            fetch_packet.valid[i] = 1'b1;
            fetch_packet.uses_rd[i] = 1'b1;  // all use dest reg
            fetch_packet.rs1_idx[i] = i;
            fetch_packet.rs2_idx[i] = i+1;
            fetch_packet.rd_idx[i]  = i+2;
        end

        @(posedge clock);

        fetch_valid[`N-1] = 1'b0;
        fetch_packet.valid[`N-1] = 1'b0;
        fetch_packet.uses_rd[`N-1] = 1'b1;
        fetch_packet.rs1_idx[`N-1] = `N-1;
        fetch_packet.rs2_idx[`N-1] = `N;
        fetch_packet.rd_idx[`N-1] = `N+1;

        @(posedge clock);

        $display("Dispatch count: %0d", dispatch_count);
        $display("Stall Fetch: %b", stall_fetch);
        $display("ROB Alloc Valid: %b", rob_alloc_valid); // TODO: check this later, for now since it's initialized, it's displayed as xxx
        $display("RS Alloc Valid:  %b", rs_alloc_valid); // check this later
        $display("num_valid_from_fetch:  %b", dut.num_valid_from_fetch);
        $display("max_dispatch:  %b", dut.max_dispatch);

        // Expect all N instructions to be dispatched
        if (dispatch_count == `N - 1)
            $display("[PASS] Dispatched %0d instructions.", dispatch_count);
        else
            $display("[FAIL] Unexpected dispatch behavior.");


        // -------------------------------
        // Test 3: Not Enough ROB, or RS, or freelist, or all of them
        // -------------------------------
        $display("\n=== TEST 3.1: Not enough ROB ===");


        fetch_valid = 0;
        fetch_packet = 0;
        free_slots_rob = `N - 1;
        free_slots_rs = `N;
        free_slots_freelst = `N;

        // normal physical register
        for (int i = 0; i < `N; i++) begin
            allocated_phys[i] = i;
            $display("allocated physical reg: %b", allocated_phys[i]);
        end

        @(posedge clock);

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
        $display("ROB Alloc Valid: %b", rob_alloc_valid); // TODO: check this later, for now since it's initialized, it's displayed as xxx
        $display("RS Alloc Valid:  %b", rs_alloc_valid); // check this later
        $display("num_valid_from_fetch:  %b", dut.num_valid_from_fetch);
        $display("max_dispatch:  %b", dut.max_dispatch);

        // Rob not enough
        if (dispatch_count == `N - 1 && stall_fetch)
            $display("[PASS] Dispatched %0d instructions.", dispatch_count);
        else
            $display("[FAIL] Unexpected dispatch behavior.");


        $display("\n=== TEST 3.2: Not enough RS ===");

        fetch_valid = 0;
        fetch_packet = 0;
        free_slots_rob = `N;
        free_slots_rs = `N - 1;
        free_slots_freelst = `N;

        // normal physical register
        for (int i = 0; i < `N; i++) begin
            allocated_phys[i] = i;
            $display("allocated physical reg: %b", allocated_phys[i]);
        end

        @(posedge clock);

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
        $display("ROB Alloc Valid: %b", rob_alloc_valid); // TODO: check this later, for now since it's initialized, it's displayed as xxx
        $display("RS Alloc Valid:  %b", rs_alloc_valid); // check this later
        $display("num_valid_from_fetch:  %b", dut.num_valid_from_fetch);
        $display("max_dispatch:  %b", dut.max_dispatch);

        // Rob not enough
        if (dispatch_count == `N - 1 && stall_fetch)
            $display("[PASS] Dispatched %0d instructions.", dispatch_count);
        else
            $display("[FAIL] Unexpected dispatch behavior.");


        $display("\n=== TEST 3.3: Not enough Free List ===");
        fetch_valid = 0;
        fetch_packet = 0;
        free_slots_rob = `N;
        free_slots_rs = `N;
        free_slots_freelst = `N - 1;

        // normal physical register
        for (int i = 0; i < `N; i++) begin
            allocated_phys[i] = i;
            $display("allocated physical reg: %b", allocated_phys[i]);
        end

        @(posedge clock);

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
        $display("ROB Alloc Valid: %b", rob_alloc_valid); // TODO: check this later, for now since it's initialized, it's displayed as xxx
        $display("RS Alloc Valid:  %b", rs_alloc_valid); // check this later
        $display("num_valid_from_fetch:  %b", dut.num_valid_from_fetch);
        $display("max_dispatch:  %b", dut.max_dispatch);

        // Rob not enough
        if (dispatch_count == `N - 1 && stall_fetch)
            $display("[PASS] Dispatched %0d instructions.", dispatch_count);
        else
            $display("[FAIL] Unexpected dispatch behavior.");

        $display("\n=== TEST 3.4: Comprehensive test ===");
        

        fetch_valid = 0;
        fetch_packet = 0;
        free_slots_rob = n - 3;
        free_slots_rs = n - 2;
        free_slots_freelst = n - 1;

        // normal physical register
        for (int i = 0; i < `N; i++) begin
            allocated_phys[i] = i;
            $display("allocated physical reg: %b", allocated_phys[i]);
        end

        @(posedge clock);

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
        $display("ROB Alloc Valid: %b", rob_alloc_valid); // TODO: check this later, for now since it's initialized, it's displayed as xxx
        $display("RS Alloc Valid:  %b", rs_alloc_valid); // check this later
        $display("num_valid_from_fetch:  %b", dut.num_valid_from_fetch);
        $display("max_dispatch:  %b", dut.max_dispatch);

        // Rob not enough
        if (dispatch_count == n - 3 && stall_fetch)
            $display("[PASS] Dispatched %0d instructions.", dispatch_count);
        else
            $display("[FAIL] Unexpected dispatch behavior.");
        



        // Test 4:
        ///
        ///
        // $display("\n=== TEST 4: Intra-Bundle Dependency ===");
        // clear_inputs();

        // // add x5, x1, x2  (rd=5, rs1=1, rs2=2)
        // fetch_valid[0] = 1'b1;
        // fetch_packet.rs1_idx[0] = 1;
        // fetch_packet.rs2_idx[0] = 2;
        // fetch_packet.rd_idx[0] = 5;
        // fetch_packet.uses_rd[0] = 1'b1;

        // // add x6, x5, x3  (rd=6, rs1=5, rs2=3)
        // fetch_valid[1] = 1'b1;
        // fetch_packet.rs1_idx[1] = 5; // Depends on inst 0
        // fetch_packet.rs2_idx[1] = 3;
        // fetch_packet.rd_idx[1] = 6;
        // fetch_packet.uses_rd[1] = 1'b1;
        
        // fetch_valid[2] = 1'b0;
        
        // allocated_phys = '{32, 33, 34}; // Inst 0 gets p32 (maps to x5), Inst 1 gets p33 (maps to x6)
        // rob_alloc_idxs = '{10, 11, 12}; // Dummy ROB indices

        // @(posedge clock);
        
        // $display("Dispatch count: %0d", dispatch_count);
        // $display("RS[0].src1_tag: %0d, RS[0].dest_tag: %0d", rs_alloc_entries[0].src1_tag, rs_alloc_entries[0].dest_tag);
        // $display("RS[1].src1_tag: %0d, RS[1].dest_tag: %0d", rs_alloc_entries[1].src1_tag, rs_alloc_entries[1].dest_tag);

        // // Check: RS[0] sources (p1, p2) are from old map. RS[0] dest is p32.
        // // Check: RS[1] src1 (p32) is from new map. RS[1] dest is p33.
        // // We assume initial map is pX -> aX. So map[1]=p1, map[5]=p5
        // if (dispatch_count == 2 && rs_alloc_entries[0].dest_tag == 32 && rs_alloc_entries[1].src1_tag == 32 && rs_alloc_entries[1].dest_tag == 33)
        //     $display("[PASS] Intra-bundle dependency renamed correctly.");
        // else
        //     $display("[FAIL] Dependency renaming failed. RS[0].dest=%0d, RS[1].src1=%0d, RS[1].dest=%0d", rs_alloc_entries[0].dest_tag, rs_alloc_entries[1].src1_tag, rs_alloc_entries[1].dest_tag);






        



        $finish;
    end

endmodule
