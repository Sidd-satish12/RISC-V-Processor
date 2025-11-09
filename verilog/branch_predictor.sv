module branch_predictor #(
  parameter int unsigned GH        = 8,   // number of global history bits
  parameter int unsigned PHT_BITS  = 10,  // PHT entries = 2^PHT_BITS
  parameter int unsigned BTB_BITS  = 8    // BTB entries = 2^BTB_BITS
)(
  input  logic                 clock_i,
  input  logic                 reset_i,

  // ---------- Predict request (Inputs from Instruction Fetch) ----------
  input  logic                 predict_req_valid_i,
  input  logic [31:0]          predict_req_pc_i,
  input  logic                 predict_req_used_i,      // shift GHR if 1

  // ---------- Predict response (Outputs to Instruction Fetch)----------
  output logic                 predict_taken_o,
  output logic [31:0]          predict_target_o,
  output logic [GH-1:0]        predict_ghr_snapshot_o,

  // ---------- Inputs from Execute Stage -----
  input  logic                 train_valid_i,
  input  logic [31:0]          train_pc_i,
  input  logic                 train_actual_taken_i,
  input  logic [31:0]          train_actual_target_i,
  input  logic [GH-1:0]        train_ghr_snapshot_i,

  // ---------- Inputs from Execute Stage -----------------
  input  logic                 recover_mispredict_pulse_i,
  input  logic [GH-1:0]        recover_ghr_snapshot_i
);

  typedef logic [1:0] saturating_counter2_t;

  localparam int unsigned PHT_ENTRY_COUNT  = (1 << PHT_BITS);
  localparam int unsigned BTB_ENTRY_COUNT  = (1 << BTB_BITS);
  localparam int unsigned BTB_TAG_BITS     = 30 - BTB_BITS; // Tag = upper PC bits above index + word-align: 32 - 2 - BTB_BITS
  integer init_idx;

  logic  [GH-1:0]            global_history_reg, global_history_next;
  saturating_counter2_t      pattern_history_table [PHT_ENTRY_COUNT];

  typedef struct packed {
    logic                     entry_valid;
    logic [BTB_TAG_BITS-1:0]  entry_tag;
    logic [31:0]              entry_target;
  } btb_entry_t;

  btb_entry_t                 btb_array [BTB_ENTRY_COUNT];

  // Predict path indices
  wire [PHT_BITS-1:0]        pht_index_predict =
    predict_req_pc_i[2 +: PHT_BITS] ^ global_history_reg[PHT_BITS-1:0];

  wire [BTB_BITS-1:0]        btb_index_predict = predict_req_pc_i[2 +: BTB_BITS];
  wire [BTB_TAG_BITS-1:0]    btb_tag_predict   = predict_req_pc_i[2+BTB_BITS +: BTB_TAG_BITS];

  // Train path indices
  wire [PHT_BITS-1:0]        pht_index_train =
    train_pc_i[2 +: PHT_BITS] ^ train_ghr_snapshot_i[PHT_BITS-1:0];

  wire [BTB_BITS-1:0]        btb_index_train = train_pc_i[2 +: BTB_BITS];
  wire [BTB_TAG_BITS-1:0]    btb_tag_train   = train_pc_i[2+BTB_BITS +: BTB_TAG_BITS];

  // -------------------- Predict (combinational) ----------------
  always_comb begin
    saturating_counter2_t pht_counter_predict_sanitized;
    logic                 btb_hit_predict;
    // Snapshot the precise history used for this prediction
    predict_ghr_snapshot_o = global_history_reg;
    unique case (pattern_history_table[pht_index_predict])
      2'b00, 2'b01, 2'b10, 2'b11: pht_counter_predict_sanitized = pattern_history_table[pht_index_predict];
      default                   : pht_counter_predict_sanitized = 2'b01;
    endcase
    // MSB of counter is the taken bit (10/11 => 1)
    predict_taken_o = predict_req_valid_i ? pht_counter_predict_sanitized[1] : 1'b0;
    // BTB hit requires: req valid, predicted taken, entry valid, tag match
    btb_hit_predict = predict_req_valid_i && predict_taken_o && btb_array[btb_index_predict].entry_valid && (btb_array[btb_index_predict].entry_tag == btb_tag_predict);
    // Provide target only on a definite BTB hit
    predict_target_o = btb_hit_predict ? btb_array[btb_index_predict].entry_target : 32'h0;
  end

  // -------------------- GHR next ---------------
  always_comb begin
    global_history_next = global_history_reg;
    if (predict_req_valid_i && predict_req_used_i) begin
      global_history_next = { global_history_reg[GH-2:0], predict_taken_o };
    end
  end

  // -------------------- Mispredict and Recovery -------
  always_ff @(posedge clock_i) begin
    if (reset_i) begin
      global_history_reg <= '0;
    end else if (recover_mispredict_pulse_i) begin
      global_history_reg <= recover_ghr_snapshot_i;
    end else begin
      global_history_reg <= global_history_next;
    end
  end

  always_ff @(posedge clock_i) begin
    if (reset_i) begin
      // ---------- Initialize: run once after reset ----------
      for (init_idx = 0; init_idx < PHT_ENTRY_COUNT; init_idx++) begin
        pattern_history_table[init_idx] <= 2'b01;
      end
      for (init_idx = 0; init_idx < BTB_ENTRY_COUNT; init_idx++) begin
        btb_array[init_idx].entry_valid  <= 1'b0;
        btb_array[init_idx].entry_tag    <= '0;
        btb_array[init_idx].entry_target <= '0;
      end
    end else if (train_valid_i) begin
      // ---------- Train: runs whenever execute tells us a branch resolved ----------
      saturating_counter2_t pht_counter_train_sanitized;
      unique case (pattern_history_table[pht_index_train])
        2'b00, 2'b01, 2'b10, 2'b11: pht_counter_train_sanitized = pattern_history_table[pht_index_train];
        default                   : pht_counter_train_sanitized = 2'b01;
      endcase
      if (train_actual_taken_i) begin
        pattern_history_table[pht_index_train] <= (pht_counter_train_sanitized == 2'b11) ? pht_counter_train_sanitized : (pht_counter_train_sanitized + 2'b01);
        btb_array[btb_index_train].entry_valid  <= 1'b1;
        btb_array[btb_index_train].entry_tag    <= btb_tag_train;
        btb_array[btb_index_train].entry_target <= train_actual_target_i;
      end else begin
        pattern_history_table[pht_index_train] <= (pht_counter_train_sanitized == 2'b00) ? pht_counter_train_sanitized : (pht_counter_train_sanitized - 2'b01);
      end
    end
  end
endmodule

