`include "sys_defs.svh"

// Pipelined multiplier with Early Tag Broadcast (ETB) architecture:
// - Request goes out at stage MULT_STAGES-2 (early tag broadcast)
// - If granted, instruction proceeds to final stage, result broadcast next cycle
// - If NOT granted, hold at request stage until granted
module mult (
    input clock,
    input reset,

    // Simplified interface: pass valid/rob_idx instead of external start pulse
    input logic valid,
    input ROB_IDX rob_idx,
    input PHYS_TAG dest_tag,
    input DATA rs1,
    input DATA rs2,
    input MULT_FUNC func,

    // CDB interface
    input logic grant,
    output DATA result,
    output logic request,
    output logic done,
    output EX_COMPLETE_ENTRY meta_out,

    // new
    output logic ready
);

    // ==========================================================================
    // Start pulse generation (moved from stage_execute)
    // ==========================================================================
    logic prev_valid;
    ROB_IDX prev_rob_idx;
    logic start;

    always_ff @(posedge clock) begin
        if (reset) begin
            prev_valid   <= 1'b0;
            prev_rob_idx <= '0;
        end else begin
            prev_valid   <= valid;
            prev_rob_idx <= rob_idx;
        end
    end

    // Start when valid rises or rob_idx changes (new instruction)
    logic busy;

    always_ff @(posedge clock) begin
        if (reset)
            busy <= 1'b0;
        else if (start)
            busy <= 1'b1;
        else if (done)
            busy <= 1'b0;
    end

    assign ready = !busy;

    assign start = valid && !busy && (!prev_valid || rob_idx != prev_rob_idx);

    // ==========================================================================
    // Construct metadata internally
    // ==========================================================================
    EX_COMPLETE_ENTRY meta_in;

    assign meta_in = '{
        rob_idx:       rob_idx,
        branch_valid:  1'b0,
        branch_taken:  1'b0,
        branch_target: '0,
        dest_pr:       dest_tag,
        result:        '0
    };

    // ==========================================================================
    // Pipeline state
    // ==========================================================================
    MULT_FUNC [`MULT_STAGES-2:0] internal_funcs;
    MULT_FUNC func_out;

    logic [(64*(`MULT_STAGES-1))-1:0] internal_sums, internal_mcands, internal_mpliers;
    logic [`MULT_STAGES-1:0] dones;

    logic [63:0] mcand, mplier, product;
    logic [63:0] mcand_out, mplier_out;

    EX_COMPLETE_ENTRY [`MULT_STAGES-2:0] internal_meta;
    EX_COMPLETE_ENTRY meta_out_pipe;

    // ==========================================================================
    // ETB holding state at request stage (MULT_STAGES-2)
    // ==========================================================================
    logic req_pending;
    logic [63:0] sum_held, mcand_held, mplier_held;
    MULT_FUNC func_held;
    EX_COMPLETE_ENTRY meta_held;

    // Final stage control
    logic [63:0] final_prev_sum, final_mplier, final_mcand;
    MULT_FUNC final_func;
    EX_COMPLETE_ENTRY final_meta;
    logic final_start;


    `ifdef DEBUG
        logic [7:0] debug_counter;
        logic       track_rob12;

        always_ff @(posedge clock) begin
            if (reset) begin
                debug_counter <= 0;
                track_rob12   <= 0;
            end else begin
                // Start tracking when we see the rob_idx=12 mult start
                if (start && rob_idx == 12) begin
                    track_rob12   <= 1'b1;
                    debug_counter <= 0;
                    $display("MULT_DEBUG: start tracking ROB 12 at time %0t", $time);
                end else if (track_rob12 && debug_counter < 20) begin
                    debug_counter <= debug_counter + 1;
                end else if (debug_counter == 20) begin
                    track_rob12 <= 1'b0;
                end
            end
        end

        always_ff @(posedge clock) begin
            if (!reset && track_rob12) begin
                $display("MULT_PIPE ROB12: t=%0t start=%0d dones={%b} req_pending=%0d request=%0d grant=%0d final_start=%0d done=%0d",
                        $time,
                        start,
                        dones,
                        req_pending,
                        request,
                        grant,
                        final_start,
                        done);
            end
        end
    `endif

    `ifdef DEBUG
    always_ff @(posedge clock) begin
        if (!reset && track_rob12) begin
            $display("MULT_ETB ROB12: t=%0t start=%0b busy=%0b dones=%b req_pending=%0b request=%0b grant=%0b final_start=%0b done=%0b",
                    $time, start, busy, dones, req_pending, request, grant, final_start, done);
        end
    end
    `endif

    // ==========================================================================
    // Early pipeline stages (0 to MULT_STAGES-2)
    // ==========================================================================
    mult_stage mstage[`MULT_STAGES-2:0] (
        .clock      (clock),
        .reset      (reset),
        .func       ({internal_funcs[`MULT_STAGES-3:0], func}),
        .start      ({dones[`MULT_STAGES-3:0], start}),
        .prev_sum   ({internal_sums[64*(`MULT_STAGES-2)-1:0], 64'h0}),
        .mplier     ({internal_mpliers[64*(`MULT_STAGES-2)-1:0], mplier}),
        .mcand      ({internal_mcands[64*(`MULT_STAGES-2)-1:0], mcand}),
        .product_sum(internal_sums),
        .next_mplier(internal_mpliers),
        .next_mcand (internal_mcands),
        .next_func  (internal_funcs),
        .meta_in    ({internal_meta[`MULT_STAGES-3:0], meta_in}),
        .meta_out   (internal_meta),
        .done       (dones[`MULT_STAGES-2:0])
    );

    // ==========================================================================
    // Final pipeline stage - gated by grant
    // ==========================================================================
    mult_stage mstage_final (
        .clock      (clock),
        .reset      (reset),
        .func       (final_func),
        .start      (final_start),
        .prev_sum   (final_prev_sum),
        .mplier     (final_mplier),
        .mcand      (final_mcand),
        .product_sum(product),
        .next_mplier(mplier_out),
        .next_mcand (mcand_out),
        .next_func  (func_out),
        .meta_in    (final_meta),
        .meta_out   (meta_out_pipe),
        .done       (dones[`MULT_STAGES-1])
    );

    // ==========================================================================
    // Sign extension based on operation
    // ==========================================================================
    always_comb begin
        case (func)
            MUL, MULH, MULHSU: mcand = {{32{rs1[31]}}, rs1};
            default:           mcand = {32'b0, rs1};
        endcase
        case (func)
            MUL, MULH: mplier = {{32{rs2[31]}}, rs2};
            default:   mplier = {32'b0, rs2};
        endcase
    end

    // ==========================================================================
    // Request stage holding logic
    // ==========================================================================
    always_ff @(posedge clock) begin
        if (reset) begin
            req_pending <= 1'b0;
            sum_held    <= '0;
            mcand_held  <= '0;
            mplier_held <= '0;
            func_held   <= MUL;
            meta_held   <= '0;
        end else if (req_pending && grant) begin
            req_pending <= 1'b0;
        end else if (dones[`MULT_STAGES-2] && !grant) begin
            req_pending <= 1'b1;
            sum_held    <= internal_sums[64*(`MULT_STAGES-1)-1 -: 64];
            mcand_held  <= internal_mcands[64*(`MULT_STAGES-1)-1 -: 64];
            mplier_held <= internal_mpliers[64*(`MULT_STAGES-1)-1 -: 64];
            func_held   <= internal_funcs[`MULT_STAGES-2];
            meta_held   <= internal_meta[`MULT_STAGES-2];
        end
    end

    // ==========================================================================
    // Final stage input muxing
    // ==========================================================================
    always_comb begin
        if (req_pending && grant) begin
            final_prev_sum = sum_held;
            final_mcand    = mcand_held;
            final_mplier   = mplier_held;
            final_func     = func_held;
            final_meta     = meta_held;
            final_start    = 1'b1;
        end else if (dones[`MULT_STAGES-2] && grant) begin
            final_prev_sum = internal_sums[64*(`MULT_STAGES-1)-1 -: 64];
            final_mcand    = internal_mcands[64*(`MULT_STAGES-1)-1 -: 64];
            final_mplier   = internal_mpliers[64*(`MULT_STAGES-1)-1 -: 64];
            final_func     = internal_funcs[`MULT_STAGES-2];
            final_meta     = internal_meta[`MULT_STAGES-2];
            final_start    = 1'b1;
        end else begin
            final_prev_sum = '0;
            final_mcand    = '0;
            final_mplier   = '0;
            final_func     = MUL;
            final_meta     = '0;
            final_start    = 1'b0;
        end
    end

    `ifdef DEBUG
    always_ff @(posedge clock) begin
        if (!reset) begin
            $display("MULT_CTRL t=%0t valid=%0b start=%0b busy=%0b done=%0b rob_idx=%0d",
                 $time, valid, start, busy, done, rob_idx);
            if (start) begin
                $display("MULT_START: fu=%0d rob_idx=%0d dest_pr=P%0d rs1=%h rs2=%h func=%0d",
                        0, rob_idx, dest_tag, rs1, rs2, func);
            end
            if (request) begin
                $display("MULT_REQ:   fu=%0d rob_idx=%0d dest_pr=P%0d req_pending=%0d grant=%0d",
                        0, meta_out.rob_idx, meta_out.dest_pr, req_pending, grant);
            end
            if (done) begin
                $display("MULT_DONE:  fu=%0d rob_idx=%0d dest_pr=P%0d result=%h",
                        0, meta_out.rob_idx, meta_out.dest_pr, result);
            end
        end
    end
    `endif

    // ==========================================================================
    // Outputs
    // ==========================================================================
    assign result   = (func_out == MUL) ? product[31:0] : product[63:32];
    assign meta_out = meta_out_pipe;
    assign request  = dones[`MULT_STAGES-2] || req_pending;
    assign done     = dones[`MULT_STAGES-1];

endmodule


module mult_stage (
    input clock,
    input reset,
    input start,
    input [63:0] prev_sum, mplier, mcand,
    input MULT_FUNC func,
    input EX_COMPLETE_ENTRY meta_in,

    output logic [63:0] product_sum, next_mplier, next_mcand,
    output MULT_FUNC next_func,
    output EX_COMPLETE_ENTRY meta_out,
    output logic done
);

    localparam SHIFT = 64 / `MULT_STAGES;

    logic [63:0] partial_product, shifted_mplier, shifted_mcand;

    assign partial_product = mplier[SHIFT-1:0] * mcand;
    assign shifted_mplier  = {SHIFT'('b0), mplier[63:SHIFT]};
    assign shifted_mcand   = {mcand[63-SHIFT:0], SHIFT'('b0)};

    always_ff @(posedge clock) begin
        product_sum <= prev_sum + partial_product;
        next_mplier <= shifted_mplier;
        next_mcand  <= shifted_mcand;
        next_func   <= func;
        meta_out    <= meta_in;
    end

    always_ff @(posedge clock) begin
        if (reset)
            done <= 1'b0;
        else
            done <= start;
    end

endmodule
