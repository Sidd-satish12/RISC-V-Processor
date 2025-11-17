`include "sys_defs.svh"

module stage_fetch #(
    parameter int unsigned GH = `BP_PHT_BITS
) (
    input  logic                clock,
    input  logic                reset,

    // #1: input and output from icache
    output ADDR          [`N-1:0]     icache_read_addr_o,
    input  CACHE_DATA    [`N-1:0]     icache_cache_out_i,

    // #2: Instruction Buffer Suite
    input  logic                ib_stall_i,
    output logic                ib_bundle_valid_o,
    output FETCH_ENTRY    [`N-1:0]      ib_fetch_o               ,

    // #3: Branch Predictor
    output  BP_PREDICT_REQUEST   bp_predict_req_o,
    input   BP_PREDICT_RESPONSE  bp_predict_resp_i,

    // Redirect from EX/ROB
    input  logic                ex_redirect_valid_i,
    input  ADDR                 ex_redirect_pc_i,

    // fetch enable or stall
    input  logic                fetch_enable_i,
    output logic                fetch_stall_o,

    // debug
    output logic                pc_debug
);

    ADDR pc_reg, pc_next;
    ADDR         bundle_pc        [`N-1:0];
    logic        lane_valid       [`N-1:0];
    logic [31:0] lane_instr       [`N-1:0];
    logic        lane_is_branch   [`N-1:0];
    logic        found_branch;
    int          first_branch_idx;
    logic        all_lanes_ready;
    logic        icache_stall_if;
    logic        ibuf_stall_if;
    logic        fetch_blocked_if;


    // detect predictable branch
    function automatic logic is_predictable_branch(input logic [31:0] instr);
        logic [6:0] opcode;
        opcode = instr[6:0];
        return (opcode == 7'b1100011);
    endfunction

    // compute PC, PC + 4*i
    always_comb begin
        for (int i = 0; i < `N; i++) begin
            bundle_pc[i] = pc_reg + (ADDR'(i) << 2);  // pc + 4*i
        end
    end

    // to icache, read address
    always_comb begin
        for (int i = 0; i < `N; i++) begin
            icache_read_addr_o[i] = bundle_pc[i];
        end
    end

    // from icache, data coming in
    always_comb begin
        for (int i = 0; i < `N; i++) begin
            lane_valid[i] = icache_cache_out_i[i].valid;
            lane_instr[i] = icache_cache_out_i[i].cache_line[31:0];
        end
    end

    always_comb begin
        all_lanes_ready = 1'b1;
        for (int i = 0; i < `N; i++) begin
            if (!lane_valid[i]) begin
                all_lanes_ready = 1'b0;
            end
        end
    end

    assign icache_stall_if  = ~all_lanes_ready;
    assign ibuf_stall_if    = ib_stall_i;
    assign fetch_blocked_if = icache_stall_if | ibuf_stall_if;
    assign fetch_stall_o    = fetch_blocked_if;

    always_comb begin
        for (int i = 0; i < `N; i++) begin
            lane_is_branch[i] = lane_valid[i] && is_predictable_branch(lane_instr[i]);
        end
        found_branch     = 1'b0;
        first_branch_idx = 0;
        for (int i = 0; i < `N; i++) begin
            if (!found_branch && lane_is_branch[i]) begin
                found_branch     = 1'b1;
                first_branch_idx = i;
            end
        end
    end

    always_comb begin
        bp_predict_req_o.valid = fetch_enable_i && found_branch;
        bp_predict_req_o.pc    = found_branch ? bundle_pc[first_branch_idx] : '0;
        bp_predict_req_o.used  = fetch_enable_i && ~fetch_blocked_if && ~ex_redirect_valid_i && found_branch;
    end

    always_comb begin
        ib_bundle_valid_o = fetch_enable_i && all_lanes_ready && ~ib_stall_i && ~ex_redirect_valid_i;
        for (int i = 0; i < `N; i++) begin
            ib_fetch_o[i].pc              = bundle_pc[i];
            ib_fetch_o[i].inst            = lane_instr[i];

            ib_fetch_o[i].is_branch       = 1'b0;
            ib_fetch_o[i].bp_pred_taken   = 1'b0;
            ib_fetch_o[i].bp_pred_target  = '0;
            ib_fetch_o[i].bp_ghr_snapshot = '0;
        end
        if (ib_bundle_valid_o && found_branch) begin
            ib_fetch_o[first_branch_idx].is_branch       = 1'b1;
            ib_fetch_o[first_branch_idx].bp_pred_taken   = bp_predict_resp_i.taken;
            ib_fetch_o[first_branch_idx].bp_pred_target  = bp_predict_resp_i.target;
            ib_fetch_o[first_branch_idx].bp_ghr_snapshot = bp_predict_resp_i.ghr_snapshot;
        end
    end

    always_comb begin
        pc_next = pc_reg;

        if (fetch_enable_i) begin
            if (ex_redirect_valid_i) begin
                pc_next = ex_redirect_pc_i;
            end else if (~fetch_blocked_if && found_branch && bp_predict_resp_i.taken) begin
                pc_next = bp_predict_resp_i.target;
            end else if (~fetch_blocked_if) begin
                pc_next = pc_reg + (ADDR'(`N) << 2);
            end
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            pc_reg <= '0;
        end else begin
            pc_reg <= pc_next;
        end
    end

    assign pc_debug = pc_reg;

endmodule
