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
    ROB_IDX [`N-1:0] rob_alloc_idxs;

    logic stall_fetch;
    logic [$clog2(`N)-1:0] dispatch_count;

    logic [`N-1:0] rob_alloc_valid;
    ROB_ENTRY [`N-1:0] rob_alloc_entries;

    logic [`N-1:0] rs_alloc_valid;
    RS_ENTRY [`N-1:0] rs_alloc_entries;

    logic [`N-1:0] free_alloc_valid;
    PHYS_TAG [`N-1:0] allocated_phys;

    // Map Table I/O
    logic [`PHYS_REG_SZ_R10K - `ROB_SZ -1:0][`PHYS_TAG_BITS-1:0] archi_maptable;
    logic BPRecoverEN;
    logic [`N-1:0] cdb_valid;
    logic [`N-1:0][`PHYS_TAG_BITS-1:0] cdb_tag;
    
    // Dispatch -> Map Table
    logic [`N-1:0][`PHYS_TAG_BITS-1:0] tb_maptable_new_pr;
    logic [`N-1:0][$clog2(`PHYS_REG_SZ_R10K - `ROB_SZ) -1:0] tb_maptable_new_ar;
    logic [`N-1:0][$clog2(`PHYS_REG_SZ_R10K - `ROB_SZ) -1:0] tb_reg1_ar, tb_reg2_ar;
    logic [`N-1:0][$clog2(`PHYS_REG_SZ_R10K - `ROB_SZ) -1:0] tb_told_ar;  // NEW: separate Told lookup
    
    // Map Table -> Dispatch
    logic [`N-1:0][`PHYS_TAG_BITS-1:0] reg1_tag, reg2_tag;
    logic [`N-1:0] reg1_ready, reg2_ready;
    logic [`N-1:0][`PHYS_TAG_BITS-1:0] Told_out;

    // DUT Instance
    stage_dispatch dut (
        .clock(clock),
        .reset(reset),
        .fetch_packet(fetch_packet),
        .fetch_valid(fetch_valid),
        .free_slots_rob(free_slots_rob),
        .free_slots_rs(free_slots_rs),
        .free_slots_freelst(free_slots_freelst),
        .rob_alloc_idxs(rob_alloc_idxs),
        .stall_fetch(stall_fetch),
        .dispatch_count(dispatch_count),
        .rob_alloc_valid(rob_alloc_valid),
        .rob_entry_packet(rob_alloc_entries),
        .rs_alloc_valid(rs_alloc_valid),
        .rs_alloc_entries(rs_alloc_entries),
        .free_alloc_valid(free_alloc_valid),
        .allocated_phys(allocated_phys),

        // Map table interface
        .maptable_new_pr(tb_maptable_new_pr),
        .maptable_new_ar(tb_maptable_new_ar),
        .reg1_ar(tb_reg1_ar),
        .reg2_ar(tb_reg2_ar),
        .told_ar(tb_told_ar),           // NEW
        .reg1_tag(reg1_tag),
        .reg2_tag(reg2_tag),
        .reg1_ready(reg1_ready),
        .reg2_ready(reg2_ready),
        .Told_in(Told_out)
    );

    // Map Table Instance (also needs update)
    map_table #(
        .ARCH_COUNT(`PHYS_REG_SZ_R10K - `ROB_SZ),
        .PHYS_REGS(`PHYS_REG_SZ_R10K),
        .N(`N)
    ) map_table_inst (
        .clock(clock),
        .reset(reset),
        .archi_maptable(archi_maptable),
        .BPRecoverEN(BPRecoverEN),
        .cdb_valid(cdb_valid),
        .cdb_tag(cdb_tag),
        
        // Rename interface
        .maptable_new_pr(tb_maptable_new_pr),
        .maptable_new_ar(tb_maptable_new_ar),
        
        // Source operand lookups
        .reg1_ar(tb_reg1_ar),
        .reg2_ar(tb_reg2_ar),
        .reg1_tag(reg1_tag),
        .reg2_tag(reg2_tag),
        .reg1_ready(reg1_ready),
        .reg2_ready(reg2_ready),
        
        // Told lookup (NEW)
        .told_ar(tb_told_ar),
        .Told_out(Told_out)
    );

    // ============================================================
    // Test Procedure
    // ============================================================

    localparam n = 4;
    logic passed;
    PHYS_TAG expected_tag1;
    PHYS_TAG expected_tag2;
    PHYS_TAG expected_told;
    PHYS_TAG [`PHYS_REG_SZ_R10K - `ROB_SZ -1:0] map_snapshot;  // For tracking map state

    initial begin
        // Initialize ROB allocation indices
        for (int i = 0; i < `N; i++) begin
            rob_alloc_idxs[i] = i;
        end

        // Wait for reset release
        @(negedge reset);
        @(posedge clock);

        // -------------------------------
        // Test 1: Basic Dispatch
        // -------------------------------
        $display("\n=== TEST 1: Basic Dispatch ===");

        fetch_valid = '0;
        fetch_packet = '0;
        free_slots_rob = `N;
        free_slots_rs = `N;
        free_slots_freelst = `N;

        for (int i = 0; i < `N; i++) begin
            allocated_phys[i] = i + 32;  // Use high physical regs
        end

        for (int i = 0; i < `N; i++) begin
            fetch_valid[i] = 1'b1;
            fetch_packet.valid[i] = 1'b1;
            fetch_packet.uses_rd[i] = 1'b1;
            fetch_packet.rs1_idx[i] = i;
            fetch_packet.rs2_idx[i] = i+1;
            fetch_packet.rd_idx[i]  = i+2;
        end

        @(posedge clock);

        $display("Dispatch count: %0d", dispatch_count);
        $display("Stall Fetch: %b", stall_fetch);
        $display("ROB Alloc Valid: %b", rob_alloc_valid);
        $display("RS Alloc Valid:  %b", rs_alloc_valid);

        if (dispatch_count == `N)
            $display("[PASS] Dispatched %0d instructions.", dispatch_count);
        else
            $display("[FAIL] Expected %0d, got %0d", `N, dispatch_count);

        // -------------------------------
        // Test 2: Partial Valid Bundle
        // -------------------------------
        $display("\n=== TEST 2: Partial Valid Bundle ===");

        fetch_valid = '0;
        fetch_packet = '0;
        free_slots_rob = `N;
        free_slots_rs = `N;
        free_slots_freelst = `N;

        for (int i = 0; i < `N - 1; i++) begin
            fetch_valid[i] = 1'b1;
            fetch_packet.valid[i] = 1'b1;
            fetch_packet.uses_rd[i] = 1'b1;
            fetch_packet.rs1_idx[i] = i;
            fetch_packet.rs2_idx[i] = i+1;
            fetch_packet.rd_idx[i]  = i+2;
            allocated_phys[i] = i + 32;
        end

        @(posedge clock);

        if (dispatch_count == `N - 1)
            $display("[PASS] Dispatched %0d instructions.", dispatch_count);
        else
            $display("[FAIL] Expected %0d, got %0d", `N-1, dispatch_count);

        // -------------------------------
        // Test 3: Resource Constraints
        // -------------------------------
        $display("\n=== TEST 3.1: Not enough ROB ===");

        fetch_valid = '0;
        fetch_packet = '0;
        free_slots_rob = `N - 1;
        free_slots_rs = `N;
        free_slots_freelst = `N;

        for (int i = 0; i < `N; i++) begin
            fetch_valid[i] = 1'b1;
            fetch_packet.valid[i] = 1'b1;
            fetch_packet.uses_rd[i] = 1'b1;
            fetch_packet.rs1_idx[i] = i;
            fetch_packet.rs2_idx[i] = i+1;
            fetch_packet.rd_idx[i]  = i+2;
            allocated_phys[i] = i + 32;
        end

        @(posedge clock);

        if (dispatch_count == `N - 1 && stall_fetch)
            $display("[PASS] Correctly limited by ROB slots");
        else
            $display("[FAIL] Expected stall with %0d dispatch", `N-1);

        // Repeat for RS and freelist...
        $display("\n=== TEST 3.2: Not enough RS ===");
        free_slots_rob = `N;
        free_slots_rs = `N - 1;
        @(posedge clock);
        if (dispatch_count == `N - 1 && stall_fetch)
            $display("[PASS] Correctly limited by RS slots");
        else
            $display("[FAIL] Expected stall with %0d dispatch", `N-1);

        $display("\n=== TEST 3.3: Not enough Free List ===");
        free_slots_rs = `N;
        free_slots_freelst = `N - 1;
        @(posedge clock);
        if (dispatch_count == `N - 1 && stall_fetch)
            $display("[PASS] Correctly limited by freelist");
        else
            $display("[FAIL] Expected stall with %0d dispatch", `N-1);

        // ============================================================
        // Test 4: Simple Dispatch of N Instructions
        // ============================================================
        $display("\n=== TEST 4: Simple Dispatch & Told Verification ===");
        @(negedge clock);
        reset = 1;
        @(negedge clock);
        reset = 0;

        // Reset all input signals
        fetch_valid        = '0;
        fetch_packet       = '0;
        free_slots_rob     = `N;
        free_slots_rs      = `N;
        free_slots_freelst = `N;
        BPRecoverEN        = 0;
        cdb_valid          = '0;
        cdb_tag            = '0;

        // ============================================================
        // Wait for map table to reset internally
        // ============================================================
        @(posedge clock);
        $display("Waiting for map table reset to complete...");
        @(posedge clock);
        $display("Map table reset done. Assuming default AR→PR mapping after reset.\n");

        // ============================================================
        // Prepare simple N instructions for dispatch
        // Skip AR0 (start from AR1)
        // Each instruction renames AR(i+1) to a new physical register
        // ============================================================
        for (int i = 0; i < `N; i++) begin
            fetch_valid[i]            = 1'b1;
            fetch_packet.valid[i]     = 1'b1;
            fetch_packet.uses_rd[i]   = 1'b1;
            fetch_packet.rs1_idx[i]   = (i + 1) % 8;  // arbitrary sources
            fetch_packet.rs2_idx[i]   = (i + 2) % 8;
            fetch_packet.rd_idx[i]    = i + 1;        // AR1, AR2, AR3...
            allocated_phys[i]         = 40 + i;       // assign PR40, PR41, ...
        end

        // ============================================================
        // Dispatch N instructions
        // ============================================================
        $display("Dispatching %0d instructions...", `N);
        @(negedge clock);
        #1; // allow combinational logic to settle

        $display("\n--- Dispatch Results ---");
        for (int i = 0; i < `N; i++) begin
            $display("Instr %0d:", i);
            $display("  AR%0d renamed to PR%0d", fetch_packet.rd_idx[i], allocated_phys[i]);
            $display("  Told_out[%0d] = PR%0d", i, Told_out[i]);
        end

        // ============================================================
        // Verify Told Values
        // ============================================================
        $display("\n--- Told Verification ---");
        passed = 1'b1;

        for (int i = 0; i < `N; i++) begin
            expected_told = fetch_packet.rd_idx[i];  // assume reset made ARi → PRi
            if (Told_out[i] != expected_told) begin
                $display("[FAIL] Instr %0d: Expected Told=PR%0d, Got=PR%0d", i, expected_told, Told_out[i]);
                passed = 1'b0;
            end else begin
                $display("[PASS] Instr %0d: Told=PR%0d correct", i, Told_out[i]);
            end
        end

        // ============================================================
        // Verify ROB Entries Got Correct prev_phys_rd
        // ============================================================
        $display("\n--- ROB Entry Verification ---");
        for (int i = 0; i < `N; i++) begin
            $display("ROB Entry %0d: arch_rd=%0d phys_rd=PR%0d prev_phys_rd=PR%0d", 
                    i,
                    rob_alloc_entries[i].arch_rd,
                    rob_alloc_entries[i].phys_rd,
                    rob_alloc_entries[i].prev_phys_rd);
            if (rob_alloc_entries[i].prev_phys_rd != Told_out[i]) begin
                $display("  [FAIL] prev_phys_rd mismatch!");
                passed = 1'b0;
            end
        end

        if (passed)
            $display("\n[PASS] All Test 4 checks passed!");
        else
            $display("\n[FAIL] Test 4 had failures!");

        // ============================================================
        // Test 4b: Dispatch 3 More Instructions and Verify Told Updates
        // ============================================================
        @(negedge clock);
        $display("\n=== TEST 4b: Additional Dispatch & Told Tracking ===");
        //@(negedge clock);
        // Reuse existing arrays
        for (int i = 0; i < `N; i++) begin
            fetch_valid[i]            = 1'b1;
            fetch_packet.valid[i]     = 1'b1;
            fetch_packet.uses_rd[i]   = 1'b1;
            fetch_packet.rs1_idx[i]   = (i + 2) % 8;
            fetch_packet.rs2_idx[i]   = (i + 3) % 8;
            fetch_packet.rd_idx[i]    = i + 1;          // reuse AR1–AR3
            allocated_phys[i]         = 50 + i;         // assign PR50, PR51, PR52
        end

        //@(negedge clock);
        //#1;

        $display("Dispatching %0d additional instructions...", `N);

        //@(negedge clock);
        //#1;

        $display("\n--- Dispatch Results (Extra) ---");
        for (int i = 0; i < `N; i++) begin
            $display("Instr %0d:", i);
            $display("  AR%0d renamed to PR%0d", fetch_packet.rd_idx[i], allocated_phys[i]);
            $display("  Told_out[%0d] = PR%0d", i, Told_out[i]);
        end

        // ============================================================
        // Verify Told Values (should match old mappings)
        // ============================================================
        $display("\n--- Told Verification (Extra) ---");
        passed = 1'b1;

        for (int i = 0; i < `N; i++) begin
            expected_told = i + 1;  // original reset mapping ARi → PRi
            if (Told_out[i] != expected_told) begin
                $display("[FAIL] Extra Instr %0d: Expected Told=PR%0d, Got=PR%0d", 
                         i, expected_told, Told_out[i]);
                passed = 1'b0;
            end else begin
                $display("[PASS] Extra Instr %0d: Told=PR%0d correct", i, Told_out[i]);
            end
        end

        // ============================================================
        // Verify ROB Entries for Additional Dispatch
        // ============================================================
        $display("\n--- ROB Entry Verification (Extra) ---");
        for (int i = 0; i < `N; i++) begin
            $display("ROB Entry %0d: arch_rd=%0d phys_rd=PR%0d prev_phys_rd=PR%0d", 
                    i,
                    rob_alloc_entries[i].arch_rd,
                    rob_alloc_entries[i].phys_rd,
                    rob_alloc_entries[i].prev_phys_rd);
            if (rob_alloc_entries[i].prev_phys_rd != Told_out[i]) begin
                $display("  [FAIL] prev_phys_rd mismatch!");
                passed = 1'b0;
            end
        end

        if (passed)
            $display("\n[PASS] All Test 4b checks passed!");
        else
            $display("\n[FAIL] Test 4b had failures!");

        $display("\n=== Test 4b Complete ===\n");



        $display("\n=== Test 4 Complete ===");

        $finish;
    end

endmodule