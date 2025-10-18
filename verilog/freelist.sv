`timescale 1ns / 100ps
`include "sys_defs.svh"

// ------------------------------------------------------------------
// N-way freelist (no branch recovery)
// - Holds free physical registers in a circular buffer
// - Up to N allocs and N returns per cycle
// - Reset seeds the queue with tags [START_TAG .. PR_COUNT-1]
// - Oldest lane (0) has priority on allocation
// ------------------------------------------------------------------
module freelist #(
    parameter int N            = `N,
    parameter int PR_COUNT     = `PHYS_REG_SZ_R10K,
    parameter int ARCH_COUNT   = 32,
    parameter bit EXCLUDE_ZERO = 1'b1
) (
    input  logic            clock,
    input  logic            reset_n,
    input  logic    [N-1:0] DispatchEN,
    input  logic    [N-1:0] RetireEN,
    input  PHYS_TAG [N-1:0] RetireReg,
    output PHYS_TAG [N-1:0] FreeReg,      // valid when FreeRegValid[i] = 1
    output logic    [N-1:0] FreeRegValid
);


    // default seed range: [START_TAG .. PR_COUNT-1]
    localparam int START_TAG = (EXCLUDE_ZERO ? ((ARCH_COUNT > 0) ? ARCH_COUNT : 1) : ARCH_COUNT);
    localparam int DEPTH = (PR_COUNT > START_TAG) ? (PR_COUNT - START_TAG) : 0;
    localparam int PTRW = (DEPTH <= 1) ? 1 : $clog2(DEPTH);

    PHYS_TAG queue[(DEPTH > 0 ? DEPTH : 1) - 1 : 0];  // avoid zero-sized arrays
    logic [PTRW-1:0] head, tail;
    logic [$clog2(PR_COUNT+1)-1:0] count;  // 0..DEPTH

    integer req_pop_c, req_push_c, grant_pop_c;
    integer i_pop_c, i_tag_c, idx_tmp_c;
    integer i_seed_s, i_lane_s, i_off_s;

    logic [PTRW-1:0] head_n, tail_n;
    logic [$clog2(PR_COUNT+1)-1:0] count_n;

    // Count the number of instructions that need/return the PRs
    function automatic int sum_bits(input logic [N-1:0] b);
        int s = 0;
        for (int t = 0; t < N; t++) s += (b[t] ? 1 : 0);
        return s;
    endfunction

    // combinational logic
    always_comb begin
        req_pop_c = sum_bits(DispatchEN);
        req_push_c = sum_bits(RetireEN);

        // only grant what we have
        grant_pop_c = (count >= req_pop_c) ? req_pop_c : count;

        // Oldest gets the priority
        FreeRegValid = '0;
        for (i_pop_c = 0; i_pop_c < grant_pop_c; i_pop_c = i_pop_c + 1)
        FreeRegValid[i_pop_c] = 1'b1;

        // tags for granted instructions (head = oldest)
        FreeReg = '{default: PHYS_TAG'(0)};
        for (i_tag_c = 0; i_tag_c < grant_pop_c; i_tag_c = i_tag_c + 1) begin
            idx_tmp_c = (head + i_tag_c) % ((DEPTH > 0) ? DEPTH : 1);
            FreeReg[i_tag_c] = queue[idx_tmp_c];
        end

        // pointer/count next state 
        head_n  = (DEPTH > 0) ? (head + grant_pop_c) % DEPTH : head;
        tail_n  = (DEPTH > 0) ? (tail + req_push_c) % DEPTH : tail;
        count_n = count - grant_pop_c + req_push_c;
    end

    //sequential logic
    always_ff @(posedge clock or negedge reset_n) begin
        if (!reset_n) begin
            if (DEPTH > 0) begin
                head  <= '0;
                tail  <= '0;
                count <= DEPTH[$bits(count)-1:0];

                for (i_seed_s = 0; i_seed_s < DEPTH; i_seed_s = i_seed_s + 1)
                queue[i_seed_s] <= PHYS_TAG'(START_TAG + i_seed_s);
            end else begin
                head  <= '0;
                tail  <= '0;
                count <= '0;
            end
        end else begin

            if (DEPTH > 0) begin
                i_off_s = 0;
                for (i_lane_s = 0; i_lane_s < N; i_lane_s = i_lane_s + 1) begin
                    if (RetireEN[i_lane_s]) begin
                        queue[(tail+i_off_s)%DEPTH] <= RetireReg[i_lane_s];
                        i_off_s = i_off_s + 1;
                    end
                end
            end

            head  <= head_n;
            tail  <= tail_n;
            count <= count_n;
        end
    end

endmodule
