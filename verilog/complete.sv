// - Only marks ROB entries complete (per-lane).
// - Writes resolved branch_taken/branch_target into the ROB packet.
// - Does NOT detect mispredict or trigger recovery (handled in RETIRE).

`include "sys_defs.svh"

// Local stub so this file is standalone if needed
`ifndef HAS_EX_COMP_PACKAGE
typedef struct packed {
  ROB_IDX     rob_idx;
  logic       branch_valid;
  logic       mispredict;     // ignored by this stage
  logic       branch_taken;
  ADDR        branch_target;
  PHYS_TAG    dest_pr;        // unused here
  DATA        result;         // unused here
} EX_COMP_PACKAGE;
`define HAS_EX_COMP_PACKAGE
`endif

module complete #(
  parameter int N = `N
)(
  input  logic                         clock,
  input  logic                         reset,

  // From EX/COMP pipe reg
  input  logic           ex_valid [N-1:0],
  input  EX_COMP_PACKAGE ex_comp  [N-1:0],

  // To ROB
  output ROB_UPDATE_PACKET              rob_update_packet
);

  // -----------------------------
  // ROB updates: mark complete
  // -----------------------------
  always_comb begin
    rob_update_packet.valid          = '0;
    rob_update_packet.idx            = '0;
    rob_update_packet.values         = '0;  // not used here
    rob_update_packet.branch_taken   = '0;
    rob_update_packet.branch_targets = '0;

    
    for (int i = 0; i < N; i++) begin // Per-lane fan-out (not a dependent loop)
      if (ex_valid[i]) begin
        rob_update_packet.valid[i] = 1'b1;
        rob_update_packet.idx  [i] = ex_comp[i].rob_idx;

        if (ex_comp[i].branch_valid) begin
          rob_update_packet.branch_taken  [i] = ex_comp[i].branch_taken;
          rob_update_packet.branch_targets[i] = ex_comp[i].branch_target;
        end
      end
    end
  end

endmodule
