// retire.sv
`timescale 1ns/1ps
`include "sys_defs.svh"

module retire #(
  parameter int N          = `N,
  parameter int ARCH_COUNT = 32,
  parameter int PHYS_REGS  = `PHYS_REG_SZ_R10K,
  localparam  int PRW      = (PHYS_REGS <= 2) ? 1 : $clog2(PHYS_REGS)
)(
  input  logic                         clock,
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
    // ---- Decls first (tool-friendly) ----
    logic     recover;
    ROB_ENTRY h;               // oldest head entry (for mispred check)
    ROB_ENTRY e;               // iterator entry for normal retire walk
    logic     mispred_dir, mispred_tgt, mispred;
    int       w;               // loop index

    // defaults
    rob_mispredict  = 1'b0;
    rob_mispred_idx = '0;
    BPRecoverEN     = 1'b0;

    Arch_Retire_EN  = '0;
    Arch_Tnew_in    = '0;
    Arch_Retire_AR  = '0;

    FL_RetireEN     = '0;
    FL_RetireReg    = '0;

    recover         = 1'b0;
    mispred_dir     = 1'b0;
    mispred_tgt     = 1'b0;
    mispred         = 1'b0;
    h               = '0;
    e               = '0;

    // Detect mispredict on the oldest visible head
    if (head_valids[N-1]) begin
      h = head_entries[N-1];
      if (h.branch) begin
        mispred_dir = (h.pred_taken  != h.branch_taken);
        mispred_tgt = (h.branch_taken && (h.pred_target != h.branch_target));
        mispred     = (mispred_dir || mispred_tgt);

        if (mispred) begin
          rob_mispredict  = 1'b1;
          rob_mispred_idx = h.rob_idx;
          BPRecoverEN     = 1'b1;
          recover         = 1'b1;   // block normal retire work this cycle
        end
      end
    end

    // Normal retire path only if no recovery this cycle
    if (!recover) begin
      // Walk oldest→youngest; stop at first incomplete
      for (w = N-1; w >= 0; w--) begin
        if (!head_valids[w]) continue;

        e = head_entries[w];
        if (!e.complete)     break;   // in-order: stop at first incomplete

        // If this instruction writes a dest, update precise map and return Told
        if (e.arch_rd != '0) begin
          Arch_Retire_EN[w] = 1'b1;
          Arch_Retire_AR[w] = e.arch_rd;
          Arch_Tnew_in[w]   = e.phys_rd;
          FL_RetireEN[w]    = 1'b1;
          FL_RetireReg[w]   = e.prev_phys_rd;
        end
        // Branch with no dest retires silently.
      end
    end
  end


endmodule
