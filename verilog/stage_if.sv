`include "sys_defs.svh"

module stage_if #(
  parameter int unsigned GH = GHR_BITS  
)(
  input  logic                 clock,
  input  logic                 reset,
  output ADDR                  icache_read_addr_o [`N-1:0],
  input  CACHE_DATA            icache_cache_out_i [`N-1:0],
  input  logic                 ib_stall_i,         
  output logic                 ib_bundle_valid_o,  
  output FETCH_ENTRY           ib_fetch_o        [`N-1:0], 
  output logic                 bp_predict_req_valid_o,
  output ADDR                  bp_predict_req_pc_o,
  output logic                 bp_predict_req_used_o,
  input  logic                 bp_predict_taken_i,
  input  ADDR                  bp_predict_target_i,
  input  logic [GH-1:0]        bp_predict_ghr_snapshot_i,
  input  logic                 ex_redirect_valid_i,
  input  ADDR                  ex_redirect_pc_i,
  input  logic                 fetch_enable_i,
  output logic                 fetch_stall_o
);

  ADDR pc_reg, pc_next;
  ADDR bundle_pc [`N-1:0];
  logic        lane_valid     [`N-1:0];
  logic [31:0] lane_instr     [`N-1:0];
  logic        lane_is_branch [`N-1:0];
  logic        found_branch;
  int          first_branch_idx;
  logic        all_lanes_ready;
  logic        icache_stall_if;
  logic        ibuf_stall_if;
  logic        fetch_blocked_if;

  function automatic logic is_predictable_branch(input logic [31:0] instr);
    logic [6:0] opcode;
    opcode = instr[6:0];
    return (opcode == 7'b1100011);
  endfunction
  always_comb begin
    for (int i = 0; i < `N; i++) begin
      bundle_pc[i] = pc_reg + (ADDR'(i) << 2);  // pc + 4*i
    end
  end
  always_comb begin
    for (int i = 0; i < `N; i++) begin
      icache_read_addr_o[i] = bundle_pc[i];
    end
  end
  always_comb begin
    for (int i = 0; i < `N; i++) begin
      lane_valid[i] = icache_cache_out_i[i].valid;
      lane_instr[i] = icache_cache_out_i[i].cache_line[31:0];
    end
  end
  always_comb begin
    all_lanes_ready = 1'b1;
    for (int i = 0; i < `N; i++) begin
      if (!lane_valid[i]) begin
        all_lanes_ready = 1'b0;
      end
    end
  end
  assign icache_stall_if  = ~all_lanes_ready;
  assign ibuf_stall_if    = ib_stall_i;
  assign fetch_blocked_if = icache_stall_if | ibuf_stall_if;
  assign fetch_stall_o    = fetch_blocked_if;
  always_comb begin
    for (int i = 0; i < `N; i++) begin
      lane_is_branch[i] = lane_valid[i] && is_predictable_branch(lane_instr[i]);
    end
    found_branch     = 1'b0;
    first_branch_idx = 0;
    for (int i = 0; i < `N; i++) begin
      if (!found_branch && lane_is_branch[i]) begin
        found_branch     = 1'b1;
        first_branch_idx = i;
      end
    end
  end
  always_comb begin
    bp_predict_req_valid_o = fetch_enable_i && found_branch;
    bp_predict_req_pc_o    = found_branch ? bundle_pc[first_branch_idx] : '0;
    bp_predict_req_used_o  = fetch_enable_i && ~fetch_blocked_if && ~ex_redirect_valid_i && found_branch;
  end
  always_comb begin
    ib_bundle_valid_o = fetch_enable_i  && all_lanes_ready  && ~ib_stall_i  && ~ex_redirect_valid_i;
    for (int i = 0; i < `N; i++) begin
      ib_fetch_o[i].pc              = bundle_pc[i];
      ib_fetch_o[i].inst            = lane_instr[i];

      ib_fetch_o[i].is_branch       = 1'b0;
      ib_fetch_o[i].bp_pred_taken   = 1'b0;
      ib_fetch_o[i].bp_pred_target  = '0;
      ib_fetch_o[i].bp_ghr_snapshot = '0;
    end
    if (ib_bundle_valid_o && found_branch) begin
      ib_fetch_o[first_branch_idx].is_branch       = 1'b1;
      ib_fetch_o[first_branch_idx].bp_pred_taken   = bp_predict_taken_i;
      ib_fetch_o[first_branch_idx].bp_pred_target  = bp_predict_target_i;
      ib_fetch_o[first_branch_idx].bp_ghr_snapshot = bp_predict_ghr_snapshot_i;
    end
  end
  always_comb begin
    pc_next = pc_reg;

    if (fetch_enable_i) begin
      if (ex_redirect_valid_i) begin
        pc_next = ex_redirect_pc_i;
      end else if (~fetch_blocked_if && found_branch && bp_predict_taken_i) begin
        pc_next = bp_predict_target_i;
      end else if (~fetch_blocked_if) begin
        pc_next = pc_reg + (ADDR'(`N) << 2);
      end
    end
  end
  always_ff @(posedge clock) begin
    if (reset) begin
      pc_reg <= '0;  
    end else begin
      pc_reg <= pc_next;
    end
  end

endmodule
