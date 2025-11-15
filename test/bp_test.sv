`timescale 1ns / 1ps

`include "sys_defs.svh"

// Testbench for branch predictor module
// Tests basic functionality and correctness of GShare + BTB predictor

module branch_predictor_test_all;

    // ---------------------------------------------------------------------------
    // Parameters (keep small so indices are easy to reason about)
    // ---------------------------------------------------------------------------
    localparam int unsigned PC_BITS = 32;  // fixed 32-bit PCs/targets
    localparam int unsigned GH = `BP_GH;  // Use macro from sys_defs.svh
    localparam int unsigned PHT_BITS = `BP_PHT_BITS;  // Use macro from sys_defs.svh
    localparam int unsigned BTB_BITS = `BP_BTB_BITS;  // Use macro from sys_defs.svh

    // ---------------------------------------------------------------------------
    // DUT I/O (testbench-side signals)
    // ---------------------------------------------------------------------------
    logic clock, reset;

    // Predict req/resp
    BP_PREDICT_REQUEST predict_req;
    BP_PREDICT_RESPONSE predict_resp;

    // Train (update)
    BP_TRAIN_REQUEST train_req;

    // Recovery
    BP_RECOVER_REQUEST recover_req;

    // ---------------------------------------------------------------------------
    // DUT instance (matches the cleaned-up RTL names)
    // ---------------------------------------------------------------------------
    bp dut (
        .clock(clock),
        .reset(reset),

        .predict_req_i (predict_req),
        .predict_resp_o(predict_resp),

        .train_req_i(train_req),

        .recover_req_i(recover_req)
    );

    // ---------------------------------------------------------------------------
    // Clock / Reset
    // ---------------------------------------------------------------------------
    initial clock = 0;
    always begin
        #(`CLOCK_PERIOD / 2.0);
        clock = ~clock;
    end

    task automatic init_signals();
        begin
            predict_req = '0;
            train_req   = '0;
            recover_req = '0;
        end
    endtask

    task automatic do_reset();
        begin
            reset = 1;
            init_signals();
            repeat (3) @(posedge clock);
            reset = 0;
            @(posedge clock);
        end
    endtask

    // ---------------------------------------------------------------------------
    // Global pass/fail counters and EXPECT helpers (no $fatal)
    // ---------------------------------------------------------------------------
    int total_pass = 0;
    int total_fail = 0;

    task automatic EXPECT_EQ(input string what, input logic [31:0] got, exp);
        if (got !== exp) begin
            $display("FAIL: %s: got 0x%08x exp 0x%08x", what, got, exp);
            total_fail++;
        end else begin
            total_pass++;
        end
    endtask

    task automatic EXPECT_BIT(input string what, input bit got, exp);
        if (got !== exp) begin
            $display("FAIL: %s: got %0d exp %0d", what, got, exp);
            total_fail++;
        end else begin
            total_pass++;
        end
    endtask

    // ---------------------------------------------------------------------------
    // Utility: predict(), train_task(), mispredict_restore()
    // ---------------------------------------------------------------------------

    task automatic reset_dut();
        reset = 1'b1;
        predict_req = '0;
        train_req = '0;
        recover_req = '0;
        repeat (3) @(posedge clock);
        reset = 1'b0;
        @(posedge clock);  // allow flops to initialize
    endtask

    task automatic predict(input logic [31:0] pc, input bit mark_used, output logic taken, output logic [31:0] target,
                           output logic [GH-1:0] ghr_snap);
        // 1) drive inputs
        @(negedge clock);
        predict_req.pc = pc;
        predict_req.valid = 1'b1;
        predict_req.used = mark_used;

        // 2) let DUT comb settle across posedge
        @(posedge clock);
        #1;
        taken = predict_resp.taken;
        target = predict_resp.target;
        ghr_snap = predict_resp.ghr_snapshot;
        // caller deasserts after checks
    endtask

    task automatic train_task(input logic [31:0] pc, input logic [GH-1:0] ghr_snap, input bit actual_taken,
                              input logic [31:0] actual_target);
        @(negedge clock);
        train_req.pc = pc;
        train_req.ghr_snapshot = ghr_snap;
        train_req.actual_taken = actual_taken;
        train_req.actual_target = actual_target;
        train_req.valid = 1'b1;
        @(posedge clock);  // capture update
        @(negedge clock);
        train_req.valid = 1'b0;  // tidy deassert
        @(posedge clock);
    endtask

    task automatic mispredict_restore(input logic [GH-1:0] restore_snap);
        @(negedge clock);
        recover_req.ghr_snapshot = restore_snap;
        recover_req.pulse = 1'b1;
        @(posedge clock);
        recover_req.pulse = 1'b0;
    endtask

    // ---------------------------------------------------------------------------
    // Unique PCs per test (so tests are independent even though PHT/BTB aren't reset)
    // ---------------------------------------------------------------------------
    localparam logic [GH-1:0] GHRS0 = '0;  // fixed snapshot for deterministic training
    localparam logic [31:0] PC_T0 = 32'h0000_0040;  // idx 0x4
    localparam logic [31:0] PC_T1 = 32'h0000_0080;  // idx 0x8
    localparam logic [31:0] PC_T2 = 32'h0000_00C0;  // idx 0xC
    localparam logic [31:0] PC_T3 = 32'h0000_0100;  // idx 0x0 (new tag)
    localparam logic [31:0] PC_T4 = 32'h0000_0140;  // idx 0x4 but different tag
    localparam logic [31:0] PC_T5 = 32'h0000_0180;  // idx 0x8 (separate from T1 by tag)

    localparam logic [31:0] TGT_A = 32'h0000_0800;
    localparam logic [31:0] TGT_B = 32'h0000_0888;

    // ---------------------------------------------------------------------------
    // Individual tests (each self-contained, primes its own state)
    // ---------------------------------------------------------------------------

    // T0: Prime PHT entry to NT for the used PC (predict NT; target=0).
    task automatic TEST0();
        logic t;
        logic [31:0] tgt;
        logic [GH-1:0] snap;
        $display("T0: Prime PHT to NT and check NT prediction (PC_T0)");
        mispredict_restore(GHRS0);  // precise GHR = 0
        repeat (3) train_task(PC_T0, GHRS0, 1'b0, '0);  // move that entry toward NT
        predict(PC_T0, 1'b0, t, tgt, snap);  // read without shifting history
        EXPECT_BIT("T0.taken", t, 1'b0);
        EXPECT_EQ("T0.target", tgt, 32'h0);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;
    endtask

    task automatic TEST1();
        logic t;
        logic [31:0] tgt;
        logic [GH-1:0] snap;
        $display("T1: Train TAKEN+BTB, expect TAKEN + target (PC_T1 -> TGT_A)");
        reset_dut();
        repeat (3) train_task(PC_T1, '0, 1'b1, TGT_A);  // deterministic training
        @(posedge clock);

        predict(PC_T1, 1'b0, t, tgt, snap);  // don’t shift GHR
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;

        EXPECT_BIT("T1.taken", t, 1'b1);
        EXPECT_EQ("T1.target", tgt, TGT_A);
    endtask

    task automatic TEST2();
        logic t;
        logic [31:0] tgt;
        logic [GH-1:0] snap;
        $display("T2: Saturation clamp check (PC_T2)");
        mispredict_restore(GHRS0);
        repeat (4) train_task(PC_T2, GHRS0, 1'b1, TGT_A);  // drive to strongly TAKEN
        predict(PC_T2, 1'b0, t, tgt, snap);
        EXPECT_BIT("T2.post_push_taken", t, 1'b1);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;

        repeat (5) train_task(PC_T2, GHRS0, 1'b0, '0);  // drive to strongly NT
        predict(PC_T2, 1'b0, t, tgt, snap);
        EXPECT_BIT("T2.post_pull_taken", t, 1'b0);
        EXPECT_EQ("T2.post_pull_target", tgt, 32'h0);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;
    endtask

    task automatic TEST3();
        logic t;
        logic [31:0] tgt;
        logic [GH-1:0] snap;
        $display("T3: Independent PC TAKEN+BTB (PC_T3 -> TGT_B)");
        mispredict_restore(GHRS0);
        repeat (3) train_task(PC_T3, GHRS0, 1'b1, TGT_B);
        predict(PC_T3, 1'b0, t, tgt, snap);
        EXPECT_BIT("T3.taken", t, 1'b1);
        EXPECT_EQ("T3.target", tgt, TGT_B);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;
    endtask

    task automatic TEST4();
        logic t;
        logic [31:0] tgt;
        logic [GH-1:0] snap;
        $display("T4: NT prediction -> target must be 0 (PC_T4)");
        mispredict_restore(GHRS0);
        repeat (3) train_task(PC_T4, GHRS0, 1'b0, '0);
        predict(PC_T4, 1'b0, t, tgt, snap);
        EXPECT_BIT("T4.taken", t, 1'b0);
        EXPECT_EQ("T4.target", tgt, 32'h0);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;
    endtask

    // T5: GHR speculative shift + mispredict restore sanity.
    task automatic TEST5();
        logic t;
        logic [31:0] tgt;
        logic [GH-1:0] snap_before, snap_after;
        $display("T5: GHR mispredict restore (PC_T5)");
        // Predict with use => speculative shift
        predict(PC_T5, 1'b1, t, tgt, snap_before);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;

        // Restore precise GHR to snapshot
        mispredict_restore(snap_before);

        // Next predict (no use) should show same snapshot again
        predict(PC_T5, 1'b0, t, tgt, snap_after);
        EXPECT_EQ("T5.ghr_restored", {{(PC_BITS - GH) {1'b0}}, snap_after}, {{(PC_BITS - GH) {1'b0}}, snap_before});
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;
    endtask

    // T6: BTB conflict resolution (same index, different tags)
    task automatic TEST6();
        logic t;
        logic [31:0] tgt;
        logic [GH-1:0] snap;
        logic [31:0] PC_CONFLICT1, PC_CONFLICT2;

        // Create two PCs that map to the same BTB index but have different tags
        // BTB index = pc[2+:BTB_BITS], tag = pc[2+BTB_BITS+:BTB_TAG_BITS]
        PC_CONFLICT1 = 32'h0000_0000;  // index=0, tag=0
        PC_CONFLICT2 = 32'h0001_0000;  // index=0, tag=different

        $display("T6: BTB conflict resolution (same BTB index, different tags)");

        reset_dut();

        // First, train PC_CONFLICT1 -> TGT_A
        repeat (3) train_task(PC_CONFLICT1, '0, 1'b1, TGT_A);

        // Then train PC_CONFLICT2 -> TGT_B (same BTB index, different tag)
        repeat (3) train_task(PC_CONFLICT2, '0, 1'b1, TGT_B);

        // PCs have different tags, so PC_CONFLICT1 won't hit BTB (tag mismatch)
        predict(PC_CONFLICT1, 1'b0, t, tgt, snap);
        EXPECT_BIT("T6.pc_conflict1_taken", t, 1'b1);  // PHT still predicts taken
        EXPECT_EQ("T6.pc_conflict1_target", tgt, 32'h0);  // No BTB hit due to tag mismatch
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;

        // PC_CONFLICT2 should predict TGT_B
        predict(PC_CONFLICT2, 1'b0, t, tgt, snap);
        EXPECT_BIT("T6.pc_conflict2_taken", t, 1'b1);
        EXPECT_EQ("T6.pc_conflict2_target", tgt, TGT_B);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;
    endtask

    // T7: GHR pattern influence on prediction
    task automatic TEST7();
        logic t;
        logic [31:0] tgt;
        logic [GH-1:0] snap;
        logic [31:0] PC_A, PC_B;

        $display("T7: GHR pattern influence on different PCs with same PHT index");

        reset_dut();

        // Find two PCs that have the same PHT index with different GHR
        // PC_A ^ GHR1 = PC_B ^ GHR2
        // Use PC_T1 with GHR=0000, and find PC that gives same index with GHR=1111
        PC_A = PC_T1;  // index with GHR=0000
        PC_B = PC_T1 ^ 4'b1111;  // PC_A ^ 1111, so PC_B ^ 1111 = PC_A ^ 0000

        // Train PC_A with GHR=0000 -> taken
        repeat (4) train_task(PC_A, 4'b0000, 1'b1, TGT_A);

        // Train PC_B with GHR=1111 -> not taken (same PHT index as PC_A with GHR=0000)
        repeat (4) train_task(PC_B, 4'b1111, 1'b0, '0);

        // Predict PC_A with GHR=0000 -> should be taken
        mispredict_restore(4'b0000);
        predict(PC_A, 1'b0, t, tgt, snap);
        EXPECT_BIT("T7.pca_taken", t, 1'b1);
        EXPECT_EQ("T7.pca_target", tgt, TGT_A);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;

        // Predict PC_B with GHR=1111 -> should be not taken (same PHT entry as PC_A with GHR=0000)
        mispredict_restore(4'b1111);
        predict(PC_B, 1'b0, t, tgt, snap);
        EXPECT_BIT("T7.pcb_taken", t, 1'b0);
        EXPECT_EQ("T7.pcb_target", tgt, 32'h0);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;
    endtask

    // T8: Training without prediction (edge case)
    task automatic TEST8();
        logic t;
        logic [31:0] tgt;
        logic [GH-1:0] snap;
        $display("T8: Training without prior prediction");

        reset_dut();

        // Train directly without predicting first
        train_task(PC_T4, '0, 1'b1, TGT_B);

        // Now predict
        predict(PC_T4, 1'b0, t, tgt, snap);
        EXPECT_BIT("T8.train_only_taken", t, 1'b1);
        EXPECT_EQ("T8.train_only_target", tgt, TGT_B);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;
    endtask


    // T9: Reset verification - all structures cleared
    task automatic TEST9();
        logic t;
        logic [31:0] tgt;
        logic [GH-1:0] snap;
        $display("T9: Reset verification - all structures cleared");

        // First, train some state
        reset_dut();
        repeat (2) train_task(PC_T0, '0, 1'b1, TGT_A);
        repeat (2) train_task(PC_T1, '0, 1'b1, TGT_B);

        // Verify training worked
        predict(PC_T0, 1'b0, t, tgt, snap);
        EXPECT_BIT("T9.pre_reset_taken", t, 1'b1);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;

        // Apply reset
        reset_dut();

        // Verify reset cleared everything
        predict(PC_T0, 1'b0, t, tgt, snap);
        EXPECT_BIT("T9.post_reset_taken", t, 1'b0);  // Should be NT after reset
        EXPECT_EQ("T9.post_reset_target", tgt, 32'h0);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;

        predict(PC_T1, 1'b0, t, tgt, snap);
        EXPECT_BIT("T9.post_reset_t1_taken", t, 1'b0);
        EXPECT_EQ("T9.post_reset_t1_target", tgt, 32'h0);
        @(negedge clock);
        predict_req.valid = 0;
        predict_req.used  = 0;
    endtask

    // ---------------------------------------------------------------------------
    // Test runner
    // ---------------------------------------------------------------------------
    initial begin
        $display("\n==== branch_predictor_test_all ====\n");
        do_reset();  // one reset at start

        TEST0();
        TEST1();
        TEST2();
        TEST3();
        TEST4();
        TEST5();
        TEST6();
        TEST7();
        TEST8();
        TEST9();

        $display("\n");
        if (total_fail == 0) begin
            $display("@@@ PASSED");
        end else begin
            $display("@@@ FAILED");
        end

        $finish;
    end

endmodule
