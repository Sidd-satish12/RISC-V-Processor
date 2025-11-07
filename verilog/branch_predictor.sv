/////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                             //
//  Modulename :  branch_predictor.sv                                                         //
//                                                                                             //
//  Description :  Single-request GShare predictor with direct-mapped BTB.                      //
//                                                                                             //
//                1. One prediction per cycle for req_pc; index = PC[2 +: PHT_BITS] XOR        //
//                   GHR[PHT_BITS-1:0]; PHT entry is 2-bit counter, MSB = taken.               //
//                2. If predicted TAKEN and BTB valid+tag match, resp_target = BTB target;     //
//                   otherwise resp_target = '0.                                               //
//                3. Outputs resp_ghr_snapshot = GHR before any shift (attach to branch for    //
//                   training/recovery).                                                       //
//                4. On req_fire, speculatively shift GHR <= {GHR[GH-2:0], resp_taken}.         //
//                5. On upd_valid, train PHT (inc/dec with clamp) and update BTB on taken.     //
//                6. On mispred_pulse, restore precise history: GHR <= mispred_ghr_snapshot.   //
//                7. Reset clears GHR and BTB; PHT left uninitialized (warms up with traffic). //
//                8. Parameters: XLEN (PC/target width), GH (GHR bits),                        //
//                   PHT_BITS (log2 PHT entries), BTB_BITS (log2 BTB entries).                 //
//                9. 3-wide tip: predecode bundle, predict earliest control-flow only;         //
//                   on TAKEN, squash younger slots and redirect to resp_target.               //
/////////////////////////////////////////////////////////////////////////////////////////////////


module branch_predictor #(
  parameter int unsigned XLEN      = 32,
  parameter int unsigned GH        = 8,
  parameter int unsigned PHT_BITS  = 10,
  parameter int unsigned BTB_BITS  = 8
)(
  input  logic                 clock,
  input  logic                 reset,

  input  logic                 req_valid,
  input  logic [XLEN-1:0]      req_pc,
  input  logic                 req_fire,

  output logic                 resp_taken,
  output logic [XLEN-1:0]      resp_target,
  output logic [GH-1:0]        resp_ghr_snapshot,

  input  logic                 upd_valid,
  input  logic [XLEN-1:0]      upd_pc,
  input  logic                 upd_actual_taken,
  input  logic [XLEN-1:0]      upd_actual_target,
  input  logic [GH-1:0]        upd_ghr_snapshot,

  input  logic                 mispred_pulse,
  input  logic [GH-1:0]        mispred_ghr_snapshot
);

  typedef logic [1:0] scnt_t;
  localparam int unsigned PHT_ENTRIES = (1 << PHT_BITS);
  localparam int unsigned BTB_ENTRIES = (1 << BTB_BITS);

  // State
  logic [GH-1:0]            ghr_q, ghr_d;
  scnt_t                    pht      [PHT_ENTRIES];    // not reset (trained by traffic)
  logic                     btb_valid[BTB_ENTRIES];
  logic [XLEN-BTB_BITS-2:0] btb_tag  [BTB_ENTRIES];
  logic [XLEN-1:0]          btb_tgt  [BTB_ENTRIES];

  // --------- Combinational index wires (Predict path) ---------
  logic [PHT_BITS-1:0] req_pc_lo;
  logic [PHT_BITS-1:0] req_ghr_lo;
  logic [PHT_BITS-1:0] req_pht_idx;

  logic [BTB_BITS-1:0] req_btb_idx;
  logic [XLEN-BTB_BITS-2:0] req_btb_tag;

  assign req_pc_lo   = req_pc[2 +: PHT_BITS];
  assign req_ghr_lo  = ghr_q[PHT_BITS-1:0];
  assign req_pht_idx = req_pc_lo ^ req_ghr_lo;

  assign req_btb_idx = req_pc[2 +: BTB_BITS];
  assign req_btb_tag = req_pc[2+BTB_BITS +: (XLEN-2-BTB_BITS)];

  // --------- Combinational index wires (Update path) ----------
  logic [PHT_BITS-1:0] upd_pc_lo;
  logic [PHT_BITS-1:0] upd_ghr_lo;
  logic [PHT_BITS-1:0] upd_pht_idx;

  logic [BTB_BITS-1:0] upd_btb_idx;
  logic [XLEN-BTB_BITS-2:0] upd_btb_tag;

  assign upd_pc_lo    = upd_pc[2 +: PHT_BITS];
  assign upd_ghr_lo   = upd_ghr_snapshot[PHT_BITS-1:0];
  assign upd_pht_idx  = upd_pc_lo ^ upd_ghr_lo;

  assign upd_btb_idx  = upd_pc[2 +: BTB_BITS];
  assign upd_btb_tag  = upd_pc[2+BTB_BITS +: (XLEN-2-BTB_BITS)];

  // ----------------- Prediction (combinational) -----------------
  always_comb begin
    resp_taken        = 1'b0;
    resp_target       = '0;
    resp_ghr_snapshot = ghr_q;

    if (req_valid) begin
      scnt_t c = pht[req_pht_idx];
      resp_taken = c[1]; // MSB = taken

      if (resp_taken && btb_valid[req_btb_idx] && (btb_tag[req_btb_idx] == req_btb_tag))
        resp_target = btb_tgt[req_btb_idx];
      else
        resp_target = '0; // "no target/hit"
    end
  end

  // ----------------- GHR update / recovery -----------------
  always_comb begin
    ghr_d = ghr_q;
    if (req_valid && req_fire) begin
      ghr_d = {ghr_q[GH-2:0], resp_taken}; // speculative shift-in
    end
  end

  always_ff @(posedge clock) begin
    if (reset) begin
      ghr_q <= '0;
    end else if (mispred_pulse) begin
      ghr_q <= mispred_ghr_snapshot; // exact restore
    end else begin
      ghr_q <= ghr_d;
    end
  end

  // ----------------- Training (PHT + BTB) -----------------
  integer i;
  always_ff @(posedge clock) begin
    if (reset) begin
      // PHT left uninitialized for synthesis-friendliness (will warm up)
      for (i = 0; i < BTB_ENTRIES; i++) begin
        btb_valid[i] <= 1'b0;
        btb_tag[i]   <= '0;
        btb_tgt[i]   <= '0;
      end
    end else begin
      if (upd_valid) begin
        // 2-bit counter inc/dec with clamp
        scnt_t c = pht[upd_pht_idx];
        if (upd_actual_taken) begin
          pht[upd_pht_idx] <= (c != 2'b11) ? (c + 2'b01) : c;
        end else begin
          pht[upd_pht_idx] <= (c != 2'b00) ? (c - 2'b01) : c;
        end

        // BTB update on taken
        if (upd_actual_taken) begin
          btb_valid[upd_btb_idx] <= 1'b1;
          btb_tag  [upd_btb_idx] <= upd_btb_tag;
          btb_tgt  [upd_btb_idx] <= upd_actual_target;
        end
      end
    end
  end

endmodule
