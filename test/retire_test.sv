`timescale 1ns/1ps
`ifndef __RETIRE_TEST_SV__
`define __RETIRE_TEST_SV__

`include "sys_defs.svh"

// Small helper to convert int->logic width safely
function automatic logic [$clog2(`ROB_SZ)-1:0] to_robidx(int i);
  return logic'((i % `ROB_SZ));
endfunction

module retire_test;

  localparam int N          = `N;
  localparam int ARCH_COUNT = 32;
  localparam int PHYS_REGS  = `PHYS_REG_SZ_R10K;
  localparam int PRW        = (PHYS_REGS <= 2) ? 1 : $clog2(PHYS_REGS);
  localparam time TCK       = 10ns;

  // ----------------
  // Clock / Reset
  // ----------------
  logic clock, reset;
  initial clock = 1'b0;
  always  #(TCK/2) clock = ~clock;

  task automatic do_reset;
    reset = 1'b1; repeat (2) @(posedge clock);
    reset = 1'b0; @(posedge clock);
  endtask

  // ----------------
  // DUT instances
  // ----------------

  // ROB <-> Retire signals
  logic        [N-1:0]  alloc_valid;
  ROB_ENTRY    [N-1:0]  rob_entry_packet;
  ROB_IDX      [N-1:0]  alloc_idxs;
  logic [$clog2(`ROB_SZ+1)-1:0] rob_free_slots;

  ROB_UPDATE_PACKET      rob_update_packet;
  ROB_ENTRY    [N-1:0]   head_entries;
  logic        [N-1:0]   head_valids;

  logic                  rob_mispredict;
  ROB_IDX                rob_mispred_idx;

  // Retire -> Map / Freelist
  logic                  BPRecoverEN;
  logic        [N-1:0]   Arch_Retire_EN;
  logic [N-1:0][PRW-1:0] Arch_Tnew_in;
  logic [N-1:0][$clog2(ARCH_COUNT)-1:0] Arch_Retire_AR;

  logic        [N-1:0]   FL_RetireEN;
  logic [N-1:0][PRW-1:0] FL_RetireReg;

  // Precise map
  logic [ARCH_COUNT-1:0][PRW-1:0] archi_maptable_img;

  // Map-table side (CDB disabled in this test)
  logic [N-1:0]                 cdb_valid;
  logic [N-1:0][PRW-1:0]        cdb_tag;
  logic [N-1:0][PRW-1:0]        reg1_tag, reg2_tag;
  logic [N-1:0]                 reg1_ready, reg2_ready;
  logic [N-1:0][PRW-1:0]        Told_out;

  // Freelist side
  logic [N-1:0]                 AllocReqMask;
  PHYS_TAG [N-1:0]              FreeReg;
  logic [$clog2(PHYS_REGS+1)-1:0] free_count;
  logic [$clog2(N+1)-1:0]       FreeSlotsForN;

  // ================== INSTANCES ==================

  // ROB
  rob u_rob (
    .clock,
    .reset,
    .alloc_valid,
    .rob_entry_packet,
    .alloc_idxs,
    .free_slots(rob_free_slots),

    .rob_update_packet,

    .head_entries,
    .head_valids,

    .mispredict   (rob_mispredict),   // driven by retire
    .mispred_idx  (rob_mispred_idx)
  );

  `ifndef SYNTH
  retire #(.N(N), .ARCH_COUNT(ARCH_COUNT), .PHYS_REGS(PHYS_REGS)) u_retire (
`else
  retire u_retire (
`endif
    .clock, .reset,
    .head_entries, .head_valids,
    .rob_mispredict, .rob_mispred_idx,
    .BPRecoverEN,
    .Arch_Retire_EN, .Arch_Tnew_in, .Arch_Retire_AR,
    .FL_RetireEN, .FL_RetireReg,
    .archi_maptable(archi_maptable_img)
  );


  // Retire
  // retire #(.N(N), .ARCH_COUNT(ARCH_COUNT), .PHYS_REGS(PHYS_REGS)) u_retire (
  //   .clock,
  //   .reset,

  //   .head_entries,
  //   .head_valids,

  //   .rob_mispredict,
  //   .rob_mispred_idx,

  //   .BPRecoverEN,

  //   .Arch_Retire_EN,
  //   .Arch_Tnew_in,
  //   .Arch_Retire_AR,

  //   .FL_RetireEN,
  //   .FL_RetireReg,

  //   .archi_maptable(archi_maptable_img)
  // );

  // Precise architectural map (commit-time)

  `ifndef SYNTH
  arch_maptable #(.ARCH_COUNT(ARCH_COUNT), .PHYS_REGS(PHYS_REGS), .N(N)) u_arch (
`else
  arch_maptable u_arch (
`endif
    .clock, .reset,
    .Retire_EN(Arch_Retire_EN), .Tnew_in(Arch_Tnew_in), .Retire_AR(Arch_Retire_AR),
    .archi_maptable(archi_maptable_img)
  );

  // arch_maptable #(.ARCH_COUNT(ARCH_COUNT), .PHYS_REGS(PHYS_REGS), .N(N)) u_arch (
  //   .clock,
  //   .reset,
  //   .Retire_EN (Arch_Retire_EN),
  //   .Tnew_in   (Arch_Tnew_in),
  //   .Retire_AR (Arch_Retire_AR),
  //   .archi_maptable(archi_maptable_img)
  // );

  // Speculative map (rename-time). We only need it to listen to BPRecoverEN and to
  // reflect the precise image; CDB/operand lookups unused here.

  `ifndef SYNTH
  map_table #(.ARCH_COUNT(ARCH_COUNT), .PHYS_REGS(PHYS_REGS), .N(N)) u_map (
`else
  map_table u_map (
`endif
    .clock, .reset,
    .archi_maptable(archi_maptable_img), .BPRecoverEN,
    .cdb_valid('0), .cdb_tag('0),
    .maptable_new_pr('0), .maptable_new_ar('0),
    .reg1_ar('0), .reg2_ar('0),
    .reg1_tag, .reg2_tag, .reg1_ready, .reg2_ready,
    .Told_out
  );

  // map_table #(.ARCH_COUNT(ARCH_COUNT), .PHYS_REGS(PHYS_REGS), .N(N)) u_map (
  //   .clock,
  //   .reset,
  //   .archi_maptable(archi_maptable_img),
  //   .BPRecoverEN,

  //   .cdb_valid('0),
  //   .cdb_tag  ('0),

  //   .maptable_new_pr('0),
  //   .maptable_new_ar('0),

  //   .reg1_ar('0),
  //   .reg2_ar('0),

  //   .reg1_tag,
  //   .reg2_tag,
  //   .reg1_ready,
  //   .reg2_ready,

  //   .Told_out
  // );

  // Freelist (Dispatch-driven)

  `ifndef SYNTH
  freelist #(.N(N), .PR_COUNT(PHYS_REGS), .ARCH_COUNT(ARCH_COUNT), .EXCLUDE_ZERO(1'b1)) u_fl (
`else
  freelist u_fl (
`endif
    .clock, .reset_n(~reset),
    .AllocReqMask(AllocReqMask), .FreeReg(FreeReg),
    .free_count, .FreeSlotsForN,
    .RetireEN(FL_RetireEN), .RetireReg(FL_RetireReg),
    .BPRecoverEN(BPRecoverEN), .archi_maptable(archi_maptable_img)
  );

  // freelist #(.N(N), .PR_COUNT(PHYS_REGS), .ARCH_COUNT(ARCH_COUNT), .EXCLUDE_ZERO(1'b1)) u_fl (
  //   .clock,
  //   .reset_n(~reset),

  //   .AllocReqMask (AllocReqMask),
  //   .FreeReg (FreeReg),
  //   .free_count,
  //   .FreeSlotsForN,

  //   .RetireEN (FL_RetireEN),
  //   .RetireReg(FL_RetireReg),

  //   .BPRecoverEN  (BPRecoverEN),
  //   .archi_maptable (archi_maptable_img)
  // );

  // ----------------
  // Test utilities
  // ----------------
  task automatic expect_ok(input bit cond, input string msg);
    if (!cond) begin
      $display("[%0t] FAIL: %s", $time, msg);
      $display("@@@ Failed");
      $fatal(1);
    end
  endtask

  // init a ROB entry struct quickly

  function automatic ROB_ENTRY mk_entry(
    input int ridx,
    input bit is_branch,
    input bit pred_taken, input logic [31:0] pred_tgt,
    input bit has_dest,  input int dest_ar,
    input int Tnew,      input int Told);
  ROB_ENTRY e;
    e.valid    = 1'b1;
    e.complete = 1'b0;
    e.exception = NO_ERROR;
    e.rob_idx  = to_robidx(ridx);

    e.branch        = is_branch;
    e.pred_taken    = pred_taken;
    e.pred_target   = pred_tgt;
    e.branch_taken  = 1'b0;
    e.branch_target = '0;

    e.arch_rd      = has_dest ? REG_IDX'(dest_ar[4:0]) : '0;
    e.phys_rd      = PHYS_TAG'(Tnew);       // (≙ Tnew)
    e.prev_phys_rd = PHYS_TAG'(Told);       // (≙ Told)
    
    e.PC   = '0;
    e.inst = '0;
    e.value = '0;
    e.halt = 1'b0;
    e.illegal = 1'b0;
    return e;
  endfunction

// Capture the slot the ROB assigned to a given lane on the *last* alloc edge
  function automatic ROB_IDX last_alloc_slot(input int lane);
    // Using the alloc_idxs that ROB drives after the alloc posedge
    return alloc_idxs[lane];
  endfunction

  // clear ROB update packet
  task automatic clear_rob_update();
    rob_update_packet.valid          = '0;
    rob_update_packet.idx            = '0;
    rob_update_packet.values         = '0;
    rob_update_packet.branch_taken   = '0;
    rob_update_packet.branch_targets = '0;
  endtask

  // mark one lane complete (and optionally set branch resolution)
  task automatic rob_complete_lane(
      input int lane, input int ridx, input bit br_valid, input bit br_taken, input int br_tgt);
    rob_update_packet.valid[lane]          = 1'b1;
    rob_update_packet.idx  [lane]          = to_robidx(ridx);
    if (br_valid) begin
      rob_update_packet.branch_taken  [lane] = br_taken;
      rob_update_packet.branch_targets[lane] = ADDR'(br_tgt);
    end
  endtask


  // ----------------
  // The test
  // ----------------
  int ridx_base;
  int cA;
  int cF; 
  int cA2; 
  int cF2;
  logic saw5;
  logic saw6;
  ROB_IDX s0;
  ROB_IDX s1;
  ROB_IDX sB_head;
  ROB_IDX sB_slot;
  ROB_IDX sel_slot;

  initial begin
    // defaults
    alloc_valid       = '0;
    rob_entry_packet  = '{default:'0};
    clear_rob_update();

    cdb_valid         = '0; cdb_tag = '0;
    AllocReqMask      = '0;

    do_reset();

    // Make a little room in freelist so later returns don't overflow the fixed-depth queue
    // Pop N tags for a couple cycles
    repeat (3) begin
      @(negedge clock);
      AllocReqMask = {N{1'b1}};
      @(posedge clock);
    end
    @(negedge clock) AllocReqMask = '0; @(posedge clock);

    // =========================
    // SCENARIO 1: normal commit
    // =========================
    // Allocate 2 ALU uops with dests:
    //   E0: dest x5,  Tnew=40, Told=5
    //   E1: dest x6,  Tnew=41, Told=6
    ridx_base = 10;

    @(negedge clock);
      alloc_valid = '0;
      rob_entry_packet = '{default:'0};

      alloc_valid[0] = 1'b1;
      rob_entry_packet[0] = mk_entry(ridx_base+0, /*branch*/0, 0, 32'h0,
                                     /*has_dest*/1, /*dest_ar*/5, /*Tnew*/40, /*Told*/5);

      alloc_valid[1] = 1'b1;
      rob_entry_packet[1] = mk_entry(ridx_base+1, 0, 0, 32'h0,
                                     1, 6, 41, 6);
    @(posedge clock);

    // Capture the actual ROB slots assigned for each lane (this cycle's grants)
    s0 = last_alloc_slot(0);
    s1 = last_alloc_slot(1);


    // IMPORTANT: drop alloc_valid before issuing completes to avoid any new grants
    @(negedge clock) alloc_valid = '0;

    // Mark both complete (same cycle)
    @(negedge clock);
      clear_rob_update();
      rob_complete_lane(1, s1, /*br_valid*/0, 0, 0);
      rob_complete_lane(0, s0, /*br_valid*/0, 0, 0);
    @(posedge clock);

    // Let retire consume head entries
    @(negedge clock) begin
      cA = 0; cF = 0;
      saw5=0; saw6=0;
      for (int i=0;i<N;i++) begin cA += Arch_Retire_EN[i]; cF += FL_RetireEN[i]; end
      expect_ok(cA==2, "Scenario1: expected 2 precise-map commits");
      expect_ok(cF==2, "Scenario1: expected 2 freelist returns");

      // Spot-check contents: the returned Told must be {5,6} in some lanes.
      for (int i=0;i<N;i++) begin
        if (FL_RetireEN[i]) begin
          if (FL_RetireReg[i]==PHYS_TAG'(5)) saw5=1;
          if (FL_RetireReg[i]==PHYS_TAG'(6)) saw6=1;
        end
      end
      expect_ok(saw5 && saw6, "Scenario1: freelist did not see Told={5,6}");
      $display("[%0t] PASS: Scenario 1 (normal commit) — precise map updated for x5,x6 and Told={5,6} returned", $time);
      $display("=== SCENARIO 1 PASSED ===");
    end
    @(posedge clock);

    // ==============================
    // SCENARIO 2: branch mispredict
    // ==============================
    ridx_base = 20;

    @(negedge clock);
      alloc_valid = '0;
      rob_entry_packet = '{default:'0};
      alloc_valid[0] = 1'b1;
      rob_entry_packet[0] = mk_entry(
        ridx_base+0, /*branch*/1, /*pred_taken*/0, /*pred_tgt*/32'h20,
        /*has_dest*/0, /*dest_ar*/0, /*Tnew*/0, /*Told*/0
      );
    @(posedge clock);

    // Freeze alloc so indices don't shift
    @(negedge clock) alloc_valid = '0;

    // Complete the PHYSICAL SLOT that holds the oldest entry
// - In simulation we can peek u_rob.head
// - Under synthesis we use the captured alloc slot (sel_slot)
  `ifndef SYNTH
    sB_slot = u_rob.head;
  `else
    sB_slot = sel_slot;
  `endif


    // Complete the PHYSICAL SLOT that holds the oldest entry: u_rob.head
    //sB_slot = u_rob.head;

    // ---- BEFORE COMPLETE ----
    //dump_head("S2 BEFORE"); // shows oldest entry
    $display("S2 BEFORE: selecting slot=%0d", sB_slot);

    // Drive the COMPLETE packet **directly** (no helpers, no to_robidx)
    @(negedge clock);
      clear_rob_update();
      rob_update_packet.valid = '0;
      rob_update_packet.valid[0]          = 1'b1;
      rob_update_packet.idx  [0]          = sB_slot;      // PHYSICAL SLOT
      rob_update_packet.branch_taken[0]   = 1'b1;         // resolved taken
      rob_update_packet.branch_targets[0] = 32'h00000100; // resolved target
      //dump_complete_pkt("S2 PACKET DRIVEN (pre-pos)");
    @(posedge clock); // ROB samples here
    sel_slot = alloc_idxs[0];

    // ---- AFTER COMPLETE (state visible to retire) ----
    @(negedge clock);
    `ifndef SYNTH
      // Sim-only: safe to peek internals for richer debug
      //dump_head("S2 AFTER"); // oldest.complete should now be 1
      $display("S2 AFTER: slot=%0d -> complete=%0b br_tkn=%0b br_tgt=%h",
              sB_slot,
              u_rob.rob_array[sB_slot].complete,
              u_rob.rob_array[sB_slot].branch_taken,
              u_rob.rob_array[sB_slot].branch_target);
    `else
      // Synth-safe: don’t XMR into u_rob.* — print retire-facing signals instead
      $display("S2 AFTER (synth): will check retire signals; slot=%0d", sB_slot);
    `endif

      // Now retire should see mispredict at oldest head
      cA2 = 0;
      cF2 = 0;
      for (int i=0;i<`N;i++) begin
        cA2 += Arch_Retire_EN[i];
        cF2 += FL_RetireEN[i];
      end
      $display("S2 RETIRE VIEW: mispred=%0b BPRecoverEN=%0b mispred_idx=%0d ArchEN_sum=%0d FLen_sum=%0d",
              rob_mispredict, BPRecoverEN, rob_mispred_idx, cA2, cF2);

      expect_ok(rob_mispredict==1'b1, "Scenario2: expected rob_mispredict=1");
      expect_ok(cA2==0 && cF2==0,      "Scenario2: no Arch/FL on recovery cycle");
      expect_ok(BPRecoverEN==1'b1,     "Scenario2: expected BPRecoverEN=1");
    @(posedge clock);



    $display("=== PASS: retire full-stack basic scenarios OK ===");
    $display("@@@ Passed");
    $finish;
  end


endmodule
`endif