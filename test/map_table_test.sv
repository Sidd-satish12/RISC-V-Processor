// test/map_table_test.sv
`timescale 1ns/100ps
`ifndef SYNTH
`define TEST_MODE
`endif


module map_table_test;
  // ---- DUT params ----
  localparam int ARCH_COUNT = 32;
  localparam int PHYS_REGS  = 64;
  localparam int N          = 3;
  localparam int PRW        = (PHYS_REGS <= 2) ? 1 : $clog2(PHYS_REGS);

  // ---- Clock/Reset ----
  logic clock, reset;
  initial begin clock = 0; forever #5 clock = ~clock; end
  initial begin reset = 1; repeat (2) @(posedge clock); reset = 0; end

  // ---- Wires between DUTs ----
  logic [ARCH_COUNT-1:0][PRW-1:0] archi_maptable;

  // map_table inputs
  logic                           BPRecoverEN;
  logic         [N-1:0]           cdb_valid;
  logic [N-1:0][PRW-1:0]          cdb_tag;
  logic [N-1:0][PRW-1:0]          maptable_new_pr;
  logic [N-1:0][$clog2(ARCH_COUNT)-1:0] maptable_new_ar;
  logic [N-1:0][$clog2(ARCH_COUNT)-1:0] reg1_ar, reg2_ar;

  // map_table outputs
  logic [N-1:0][PRW-1:0]          reg1_tag, reg2_tag;
  logic [N-1:0]                   reg1_ready, reg2_ready;
  logic [N-1:0][PRW-1:0]          Told_out;

  // TEST_MODE taps from map_table
  logic [ARCH_COUNT-1:0][PRW-1:0] map_array_disp;
  logic [ARCH_COUNT-1:0]          ready_array_disp;

  // arch_maptable (retire) inputs
  logic [N-1:0]                   Retire_EN;
  logic [N-1:0][PRW-1:0]          Tnew_in;
  logic [N-1:0][$clog2(ARCH_COUNT)-1:0] Retire_AR;

  // ---- DUTs ----
  map_table #(.ARCH_COUNT(ARCH_COUNT), .PHYS_REGS(PHYS_REGS), .N(N)) u_mt (
    .clock, .reset,
    .archi_maptable(archi_maptable),
    .BPRecoverEN(BPRecoverEN),
    .cdb_valid, .cdb_tag,
    .maptable_new_pr, .maptable_new_ar,
    .reg1_ar, .reg2_ar,
    .reg1_tag, .reg2_tag, .reg1_ready, .reg2_ready,
    .Told_out,
    .map_array_disp, .ready_array_disp
  );

  arch_maptable #(.ARCH_COUNT(ARCH_COUNT), .PHYS_REGS(PHYS_REGS), .N(N)) u_amt (
    .clock, .reset,
    .Retire_EN, .Tnew_in, .Retire_AR,
    .archi_maptable
  );

  // ================= Helpers =================
  // zero inputs each cycle unless a test overrides them
  task automatic clear_dispatch();
    for (int i = 0; i < N; ++i) begin
      maptable_new_ar[i] = '0;
      maptable_new_pr[i] = '0;
      reg1_ar[i]         = '0;
      reg2_ar[i]         = '0;
    end
  endtask

  task automatic clear_cdb();    cdb_valid = '0; cdb_tag = '0; endtask
  task automatic clear_retire(); Retire_EN = '0; Tnew_in = '0; Retire_AR = '0; endtask

  // begin/end cycle: we *drive* on negedge, we *sample/check* just after posedge
  task automatic begin_cycle();
    @(negedge clock);
    clear_dispatch(); clear_cdb(); clear_retire();
    BPRecoverEN = 1'b0;
  endtask

  task automatic end_cycle();
    @(posedge clock); #1;
  endtask

  // set a single dispatch lane (N-1 = oldest)
  task automatic set_lane(
    input int lane,
    input int ar_dst,
    input int pr_new,
    input int ar_src1,
    input int ar_src2
  );
    maptable_new_ar[lane] = ar_dst[$clog2(ARCH_COUNT)-1:0];
    maptable_new_pr[lane] = pr_new[PRW-1:0];
    reg1_ar[lane]         = ar_src1[$clog2(ARCH_COUNT)-1:0];
    reg2_ar[lane]         = ar_src2[$clog2(ARCH_COUNT)-1:0];
  endtask

  task automatic set_cdb(input int slot, input bit v, input int tag);
    cdb_valid[slot] = v;
    cdb_tag  [slot] = tag[PRW-1:0];
  endtask

  // convenience accessors
  function automatic int get_map(input int ar);   return map_array_disp[ar]; endfunction
  function automatic bit get_ready(input int ar); return ready_array_disp[ar]; endfunction

  // tiny assert wrappers (count pass/fail)
  int pass_ct = 0, fail_ct = 0;
  task automatic expect_eq_int(string name, int got, int exp);
    if (got !== exp) begin
      $display("FAIL: %s  got=%0d exp=%0d", name, got, exp); fail_ct++;
    end else begin
      pass_ct++;
    end
  endtask
  task automatic expect_eq_bit(string name, bit got, bit exp);
    if (got !== exp) begin
      $display("FAIL: %s  got=%0b exp=%0b", name, got, exp); fail_ct++;
    end else begin
      pass_ct++;
    end
  endtask

  // ================= Testcases =================

  // 0) Reset: identity mapping, all ready=1
  task automatic tc_reset();
    // wait for reset to drop then sample
    @(negedge reset); @(posedge clock); #1;
    for (int ar = 0; ar < ARCH_COUNT; ++ar) begin
      expect_eq_int($sformatf("reset map[%0d]", ar), get_map(ar), ar);
      expect_eq_bit($sformatf("reset ready[%0d]", ar), get_ready(ar), 1'b1);
    end
  endtask

  // 1) Register renaming (multi-lane) + Told correctness
  task automatic tc_rename_and_told();
    begin_cycle();
      // oldest..youngest: AR1->33, AR2->34, AR3->35
      set_lane(2, 1, 33, 0, 0);
      set_lane(1, 2, 34, 0, 0);
      set_lane(0, 3, 35, 0, 0);
    end_cycle();

    // Told must be old mappings (1,2,3)
    expect_eq_int("Told lane2 (AR1)", Told_out[2], 1);
    expect_eq_int("Told lane1 (AR2)", Told_out[1], 2);
    expect_eq_int("Told lane0 (AR3)", Told_out[0], 3);

    // New MT contents
    expect_eq_int("map[1] C1", get_map(1), 33);
    expect_eq_int("map[2] C1", get_map(2), 34);
    expect_eq_int("map[3] C1", get_map(3), 35);

    // Ready bits drop for renamed (except AR0)
    expect_eq_bit("ready[1] C1", get_ready(1), 0);
    expect_eq_bit("ready[2] C1", get_ready(2), 0);
    expect_eq_bit("ready[3] C1", get_ready(3), 0);
  endtask

  // 2) CDB match → mark ready; ignore mismatches and tag=0
  task automatic tc_cdb_ready();
    // broadcast PR33 and PR34 only; AR3 should stay not ready
    begin_cycle();
      set_cdb(0, 1, 33);
      set_cdb(1, 1, 34);
      set_cdb(2, 0, 0); // ignored
    end_cycle();

    expect_eq_bit("CDB: AR1 ready", get_ready(1), 1);
    expect_eq_bit("CDB: AR2 ready", get_ready(2), 1);
    expect_eq_bit("CDB: AR3 still 0", get_ready(3), 0);
  endtask

  // 3) Rename again + CDB hit for a different PR
  task automatic tc_rename_again_and_cdb();
    // Rename AR1 -> 36, and complete PR35 (AR3)
    begin_cycle();
      set_lane(2, 1, 36, 1, 2); // AR1 new PR36 makes AR1 not-ready again
      set_cdb(0, 1, 35);       // complete AR3's PR35
    end_cycle();

    expect_eq_int("C3 map[1]=36", get_map(1), 36);
    expect_eq_bit("C3 AR1 not-ready", get_ready(1), 0);
    expect_eq_bit("C3 AR3 now ready", get_ready(3), 1);
  endtask

  // 4) Retirement updates architectural map table (AMT)
  task automatic tc_retire_updates_amt();
    // Retire in order: (AR1<-33), (AR2<-34)
    begin_cycle();
      Retire_EN[N-1] = 1; Retire_AR[N-1] = 1; Tnew_in[N-1] = 33;
      Retire_EN[N-2] = 1; Retire_AR[N-2] = 2; Tnew_in[N-2] = 34;
    end_cycle();

    expect_eq_int("AMT AR1=33", archi_maptable[1], 33);
    expect_eq_int("AMT AR2=34", archi_maptable[2], 34);
  endtask

  // 5) Branch recovery policy: copy AMT -> MT and set all ready=1
  // (this corresponds to your first bullet: copy AMT on mispredict)
  task automatic tc_recovery_from_amt();
    begin_cycle();
      BPRecoverEN = 1;
    end_cycle();
    BPRecoverEN = 0;

    for (int ar = 0; ar < ARCH_COUNT; ++ar) begin
      expect_eq_int($sformatf("REC map[%0d]=AMT", ar), get_map(ar), archi_maptable[ar]);
      expect_eq_bit($sformatf("REC ready[%0d]=1", ar), get_ready(ar), 1);
    end
  endtask

  // 6) Source lookup bypass: same-cycle older-lane rename should be seen by younger lanes
  task automatic tc_same_cycle_bypass();
    // Make a clean rename trio to test source tags/ready against older lanes
    begin_cycle();
      // oldest lane sets AR10->50, middle lane uses AR10 as a source
      set_lane(2, 10, 50, 0, 0);
      set_lane(1, 11, 51, 10, 0); // reg1_ar sees updated mapping from lane2
      set_lane(0, 12, 52, 11, 10); // sees mapping from lane2 and lane1
    end_cycle();

    // After cycle, MT reflects new mapping…
    expect_eq_int("bypass map[10]=50", get_map(10), 50);
    expect_eq_int("bypass map[11]=51", get_map(11), 51);
    expect_eq_int("bypass map[12]=52", get_map(12), 52);
    // …and younger lanes' source tags must correspond to older lanes' mapping
    expect_eq_int("lane1 reg1_tag == 50", reg1_tag[1], 50);
    expect_eq_int("lane0 reg1_tag == 51", reg1_tag[0], 51);
    expect_eq_int("lane0 reg2_tag == 50", reg2_tag[0], 50);
  endtask

  // 7) AR0 (x0) behavior: stays ready even if “renamed” by mistake
  task automatic tc_ar0_always_ready();
    begin_cycle();
      set_lane(2, 0, 63, 0, 0); // if someone writes AR0, ready should not drop
    end_cycle();
    expect_eq_bit("AR0 ready stays 1", get_ready(0), 1);
  endtask

  // ================= Test Runner =================
  initial begin
    // defaults
    BPRecoverEN = 0; clear_dispatch(); clear_cdb(); clear_retire();

    tc_reset();
    tc_rename_and_told();
    tc_cdb_ready();
    tc_rename_again_and_cdb();
    tc_retire_updates_amt();
    tc_recovery_from_amt();
    tc_same_cycle_bypass();
    tc_ar0_always_ready();

    $display("\n===== SUMMARY =====");
    $display("PASS: %0d", pass_ct);
    $display("FAIL: %0d", fail_ct);
    if (fail_ct == 0) $display("\n@@@PASS: rename_tables_unit_tb completed successfully\n");
    else              $display("\n@@@FAIL: rename_tables_unit_tb had failures\n");
    $finish;
  end
endmodule
