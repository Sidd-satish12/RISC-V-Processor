/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  rs.sv                                               //
//                                                                     //
//  Description :  Reservation Station module; holds up to RS_SZ       //
//                 instructions waiting for operands to become ready.  //
//                 Supports allocation of new entries from dispatch,   //
//                 wakeup via CDB broadcasts from complete, clearing   //
//                 of issued entries from issue, and flushing of       //
//                 speculative entries on branch mispredictions.       //
//                 Entries are allocated to the lowest available       //
//                 indices to approximate age ordering. Issue selects  //
//                 ready entries preferring lower indices.            //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"

// Parameters and typedefs are now centrally defined in sys_defs.svh

// RS entry structure (extended for full control signals)
typedef struct packed {
    logic valid;               // Entry occupied
    ALU_OPA_SELECT opa_select; // From decode
    ALU_OPB_SELECT opb_select; // From decode
    ALU_FUNC alu_func;         // From decode
    logic mult;                // Is multiply?
    logic rd_mem;              // Load?
    logic wr_mem;              // Store?
    logic cond_branch;         // Conditional branch?
    logic uncond_branch;       // Unconditional branch?
    PHYS_TAG src1_tag;         // Physical source 1 tag
    logic src1_ready;          // Source 1 ready
    DATA src1_value;           // Source 1 value if ready
    PHYS_TAG src2_tag;         // Physical source 2 tag
    logic src2_ready;          // Source 2 ready
    DATA src2_value;           // Source 2 value if ready
    PHYS_TAG dest_tag;         // Physical destination tag
    ROB_IDX rob_idx;           // Associated ROB index (for flush and potential age selection)
    ADDR PC;                   // PC for branch/debug
    // Added for branches (prediction info from fetch via dispatch)
    logic pred_taken;
    ADDR pred_target;
    // Added for mem ops (from decode)
    MEM_SIZE mem_size;
    logic mem_unsigned;
} RS_ENTRY;

// CDB packet (from complete, for wakeup)
typedef struct packed {
    logic [`CDB_SZ-1:0] valid;  // Valid broadcasts this cycle
    PHYS_TAG [`CDB_SZ-1:0] tags;  // Physical dest tags
    DATA [`CDB_SZ-1:0] values;    // Computed values
} CDB_PACKET;

module rs (
    input              clock,           // system clock
    input              reset,           // system reset

    // From dispatch: allocation signals
    input logic [`N-1:0] alloc_valid,   // Valid allocations this cycle
    input RS_ENTRY [`N-1:0] alloc_entries,  // New entries to allocate

    // From complete: CDB broadcasts for operand wakeup
    input CDB_PACKET   cdb_broadcast,

    // From issue: clear signals for issued entries
    input logic [`N-1:0] clear_valid,   // Valid clears this cycle
    input RS_IDX [`N-1:0] clear_idxs,   // RS indices to clear

    // From execute: mispredict flush signal
    input logic        mispredict,      // Mispredict detected (flush speculative)
    input ROB_IDX      mispred_rob_idx, // ROB index of mispredicted branch

    // Outputs to issue/dispatch
    output RS_ENTRY [`RS_SZ-1:0] entries,  // Full RS entries for issue selection
    output logic [$clog2(`RS_SZ+1)-1:0] free_count  // Number of free entries (for dispatch stall)
);

    // Internal storage: array of RS entries
    RS_ENTRY [`RS_SZ-1:0] rs_array, rs_array_next;

    // Combinational logic for free count
    always_comb begin
        free_count = 0;
        for (int i = 0; i < `RS_SZ; i++) begin
            if (!rs_array[i].valid) free_count += 1;
        end
    end

    // Output the current RS array
    assign entries = rs_array;

    // Sequential logic for updates: wakeup, clear, alloc, flush
    always_comb begin
        rs_array_next = rs_array;

        // Step 1: Wakeup operands via CDB (associative tag match)
        for (int i = 0; i < `RS_SZ; i++) begin
            if (rs_array_next[i].valid) begin
                // Check src1
                if (!rs_array_next[i].src1_ready) begin
                    for (int c = 0; c < `CDB_SZ; c++) begin
                        if (cdb_broadcast.valid[c] && cdb_broadcast.tags[c] == rs_array_next[i].src1_tag) begin
                            rs_array_next[i].src1_ready = 1'b1;
                            rs_array_next[i].src1_value = cdb_broadcast.values[c];
                        end
                    end
                end
                // Check src2
                if (!rs_array_next[i].src2_ready) begin
                    for (int c = 0; c < `CDB_SZ; c++) begin
                        if (cdb_broadcast.valid[c] && cdb_broadcast.tags[c] == rs_array_next[i].src2_tag) begin
                            rs_array_next[i].src2_ready = 1'b1;
                            rs_array_next[i].src2_value = cdb_broadcast.values[c];
                        end
                    end
                end
            end
        end

        // Step 2: Clear issued entries
        for (int c = 0; c < `N; c++) begin
            if (clear_valid[c]) begin
                rs_array_next[clear_idxs[c]].valid = 1'b0;
            end
        end

        // Step 3: Allocate new entries into lowest free indices
        int alloc_cnt = 0;
        for (int i = 0; i < `RS_SZ; i++) begin
            if (!rs_array_next[i].valid && alloc_cnt < `N && alloc_valid[alloc_cnt]) begin
                rs_array_next[i] = alloc_entries[alloc_cnt];
                alloc_cnt++;
            end
        end

        // Step 4: Flush speculative entries on mispredict
        if (mispredict) begin
            for (int i = 0; i < `RS_SZ; i++) begin
                if (rs_array_next[i].valid && (rs_array_next[i].rob_idx > mispred_rob_idx)) begin
                    rs_array_next[i].valid = 1'b0;
                end
            end
        end
    end

    // Clocked update
    always_ff @(posedge clock) begin
        if (reset) begin
            for (int i = 0; i < `RS_SZ; i++) begin
                rs_array[i].valid <= 1'b0;
            end
        end else begin
            rs_array <= rs_array_next;
        end
    end

endmodule // rs