`timescale 1ns/1ps

module branch_predictor_test_all;

  // ---------------------------------------------------------------------------
  // Parameters (keep small so indices are easy to reason about)
  // ---------------------------------------------------------------------------
  localparam int unsigned PC_BITS   = 32; // fixed 32-bit PCs/targets
  localparam int unsigned GH        = 4;  // 4-bit GHR
  localparam int unsigned PHT_BITS  = 4;  // 16-entry PHT
  localparam int unsigned BTB_BITS  = 4;  // 16-entry BTB

  // ---------------------------------------------------------------------------
  // DUT I/O (testbench-side signals)
  // ---------------------------------------------------------------------------
  logic clock, reset;

  // Predict req/resp
  logic              predict_req_valid;
  logic [31:0]       predict_req_pc;
  logic              predict_req_used;

  logic              predict_taken;
  logic [31:0]       predict_target;
  logic [GH-1:0]     predict_ghr_snapshot;

  // Train (update)
  logic              train_valid;
  logic [31:0]       train_pc;
  logic              train_actual_taken;
  logic [31:0]       train_actual_target;
  logic [GH-1:0]     train_ghr_snapshot;

  // Recovery
  logic              recover_mispredict_pulse;
  logic [GH-1:0]     recover_ghr_snapshot;

  // ---------------------------------------------------------------------------
  // DUT instance (matches the cleaned-up RTL names)
  // ---------------------------------------------------------------------------
  branch_predictor #(
    .GH(GH),
    .PHT_BITS(PHT_BITS),
    .BTB_BITS(BTB_BITS)
  ) dut (
    .clock                   (clock),
    .reset                   (reset),

    .predict_req_valid_i        (predict_req_valid),
    .predict_req_pc_i           (predict_req_pc),
    .predict_req_used_i         (predict_req_used),

    .predict_taken_o            (predict_taken),
    .predict_target_o           (predict_target),
    .predict_ghr_snapshot_o     (predict_ghr_snapshot),

    .train_valid_i              (train_valid),
    .train_pc_i                 (train_pc),
    .train_actual_taken_i       (train_actual_taken),
    .train_actual_target_i      (train_actual_target),
    .train_ghr_snapshot_i       (train_ghr_snapshot),

    .recover_mispredict_pulse_i (recover_mispredict_pulse),
    .recover_ghr_snapshot_i     (recover_ghr_snapshot)
  );

  // ---------------------------------------------------------------------------
  // Clock / Reset
  // ---------------------------------------------------------------------------
  initial clock = 0;
  always #5 clock = ~clock;  // 100 MHz

  task automatic init_signals();
    begin
      predict_req_valid        = 0;
      predict_req_pc           = '0;
      predict_req_used         = 0;

      train_valid              = 0;
      train_pc                 = '0;
      train_actual_taken       = 0;
      train_actual_target      = '0;
      train_ghr_snapshot       = '0;

      recover_mispredict_pulse = 0;
      recover_ghr_snapshot     = '0;
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
    predict_req_valid        = 0; predict_req_pc = '0; predict_req_used = 0;
    train_valid              = 0; train_pc = '0; train_actual_taken = 0; train_actual_target = '0; train_ghr_snapshot = '0;
    recover_mispredict_pulse = 0; recover_ghr_snapshot = '0;
    repeat (3) @(posedge clock);
    reset = 1'b0;
    @(posedge clock); // allow flops to initialize
  endtask

  task automatic predict(
    input  logic [31:0] pc,
    input  bit          mark_used,
    output logic        taken,
    output logic [31:0] target,
    output logic [GH-1:0] ghr_snap
  );
    // 1) drive inputs
    @(negedge clock);
    predict_req_pc    = pc;
    predict_req_valid = 1'b1;
    predict_req_used  = mark_used;

    // 2) let DUT comb settle across posedge
    @(posedge clock);
    #1;
    taken    = predict_taken;
    target   = predict_target;
    ghr_snap = predict_ghr_snapshot;
    // caller deasserts after checks
  endtask

  task automatic train_task(
    input logic [31:0]  pc,
    input logic [GH-1:0] ghr_snap,
    input bit            actual_taken,
    input logic [31:0]   actual_target
  );
    @(negedge clock);
    train_pc            = pc;
    train_ghr_snapshot  = ghr_snap;
    train_actual_taken  = actual_taken;
    train_actual_target = actual_target;
    train_valid         = 1'b1;
    @(posedge clock);           // capture update
    @(negedge clock);
    train_valid         = 1'b0; // tidy deassert
    @(posedge clock);
  endtask

  task automatic mispredict_restore(input logic [GH-1:0] restore_snap);
    @(negedge clock);
    recover_ghr_snapshot = restore_snap;
    @(posedge clock);
    recover_mispredict_pulse = 1'b1;
    @(negedge clock);
    recover_mispredict_pulse = 1'b0;
  endtask

  // ---------------------------------------------------------------------------
  // Unique PCs per test (so tests are independent even though PHT/BTB aren't reset)
  // ---------------------------------------------------------------------------
  localparam logic [GH-1:0]   GHRS0 = '0;            // fixed snapshot for deterministic training
  localparam logic [31:0]     PC_T0 = 32'h0000_0040; // idx 0x4
  localparam logic [31:0]     PC_T1 = 32'h0000_0080; // idx 0x8
  localparam logic [31:0]     PC_T2 = 32'h0000_00C0; // idx 0xC
  localparam logic [31:0]     PC_T3 = 32'h0000_0100; // idx 0x0 (new tag)
  localparam logic [31:0]     PC_T4 = 32'h0000_0140; // idx 0x4 but different tag
  localparam logic [31:0]     PC_T5 = 32'h0000_0180; // idx 0x8 (separate from T1 by tag)

  localparam logic [31:0]     TGT_A  = 32'h0000_0800;
  localparam logic [31:0]     TGT_B  = 32'h0000_0888;

  // ---------------------------------------------------------------------------
  // Individual tests (each self-contained, primes its own state)
  // ---------------------------------------------------------------------------

  // T0: Prime PHT entry to NT for the used PC (predict NT; target=0).
  task automatic TEST0();
    logic t; logic [31:0] tgt; logic [GH-1:0] snap;
    $display("T0: Prime PHT to NT and check NT prediction (PC_T0)");
    mispredict_restore(GHRS0);                     // precise GHR = 0
    repeat (3) train_task(PC_T0, GHRS0, 1'b0, '0); // move that entry toward NT
    predict(PC_T0, 1'b0, t, tgt, snap);            // read without shifting history
    EXPECT_BIT("T0.taken", t, 1'b0);
    EXPECT_EQ ("T0.target", tgt, 32'h0);
    @(negedge clock); predict_req_valid = 0; predict_req_used = 0;
  endtask

  task automatic TEST1();
    logic t; logic [31:0] tgt; logic [GH-1:0] snap;
    $display("T1: Train TAKEN+BTB, expect TAKEN + target (PC_T1 -> TGT_A)");
    reset_dut();
    repeat (3) train_task(PC_T1, '0, 1'b1, TGT_A); // deterministic training
    @(posedge clock);

    predict(PC_T1, 1'b0, t, tgt, snap);            // don’t shift GHR
    @(negedge clock); predict_req_valid = 0; predict_req_used = 0;

    EXPECT_BIT("T1.taken",  t,   1'b1);
    EXPECT_EQ ("T1.target", tgt, TGT_A);
  endtask

  task automatic TEST2();
    logic t; logic [31:0] tgt; logic [GH-1:0] snap;
    $display("T2: Saturation clamp check (PC_T2)");
    mispredict_restore(GHRS0);
    repeat (4) train_task(PC_T2, GHRS0, 1'b1, TGT_A); // drive to strongly TAKEN
    predict(PC_T2, 1'b0, t, tgt, snap);
    EXPECT_BIT("T2.post_push_taken", t, 1'b1);
    @(negedge clock); predict_req_valid = 0; predict_req_used = 0;

    repeat (5) train_task(PC_T2, GHRS0, 1'b0, '0);    // drive to strongly NT
    predict(PC_T2, 1'b0, t, tgt, snap);
    EXPECT_BIT("T2.post_pull_taken", t, 1'b0);
    EXPECT_EQ ("T2.post_pull_target", tgt, 32'h0);
    @(negedge clock); predict_req_valid = 0; predict_req_used = 0;
  endtask

  task automatic TEST3();
    logic t; logic [31:0] tgt; logic [GH-1:0] snap;
    $display("T3: Independent PC TAKEN+BTB (PC_T3 -> TGT_B)");
    mispredict_restore(GHRS0);
    repeat (3) train_task(PC_T3, GHRS0, 1'b1, TGT_B);
    predict(PC_T3, 1'b0, t, tgt, snap);
    EXPECT_BIT("T3.taken", t, 1'b1);
    EXPECT_EQ ("T3.target", tgt, TGT_B);
    @(negedge clock); predict_req_valid = 0; predict_req_used = 0;
  endtask

  task automatic TEST4();
    logic t; logic [31:0] tgt; logic [GH-1:0] snap;
    $display("T4: NT prediction -> target must be 0 (PC_T4)");
    mispredict_restore(GHRS0);
    repeat (3) train_task(PC_T4, GHRS0, 1'b0, '0);
    predict(PC_T4, 1'b0, t, tgt, snap);
    EXPECT_BIT("T4.taken", t, 1'b0);
    EXPECT_EQ ("T4.target", tgt, 32'h0);
    @(negedge clock); predict_req_valid = 0; predict_req_used = 0;
  endtask

  // T5: GHR speculative shift + mispredict restore sanity.
  task automatic TEST5();
    logic t; logic [31:0] tgt; logic [GH-1:0] snap_before, snap_after;
    $display("T5: GHR mispredict restore (PC_T5)");
    // Predict with use => speculative shift
    predict(PC_T5, 1'b1, t, tgt, snap_before);
    @(negedge clock); predict_req_valid = 0; predict_req_used = 0;

    // Restore precise GHR to snapshot
    mispredict_restore(snap_before);

    // Next predict (no use) should show same snapshot again
    predict(PC_T5, 1'b0, t, tgt, snap_after);
    EXPECT_EQ("T5.ghr_restored",
              {{(PC_BITS-GH){1'b0}}, snap_after},
              {{(PC_BITS-GH){1'b0}}, snap_before});
    @(negedge clock); predict_req_valid = 0; predict_req_used = 0;
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

    $display("\n==== SUMMARY ====");
    $display("Total PASS: %0d", total_pass);
    $display("Total FAIL: %0d", total_fail);
    if (total_fail == 0)
      $display("All tests PASSED ✔️");
    else
      $display("Some tests FAILED ❌");

    $finish;
  end

endmodule
