/////////////////////////////////////////////////////////////////////////
//                                                                     //
//  Modulename :  bp.sv                                                //
//                                                                     //
//  Description :  Branch Predictor module; implements a hybrid        //
//                 gshare + BTB predictor with global history.         //
//                 Handles prediction requests from fetch, training    //
//                 from retire, and mispredict recovery.               //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

module bp (
    input logic clock,
    input logic reset,

    // Fetch stage IOs
    input BP_PREDICT_REQUEST predict_req_i,
    output BP_PREDICT_RESPONSE predict_resp_o,

    // Retire stage IOs
    input BP_TRAIN_REQUEST train_req_i
);

    // Local parameters derived from macros
    localparam PHT_ENTRY_COUNT = (1 << `BP_PHT_BITS);
    localparam BTB_ENTRY_COUNT = (1 << `BP_BTB_BITS);

    // Internal storage
    logic              [`BP_GHR_WIDTH-1:0] ghr, ghr_next;
    logic                                  recovery_active;
    BP_COUNTER_STATE [PHT_ENTRY_COUNT-1:0] pattern_history_table;
    BP_BTB_ENTRY     [BTB_ENTRY_COUNT-1:0] btb_array;

    BP_INDICES prediction_indices, training_indices;
    logic btb_hit;
    logic predict_taken;
    // Branch prediction statistics
    logic [63:0] bp_total_branches;
    logic [63:0] bp_correct_predictions;

    // =======================
    // Return Address Stack
    // =======================
    localparam RAS_DEPTH = 32;
    ADDR ras [RAS_DEPTH-1:0];                     // stack entries
    logic [$clog2(RAS_DEPTH)-1:0] ras_ptr;       // pointer
    logic ras_push;
    ADDR ras_data_out;


    // RAS push/pop logic
    always_ff @(posedge clock or posedge reset) begin
        if (reset) begin
            ras_ptr <= 0;
        end 
        else begin
            if (ras_push && (ras_ptr < RAS_DEPTH)) begin
                ras[ras_ptr] <= predict_req_i.pc + 32'd4;  // push return addr
                ras_ptr <= ras_ptr + 1;
            end
            if (train_req_i.ras_pop && (ras_ptr > 0)) begin
                ras[ras_ptr] <= '0;
                ras_ptr <= ras_ptr - 1;
            end
        end

        // -------------------------
        // DEBUG: print RAS contents
        // -------------------------
        `ifdef DEBUG
            $display("---- RAS STATE ----");
            for (int i = 0; i < RAS_DEPTH; i = i + 1) begin
                $display("RAS[%0d] = 0x%08h", i, ras[i]);
            end
            $display("RAS pointer = %0d", ras_ptr);
            $display("-------------------");
        `endif
    end

    // combinational read of top-of-stack for JALR prediction
    assign ras_data_out = (ras_ptr > 0) ? ras[ras_ptr-1] : 32'd0;

    // Helper functions
    function automatic BP_COUNTER_STATE update_counter(BP_COUNTER_STATE current_counter, logic branch_taken);
        case (current_counter)
            STRONGLY_NOT_TAKEN: return branch_taken ? WEAKLY_NOT_TAKEN : STRONGLY_NOT_TAKEN;
            WEAKLY_NOT_TAKEN: return branch_taken ? WEAKLY_TAKEN : STRONGLY_NOT_TAKEN;
            WEAKLY_TAKEN: return branch_taken ? STRONGLY_TAKEN : WEAKLY_NOT_TAKEN;
            STRONGLY_TAKEN: return branch_taken ? STRONGLY_TAKEN : WEAKLY_TAKEN;
        endcase
    endfunction

    function automatic BP_INDICES compute_indices(logic [31:0] pc, logic [`BP_GHR_WIDTH-1:0] ghr);
        BP_INDICES computed_indices;
        computed_indices.pht_idx = pc[`BP_PC_WORD_ALIGN_BITS+:`BP_PHT_BITS] ^ {{(`BP_PHT_BITS - `BP_GHR_WIDTH) {1'b0}}, ghr};
        computed_indices.btb_idx = pc[`BP_PC_WORD_ALIGN_BITS+:`BP_BTB_BITS];
        computed_indices.btb_tag = pc[`BP_PC_WORD_ALIGN_BITS+`BP_BTB_BITS+:`BP_BTB_TAG_BITS];
        return computed_indices;
    endfunction

    // Index calculations
    always_comb begin
        prediction_indices = compute_indices(predict_req_i.pc, ghr);
        training_indices   = compute_indices(train_req_i.pc, train_req_i.ghr_snapshot);
    end

    // Prediction logic
    always_comb begin
        predict_resp_o.ghr_snapshot = ghr;
        predict_taken = pattern_history_table[prediction_indices.pht_idx][1];  // MSB of counter is the taken bit

        btb_hit = btb_array[prediction_indices.btb_idx].valid && btb_array[prediction_indices.btb_idx].tag == prediction_indices.btb_tag;

        predict_resp_o.taken = predict_taken;
        predict_resp_o.target = btb_hit ? btb_array[prediction_indices.btb_idx].target : (predict_req_i.pc + 32'h4);


        // -----------------------------
        // RAS push/pop logic (updated)
        // -----------------------------
        if (predict_req_i.valid) begin
            if ((predict_req_i.is_jal || predict_req_i.is_jalr) && predict_req_i.uses_rd) begin
                // Push for JAL or JALR that writes to rd
                ras_push = 1'b1;
            end
            else if (predict_req_i.is_jalr && !predict_req_i.uses_rd) begin
                // Pop for JALR that does NOT write to rd (return)
                ras_push = 1'b0;
            end
            else begin
                ras_push = 1'b0;
            end
        end else begin
            ras_push = 1'b0;
        end

        // Use top-of-stack for JALR returns
        if (predict_req_i.is_jalr && !predict_req_i.uses_rd) begin
            predict_resp_o.target = ras_data_out;
            predict_resp_o.taken = 1'b1;
        end

    end

    // ghr_next logic
    always_comb begin
        ghr_next = ghr;  // Default: hold current GHR
        
        if (train_req_i.valid && train_req_i.mispredict && train_req_i.cond) begin // a retiring branch instruction was mispredicted
            ghr_next = {train_req_i.ghr_snapshot[`BP_GHR_WIDTH-2:0], train_req_i.actual_taken};
        end else if (predict_req_i.valid && !predict_req_i.is_jal && !predict_req_i.is_jalr) begin // from fetch
            ghr_next = {ghr[`BP_GHR_WIDTH-2:0], predict_taken};
        end 
    end 




    
    always_ff @(posedge clock) begin
        if (reset) begin
            ghr                    <= '0;
            for (int i = 0; i < PHT_ENTRY_COUNT; i = i + 1) begin
                pattern_history_table[i] <= WEAKLY_TAKEN;
            end
            btb_array              <= '0;

            // stats
            bp_total_branches      <= 64'd0;
            bp_correct_predictions <= 64'd0;
        end else begin
            ghr <= ghr_next;

            if (train_req_i.valid) begin
                bp_total_branches <= bp_total_branches + 1;
                if (!train_req_i.mispredict)
                    bp_correct_predictions <= bp_correct_predictions + 1;
            end
            // Handle training updates
            if (train_req_i.valid && train_req_i.cond) begin
                // Update stats


                // Update PHT counter
                pattern_history_table[training_indices.pht_idx] <= update_counter(
                    pattern_history_table[training_indices.pht_idx], 
                    train_req_i.actual_taken
                );

                //Update BTB on taken branches
                if (train_req_i.actual_taken) begin
                    btb_array[training_indices.btb_idx].valid  <= 1'b1;
                    btb_array[training_indices.btb_idx].tag    <= training_indices.btb_tag;
                    btb_array[training_indices.btb_idx].target <= train_req_i.actual_target;
                end
            end
        end
    end

    final begin
        real accuracy;
        if (bp_total_branches != 0)
            accuracy = 100.0 * bp_correct_predictions / bp_total_branches;
        else
            accuracy = 0.0;

        $display("==== Branch Predictor Stats ====");
        $display("Total branches      = %0d", bp_total_branches);
        $display("Correct predictions = %0d", bp_correct_predictions);
        $display("Accuracy            = %0.2f%%", accuracy);
        $display("================================");
    end


endmodule
