/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  stage_dispatch.sv                                   //
//                                                                     //
//  Description :  Dispatch stage of the pipeline; handles register    //
//                 renaming, allocates entries in the ROB and RS,      //
//                 checks for structural hazards (space in ROB/RS/     //
//                 free list). Inserts instructions into RS with       //
//                 priority for oldest (using compacting shifter or    //
//                 priority encoder from top). Demonstrates OoO by     //
//                 allowing dispatch of non-dependent instructions.    //
//                 Builds on partial decode from Fetch.                //
//                 Supports recovery on branch mispredictions via      //
//                 map table checkpoints or ROB walkback (simplified). //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"
`include "ISA.svh"

// Parameters and typedefs are now centrally defined in sys_defs.svh

// Map table entry: maps arch reg to phys reg
// typedef struct packed {
//     PHYS_TAG phys_tag;  // Current physical register mapping
// } MAP_ENTRY;


module stage_dispatch (
    input logic clock,
    input logic reset,

    // From Fetch: partially decoded bundle
    input  FETCH_DISP_PACKET fetch_packet,
    input  logic [`N-1:0]    fetch_valid,

    // From ROB/RS/Freelist
    input logic   [          $clog2(`ROB_SZ+1)-1:0] free_slots_rob,
    input logic   [           $clog2(`RS_SZ+1)-1:0] free_slots_rs,
    input logic   [$clog2(`PHYS_REG_SZ_R10K+1)-1:0] free_slots_freelst,
    input ROB_IDX [                         `N-1:0] rob_alloc_idxs,

    // To Fetch
    output logic stall_fetch,
    output logic [$clog2(`N)-1:0] dispatch_count,

    // TO ROB
    output logic [`N-1:0] rob_alloc_valid,
    output ROB_ENTRY [`N-1:0] rob_entry_packet,

    // TO RS
    output logic [`N-1:0] rs_alloc_valid,
    output RS_ENTRY [`N-1:0] rs_alloc_entries,

    // TO FREE LIST
    output logic [`N-1:0] free_alloc_valid,
    input PHYS_TAG [`N-1:0] allocated_phys,

    // TO MAP TABLE - for RENAMING (writes)
    output logic [`N-1:0][                       `PHYS_TAG_BITS-1:0] maptable_new_pr,
    output logic [`N-1:0][$clog2(`PHYS_REG_SZ_R10K - `ROB_SZ) - 1:0] maptable_new_ar,

    // TO MAP TABLE - for SOURCE LOOKUPS (reads)
    output logic [`N-1:0][$clog2(`PHYS_REG_SZ_R10K - `ROB_SZ) - 1:0] reg1_ar,
    output logic [`N-1:0][$clog2(`PHYS_REG_SZ_R10K - `ROB_SZ) - 1:0] reg2_ar,

    // TO MAP TABLE - for TOLD LOOKUPS (reads, separate from renames!)
    output logic [`N-1:0][$clog2(`PHYS_REG_SZ_R10K - `ROB_SZ) - 1:0] told_ar,

    // FROM MAP TABLE - source operands
    input logic [`N-1:0][`PHYS_TAG_BITS-1:0] reg1_tag,
    input logic [`N-1:0][`PHYS_TAG_BITS-1:0] reg2_tag,
    input logic [`N-1:0]                     reg1_ready,
    input logic [`N-1:0]                     reg2_ready,

    // FROM MAP TABLE - Told (OLD mappings before this rename)
    input logic [`N-1:0][`PHYS_TAG_BITS-1:0] Told_in
);

    logic [$clog2(`N+1)-1:0] num_to_dispatch;
    int max_dispatch;
    int num_valid_from_fetch;
    int num_rds_needed;

    // Separate local storage for clarity
    logic [`PHYS_TAG_BITS-1:0] local_reg1_tag[`N-1:0];
    logic [`PHYS_TAG_BITS-1:0] local_reg2_tag[`N-1:0];
    logic local_reg1_ready[`N-1:0];
    logic local_reg2_ready[`N-1:0];
    logic [`PHYS_TAG_BITS-1:0] local_Told[`N-1:0];

    always_comb begin
        // ======================================================
        // STEP 1: Count valid instructions and determine dispatch
        // ======================================================
        num_valid_from_fetch = $countones(fetch_valid);
        num_rds_needed = $countones(fetch_valid & fetch_packet.uses_rd);

        max_dispatch = num_valid_from_fetch;
        if (free_slots_rob < max_dispatch) max_dispatch = free_slots_rob;
        if (free_slots_rs < max_dispatch) max_dispatch = free_slots_rs;
        if (free_slots_freelst < num_rds_needed) max_dispatch = free_slots_freelst;

        num_to_dispatch = max_dispatch;
        stall_fetch = (num_valid_from_fetch > 0) && (num_to_dispatch < num_valid_from_fetch);
        dispatch_count = num_to_dispatch;

        // ======================================================
        // STEP 2: Setup MAP TABLE READS (before any writes!)
        // ======================================================
        // Read source operands
        for (int i = 0; i < `N; i++) begin
            reg1_ar[i] = fetch_packet.rs1_idx[i];
            reg2_ar[i] = fetch_packet.rs2_idx[i];
            // Read Told BEFORE setting up the rename
            told_ar[i] = fetch_packet.rd_idx[i];
        end

        // Capture map table outputs locally
        for (int i = 0; i < `N; i++) begin
            local_reg1_tag[i]   = reg1_tag[i];
            local_reg2_tag[i]   = reg2_tag[i];
            local_reg1_ready[i] = reg1_ready[i];
            local_reg2_ready[i] = reg2_ready[i];
            local_Told[i]       = Told_in[i];
        end

        // ======================================================
        // STEP 3: Setup MAP TABLE WRITES (renames)
        // ======================================================
        for (int i = 0; i < `N; i++) begin
            if (i < dispatch_count && fetch_valid[i] && fetch_packet.uses_rd[i]) begin
                maptable_new_pr[i] = allocated_phys[i];
                maptable_new_ar[i] = fetch_packet.rd_idx[i];
            end else begin
                maptable_new_pr[i] = '0;
                maptable_new_ar[i] = '0;
            end
        end

        // ======================================================
        // STEP 4: Construct outputs to ROB, RS, Free List
        // ======================================================
        rob_alloc_valid  = '0;
        rs_alloc_valid   = '0;
        free_alloc_valid = '0;

        for (int i = 0; i < dispatch_count; i++) begin
            if (fetch_valid[i]) begin
                // --- ROB ---
                rob_alloc_valid[i]                = 1'b1;
                rob_entry_packet[i].valid         = 1'b1;
                rob_entry_packet[i].PC            = fetch_packet.PC[i];
                rob_entry_packet[i].inst          = fetch_packet.inst[i];
                rob_entry_packet[i].arch_rd       = fetch_packet.rd_idx[i];
                rob_entry_packet[i].phys_rd       = allocated_phys[i];
                rob_entry_packet[i].prev_phys_rd  = local_Told[i];
                rob_entry_packet[i].value         = '0;
                rob_entry_packet[i].complete      = 1'b0;
                rob_entry_packet[i].exception     = NO_ERROR;
                rob_entry_packet[i].branch        = (fetch_packet.op_type[i] == CAT_BRANCH);
                rob_entry_packet[i].branch_target = '0;
                rob_entry_packet[i].branch_taken  = 1'b0;
                rob_entry_packet[i].pred_target   = fetch_packet.pred_target[i];
                rob_entry_packet[i].pred_taken    = fetch_packet.pred_taken[i];
                rob_entry_packet[i].halt          = 1'b0;
                rob_entry_packet[i].illegal       = 1'b0;

                // --- RS ---
                rs_alloc_valid[i]                 = 1'b1;
                rs_alloc_entries[i].valid         = 1'b1;
                rs_alloc_entries[i].op_type       = fetch_packet.op_type[i];
                rs_alloc_entries[i].opa_select    = fetch_packet.opa_select[i];
                rs_alloc_entries[i].opb_select    = fetch_packet.opb_select[i];
                rs_alloc_entries[i].src1_tag      = local_reg1_tag[i];
                rs_alloc_entries[i].src1_ready    = local_reg1_ready[i];
                rs_alloc_entries[i].src2_tag      = local_reg2_tag[i];
                rs_alloc_entries[i].src2_ready    = local_reg2_ready[i];
                rs_alloc_entries[i].dest_tag      = allocated_phys[i];
                rs_alloc_entries[i].rob_idx       = rob_alloc_idxs[i];
                rs_alloc_entries[i].PC            = fetch_packet.PC[i];
                rs_alloc_entries[i].pred_taken    = fetch_packet.pred_taken[i];
                rs_alloc_entries[i].pred_target   = fetch_packet.pred_target[i];

                // --- Free List ---
                free_alloc_valid[i]               = fetch_packet.uses_rd[i];
            end
        end
    end

endmodule
