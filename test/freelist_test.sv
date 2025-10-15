`timescale 1ns/100ps
`ifndef __FREELIST_TEST_SV__
`define __FREELIST_TEST_SV__

`include "sys_defs.svh"

module freelist_test;

  localparam int  N   = `N;
  localparam time TCK = 10ns;
  logic clock, reset_n;
  logic       [N-1:0] DispatchEN;
  logic       [N-1:0] RetireEN;
  PHYS_TAG    [N-1:0] RetireReg;
  PHYS_TAG    [N-1:0] FreeReg;
  logic       [N-1:0] FreeRegValid;

  int unsigned cycle_count;
  integer tb_i, tb_j;
  integer safety;

  function automatic int popcount(input logic [N-1:0] b);
    int s = 0;
    for (int k = 0; k < N; k++) s += (b[k] ? 1 : 0);
    return s;
  endfunction

  task automatic expect_ok(bit cond, string msg);
    if (!cond) begin
      $display("[%0t] FAIL: %s", $time, msg);
      $display("@@@ Failed");
      $fatal(1);
    end
  endtask

  freelist #(.N(N)) dut (
    .clock       (clock),
    .reset_n     (reset_n),
    .DispatchEN  (DispatchEN),
    .RetireEN    (RetireEN),
    .RetireReg   (RetireReg),
    .FreeReg     (FreeReg),
    .FreeRegValid(FreeRegValid)
  );


  initial clock = 1'b0;
  always  #(TCK/2) clock = ~clock;

  always_ff @(posedge clock) begin
    if (!reset_n) cycle_count <= 0;
    else          cycle_count <= cycle_count + 1;
  end

  task automatic check_no_dups_this_cycle();
    for (tb_i = 0; tb_i < N; tb_i = tb_i + 1) begin
      if (FreeRegValid[tb_i]) begin
        expect_ok(^FreeReg[tb_i] !== 1'bx, $sformatf("lane %0d got X tag", tb_i));
        expect_ok(FreeReg[tb_i] != PHYS_TAG'(0), $sformatf("lane %0d got tag 0", tb_i));
        for (tb_j = tb_i + 1; tb_j < N; tb_j = tb_j + 1)
          if (FreeRegValid[tb_j])
            expect_ok(FreeReg[tb_i] != FreeReg[tb_j],
                      $sformatf("duplicate tags same cycle: lane%0d=%0d lane%0d=%0d",
                                tb_i, FreeReg[tb_i], tb_j, FreeReg[tb_j]));
      end
    end
  endtask

  PHYS_TAG saved_first_tag;
  int      total_tags_seen;
  bit      saved_first_tag_set;


  initial begin
    DispatchEN = '0;
    RetireEN   = '0;
    RetireReg  = '{default: PHYS_TAG'(0)};
    saved_first_tag_set = 0;
    total_tags_seen     = 0;
    safety              = 0;

    // reset
    reset_n = 1'b0; repeat (2) @(posedge clock);
    reset_n = 1'b1; @(posedge clock);

    // 1) Drain the freelist
    $display("== Drain freelist (lane0 priority) ==");
    DispatchEN = '1;
    do begin
      @(negedge clock);
      check_no_dups_this_cycle();

      // oldest heads first
      if (!saved_first_tag_set && FreeRegValid[0]) begin
        saved_first_tag     = FreeReg[0];
        saved_first_tag_set = 1;
      end

      total_tags_seen += popcount(FreeRegValid);

      @(posedge clock);
      safety = safety + 1;
      expect_ok(safety < 1000, "drain took too long");
    end while (FreeRegValid != '0);

    expect_ok(saved_first_tag_set, "never saw a first grant on lane 0");
    expect_ok(total_tags_seen > 0,  "no tags were granted during drain");

    // 2) After empty it should stay empty
    $display("== Check empty after drain ==");
    @(negedge clock);
    expect_ok(FreeRegValid == '0, "expected empty after drain");

    // 3) Return one tag and see it granted next cycle to lane 0
    $display("== Return one and re-allocate to lane 0 ==");
    @(posedge clock);
    RetireEN  = '0;
    RetireReg = '{default: PHYS_TAG'(0)};
    if (N > 0) begin
      RetireEN[0]  = 1'b1;
      RetireReg[0] = saved_first_tag;
    end
    DispatchEN = '0;           // no alloc same cycle as return
    @(posedge clock);          // push happens

    DispatchEN = '1;
    @(negedge clock);
    expect_ok(FreeRegValid != '0, "expected a grant after returning one tag");
    expect_ok(FreeReg[0] === saved_first_tag,
              $sformatf("lane 0 didn't get returned tag (got %0d exp %0d)",
                        FreeReg[0], saved_first_tag));
    check_no_dups_this_cycle();
    @(posedge clock);

    $display("=== PASS: freelist oldest-first behavior OK ===");
    $display("@@@ Passed");
    $finish;
  end

endmodule

`endif
