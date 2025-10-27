`timescale 1ns/100ps
`include "sys_defs.svh"

// -------------------------------------------------------------
// Minimal N-way freelist (mask-driven)
// - Dispatch provides AllocReqMask[N]: which lanes need a tag.
// - Freelist exposes next up to N tags in FreeReg[0..N-1].
//   Dispatch must only consume the first pop_now tags, where
//     pop_now = min(popcount(AllocReqMask), FreeSlotsForN).
// - Retire returns up to N old tags.
// - Optional reseed on mispredict (from Retire) using arch map.
// -------------------------------------------------------------
module freelist #(
  parameter int N            = `N,
  parameter int PR_COUNT     = `PHYS_REG_SZ_R10K,
  parameter int ARCH_COUNT   = 32,
  parameter bit EXCLUDE_ZERO = 1'b1
)(
  input  logic                             clock,
  input  logic                             reset_n,

  // ---- DISPATCH ----
  // Per-lane request mask from Dispatch (aka free_alloc_valid)
  input  logic [N-1:0]                     AllocReqMask,
  // Up to N tags visible (Dispatch MUST only use first pop_now entries)
  output PHYS_TAG [N-1:0]                  FreeReg,
  // Availability info
  output logic [$clog2(PR_COUNT+1)-1:0]    free_count,     // total free
  output logic [$clog2(N+1)-1:0]           FreeSlotsForN,  // min(N, free_count)

  // ---- RETIRE (returns) ----
  input  logic       [N-1:0]               RetireEN,
  input  PHYS_TAG    [N-1:0]               RetireReg,

  // ---- RECOVERY (from Retire on mispredict) ----
  input  logic                             BPRecoverEN,  // 1-cycle pulse
  input  logic [ARCH_COUNT-1:0][(PR_COUNT<=2?1:$clog2(PR_COUNT))-1:0] archi_maptable
);

  // ---- Params / storage ----
  localparam int START_TAG = (EXCLUDE_ZERO ? ((ARCH_COUNT > 0) ? ARCH_COUNT : 1) : ARCH_COUNT);
  localparam int DEPTH     = (PR_COUNT > START_TAG) ? (PR_COUNT - START_TAG) : 0;
  localparam int PTRW      = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

  PHYS_TAG                 queue[(DEPTH>0?DEPTH:1)-1:0];
  logic [PTRW-1:0]         head, tail;
  logic [$clog2(PR_COUNT+1)-1:0] count;  // 0..DEPTH

  // ---- helper ----
  function automatic int popcount(input logic [N-1:0] v);
    int s=0; for (int i=0;i<N;i++) s+=v[i]; return s;
  endfunction

  // ---- Combinational: expose next tags + counters ----
  always_comb begin
    // Counters for external use
    free_count    = count;
    FreeSlotsForN = (count >= N) ? N[$clog2(N+1)-1:0] : count[$clog2(N+1)-1:0];

    // Next up to N tags (Dispatch should only use first pop_now entries)
    for (int i = 0; i < N; i++) begin
      if (DEPTH > 0 && i < FreeSlotsForN)
        FreeReg[i] = queue[(head + i) % DEPTH];
      else
        FreeReg[i] = '0;
    end
  end

  // ---- Sequential: update FIFO on reset / recovery / normal ----
  always_ff @(posedge clock or negedge reset_n) begin
    // Temps declared up-front (tool-friendly)
    logic [PR_COUNT-1:0]             used;
    int unsigned                     w;
    int unsigned                     pushed;
    logic [$clog2(N+1)-1:0]          req_count;
    logic [$clog2(N+1)-1:0]          pop_now;

    if (!reset_n) begin
      head  <= '0;
      tail  <= '0;
      count <= DEPTH[$bits(count)-1:0];
      if (DEPTH > 0) begin
        for (int i=0; i<DEPTH; i++) queue[i] <= PHYS_TAG'(START_TAG + i);
      end

    // Recovery: rebuild freelist from precise map (everything not named)
    end else if (BPRecoverEN) begin
      used = '0;
      if (EXCLUDE_ZERO) used[0] = 1'b1;
      for (int r=0; r<ARCH_COUNT; r++) used[ archi_maptable[r] ] <= 1'b1;

      w = 0;
      if (DEPTH > 0) begin
        for (int p=START_TAG; p<PR_COUNT; p++) begin
          if (!used[p]) begin
            queue[w[PTRW-1:0]] <= PHYS_TAG'(p);
            w++;
            if (w == DEPTH) break;
          end
        end
      end
      head  <= '0;
      tail  <= (DEPTH>0) ? w[PTRW-1:0] : '0;
      count <= w[$bits(count)-1:0];

    // Normal operation
    end else begin
      // 1) Push returns (append in-lane order)
      pushed = 0;
      if (DEPTH > 0) begin
        for (int i=0; i<N; i++) begin
          if (RetireEN[i]) begin
            queue[(tail + pushed) % DEPTH] <= RetireReg[i];
            pushed++;
          end
        end
        tail <= (tail + pushed) % DEPTH;
      end

      // 2) Pop what Dispatch requested (bounded by availability)
      req_count = popcount(AllocReqMask);
      pop_now   = (req_count <= FreeSlotsForN) ? req_count : FreeSlotsForN;

      if (DEPTH > 0) head <= (head + pop_now) % DEPTH;

      // 3) Single count update = pushes - pops
      count <= count + pushed - pop_now;
    end
  end

endmodule
