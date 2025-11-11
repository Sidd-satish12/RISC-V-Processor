`include "sys_defs.svh"

module stage_if (
  input  logic                 clock,
  input  logic                 reset,
  output logic                 icache_req_valid_o,
  output ADDR         [`N-1:0] icache_req_addr_o,
  input  logic        [`N-1:0] icache_resp_valid_i,
  input  logic [31:0] [`N-1:0] icache_resp_instr_i,
  output CACHE_DATA   [`N-1:0] cache_out_o,
  output logic                 fetch_stall_o,

  output logic                 bp_predict_req_valid_o,
  output ADDR                  bp_predict_req_pc_o,
  output logic                 bp_predict_req_used_o,
  input  logic                 bp_predict_taken_i,
  input  ADDR                  bp_predict_target_i,

  input  logic                 ex_redirect_valid_i,  
  input  ADDR                  ex_redirect_pc_i,      

  // -------- Global fetch enable (freeze whole IF) ----------------
  input  logic                 fetch_enable_i
);

  // -------------------- PC state (owned by IF) --------------------
  ADDR pc_reg, pc_next;

  // Convenience: compute the N PCs we’ll request this cycle
  ADDR bundle_pc[`N];
  always_comb begin
    bundle_pc[0] = pc_reg;
    // straight-line: each instruction is 4 bytes
    if (`N > 1) bundle_pc[1] = pc_reg + 32'd4;
    if (`N > 2) bundle_pc[2] = pc_reg + 32'd8;
    // (extend similarly if N > 3)
  end

  // Drive ICache request whenever fetch is enabled
  always_comb begin
    icache_req_valid_o = fetch_enable_i;
    icache_req_addr_o  = bundle_pc;
  end

  // Stall if ANY lane isn’t ready
  wire all_lanes_ready = &icache_resp_valid_i;
  assign fetch_stall_o = ~all_lanes_ready;

  // Pack outputs to Decode
  always_comb begin
    foreach (cache_out_o[i]) begin
      cache_out_o[i].valid = icache_resp_valid_i[i];
      cache_out_o[i].pc    = bundle_pc[i];
      cache_out_o[i].instr = icache_resp_instr_i[i];
    end
  end

  // ---------------- Branch Predictor request ----------------
  // Query BP with the *first* PC in the bundle (lane 0).
  // Mark “used” only if we’re actually consuming the bundle this cycle.
  always_comb begin
    bp_predict_req_valid_o = fetch_enable_i;
    bp_predict_req_pc_o    = bundle_pc[0];
    bp_predict_req_used_o  = fetch_enable_i & ~fetch_stall_o;
  end

  // ---------------- Next-PC selection (priority mux) -------------
  // Priority each cycle:
  // 1) Redirect from Execute (actual mispredict fix)
  // 2) Use BP target if predicted taken AND we’re consuming this fetch
  // 3) Sequential: pc + 4*N (consume straight-line bundle)
  always_comb begin
    pc_next = pc_reg;  // hold by default

    if (fetch_enable_i) begin
      if (ex_redirect_valid_i) begin
        pc_next = ex_redirect_pc_i;                         // (1) redirect
      end else if ((~fetch_stall_o) && bp_predict_taken_i) begin
        pc_next = bp_predict_target_i;                      // (2) predicted-taken redirect
      end else if (~fetch_stall_o) begin
        pc_next = pc_reg + (32'(4 * `N));                   // (3) sequential advance
      end
      // else: stall => hold pc_next = pc_reg
    end
  end

  // ---------------- PC register ----------------
  always_ff @(posedge clock) begin
    if (reset) begin
      pc_reg <= '0;            // your reset fetch address
    end else begin
      pc_reg <= pc_next;
    end
  end

endmodule
