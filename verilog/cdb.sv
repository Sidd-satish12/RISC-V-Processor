// Pipeline sketch:
//   A) choose winners this cycle (combinational)
//   B) register winners + FU outputs (K -> K+1)
//   C) build per-lane (valid, tag, data) (combinational, using registered winners)
//   D) register and send the broadcast (K+1 outputs)

`include "sys_defs.svh"

// Simple packet for RS wakeup (tags + valids for N lanes).
`ifndef HAS_CDB_PACKET
typedef struct packed {
  logic    [`N-1:0]        valid;  // one bit per lane
  PHYS_TAG [`N-1:0]        tags;   // one tag per lane
} CDB_PACKET;
`define HAS_CDB_PACKET
`endif

module cdb #(
  // N = how many results we can broadcast in parallel this cycle.
  parameter int N      = `N,
  // NUM_FU = how many producers can request the CDB in a cycle.
  parameter int NUM_FU = `NUM_FU_ALU + `NUM_FU_MULT
)(
  input  logic                    clock,
  input  logic                    reset,

  // ---- Requests from Execute (arrive in cycle K) ----
  // fu_done_valid[i]   = FU i has a result ready to publish.
  // fu_done_tag[i]     = destination physical register tag for that result.
  // fu_done_data[i]    = actual computed value from FU i.
  input  logic     [NUM_FU-1:0]   fu_done_valid,
  input  PHYS_TAG  [NUM_FU-1:0]   fu_done_tag,
  input  DATA      [NUM_FU-1:0]   fu_done_data,

  // ---- Feedback to Execute (visible in cycle K+1) ----
  // ex_grant_mask[i]   = FU i got a slot on the CDB this time.
  // ex_grant_count     = total number of grants this cycle (0..N).
  output logic     [NUM_FU-1:0]   ex_grant_mask,
  output logic [$clog2(N+1)-1:0]  ex_grant_count,

  // ---- Broadcast outputs (visible in cycle K+1) ----
  // Tags/valids for RS and Map Table (same info, different bundling).
  output CDB_PACKET               cdb_to_rs,
  output logic     [N-1:0]        cdb_valid_to_mt,
  output PHYS_TAG  [N-1:0]        cdb_tag_to_mt,

  // Convenience mirrors (same timing as above) plus the data payload.
  output logic     [N-1:0]        cdb_valid,   // lane valids
  output PHYS_TAG  [N-1:0]        cdb_tag,     // lane tags
  output DATA      [N-1:0]        cdb_data     // lane data
);

// A) Arbitration: pick up to N winners (one per lane)

  // arb_grant_by_lane_comb[lane][fu] = 1 if FU "fu" wins lane "lane" this cycle.
  // Each "row" (a lane) should be one-hot or all-zero.
  logic [N-1:0][NUM_FU-1:0] arb_grant_by_lane_comb;

  // psel_gen looks at fu_done_valid and returns N one-hot rows for the winners.
  psel_gen #(
    .WIDTH(NUM_FU),
    .REQS (N)
  ) cdb_arbiter (
    .req     (fu_done_valid),
    .gnt     (),                       // single-winner output not used here
    .gnt_bus (arb_grant_by_lane_comb), // N rows, each one-hot among NUM_FU
    .empty   ()
  );

  // fu_grant_mask_comb[fu] = OR across all lanes. True if FU "fu" got any lane.
  logic [NUM_FU-1:0] fu_grant_mask_comb;
  always_comb begin
    fu_grant_mask_comb = '0;
    for (int fu = 0; fu < NUM_FU; fu++) begin
      for (int lane = 0; lane < N; lane++) begin
        fu_grant_mask_comb[fu] |= arb_grant_by_lane_comb[lane][fu];
      end
    end
  end

// B) Register winners + FU outputs (K -> K+1)

  // Registered copies for the next stage:
  // - arb_grant_by_lane_reg : chosen winners per lane (one-hot rows)
  // - fu_grant_mask_reg     : per-FU "I won" bits for feedback
  // - fu_done_tag_reg/data  : tags/data lined up with the registered grants
  logic   [N-1:0][NUM_FU-1:0] arb_grant_by_lane_reg;
  logic   [NUM_FU-1:0]        fu_grant_mask_reg;
  PHYS_TAG[NUM_FU-1:0]        fu_done_tag_reg;
  DATA    [NUM_FU-1:0]        fu_done_data_reg;

  always_ff @(posedge clock) begin
    if (reset) begin
      arb_grant_by_lane_reg <= '0;
      fu_grant_mask_reg     <= '0;
      for (int fu = 0; fu < NUM_FU; fu++) begin
        fu_done_tag_reg [fu] <= '0;
        fu_done_data_reg[fu] <= '0;
      end
    end else begin
      arb_grant_by_lane_reg <= arb_grant_by_lane_comb;
      fu_grant_mask_reg     <= fu_grant_mask_comb;
      for (int fu = 0; fu < NUM_FU; fu++) begin
        fu_done_tag_reg [fu] <= fu_done_tag [fu];
        fu_done_data_reg[fu] <= fu_done_data[fu];
      end
    end
  end

  // Feedback to Execute uses the registered mask (K+1 view).
  assign ex_grant_mask  = fu_grant_mask_reg;
  assign ex_grant_count = $countones(fu_grant_mask_reg);

// C) Build per-lane bundles (COMB) using registered winners

  // For each lane, compute:
  //   - cdb_lane_valid_comb[lane] : did this lane pick anyone?
  //   - cdb_lane_tag_comb[lane]   : selected FU's tag
  //   - cdb_lane_data_comb[lane]  : selected FU's data
  logic    [N-1:0]   cdb_lane_valid_comb;
  PHYS_TAG [N-1:0]   cdb_lane_tag_comb;
  DATA     [N-1:0]   cdb_lane_data_comb;

  always_comb begin
    for (int lane = 0; lane < N; lane++) begin
      cdb_lane_valid_comb[lane] = 1'b0;
      cdb_lane_tag_comb  [lane] = '0;
      cdb_lane_data_comb [lane] = '0;

      // Lane is valid if any FU was granted in this row.
      for (int fu = 0; fu < NUM_FU; fu++) begin
        cdb_lane_valid_comb[lane] |= arb_grant_by_lane_reg[lane][fu];
      end

      // One-hot select tag/data for this lane.
      for (int fu = 0; fu < NUM_FU; fu++) begin
        if (arb_grant_by_lane_reg[lane][fu]) begin
          cdb_lane_tag_comb [lane] = fu_done_tag_reg [fu];
          cdb_lane_data_comb[lane] = fu_done_data_reg[fu];
        end
      end
    end
  end

// D) Register and drive the broadcast (K+1 outputs)

  always_ff @(posedge clock) begin
    if (reset) begin
      // Clear all outputs on reset.
      cdb_to_rs.valid <= '0;
      cdb_valid_to_mt <= '0;
      cdb_valid       <= '0;
      for (int lane = 0; lane < N; lane++) begin
        cdb_to_rs.tags[lane] <= '0;
        cdb_tag_to_mt [lane] <= '0;
        cdb_tag      [lane]  <= '0;
        cdb_data     [lane]  <= '0;
      end
    end else begin
      // Tags/valids to RS + MapTable.
      cdb_to_rs.valid <= cdb_lane_valid_comb;
      cdb_valid_to_mt <= cdb_lane_valid_comb;

      // Mirrors and data payload per lane.
      cdb_valid <= cdb_lane_valid_comb;
      for (int lane = 0; lane < N; lane++) begin
        cdb_to_rs.tags[lane] <= cdb_lane_tag_comb [lane];
        cdb_tag_to_mt [lane] <= cdb_lane_tag_comb [lane];
        cdb_tag      [lane]  <= cdb_lane_tag_comb [lane];
        cdb_data     [lane]  <= cdb_lane_data_comb[lane];
      end
    end
  end

endmodule
