`timescale 1ns/1ps
`include "sys_defs.svh"

module stage_if_test;

  logic clock;
  logic reset;

  localparam int N = `N;

  // ------------- DUT I/O -------------

  // iCache side
  ADDR       [N-1:0] icache_read_addr_o;
  CACHE_DATA [N-1:0] icache_cache_out_i;

  // Instruction buffer side
  logic        ib_stall_i;
  logic        ib_bundle_valid_o;
  FETCH_ENTRY [N-1:0] ib_fetch_o;

  // Branch predictor side
  BP_PREDICT_REQUEST bp_predict_req_o;
  BP_PREDICT_RESPONSE bp_predict_resp_i;

  // Redirect / control
  logic      ex_redirect_valid_i;
  ADDR       ex_redirect_pc_i;
  logic      fetch_enable_i;
  logic      fetch_stall_o;

  ADDR      pc_debug_o;

  // ------------- DUT INSTANCE -------------

  // NOTE: We connect array ports via concatenation of elements so
  // synthesis doesn't see a "memory" as the port expression.
  // This assumes N == 3; if N changes, update the concatenations.
  stage_fetch dut (
    .clock                    (clock),
    .reset                    (reset),

    // iCache
    .icache_read_addr_o       (icache_read_addr_o),
    .icache_cache_out_i       (icache_cache_out_i),

    // Instruction buffer
    .ib_stall_i               (ib_stall_i),
    .ib_bundle_valid_o        (ib_bundle_valid_o),
    .ib_fetch_o               (ib_fetch_o),

    // Branch predictor
    .bp_predict_req_o   (bp_predict_req_o),
    .bp_predict_resp_i  (bp_predict_resp_i),

    // Redirect / control
    .ex_redirect_valid_i      (ex_redirect_valid_i),
    .ex_redirect_pc_i         (ex_redirect_pc_i),
    .fetch_enable_i           (fetch_enable_i),
    .fetch_stall_o            (fetch_stall_o),

    // debug
    .pc_dbg_o                 (pc_debug_o)
  );

  // ------------- Clock -------------

  initial clock = 1'b0;
  always #5 clock = ~clock;

  // ------------- Handy encodings -------------

  localparam logic [31:0] INSTR_ADDI = 32'h00000013; // non-branch
  localparam logic [31:0] INSTR_BEQ  = 32'h00000063; // branch (opcode 1100011)

  // One-cycle step
  task automatic step;
    begin
      @(posedge clock);
      #1;
    end
  endtask

  // ------------- Test sequence -------------

  initial begin
    // Default init
    for (int i = 0; i < N; i++) begin
      icache_cache_out_i[i].valid      = 1'b0;
      icache_cache_out_i[i].cache_line = '0;
    end

    ib_stall_i               = 1'b0;

    bp_predict_resp_i.taken        = 1'b0;
    bp_predict_resp_i.target       = '0;
    bp_predict_resp_i.ghr_snapshot = 8'hA5;  // arbitrary snapshot

    ex_redirect_valid_i      = 1'b0;
    ex_redirect_pc_i         = '0;

    fetch_enable_i           = 1'b0;

    // Reset
    reset = 1'b1;
    step();
    step();
    reset = 1'b0;

    // ---- T0: After reset ----
    $display("\n---- T0: After reset ----");
    fetch_enable_i = 1'b1;

    // No valid data from iCache yet, but we should see PC=0 on addr[0]
    step();

    assert(icache_read_addr_o[0] == '0)
      else $fatal("T0: icache_read_addr_o[0] should be 0 after reset, got %h",
                  icache_read_addr_o[0]);

    // ---- T1: Bundle with no branches ----
    $display("\n---- T1: Bundle with no branches ----");
    for (int i = 0; i < N; i++) begin
      icache_cache_out_i[i].valid      = 1'b1;
      icache_cache_out_i[i].cache_line = '0;
      icache_cache_out_i[i].cache_line[31:0] = INSTR_ADDI;
    end
    bp_predict_resp_i.taken = 1'b0;

    step();

    assert(fetch_stall_o == 1'b0)
      else $fatal("T1: fetch_stall_o should be 0 when all lanes are valid and IB not stalled");

    assert(bp_predict_req_o.valid == 1'b0)
      else $fatal("T1: bp_predict_req_o.valid should be 0 when bundle has no branches");

    assert(ib_bundle_valid_o == 1'b1)
      else $fatal("T1: ib_bundle_valid_o should be 1 when IF produces a straight-line bundle");

    // Optionally, check that ib_fetch_o[*].inst and .pc look sane
    for (int i = 0; i < N; i++) begin
      assert(ib_fetch_o[i].inst == INSTR_ADDI)
        else $fatal("T1: ib_fetch_o[%0d].inst mismatch, got %h", i, ib_fetch_o[i].inst);
    end

    // ---- T2: Branch in lane 0 ----
    $display("\n---- T2: Branch in lane 0 ----");
    for (int i = 0; i < N; i++) begin
      icache_cache_out_i[i].valid      = 1'b1;
      icache_cache_out_i[i].cache_line = '0;
      icache_cache_out_i[i].cache_line[31:0] =
        (i == 0) ? INSTR_BEQ : INSTR_ADDI;
    end
    bp_predict_resp_i.taken = 1'b0;

    step();

    assert(bp_predict_req_o.valid == 1'b1)
      else $fatal("T2: bp_predict_req_o.valid should be 1 when lane 0 is a branch");

    // BP should be predicting the PC of lane 0 this cycle
    assert(bp_predict_req_o.pc == icache_read_addr_o[0])
      else $fatal("T2: BP PC should equal lane0 PC (%h), got %h",
                  icache_read_addr_o[0], bp_predict_req_o.pc);

    // ---- T3: Branch in lane 1 ----
    $display("\n---- T3: Branch in lane 1 ----");
    for (int i = 0; i < N; i++) begin
      icache_cache_out_i[i].valid      = 1'b1;
      icache_cache_out_i[i].cache_line = '0;
      icache_cache_out_i[i].cache_line[31:0] =
        (i == 1) ? INSTR_BEQ : INSTR_ADDI;
    end
    bp_predict_resp_i.taken = 1'b0;

    step();

    assert(bp_predict_req_o.valid == 1'b1)
      else $fatal("T3: bp_predict_req_o.valid should be 1 when lane 1 is the first branch");

    // BP should be predicting the PC of lane 1 this cycle
    assert(bp_predict_req_o.pc == icache_read_addr_o[1])
      else $fatal("T3: BP PC should equal lane1 PC (%h), got %h",
                  icache_read_addr_o[1], bp_predict_req_o.pc);

    // ---- T4: Redirect overrides and cancels use ----
    $display("\n---- T4: Redirect overrides and cancels use ----");
    for (int i = 0; i < N; i++) begin
      icache_cache_out_i[i].valid      = 1'b1;
      icache_cache_out_i[i].cache_line = '0;
      icache_cache_out_i[i].cache_line[31:0] =
        (i == 0) ? INSTR_BEQ : INSTR_ADDI;
    end

    // Don't care about branch target here; we just want to see redirect win.
    // (This avoids 0x8000 vs 0x1234 fights.)
    bp_predict_resp_i.taken   = 1'b1;
    bp_predict_resp_i.target  = 32'h0000_8000;

    ex_redirect_valid_i  = 1'b1;
    ex_redirect_pc_i     = 32'h0000_1234;

    step();  // cycle where redirect should be applied to pc_reg
    step();

    // Check PC register directly
    assert(icache_read_addr_o[0] == ex_redirect_pc_i)
      else $fatal("T4: PC should follow redirect PC %h, got %h",
                  ex_redirect_pc_i, icache_read_addr_o[0]);

    // Prediction must not be considered "used" on the redirect cycle
    assert(bp_predict_req_o.used == 1'b0)
      else $fatal("T4: bp_predict_req_used_o should be 0 when ex_redirect_valid_i=1");

    $display("\nAll simple stage_fetch tests completed.\n");
    $finish;
  end

endmodule
