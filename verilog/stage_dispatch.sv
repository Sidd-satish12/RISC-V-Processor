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
typedef struct packed {
    PHYS_TAG phys_tag;  // Current physical register mapping
} MAP_ENTRY;

// ROB entry is now defined in sys_defs.svh

// RS entry is now defined in sys_defs.svh


// // Packet from Dispatch to Issue (minimal, since Issue reads from RS directly; this could signal new entries)
// typedef struct packed {
//     logic [`N-1:0]  valid;    // Valid bits for dispatched bundle
//     RS_IDX [`N-1:0] rs_idxs;  // Indices of newly allocated RS entries
// } DISP_ISS_PACKET;

// Packet for mispredict recovery (from Execute/Complete to Dispatch for map/free recovery)
typedef struct packed {
    logic valid;  // Mispredict occurred
    ROB_IDX rob_idx;  // ROB index of mispredicted branch (to truncate from)
    ADDR correct_target;  // Correct target for fetch redirect
} MISPRED_RECOVERY_PACKET;

// Packet from Retire to Dispatch (for committed map updates and free list additions)
typedef struct packed {
    logic [`N-1:0]    valid;          // Valid commits this cycle
    REG_IDX [`N-1:0]  arch_rds;       // Architectural destinations
    PHYS_TAG [`N-1:0] phys_rds;       // Committed physical regs
    PHYS_TAG [`N-1:0] prev_phys_rds;  // Previous phys to free
} RETIRE_DISP_PACKET;

typedef struct packed {
    logic [`N-1:0]    valid;
    ADDR [`N-1:0]     PC;
    INST [`N-1:0]     inst;
    REG_IDX [`N-1:0]  rs1_idx;
    REG_IDX [`N-1:0]  rs2_idx;
    REG_IDX [`N-1:0]  rd_idx;
    logic [`N-1:0]    uses_rs1;
    logic [`N-1:0]    uses_rs2;
    logic [`N-1:0]    uses_rd;
    ALU_OPA_SELECT [`N-1:0] opa_select;
    ALU_OPB_SELECT [`N-1:0] opb_select;
    OP_TYPE [`N-1:0]        op_type;
    logic [`N-1:0]    pred_taken;
    ADDR [`N-1:0]     pred_target;
} FETCH_DISP_PACKET;

module stage_dispatch (
    input clock,  // system clock
    input reset,  // system reset

    // From Fetch: partially decoded bundle
    // FETCH_DISP_PACKET Undefined right now
    input FETCH_DISP_PACKET fetch_packet,
    input logic  [`N-1:0]           fetch_valid,   // Overall valid for bundle

    // From ROB, tells us how many slots are free in ROB
    input logic [$clog2(`ROB_SZ+1)-1:0] free_slots_rob,

    // From RS, tells us how many slots are free in the RS
    input logic [$clog2(`RS_SZ+1)-1:0] free_slots_rs,

    // From Freelist, tells us how many slots are free in the free_list
    input logic [$clog2(`PHYS_REG_SZ_R10K+1)-1:0] free_slots_freelst;

    // To Fetch: stall signal if no space. Used for debugging, Could just use dispatch count instead
    output logic stall_fetch,

    // number of instructions dispatched (sent to fetch stage)
    output logic [$clog2(`N)-1:0] dispatch_count,

    // TO ROB: allocation signals (interface; full ROB module separate)
    output logic [`N-1:0] rob_alloc_valid,  // Allocate these
    output ROB_ENTRY [`N-1:0] rob_alloc_entries,  // Data to write

    // TO RS: allocation signals (interface; full RS module separate)
    output logic [`N-1:0] rs_alloc_valid,  // Allocate these
    output RS_ENTRY [`N-1:0] rs_alloc_entries,  // Data to write
    
    // output logic rs_compact,  // Signal to compact/shift for oldest-first

    // TO FREE LIST: allocations and frees (interface; full free list module separate)
    output logic [`N-1:0] free_alloc_valid,  // Request new phys regs
    input PHYS_TAG [`N-1:0] allocated_phys,  // Granted phys tags from free list

    // Should be in the retire stage
    // output logic [`N-1:0] free_add_valid,  // Add freed phys (from retire)
    // output PHYS_TAG [`N-1:0] freed_phys  // Phys to add back
);

    // Internal structures
    MAP_ENTRY [31:0] map_table;        // Arch reg -> phys tag (speculative)
    MAP_ENTRY [31:0] map_table_next;
    logic checkpoint_valid;  // Active checkpoint?

    // ROB interface signals (assume ROB is separate module, here we generate writes)
    ROB_IDX rob_head, rob_tail;  // Maintained here or from ROB module

    // Free list interface (assume FIFO-like with head/tail)
    logic free_list_empty;  // No free phys regs

    // Internal signals for dispatch bundle
    logic [`N-1:0] disp_valid;  // Per-inst valid after checks
    PHYS_TAG [`N-1:0] rs1_phys;  // Renamed rs1
    PHYS_TAG [`N-1:0] rs2_phys;  // Renamed rs2
    PHYS_TAG [`N-1:0] rd_phys;  // New phys for rd
    PHYS_TAG [`N-1:0] prev_rd_phys;  // Prev mapping for ROB
    logic [`N-1:0] src1_ready;           // Src1 ready at dispatch (from map/phys reg file?)
    logic [`N-1:0] src2_ready;  // Src2 ready
    DATA [`N-1:0] src1_value;  // If ready, value from phys reg file
    DATA [`N-1:0] src2_value;  // If ready

    // Phys reg file interface (separate module; for values if ready)
    // Assume read ports: up to 2*`N for srcs
    output logic [2*`N-1:0] prf_read_valid;
    output PHYS_TAG [2*`N-1:0] prf_read_tags;
    input DATA [2*`N-1:0] prf_read_values;

    // Stall insufficient space for ALL `N insts (atomic dispatch)
    // always_comb begin
    //     stall_fetch = fetch_valid && (free_slots_rob < `N || free_slots_rs < `N || |free_alloc_valid && free_list_empty);
    // end




    // STALL LOGIC
    logic [$clog2(`N+1)-1:0] num_to_dispatch;
    logic [$clog2(`N+1)-1:0] num_rds_needed;
    // logic [$clog2(`N+1)-1:0] dispatch_actual_instructions;


    always_comb begin
        num_to_dispatch = 0;
        num_rds_needed = 0;
        for (int i = 0; i < `N; i++) begin
            // if the fetch is valid
            if (fetch_valid [i]) begin
                num_to_dispatch ++;
                // if the inst uses dest register
                if (fetch_packet.uses_rd[i]) begin
                    num_rds_needed ++;
                end
            end
        end

        // TODO: is it all or nothing? Or is it partial dispatch?
        // if any of the freeslots (rob, rs, free_list) is not enough, stall
        stall_fetch = (free_slots_rob < num_to_dispatch) ||
                      (free_slots_rs < num_to_dispatch) ||
                      (free_slots_freelst < num_to_dispatch);

        // find the minimum of those three
        num_valid_from_fetch = 0;
        num_can_dispatch_count = 0;
        freelist_needed = 0;
        logic destreg_req;
        
        for (int i = 0; i < `N; i++) begin
            // if the fetch is valid
            if (fetch_valid [i]) begin
                num_valid_from_fetch++;
                destreg_req = fetch_packet.uses_rd[i];
                
                // check if there's any enough resources
                if ((num_can_dispatch_count < free_slots_rob) &&
                    (num_can_dispatch_count < free_slots_rs) &&
                    (~destreg_req || freelist_needed + 1 < free_slots_freelst)) begin
                        num_can_dispatch_count++;
                        if (destreg_req) begin
                            freelist_needed++;
                        end
                    end else begin
                        break;
                    end
            end
        end

        num_to_dispatch = num_can_dispatch_count;

        // stall if there is valid instr from fetch, and also at the same time can dispatch count < total valid fetch
        // prevent sending the same (partially dispatched bundle again)
        stall_fetch = (num_valid_from_fetch > 0) && (can_dispatch_count < num_valid_from_fetch);
    end


    // Dispatch logic (parallel for rename, sequential for allocation)
    always_comb begin
        // Default outputs
        disp_valid = fetch_packet.valid & {`N{!stall_fetch}};
        dispatch_valid = |disp_valid;
        
        rob_alloc_valid = '0;
        rs_alloc_valid = '0;
        free_alloc_valid = '0;
        free_add_valid = '0;
        prf_read_valid = '0;

        // Parallel: Rename srcs/dest for each inst
        for (int i = 0; i < `N; i++) begin
            if (disp_valid[i]) begin
                // Lookup srcs
                rs1_phys[i] = map_table[fetch_packet.rs1_idx[i]].phys_tag;
                rs2_phys[i] = map_table[fetch_packet.rs2_idx[i]].phys_tag;
                prev_rd_phys[i] = map_table[fetch_packet.rd_idx[i]].phys_tag;

                // Request new phys for rd if uses_rd
                if (fetch_packet.uses_rd[i]) begin
                    free_alloc_valid[i] = 1'b1;
                    rd_phys[i] = allocated_phys[i];  // Assume granted instantly (combo)
                end else begin
                    rd_phys[i] = '0;  // No dest
                end

                // Check readiness and read values if ready (assume busy table or from CDB)
                // For simplicity: assume ready if not waiting on tag (but actual: check if producer complete)
                // Here, placeholder: read from PRF always, set ready if value avail (but need busy bits)
                prf_read_valid[2*i] = fetch_packet.uses_rs1[i];
                prf_read_tags[2*i] = rs1_phys[i];
                src1_value[i] = prf_read_values[2*i];
                src1_ready[i] = 1'b1;  // Placeholder; actual: if !busy[rs1_phys[i]]

                prf_read_valid[2*i+1] = fetch_packet.uses_rs2[i];
                prf_read_tags[2*i+1] = rs2_phys[i];
                src2_value[i] = prf_read_values[2*i+1];
                src2_ready[i] = 1'b1;  // Placeholder
            end
        end

        // Sequential/atomic: if no stall, allocate all
        if (!stall_fetch && fetch_valid) begin
            ROB_IDX new_tail = rob_tail;
            for (int i = 0; i < `N; i++) begin
                if (disp_valid[i]) begin
                    // Allocate ROB
                    rob_alloc_valid[i] = 1'b1;
                    rob_alloc_entries[i].valid = 1'b1;
                    rob_alloc_entries[i].PC = fetch_packet.PC[i];
                    rob_alloc_entries[i].inst = fetch_packet.inst[i];
                    rob_alloc_entries[i].arch_rd = fetch_packet.rd_idx[i];
                    rob_alloc_entries[i].phys_rd = rd_phys[i];
                    rob_alloc_entries[i].prev_phys_rd = prev_rd_phys[i];
                    rob_alloc_entries[i].complete = 1'b0;
                    rob_alloc_entries[i].exception = NO_ERROR;
                    rob_alloc_entries[i].branch = (fetch_packet.op_type[i].category == CAT_BRANCH);

                    // Allocate RS (priority insert from top for oldest)
                    rs_alloc_valid[i] = 1'b1;
                    rs_alloc_entries[i].valid = 1'b1;
                    rs_alloc_entries[i].opa_select = fetch_packet.opa_select[i];
                    rs_alloc_entries[i].opb_select = fetch_packet.opb_select[i];
                    rs_alloc_entries[i].op_type = fetch_packet.op_type[i];
                    rs_alloc_entries[i].src1_tag = rs1_phys[i];
                    rs_alloc_entries[i].src1_ready = src1_ready[i];
                    rs_alloc_entries[i].src1_value = src1_value[i];
                    rs_alloc_entries[i].src2_tag = rs2_phys[i];
                    rs_alloc_entries[i].src2_ready = src2_ready[i];
                    rs_alloc_entries[i].src2_value = src2_value[i];
                    rs_alloc_entries[i].dest_tag = rd_phys[i];
                    rs_alloc_entries[i].rob_idx = new_tail;  // Current tail as idx
                    rs_alloc_entries[i].PC = fetch_packet.PC[i];
                    rs_alloc_entries[i].pred_taken = fetch_packet.pred_taken[i];
                    rs_alloc_entries[i].pred_target = fetch_packet.pred_target[i];

                    // Update map table (after all prev in bundle)
                    if (fetch_packet.uses_rd[i]) begin
                        map_table[fetch_packet.rd_idx[i]].phys_tag = rd_phys[i];
                    end

                    // Advance tail
                    new_tail = new_tail + 1;
                end
            end
            rob_tail_update = new_tail;
            rs_compact = 1'b1;  // Compact RS after alloc for priority
        end
    end



    // Mispredict recovery: truncate ROB/RS from mispred rob_idx, restore map/free list
    always_comb begin
        if (mispred_recovery.valid) begin
            // Walk ROB backwards from mispred.rob_idx to restore map and free list (add back allocated phys)
            // Placeholder logic: for each entry from tail to mispred+1, undo map, free phys_rd
            // Actual impl would loop over ROB entries
            // If checkpoint: restore from checkpoint_map if branch
        end
    end

    // Checkpoint map on branches (simplified: one checkpoint)
    always_ff @(posedge clock) begin
        // On dispatch of branch, checkpoint = map_table
        // On mispredict, map_table = checkpoint
    end

    // Update free counts (from ROB/RS modules)
    // assume inputs rob_free_count, rs_free_count from those modules

endmodule  // stage_dispatch
