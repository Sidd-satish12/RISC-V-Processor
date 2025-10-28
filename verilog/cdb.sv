// cdb.sv — tags-only CDB, width = N, 1-cycle delayed broadcast.
// A: psel_gen arbitration (comb)
// B: register grants & FU inputs
// C: per-lane one-hot mux (comb)
// D: register broadcast
`include "sys_defs.svh"

`ifndef HAS_CDB_PACKET
typedef struct packed {
  logic    [`N-1:0]        valid;  // N lanes
  PHYS_TAG [`N-1:0]        tags;
} CDB_PACKET;
`define HAS_CDB_PACKET
`endif

module cdb #(
  parameter int N      = `N,                                  // CDB width
  parameter int NUM_FU = `NUM_FU_ALU + `NUM_FU_MULT           // FU request lanes
)(
  input  logic                    clock,
  input  logic                    reset,

  // From Execute (Cycle K): one bit/tag per FU that finished this cycle
  input  logic     [NUM_FU-1:0]   fu_req_valid,
  input  PHYS_TAG  [NUM_FU-1:0]   fu_req_tag,

  // Back to Execute (registered, Cycle K+1): who won + count
  output logic     [NUM_FU-1:0]   ex_grant_mask_q,
  output logic [$clog2(N+1)-1:0]  ex_grant_count_q,

  // Broadcast (registered, Cycle K+1): to RS and MapTable
  output CDB_PACKET               cdb_to_rs,
  output logic     [N-1:0]        cdb_valid_to_mt,
  output PHYS_TAG  [N-1:0]        cdb_tag_to_mt
);

  // ---------------- A) Arbitration (COMB) ----------------
  // psel_gen picks up to N one-hot winners (one row per CDB lane).
  logic [N-1:0][NUM_FU-1:0] grants_by_lane;   // each row is one-hot over FU lanes

  psel_gen #(
    .WIDTH(NUM_FU),
    .REQS (N)
  ) cdb_arbiter (
    .req     (fu_req_valid),
    .gnt     (),               // unused single grant
    .gnt_bus (grants_by_lane), // N one-hot winners
    .empty   ()
  );

  // Per-FU winner mask (OR of all rows) — purely combinational
  logic [NUM_FU-1:0] grant_mask_comb;
  always_comb begin
    grant_mask_comb = '0;
    for (int fu = 0; fu < NUM_FU; fu++) begin
      for (int lane = 0; lane < N; lane++) begin
        grant_mask_comb[fu] |= grants_by_lane[lane][fu];
      end
    end
  end

  // ---------------- B) Align to next cycle (REG) ----------------
  logic [N-1:0][NUM_FU-1:0] grants_by_lane_q;
  logic [NUM_FU-1:0]        grant_mask_q;
  PHYS_TAG [NUM_FU-1:0]     fu_req_tag_q;

  always_ff @(posedge clock) begin
    if (reset) begin
      grants_by_lane_q <= '0;
      grant_mask_q     <= '0;
      for (int fu = 0; fu < NUM_FU; fu++) fu_req_tag_q[fu] <= '0;
    end else begin
      grants_by_lane_q <= grants_by_lane;
      grant_mask_q     <= grant_mask_comb;
      for (int fu = 0; fu < NUM_FU; fu++) fu_req_tag_q[fu] <= fu_req_tag[fu];
    end
  end

  assign ex_grant_mask_q  = grant_mask_q;
  assign ex_grant_count_q = $countones(grant_mask_q);

  // ---------------- C) Pack per-lane (COMB) ----------------
  // For each CDB lane, one-hot mux the FU tag that won in that lane.
  logic    [N-1:0]   lane_valid_comb;
  PHYS_TAG [N-1:0]   lane_tag_comb;

  always_comb begin
    for (int lane = 0; lane < N; lane++) begin
      lane_valid_comb[lane] = 1'b0;
      lane_tag_comb  [lane] = '0;

      // row OR for valid
      for (int fu = 0; fu < NUM_FU; fu++) begin
        lane_valid_comb[lane] |= grants_by_lane_q[lane][fu];
      end
      // one-hot mux for tag
      for (int fu = 0; fu < NUM_FU; fu++) begin
        if (grants_by_lane_q[lane][fu]) lane_tag_comb[lane] = fu_req_tag_q[fu];
      end
    end
  end

  // ---------------- D) CDB register (REG) ----------------
  always_ff @(posedge clock) begin
    if (reset) begin
      cdb_to_rs.valid <= '0;
      cdb_valid_to_mt <= '0;
      for (int lane = 0; lane < N; lane++) begin
        cdb_to_rs.tags[lane] <= '0;
        cdb_tag_to_mt [lane] <= '0;
      end
    end else begin
      cdb_to_rs.valid <= lane_valid_comb;
      cdb_valid_to_mt <= lane_valid_comb;
      for (int lane = 0; lane < N; lane++) begin
        cdb_to_rs.tags[lane] <= lane_tag_comb[lane];
        cdb_tag_to_mt [lane] <= lane_tag_comb[lane];
      end
    end
  end

endmodule
