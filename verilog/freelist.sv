`timescale 1ns/100ps
`include "sys_defs.svh"

// -------------------------------------------------------------
// Bitmap-based N-way freelist (order-agnostic)
// - Dispatch provides AllocReqMask[N] (lanes that want a tag).
// - Freelist shows up to N free tags in FreeReg[0..N-1].
//   Dispatch must only consume the first pop_now entries, where
//      pop_now = min( popcount(AllocReqMask), FreeSlotsForN ).
// - Retire returns up to N old tags.
// - BPRecoverEN rebuilds free set = {all PRs} \ {archi_maptable (+zero if excluded)}.
// - No FIFO; no modulo; shallow comb priority scan -> better timing.
// -------------------------------------------------------------
module freelist #(
  parameter int N            = `N,
  parameter int PR_COUNT     = `PHYS_REG_SZ_R10K,
  parameter int ARCH_COUNT   = 32,
  parameter bit EXCLUDE_ZERO = 1'b1
)(
  input  logic                             clock,
  input  logic                             reset_n,

  // ---- DISPATCH (requests & visibility) ----
  input  logic       [N-1:0]               AllocReqMask,  // which dispatch lanes want a tag
  output PHYS_TAG    [N-1:0]               FreeReg,       // up to N free PR indices freelist is offering this cycle
  output logic [$clog2(PR_COUNT+1)-1:0]    free_count,    // total free regs right now
  output logic [$clog2(N+1)-1:0]           FreeSlotsForN, // min(N, free_count)

  // ---- RETIRE (returns) ----
  input  logic       [N-1:0]               RetireEN, // old PRs being returned by retire state
  input  PHYS_TAG    [N-1:0]               RetireReg,

  // ---- RECOVERY ----
  input  logic                             BPRecoverEN,  // 1-cycle pulse to rebuild free set
  input  logic [ARCH_COUNT-1:0][(PR_COUNT<=2?1:$clog2(PR_COUNT))-1:0] archi_maptable
);

  // -----------------------------
  // Storage: 1 bit per phys reg
  // -----------------------------
  logic [PR_COUNT-1:0] free_bm;  // 1=free, 0=used, (says weather a PR is currently free)

  localparam int START_TAG = (EXCLUDE_ZERO ? ((ARCH_COUNT > 0) ? ARCH_COUNT : 1) : ARCH_COUNT);

  // -----------------------------
  // Popcount helper (tool-safe) (Counts how many lanes are asking for a PR)
  // -----------------------------
  function automatic int popcount_n(input logic [N-1:0] v);
    int s=0; for (int i=0;i<N;i++) s+=v[i]; return s;
  endfunction

  // ----------------------------------------
  // Combinational pick: up to N free tags (who could give this cycle)
  // ----------------------------------------
  logic [PR_COUNT-1:0]        scan_bm; // temp copy of free set
  logic [$clog2(PR_COUNT)-1:0] chosen_idx [N-1:0]; // picked PR indices (combinational)
  logic [N-1:0]               chosen_valid; // whether lane i found one
  int                         i, p;

  always_comb begin
    // Start from current free set
    scan_bm      = free_bm;
    chosen_valid = '0;

    // Greedy priority scan (lowest PR first) — order not architectural
    // We walk from low PR to high PR and grab the first N free ones (don't care about the fucking order)
    
    for (i = 0; i < N; i++) begin
      chosen_idx[i] = '0;
      for (p = 0; p < PR_COUNT; p++) begin
        if (scan_bm[p]) begin
          chosen_idx[i]   = p[$clog2(PR_COUNT)-1:0]; // this is what we would give to lane i if that many lanes are allowed to pop
          chosen_valid[i] = 1'b1;
          scan_bm[p]      = 1'b0;  // consume it in this view
          break;
        end
      end
    end

    // Counters for external use
    free_count    = '0;
    for (p = 0; p < PR_COUNT; p++) free_count += free_bm[p];
    FreeSlotsForN = (free_count >= N) ? N[$clog2(N+1)-1:0]
                                      : free_count[$clog2(N+1)-1:0];

    // Drive FreeReg: only first FreeSlotsForN entries are meaningful
    for (i = 0; i < N; i++) begin
      if (i < FreeSlotsForN && chosen_valid[i])
        FreeReg[i] = PHYS_TAG'(chosen_idx[i]);
      else
        FreeReg[i] = '0;
    end
  end

  // pop_now = min(requests this cycle, availability)
  logic [$clog2(N+1)-1:0] req_count, pop_now;
  always_comb begin
    req_count = popcount_n(AllocReqMask);
    pop_now   = (req_count <= FreeSlotsForN) ? req_count : FreeSlotsForN;
  end

  // ----------------------------------------
  // Sequential update of the bitmap
  // ----------------------------------------
  always_ff @(posedge clock or negedge reset_n) begin
    // Declare *all* temps first for VCS
    logic [PR_COUNT-1:0] base;
    logic [PR_COUNT-1:0] used;
    logic [PR_COUNT-1:0] set_mask;
    logic [PR_COUNT-1:0] clr_mask;
    int k, r, p2;

    if (!reset_n) begin
      // Initialize: free = {START_TAG .. PR_COUNT-1}; optionally disallow zero
      free_bm <= '0;
      for (p2 = START_TAG; p2 < PR_COUNT; p2++) free_bm[p2] <= 1'b1;
      if (EXCLUDE_ZERO) free_bm[0] <= 1'b0;

    end else if (BPRecoverEN) begin
      // Rebuild free set = all minus precise architectural image
      base = '0;
      used = '0;
      for (p2 = START_TAG; p2 < PR_COUNT; p2++) base[p2] = 1'b1;
      if (EXCLUDE_ZERO) used[0] = 1'b1;
      for (r = 0; r < ARCH_COUNT; r++) begin
        used[ archi_maptable[r] ] = 1'b1;
      end
      free_bm <= base & ~used;

    end else begin
      // 1) Returns set bits
      set_mask = '0;
      for (k = 0; k < N; k++) begin
        if (RetireEN[k]) set_mask[ int'(RetireReg[k]) ] = 1'b1;
      end

      // 2) Clear only first pop_now chosen this cycle
      clr_mask = '0;
      for (k = 0; k < N; k++) begin
        if (k < pop_now) clr_mask[ chosen_idx[k] ] = 1'b1;
      end

      // 3) Apply: free := (free ∪ returns) \ consumes
      free_bm <= (free_bm | set_mask) & ~clr_mask;

      // 4) Enforce zero exclusion
      if (EXCLUDE_ZERO) free_bm[0] <= 1'b0;
    end
  end

endmodule
