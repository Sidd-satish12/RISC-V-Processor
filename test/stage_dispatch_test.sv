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
        // Test 4: Map Table Interaction (CRITICAL TEST FOR Told)
        // ============================================================
        $display("\n=== TEST 4: Map Table Interaction & Told Verification ===");

        // Reset all signals
        fetch_valid      = '0;
        fetch_packet     = '0;
        free_slots_rob   = `N;
        free_slots_rs    = `N;
        free_slots_freelst = `N;
        BPRecoverEN      = 0;
        cdb_valid        = '0;
        cdb_tag          = '0;

        // Initialize architectural map table to known values
        // Let's use a non-trivial mapping to make the test interesting
        for (int i = 0; i < (`PHYS_REG_SZ_R10K - `ROB_SZ); i++) begin
            archi_maptable[i] = i + 100;  // ARi -> PR(i+100)
        end

        // Take a snapshot of the initial map state
        for (int i = 0; i < (`PHYS_REG_SZ_R10K - `ROB_SZ); i++) begin
            map_snapshot[i] = archi_maptable[i];
        end

        @(posedge clock);  // Let map table reset with these values

        // Prepare physical allocations for NEW destination registers
        for (int i = 0; i < `N; i++) begin
            allocated_phys[i] = 50 + i; // New PRs: 50, 51, 52...
        end

        // Create instructions that will RENAME some registers
        // Instr 0: R2 = R0 + R1
        // Instr 1: R3 = R1 + R2
        // Instr 2: R4 = R2 + R3  (Note: R2 was just renamed by instr 0!)
        // Instr 3: R5 = R3 + R4  (Note: R3 was just renamed by instr 1!)
        
        fetch_valid[0] = 1'b1;
        fetch_packet.valid[0] = 1'b1;
        fetch_packet.uses_rd[0] = 1'b1;
        fetch_packet.rs1_idx[0] = 0;  // R0
        fetch_packet.rs2_idx[0] = 1;  // R1
        fetch_packet.rd_idx[0]  = 2;  // R2

        fetch_valid[1] = 1'b1;
        fetch_packet.valid[1] = 1'b1;
        fetch_packet.uses_rd[1] = 1'b1;
        fetch_packet.rs1_idx[1] = 1;  // R1
        fetch_packet.rs2_idx[1] = 2;  // R2 (OLD mapping, before instr 0)
        fetch_packet.rd_idx[1]  = 3;  // R3

        fetch_valid[2] = 1'b1;
        fetch_packet.valid[2] = 1'b1;
        fetch_packet.uses_rd[2] = 1'b1;
        fetch_packet.rs1_idx[2] = 2;  // R2 (should see NEW mapping from instr 0)
        fetch_packet.rs2_idx[2] = 3;  // R3 (should see NEW mapping from instr 1)
        fetch_packet.rd_idx[2]  = 4;  // R4

        fetch_valid[3] = 1'b1;
        fetch_packet.valid[3] = 1'b1;
        fetch_packet.uses_rd[3] = 1'b1;
        fetch_packet.rs1_idx[3] = 3;  // R3
        fetch_packet.rs2_idx[3] = 4;  // R4
        fetch_packet.rd_idx[3]  = 5;  // R5

        $display("\nBefore dispatch - Initial map state:");
        $display("  AR0 -> PR%0d", map_snapshot[0]);
        $display("  AR1 -> PR%0d", map_snapshot[1]);
        $display("  AR2 -> PR%0d", map_snapshot[2]);
        $display("  AR3 -> PR%0d", map_snapshot[3]);
        $display("  AR4 -> PR%0d", map_snapshot[4]);
        $display("  AR5 -> PR%0d", map_snapshot[5]);

        @(posedge clock);
        #1;  // Small delay for combinational settling

        // ============================================================
        // Verify Source Operand Mappings
        // ============================================================
        $display("\n--- Source Operand Verification ---");
        passed = 1'b1;

        // Instruction 0: R0, R1 (should get initial mappings)
        expected_tag1 = map_snapshot[0];
        expected_tag2 = map_snapshot[1];
        $display("Instr 0: R2 = R0 + R1");
        $display("  Expected: R0->PR%0d, R1->PR%0d", expected_tag1, expected_tag2);
        $display("  Got:      R0->PR%0d, R1->PR%0d", reg1_tag[0], reg2_tag[0]);
        if (reg1_tag[0] != expected_tag1 || reg2_tag[0] != expected_tag2) begin
            $display("  [FAIL] Source mapping mismatch!");
            passed = 1'b0;
        end else begin
            $display("  [PASS]");
        end

        // Instruction 1: R1, R2 (R2 should still be OLD mapping)
        expected_tag1 = map_snapshot[1];
        expected_tag2 = map_snapshot[2];  // OLD R2, before instr 0 updates it
        $display("Instr 1: R3 = R1 + R2");
        $display("  Expected: R1->PR%0d, R2->PR%0d (old R2)", expected_tag1, expected_tag2);
        $display("  Got:      R1->PR%0d, R2->PR%0d", reg1_tag[1], reg2_tag[1]);
        if (reg1_tag[1] != expected_tag1 || reg2_tag[1] != expected_tag2) begin
            $display("  [FAIL] Source mapping mismatch!");
            passed = 1'b0;
        end else begin
            $display("  [PASS]");
        end

        // Instruction 2: R2, R3 (should see NEW mappings from instr 0, 1)
        expected_tag1 = allocated_phys[0];  // NEW R2 from instr 0
        expected_tag2 = allocated_phys[1];  // NEW R3 from instr 1
        $display("Instr 2: R4 = R2 + R3");
        $display("  Expected: R2->PR%0d (new), R3->PR%0d (new)", expected_tag1, expected_tag2);
        $display("  Got:      R2->PR%0d, R3->PR%0d", reg1_tag[2], reg2_tag[2]);
        if (reg1_tag[2] != expected_tag1 || reg2_tag[2] != expected_tag2) begin
            $display("  [FAIL] Source mapping mismatch!");
            passed = 1'b0;
        end else begin
            $display("  [PASS]");
        end

        // ============================================================
        // Verify Told Values (CRITICAL!)
        // ============================================================
        $display("\n--- Told Verification (Previous Physical Register) ---");
        
        // Instr 0: Renames R2, Told should be OLD mapping of R2
        expected_told = map_snapshot[2];
        $display("Instr 0: Renames AR2");
        $display("  Expected Told: PR%0d (old R2)", expected_told);
        $display("  Got Told:      PR%0d", Told_out[0]);
        if (Told_out[0] != expected_told) begin
            $display("  [FAIL] Told mismatch!");
            passed = 1'b0;
        end else begin
            $display("  [PASS]");
        end

        // Instr 1: Renames R3, Told should be OLD mapping of R3
        expected_told = map_snapshot[3];
        $display("Instr 1: Renames AR3");
        $display("  Expected Told: PR%0d (old R3)", expected_told);
        $display("  Got Told:      PR%0d", Told_out[1]);
        if (Told_out[1] != expected_told) begin
            $display("  [FAIL] Told mismatch!");
            passed = 1'b0;
        end else begin
            $display("  [PASS]");
        end

        // Instr 2: Renames R4, Told should be OLD mapping of R4
        expected_told = map_snapshot[4];
        $display("Instr 2: Renames AR4");
        $display("  Expected Told: PR%0d (old R4)", expected_told);
        $display("  Got Told:      PR%0d", Told_out[2]);
        if (Told_out[2] != expected_told) begin
            $display("  [FAIL] Told mismatch!");
            passed = 1'b0;
        end else begin
            $display("  [PASS]");
        end

        // Instr 3: Renames R5, Told should be OLD mapping of R5
        expected_told = map_snapshot[5];
        $display("Instr 3: Renames AR5");
        $display("  Expected Told: PR%0d (old R5)", expected_told);
        $display("  Got Told:      PR%0d", Told_out[3]);
        if (Told_out[3] != expected_told) begin
            $display("  [FAIL] Told mismatch!");
            passed = 1'b0;
        end else begin
            $display("  [PASS]");
        end

        // ============================================================
        // Verify ROB Entries Got Correct prev_phys_rd
        // ============================================================
        $display("\n--- ROB Entry Verification ---");
        for (int i = 0; i < `N; i++) begin
            $display("ROB Entry %0d:", i);
            $display("  arch_rd=%0d, phys_rd=PR%0d, prev_phys_rd=PR%0d", 
                     rob_alloc_entries[i].arch_rd,
                     rob_alloc_entries[i].phys_rd,
                     rob_alloc_entries[i].prev_phys_rd);
            
            if (rob_alloc_entries[i].prev_phys_rd != Told_out[i]) begin
                $display("  [FAIL] prev_phys_rd doesn't match Told!");
                passed = 1'b0;
            end
        end

        if (passed)
            $display("\n[PASS] All Test 4 checks passed!");
        else
            $display("\n[FAIL] Test 4 had failures!");

        $display("\n=== All Tests Complete ===");
        $finish;
    end

endmodule