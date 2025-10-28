`timescale 1ns/100ps
`ifndef __FREELIST_TEST_SV__
`define __FREELIST_TEST_SV__

`include "sys_defs.svh"

module freelist_test;

  localparam int  N   = `N;
  localparam time TCK = 10ns;

  // Clock & reset
  logic clock, reset_n;

  // ==== DUT ports (mask-driven interface) ====
  // From Dispatch: per-lane request (aka free_alloc_valid)
  logic       [N-1:0]     AllocReqMask;

  // Offered tags (Dispatch must only consume first pop_now entries)
  PHYS_TAG    [N-1:0]     FreeReg;

  // Availability info
  logic [$clog2(`PHYS_REG_SZ_R10K+1)-1:0] free_count;
  logic [$clog2(N+1)-1:0]                 FreeSlotsForN;

  // Returns from Retire
  logic       [N-1:0]     RetireEN;
  PHYS_TAG    [N-1:0]     RetireReg;

  // Recovery inputs (unused in this test; tie off)
  logic                   BPRecoverEN;
  logic [32-1:0][($clog2(`PHYS_REG_SZ_R10K)>0?$clog2(`PHYS_REG_SZ_R10K):1)-1:0] archi_maptable;

  // Bookkeeping
  int unsigned cycle_count;
  integer safety;

  // Helpers
  task automatic expect_ok(bit cond, string msg);
    if (!cond) begin
      $display("[%0t] FAIL: %s", $time, msg);
      $display("@@@ Failed");
      $fatal(1);
    end
  endtask

  // Make a mask with the lowest K bits set (K in 0..N)
  function automatic logic [N-1:0] ones_mask(input int K);
    logic [N-1:0] m;
    m = '0;
    for (int i = 0; i < N && i < K; i++) m[i] = 1'b1;
    return m;
  endfunction

  // Check the first K visible tags (K = FreeSlotsForN) are valid & unique
  task automatic check_visible_unique();
    int K = FreeSlotsForN;
    for (int i = 0; i < K; i++) begin
      expect_ok(^FreeReg[i] !== 1'bx, $sformatf("FreeReg[%0d] is X", i));
      expect_ok(FreeReg[i] != PHYS_TAG'(0), $sformatf("FreeReg[%0d] is 0", i));
      for (int j = i+1; j < K; j++) begin
        expect_ok(FreeReg[i] != FreeReg[j],
          $sformatf("duplicate tag in same cycle: [%0d]=%0d vs [%0d]=%0d",
                    i, FreeReg[i], j, FreeReg[j]));
      end
    end
  endtask

  // DUT
  freelist #(
    .N(N),
    .PR_COUNT(`PHYS_REG_SZ_R10K),
    .ARCH_COUNT(32),
    .EXCLUDE_ZERO(1'b1)
  ) dut (
    .clock,
    .reset_n,

    // Dispatch mask-driven requests
    .AllocReqMask,
    .FreeReg,
    .free_count,
    .FreeSlotsForN,

    // Returns
    .RetireEN,
    .RetireReg,

    // Recovery (unused here)
    .BPRecoverEN,
    .archi_maptable
  );

  // Clock gen
  initial clock = 1'b0;
  always  #(TCK/2) clock = ~clock;

  // Cycle counter
  always_ff @(posedge clock or negedge reset_n) begin
    if (!reset_n) cycle_count <= 0;
    else          cycle_count <= cycle_count + 1;
  end

  // Test variables
  PHYS_TAG saved_first_tag;
  bit      saved_first_tag_set;
  int      total_tags_seen;

  initial begin
    // defaults
    AllocReqMask         = '0;
    RetireEN             = '0;
    RetireReg            = '{default: '0};
    BPRecoverEN          = 1'b0;
    archi_maptable       = '{default: '0};

    saved_first_tag_set  = 0;
    total_tags_seen      = 0;
    safety               = 0;

    // Reset
    reset_n = 1'b0; repeat (2) @(posedge clock);
    reset_n = 1'b1; @(posedge clock);

    // ===========================
    // 1) Drain the freelist fast
    // ===========================
    $display("== Drain freelist (request exactly what is visible each cycle) ==");
    // While there are tags visible, request K = FreeSlotsForN on the lowest K lanes
    do begin
      @(negedge clock);
        check_visible_unique();

        if (!saved_first_tag_set && FreeSlotsForN > 0) begin
          saved_first_tag     = FreeReg[0];
          saved_first_tag_set = 1;
        end

        total_tags_seen += FreeSlotsForN;

        // Request exactly the visible amount (first K lanes)
        AllocReqMask = ones_mask(FreeSlotsForN);

      @(posedge clock);
      safety = safety + 1;
      expect_ok(safety < 1000, "drain took too long");
    end while (FreeSlotsForN != 0);

    expect_ok(saved_first_tag_set, "never saw any tags to begin with");
    expect_ok(total_tags_seen > 0,  "no tags were granted during drain");

    // ==================================
    // 2) After empty it should be empty
    // ==================================
    $display("== Check empty after drain ==");
    @(negedge clock);
      expect_ok(FreeSlotsForN == 0, "expected FreeSlotsForN=0 after drain");
      AllocReqMask = '0;  // nothing to request
    @(posedge clock);

    // ==================================================
    // 3) Return one tag, then consume exactly one (lane0)
    // ==================================================
    $display("== Return one and re-allocate to lane 0 ==");
    // Push a return this cycle; don't request in the same cycle
    @(negedge clock);
      RetireEN  = '0;
      RetireReg = '{default: '0};
      RetireEN[0]  = 1'b1;
      RetireReg[0] = saved_first_tag;
      AllocReqMask = '0;   // do not consume in same cycle as return
    @(posedge clock);

    // Now request exactly one; it should be the returned tag at FreeReg[0]
    @(negedge clock);
      expect_ok(FreeSlotsForN >= 1, "expected at least 1 tag visible after return");
      expect_ok(FreeReg[0] == saved_first_tag,
        $sformatf("lane0 isn't the returned tag (got %0d exp %0d)", FreeReg[0], saved_first_tag));
      AllocReqMask = ones_mask(1);
      RetireEN     = '0;
    @(posedge clock);

    $display("=== PASS: freelist mask-driven behavior OK ===");
    $display("@@@ Passed");
    $finish;
  end

endmodule

`endif
