/////////////////////////////////////////////////////////////////////////
//                                                                     //
//  Modulename :  bp.sv                                                //
//                                                                     //
//  Description :  Branch Predictor module; implements a hybrid       //
//                 gshare + BTB predictor with global history.        //
//                 Handles prediction requests from fetch, training   //
//                 from retire, and mispredict recovery.              //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

module bp (
    input logic clock,
    input logic reset,

    // ---------- Predict request (Inputs from Instruction Fetch) ----------
    input BP_PREDICT_REQUEST predict_req_i,

    // ---------- Predict response (Outputs to Instruction Fetch)----------
    output BP_PREDICT_RESPONSE predict_resp_o,

    // ---------- Training request (Inputs from Rob/Retire Stage) -----
    input BP_TRAIN_REQUEST train_req_i,

    // ---------- Recovery request (Inputs from Rob/Retire Stage) -----------------
    input BP_RECOVER_REQUEST recover_req_i
);

    // Local parameters derived from macros
    localparam int unsigned PHT_ENTRY_COUNT = (1 << `BP_PHT_BITS);
    localparam int unsigned BTB_ENTRY_COUNT = (1 << `BP_BTB_BITS);

    // Parameter constraints
    initial begin
        assert (`BP_GH <= `BP_PHT_BITS)
        else $fatal("Global history bits (GH=%0d) must be <= PHT index bits (PHT_BITS=%0d)", `BP_GH, `BP_PHT_BITS);
    end

    // Internal storage
    logic [`BP_GH-1:0] global_history_reg, global_history_next;
    BP_COUNTER_STATE pattern_history_table[PHT_ENTRY_COUNT];
    BP_BTB_ENTRY     btb_array            [BTB_ENTRY_COUNT];

    // Index calculations (combinational)
    BP_INDICES prediction_indices, training_indices;

    // Helper functions
    function automatic logic is_btb_hit(logic request_valid, logic prediction_taken, BP_BTB_ENTRY btb_entry,
                                        logic [`BP_BTB_TAG_BITS-1:0] btb_tag);
        return request_valid && prediction_taken && btb_entry.valid && (btb_entry.tag == btb_tag);
    endfunction

    function automatic BP_COUNTER_STATE update_counter(BP_COUNTER_STATE current_counter, logic branch_taken);
        if (branch_taken) begin
            return (current_counter == STRONGLY_TAKEN) ? current_counter : (current_counter + 2'b01);
        end else begin
            return (current_counter == STRONGLY_NOT_TAKEN) ? current_counter : (current_counter - 2'b01);
        end
    endfunction

    function automatic BP_INDICES compute_indices(logic [31:0] pc, logic [`BP_GH-1:0] global_history);
        BP_INDICES computed_indices;
        computed_indices.pht_idx = pc[`BP_PC_WORD_ALIGN_BITS+:`BP_PHT_BITS] ^ {{(`BP_PHT_BITS - `BP_GH) {1'b0}}, global_history};
        computed_indices.btb_idx = pc[`BP_PC_WORD_ALIGN_BITS+:`BP_BTB_BITS];
        computed_indices.btb_tag = pc[`BP_PC_WORD_ALIGN_BITS+`BP_BTB_BITS+:`BP_BTB_TAG_BITS];
        return computed_indices;
    endfunction

    // Index calculations
    always_comb begin
        prediction_indices = compute_indices(predict_req_i.pc, global_history_reg);
        training_indices   = compute_indices(train_req_i.pc, train_req_i.ghr_snapshot);
    end

    // Prediction logic
    always_comb begin
        logic btb_hit;

        predict_resp_o.ghr_snapshot = global_history_reg;  // Snapshot the precise history used for this prediction

        // Determine taken prediction from PHT counter MSB
        predict_resp_o.taken = predict_req_i.valid ? pattern_history_table[prediction_indices.pht_idx][1] : 1'b0;  // MSB of counter is the taken bit

        // Check BTB hit
        btb_hit = is_btb_hit(predict_req_i.valid, predict_resp_o.taken, btb_array[prediction_indices.btb_idx],
                             prediction_indices.btb_tag);
        predict_resp_o.target = btb_hit ? btb_array[prediction_indices.btb_idx].target : 32'h0; // Provide target only on a definite BTB hit

        // Update global history register
        global_history_next = global_history_reg;
        if (predict_req_i.valid && predict_req_i.used) begin
            global_history_next = {global_history_reg[`BP_GH-2:0], predict_resp_o.taken};
        end
    end

    // Sequential logic: register updates and training
    always_ff @(posedge clock) begin
        if (reset) begin
            // Initialize all structures on reset
            global_history_reg <= '0;
            pattern_history_table <= '{default: WEAKLY_NOT_TAKEN};  // Initialize to weakly not-taken
            btb_array <= '{default: '{default: '0}};     // Initialize all BTB entries to invalid
        end else begin
            // Handle mispredict recovery or normal GHR update
            if (recover_req_i.pulse) begin
                global_history_reg <= recover_req_i.ghr_snapshot;
            end else begin
                global_history_reg <= global_history_next;
            end

            // Handle training updates
            if (train_req_i.valid) begin
                // Update PHT counter
                pattern_history_table[training_indices.pht_idx] <= update_counter(
                    pattern_history_table[training_indices.pht_idx], train_req_i.actual_taken
                );

                // Update BTB on taken branches
                if (train_req_i.actual_taken) begin
                    btb_array[training_indices.btb_idx].valid <= 1'b1;
                    btb_array[training_indices.btb_idx].tag <= training_indices.btb_tag;
                    btb_array[training_indices.btb_idx].target <= train_req_i.actual_target;
                end
            end
        end
    end
endmodule

