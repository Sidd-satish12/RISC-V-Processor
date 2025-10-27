// retire.sv
`timescale 1ns/1ps
`include "sys_defs.svh"

module retire #(
  parameter int N          = `N,
  parameter int ARCH_COUNT = 32,
  parameter int PHYS_REGS  = `PHYS_REG_SZ_R10K,
  localparam  int PRW      = (PHYS_REGS <= 2) ? 1 : $clog2(PHYS_REGS)
)(
  input  logic             2            clock,
  input  logic                         reset,

  // From ROB: head window (N-1 = oldest, 0 = youngest)
  input  ROB_ENTRY       [N-1:0]       head_entries,
  input  logic           [N-1:0]       head_valids,

  // To ROB: flush younger if head is a mispredicted branch
  output logic                         rob_mispredict,
  output ROB_IDX                       rob_mispred_idx,

  // To map_table: copy precise→spec on recovery
  output logic                         BPRecoverEN,

  // To arch_maptable: in-order commits (N-1 oldest)
  output logic          [N-1:0]        Arch_Retire_EN,
  output logic [N-1:0][PRW-1:0]        Arch_Tnew_in,
  output logic [N-1:0][$clog2(ARCH_COUNT)-1:0] Arch_Retire_AR,

  // To freelist: normal returns (skip on recovery)
  output logic          [N-1:0]        FL_RetireEN,
  output logic [N-1:0][PRW-1:0]        FL_RetireReg,

  // Precise map image (freelist may use it when reseeding at recovery)
  input  logic [ARCH_COUNT-1:0][PRW-1:0] archi_maptable
);

  // -------------------------------
  // Combinational retire / recovery
  // -------------------------------
  always_comb begin
    // defaults
    rob_mispredict  = 1'b0;
    rob_mispred_idx = '0;
    BPRecoverEN     = 1'b0;

    Arch_Retire_EN  = '0;
    Arch_Tnew_in    = '0;
    Arch_Retire_AR  = '0;

    FL_RetireEN     = '0;
    FL_RetireReg    = '0;

    // 1) Check the oldest entry (head) for mispredict
    if (head_valids[N-1]) begin
      ROB_ENTRY h = head_entries[N-1];

      if (h.branch) begin
        // mismatch if direction differs OR (taken && target differs)
        logic mispred_dir = (h.pred_taken  != h.branch_taken);
        logic mispred_tgt = (h.branch_taken && (h.pred_target != h.branch_target));
        logic mispred     = (mispred_dir || mispred_tgt);

        if (mispred) begin
          rob_mispredict  = 1'b1;
          rob_mispred_idx = h.rob_idx;
          BPRecoverEN     = 1'b1;

          // On recovery cycle: do not return Told or update precise map here.
          // Freelist should reseed from archi_maptable at BPRecoverEN (in its own module).
          // Stop here.
          return;
        end
      end
    end

    // 2) Normal retire path (no mispredict at head)
    //    Walk oldest→youngest; stop at first incomplete.
    for (int w = N-1; w >= 0; w--) begin
      if (!head_valids[w])   continue;

      ROB_ENTRY e = head_entries[w];
      if (!e.complete)       break;    // in-order: stop

      // If this instruction writes a dest, update precise map and return Told
      if (e.has_dest) begin
        Arch_Retire_EN[w]   = 1'b1;
        Arch_Retire_AR[w]   = e.dest_ar;
        Arch_Tnew_in[w]     = e.Tnew;

        if (e.dest_ar != '0) begin
          FL_RetireEN[w]    = 1'b1;
          FL_RetireReg[w]   = e.Told;
        end
      end
      // If it's a branch with no dest, just retires silently.
    end
  end

endmodule