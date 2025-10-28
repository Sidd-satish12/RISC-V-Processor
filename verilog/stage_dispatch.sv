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
// move below defs to sys_defs.svh once we know they are correct
// typedef struct packed {
//     logic valid;  // Mispredict occurred
//     ROB_IDX rob_idx;  // ROB index of mispredicted branch (to truncate from)
//     ADDR correct_target;  // Correct target for fetch redirect
// } MISPRED_RECOVERY_PACKET;

// // Packet from Retire to Dispatch (for committed map updates and free list additions)
// typedef struct packed {
//     logic [`N-1:0]    valid;          // Valid commits this cycle
//     REG_IDX [`N-1:0]  arch_rds;       // Architectural destinations
//     PHYS_TAG [`N-1:0] phys_rds;       // Committed physical regs
//     PHYS_TAG [`N-1:0] prev_phys_rds;  // Previous phys to free
// } RETIRE_DISP_PACKET;

// typedef struct packed {
//     logic [`N-1:0]    valid;
//     ADDR [`N-1:0]     PC;
//     INST [`N-1:0]     inst;
//     REG_IDX [`N-1:0]  rs1_idx;
//     REG_IDX [`N-1:0]  rs2_idx;
//     REG_IDX [`N-1:0]  rd_idx;
//     logic [`N-1:0]    uses_rs1;
//     logic [`N-1:0]    uses_rs2;
//     logic [`N-1:0]    uses_rd;
//     ALU_OPA_SELECT [`N-1:0] opa_select;
//     ALU_OPB_SELECT [`N-1:0] opb_select;
//     OP_TYPE [`N-1:0]        op_type;
//     logic [`N-1:0]    pred_taken;
//     ADDR [`N-1:0]     pred_target;
// } FETCH_DISP_PACKET;

module stage_dispatch (
    input  logic clock,
    input  logic reset,

    // ======================
    // From Fetch: partially decoded bundle
    // ======================
    input  FETCH_DISP_PACKET fetch_packet,
    input  logic [`N-1:0]           fetch_valid,   // Overall valid for bundle

    // ======================
    // From ROB/RS/Freelist
    // ======================
    input  logic [$clog2(`ROB_SZ+1)-1:0]          free_slots_rob,
    input  logic [$clog2(`RS_SZ+1)-1:0]           free_slots_rs,
    input  logic [$clog2(`PHYS_REG_SZ_R10K+1)-1:0] free_slots_freelst,
    // input from ROB (for RS allocations)
    input ROB_IDX [`N-1:0] rob_alloc_idxs,


    // ======================
    // To Fetch
    // ======================
    output logic stall_fetch,
    output logic [$clog2(`N)-1:0] dispatch_count,

    // ======================
    // TO ROB
    // ======================
    output logic [`N-1:0] rob_alloc_valid,
    output ROB_ENTRY [`N-1:0] rob_entry_packet,

    // ======================
    // TO RS
    // ======================
    output logic [`N-1:0] rs_alloc_valid,
    output RS_ENTRY [`N-1:0] rs_alloc_entries,
    
    // ======================
    // TO FREE LIST
    // ======================
    output logic [`N-1:0] free_alloc_valid,
    input  PHYS_TAG [`N-1:0] allocated_phys,

    // ======================
    // TO MAP TABLE
    // ======================
    output logic [`N-1:0][`PHYS_TAG_BITS-1:0]                 maptable_new_pr,  // New physical register for each instruction
    output logic [`N-1:0][$clog2(`PHYS_REG_SZ_R10K - `ROB_SZ) - 1:0]  maptable_new_ar,  // Architectural destination register index
    output  logic [N-1:0][$clog2(`PHYS_REG_SZ_R10K - `ROB_SZ) - 1:0]  reg1_ar,
    output  logic [N-1:0][$clog2(`PHYS_REG_SZ_R10K - `ROB_SZ) - 1:0]  reg2_ar,

    // ======================
    // FROM MAP TABLE 
    // ======================
    input  logic [`N-1:0][`PHYS_TAG_BITS-1:0] Told_in,        // Old physical register mapping (Told)
    input logic [`N-1:0][`PHYS_TAG_BITS-1:0]                 reg1_tag,
    input logic [`N-1:0][`PHYS_TAG_BITS-1:0]                 reg2_tag,
    input logic [`N-1:0]                          reg1_ready,
    input logic [`N-1:0]                          reg2_ready

    
);

    // Internal structures
    //MAP_ENTRY [31:0] map_table;        // Arch reg -> phys tag (speculative)
    //MAP_ENTRY [31:0] map_table_next;
    //logic checkpoint_valid;  // Active checkpoint?

    // Free list interface (assume FIFO-like with head/tail)
    //logic free_list_empty;  // No free phys regs

    // Internal signals for dispatch bundle
    //logic [`N-1:0] disp_valid;  // Per-inst valid after checks
    // PHYS_TAG [`N-1:0] rs1_phys;  // Renamed rs1
    // //PHYS_TAG [`N-1:0] rs2_phys;  // Renamed rs2
    // PHYS_TAG [`N-1:0] rd_phys;  // New phys for rd
    // PHYS_TAG [`N-1:0] prev_rd_phys;  // Prev mapping for ROB
    // logic [`N-1:0] src1_ready;           // Src1 ready at dispatch (from map/phys reg file?)
    // logic [`N-1:0] src2_ready;  // Src2 ready
    // DATA [`N-1:0] src1_value;  // If ready, value from phys reg file
    // DATA [`N-1:0] src2_value;  // If ready




    // STALL LOGIC
    logic [$clog2(`N+1)-1:0] num_to_dispatch;
    logic [$clog2(`N+1)-1:0] num_rds_needed;
    // logic [$clog2(`N+1)-1:0] dispatch_actual_instructions;

    int max_dispatch;
    int num_valid_from_fetch;
    int num_can_dispatch_count;
    int freelist_needed;
    logic destreg_req;

    always_comb begin
        // Count valid instructions from fetch bundle
        num_valid_from_fetch = 0;
        num_rds_needed = 0;
        for (int i = 0; i < `N; i++) begin
            if (fetch_valid[i]) begin
                num_valid_from_fetch++;
                if (fetch_packet.uses_rd[i]) begin
                    num_rds_needed++;
                end
            end 
        end

        // Determine how many instructions we can actually dispatch this cycle
        max_dispatch = num_valid_from_fetch;  // start with all valid

        // Limit by available free slots in ROB, RS, and freelist (for destinations)
        // 2 approach: stall all or dispatch as much as we can
        // 1. Stall all if there's no enough space 
        // 2. Dispatch as much as we could <--- current
        if (free_slots_rob < max_dispatch)      max_dispatch = free_slots_rob;
        if (free_slots_rs  < max_dispatch)      max_dispatch = free_slots_rs;
        if (free_slots_freelst < num_rds_needed) max_dispatch = free_slots_freelst;

        // Actual number of instructions we will dispatch
        num_to_dispatch = max_dispatch;

        // Stall fetch if there are valid instructions but not enough resources to dispatch all
        stall_fetch = (num_valid_from_fetch > 0) && (num_to_dispatch < num_valid_from_fetch);

        // Output
        dispatch_count = num_to_dispatch;
    end

    always_comb begin
        rob_alloc_valid   = '0;
        rs_alloc_valid    = '0;
        free_alloc_valid  = '0;
        maptable_new_pr   = '0;
        maptable_new_ar   = '0;
        reg1_ar           = '0;
        reg2_ar           = '0;
        for(int i = 0; i < dispatch_count; i++) begin
            maptable_new_pr[i] = allocated_phys[i];             // from freelist
            maptable_new_ar[i] = fetch_packet.rd_idx[i];        // architectural dest register
            reg1_ar[i]         = fetch_packet.rs1_idx[i];
            reg2_ar[i]         = fetch_packet.rs2_idx[i];

            // ==================================================
            // 2. ROB Entry Construction
            // ==================================================
            rob_alloc_valid[i] = fetch_valid[i];

            rob_entry_packet[i].valid          = fetch_valid[i];
            rob_entry_packet[i].PC             = fetch_packet.PC[i];
            rob_entry_packet[i].inst           = fetch_packet.inst[i];
            rob_entry_packet[i].arch_rd        = fetch_packet.rd_idx[i];
            rob_entry_packet[i].phys_rd        = maptable_new_pr[i];
            rob_entry_packet[i].prev_phys_rd   = Told_in[i];              // old physical reg from Map Table
            rob_entry_packet[i].value          = '0;
            rob_entry_packet[i].complete       = 1'b0;
            rob_entry_packet[i].exception      = NO_ERROR;
            rob_entry_packet[i].branch         = (fetch_packet.op_type[i] == CAT_BRANCH);
            rob_entry_packet[i].branch_target  = '0;
            rob_entry_packet[i].branch_taken   = 1'b0;
            rob_entry_packet[i].pred_target    = fetch_packet.pred_target[i];
            rob_entry_packet[i].pred_taken     = fetch_packet.pred_taken[i];
            rob_entry_packet[i].halt           = 1'b0;
            rob_entry_packet[i].illegal        = 1'b0;

            // ==================================================
            // 3. RS Entry Construction
            // ==================================================
            rs_alloc_valid[i] = fetch_valid[i];

            rs_alloc_entries[i].valid        = fetch_valid[i];
            rs_alloc_entries[i].op_type      = fetch_packet.op_type[i];
            rs_alloc_entries[i].opa_select   = fetch_packet.opa_select[i];
            rs_alloc_entries[i].opb_select   = fetch_packet.opb_select[i];

            rs_alloc_entries[i].src1_tag     = reg1_tag[i];         // From map table lookup
            rs_alloc_entries[i].src1_ready   = reg1_ready[i];       // From map table or CDB
            //rs_alloc_entries[i].src1_value   = fetch_packet.src1_value[i]; // If immediate/literal

            rs_alloc_entries[i].src2_tag     = reg2_tag[i];         // From map table lookup
            rs_alloc_entries[i].src2_ready   = reg2_ready[i];       // From map table or CDB
            //rs_alloc_entries[i].src2_value   = fetch_packet.src2_value[i]; // If immediate/literal

            rs_alloc_entries[i].dest_tag     = maptable_new_pr[i];  // From free list (new PR)
            rs_alloc_entries[i].rob_idx      = rob_alloc_idxs[i];   // From ROB allocation

            rs_alloc_entries[i].PC           = fetch_packet.PC[i];  // For branch/debug
            rs_alloc_entries[i].pred_taken   = fetch_packet.pred_taken[i];
            rs_alloc_entries[i].pred_target  = fetch_packet.pred_target[i];

            // ==================================================
            // 4. Free List Consumption
            // ==================================================
            free_alloc_valid[i] = fetch_valid[i];
        end
    end
    

endmodule  // stage_dispatch
