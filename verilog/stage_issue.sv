`include "sys_defs.svh"

module stage_issue (
    input clock,
    input reset,

    // All RS entries (from RS module)
    input RS_ENTRY [`RS_SZ-1:0] entries,

    // signal not to take anything from the RS this cycle
    input logic mispredict,

    // Inputs from EX indicating available FUs this cycle
    input logic [`NUM_FU_ALU-1:0] alu_avail,
    input logic [`NUM_FU_MULT-1:0] mult_avail,
    input logic [`NUM_FU_BRANCH-1:0] branch_avail,
    input logic [`NUM_FU_MEM-1:0] mem_avail,

    // Outputs to RS for clearing issued entries
    output logic  [`N-1:0] clear_valid,
    output RS_IDX [`N-1:0] clear_idxs,

    // Outputs to issue-execute pipeline register
    output logic [`N-1:0] issue_valid,
    output RS_ENTRY [`N-1:0] issued_entries
);

    // Combinational logic for issue selection
    always_comb begin
        clear_valid = '0;
        clear_idxs = '0;
        issue_valid = '0;
        issued_entries = '0;

        if (reset || mispredict) begin
            // No issue on reset or mispredict
        end else begin
            // Compute readiness and age values in parallel
            logic [`RS_SZ-1:0] ready;
            logic [6:0] age[`RS_SZ-1:0];  // {rob_wrap, rob_idx}
            OP_CATEGORY cat[`RS_SZ-1:0];
            logic [3:0] num_fu[`RS_SZ-1:0];

            // Pairwise comparison matrix
            logic comp[`RS_SZ-1:0][`RS_SZ-1:0];  // comp[i][j] = (age_j < age_i)

            // Phase 1: Per-category ranking
            logic [3:0] per_cat_count[`RS_SZ-1:0];  // Number of older ready entries in same category
            logic [`RS_SZ-1:0] cand;  // Candidates that pass per-category limits

            // Phase 2: Global ranking among candidates
            logic [3:0] global_count[`RS_SZ-1:0];  // Number of older candidates
            logic [`RS_SZ-1:0] issue;  // Final issue decisions

            // Output packing
            int out_idx;

            for (int i = 0; i < `RS_SZ; i++) begin
                ready[i] = entries[i].valid && entries[i].src1_ready && entries[i].src2_ready;
                age[i]   = {entries[i].rob_wrap, entries[i].rob_idx};
                cat[i]   = entries[i].op_type.category;
            end

            // Count available FUs per category
            for (int i = 0; i < `RS_SZ; i++) begin
                case (cat[i])
                    CAT_ALU, CAT_CSR: num_fu[i] = $countones(alu_avail);
                    CAT_MULT:         num_fu[i] = $countones(mult_avail);
                    CAT_BRANCH:       num_fu[i] = $countones(branch_avail);
                    CAT_MEM:          num_fu[i] = $countones(mem_avail);
                    default:          num_fu[i] = 0;
                endcase
            end

            // Generate all pairwise age comparisons: comp_ij = (age_j < age_i)
            for (int i = 0; i < `RS_SZ; i++) begin
                for (int j = 0; j < `RS_SZ; j++) begin
                    comp[i][j] = (i != j) && (age[j] < age[i]);
                end
            end

            // Phase 1: Per-category ranking to respect FU limits
            for (int i = 0; i < `RS_SZ; i++) begin
                logic [`RS_SZ-1:0] older_in_cat;
                for (int j = 0; j < `RS_SZ; j++) begin
                    older_in_cat[j] = comp[i][j] && ready[j] && (cat[j] == cat[i]);
                end
                per_cat_count[i] = $countones(older_in_cat);
                cand[i] = ready[i] && (per_cat_count[i] < num_fu[i]);
            end

            // Phase 2: Global ranking among candidates to respect total issue width
            for (int i = 0; i < `RS_SZ; i++) begin
                logic [`RS_SZ-1:0] older_cand;
                for (int j = 0; j < `RS_SZ; j++) begin
                    older_cand[j] = comp[i][j] && cand[j];
                end
                global_count[i] = $countones(older_cand);
                issue[i] = cand[i] && (global_count[i] < `N);
            end

            // Pack issued entries into output arrays (program order not required for correctness)
            out_idx = 0;
            for (int i = 0; i < `RS_SZ && out_idx < `N; i++) begin
                if (issue[i]) begin
                    issue_valid[out_idx] = 1'b1;
                    issued_entries[out_idx] = entries[i];
                    clear_valid[out_idx] = 1'b1;
                    clear_idxs[out_idx] = i;
                    out_idx++;
                end
            end
        end
    end

endmodule
