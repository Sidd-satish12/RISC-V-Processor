`include "sys_defs.svh"

// Memory Functional Unit: handles load/store operations
// Single-register design per user spec:
//   - FU handles ONE instruction at a time (load OR store)
//   - While waiting for data: send dcache requests every cycle
//   - When data arrives: store in register, stop dcache requests, stay BUSY
//   - Drive cdb_request when data is ready
//   - When CDB grants: clear register NEXT cycle, mark available SAME cycle
module mem_fu #(
    parameter FU_ID = 0  // For debug identification
) (
    input clock,
    input reset,
    input logic valid,
    input MEM_FUNC func,
    input DATA rs1,
    input DATA rs2,
    input DATA imm,
    input STOREQ_IDX store_queue_idx,
    input PHYS_TAG dest_tag,
    input ROB_IDX rob_idx,
    input CACHE_DATA cache_hit_data,

    // Store-to-load forwarding
    input logic forward_valid,
    input DATA  forward_data,
    input logic forward_stall,  // Unused, kept for interface compatibility

    // CDB interface
    input logic grant,
    output CDB_ENTRY cdb_result,
    output logic cdb_request,

    // Address/data outputs
    output DATA addr,
    output DATA data,
    output EXECUTE_STOREQ_ENTRY store_queue_entry,
    output logic is_load_request,
    output logic is_store_op,
    output D_ADDR dcache_addr,

    // Store queue forwarding lookup
    output logic lookup_valid,
    output ADDR  lookup_addr,
    output STOREQ_IDX lookup_sq_tail,

    // ROB index output (for pending loads)
    output ROB_IDX rob_idx_out
);

    // =========================================================================
    // Single register to track the current instruction
    // =========================================================================
    typedef struct packed {
        logic       valid;          // Is there an instruction in this FU?
        logic       has_data;       // Has the data been received (for loads)?
        PHYS_TAG    dest_tag;       // Destination physical register
        ROB_IDX     rob_idx;        // ROB index for completion
        ADDR        full_addr;      // Computed address
        DATA        result_data;    // The result data (for loads)
        STOREQ_IDX  sq_tail;        // Store queue index
        MEM_FUNC    op_func;        // Operation type
    } FU_REG;

    FU_REG fu_reg, fu_reg_next;

    // =========================================================================
    // Combinational signals
    // =========================================================================
    ADDR computed_addr;
    logic is_load, is_store;
    logic data_available;       // Cache hit or forwarding provides data
    logic waiting_for_data;     // Load is waiting for cache data
    logic ready_for_cdb;        // Result ready, waiting for CDB grant

    // Load data extraction
    DATA loaded_word, final_load_data;
    logic word_select;
    logic [1:0] byte_offset;
    logic [7:0] byte_val;
    logic [15:0] half_val;

    // =========================================================================
    // Main combinational logic
    // =========================================================================
    always_comb begin
        // Address computation (for new instructions)
        computed_addr = rs1 + imm;
        addr = computed_addr;
        data = rs2;

        // Operation type detection (for new instructions)
        is_load = func inside {LOAD_BYTE, LOAD_HALF, LOAD_WORD, LOAD_DOUBLE, LOAD_BYTE_U, LOAD_HALF_U};
        is_store = func inside {STORE_BYTE, STORE_HALF, STORE_WORD, STORE_DOUBLE};

        // Data availability from cache or forwarding
        data_available = cache_hit_data.valid || forward_valid;

        // FU state
        waiting_for_data = fu_reg.valid && !fu_reg.has_data;
        ready_for_cdb = fu_reg.valid && fu_reg.has_data;

        // =====================================================================
        // Load data extraction
        // =====================================================================
        // Use stored address for pending loads, computed address for new loads
        word_select = fu_reg.valid ? fu_reg.full_addr[2] : computed_addr[2];
        byte_offset = fu_reg.valid ? fu_reg.full_addr[1:0] : computed_addr[1:0];

        // Select word from cache line or use forwarded data
        if (forward_valid) begin
            loaded_word = forward_data;
        end else if (cache_hit_data.valid) begin
            loaded_word = word_select ? cache_hit_data.data.word_level[1]
                                      : cache_hit_data.data.word_level[0];
        end else begin
            loaded_word = '0;
        end

        // Extract byte/half from word (use stored func for pending, input func for new)
        byte_val = loaded_word >> (8 * byte_offset);
        half_val = byte_offset[1] ? loaded_word[31:16] : loaded_word[15:0];

        // Apply size/sign extension based on operation type
        case (fu_reg.valid ? fu_reg.op_func : func)
            LOAD_BYTE:   final_load_data = {{24{byte_val[7]}}, byte_val};
            LOAD_BYTE_U: final_load_data = {24'b0, byte_val};
            LOAD_HALF:   final_load_data = {{16{half_val[15]}}, half_val};
            LOAD_HALF_U: final_load_data = {16'b0, half_val};
            default:     final_load_data = loaded_word;
        endcase

        // =====================================================================
        // Store queue entry (for new stores)
        // =====================================================================
        store_queue_entry = (valid && is_store && !fu_reg.valid) ? '{
            valid: 1'b1,
            addr: computed_addr,
            data: rs2,
            store_queue_idx: store_queue_idx
        } : '0;
        is_store_op = valid && is_store && !fu_reg.valid;

        // =====================================================================
        // Store queue forwarding lookup
        // =====================================================================
        if (waiting_for_data) begin
            lookup_valid   = 1'b1;
            lookup_addr    = fu_reg.full_addr;
            lookup_sq_tail = fu_reg.sq_tail;
        end else if (valid && is_load && !fu_reg.valid) begin
            lookup_valid   = 1'b1;
            lookup_addr    = computed_addr;
            lookup_sq_tail = store_queue_idx;
        end else begin
            lookup_valid   = 1'b0;
            lookup_addr    = '0;
            lookup_sq_tail = '0;
        end

        // =====================================================================
        // Dcache request
        // IMPORTANT: Do NOT use data_available here - it creates a combinational loop:
        //   is_load_request -> mem_fu_to_dcache_slot -> cache_hit_data -> data_available -> is_load_request
        // Instead, use registered state (fu_reg.has_data) to decide when to stop requesting.
        // =====================================================================
        if (fu_reg.valid && !fu_reg.has_data && !forward_valid) begin
            // Pending load still waiting for cache - request every cycle until has_data
            is_load_request = 1'b1;
            dcache_addr = '{zeros: 16'b0, tag: fu_reg.full_addr[31:3], block_offset: fu_reg.full_addr[2:0]};
        end else if (valid && is_load && !fu_reg.valid && !forward_valid) begin
            // New load arriving - always request on first cycle
            is_load_request = 1'b1;
            dcache_addr = '{zeros: 16'b0, tag: computed_addr[31:3], block_offset: computed_addr[2:0]};
        end else begin
            is_load_request = 1'b0;
            dcache_addr = '0;
        end

        // =====================================================================
        // FU register state machine
        // =====================================================================
        fu_reg_next = fu_reg;
        cdb_result = '0;
        cdb_request = 1'b0;

        if (fu_reg.valid) begin
            // FU is busy with an instruction
            if (fu_reg.has_data) begin
                // Has data, waiting for CDB grant
                if (grant) begin
                    // CDB granted - clear register for NEXT cycle
                    // Allocator will mark us available in SAME cycle (via fu_grants)
                    // IMPORTANT: Still drive result this cycle so CDB can broadcast it
                    cdb_result = '{valid: 1'b1, tag: fu_reg.dest_tag, data: fu_reg.result_data};
                    // Do NOT request again - we're done with this instruction
                    cdb_request = 1'b0;
                    fu_reg_next.valid = 1'b0;
                    fu_reg_next.has_data = 1'b0;
                end else begin
                    // Not granted yet, keep requesting
                    cdb_result = '{valid: 1'b1, tag: fu_reg.dest_tag, data: fu_reg.result_data};
                    cdb_request = 1'b1;
                end
            end else begin
                // Waiting for data (load)
                if (data_available) begin
                    // Data arrived! Store it and request CDB
                    fu_reg_next.has_data = 1'b1;
                    fu_reg_next.result_data = final_load_data;
                    // Drive CDB request this cycle (grant won't come until next cycle at earliest)
                    cdb_result = '{valid: 1'b1, tag: fu_reg.dest_tag, data: final_load_data};
                    cdb_request = 1'b1;
                    // Note: Don't check grant here - any grant would be stale since we 
                    // weren't requesting in the previous cycle (was waiting for data)
                end
            end
        end else if (valid) begin
            // FU is idle, accept new instruction
            // IMPORTANT: Do NOT check 'grant' here - it's STALE from a previous instruction!
            // The grant signal is registered and reflects the previous cycle's CDB decision.
            // When fu_reg.valid=0, any grant is for an instruction we've already handled.
            if (is_load) begin
                if (data_available) begin
                    // Load with immediate cache hit - go directly to waiting for CDB
                    fu_reg_next = '{
                        valid: 1'b1,
                        has_data: 1'b1,
                        dest_tag: dest_tag,
                        rob_idx: rob_idx,
                        full_addr: computed_addr,
                        result_data: final_load_data,
                        sq_tail: store_queue_idx,
                        op_func: func
                    };
                    cdb_result = '{valid: 1'b1, tag: dest_tag, data: final_load_data};
                    cdb_request = 1'b1;
                    // Grant will come next cycle - don't check stale grant here
                end else begin
                    // Load with cache miss - wait for data
                    fu_reg_next = '{
                        valid: 1'b1,
                        has_data: 1'b0,
                        dest_tag: dest_tag,
                        rob_idx: rob_idx,
                        full_addr: computed_addr,
                        result_data: '0,
                        sq_tail: store_queue_idx,
                        op_func: func
                    };
                end
            end else if (is_store) begin
                // Store - immediately ready for CDB (no data to wait for)
                fu_reg_next = '{
                    valid: 1'b1,
                    has_data: 1'b1,
                    dest_tag: '0,  // Stores don't write to a register
                    rob_idx: rob_idx,
                    full_addr: computed_addr,
                    result_data: '0,
                    sq_tail: store_queue_idx,
                    op_func: func
                };
                cdb_result = '{valid: 1'b1, tag: '0, data: '0};
                cdb_request = 1'b1;
                // Grant will come next cycle - don't check stale grant here
            end
        end

        // =====================================================================
        // ROB index output
        // =====================================================================
        rob_idx_out = fu_reg.valid ? fu_reg.rob_idx : rob_idx;
    end

    // =========================================================================
    // Sequential state update
    // =========================================================================
    always_ff @(posedge clock) begin
        if (reset) begin
            fu_reg <= '0;
        end else begin
            fu_reg <= fu_reg_next;
        end
    end

    // =========================================================================
    // Debug Display
    // =========================================================================
`ifdef DEBUG
    always_ff @(posedge clock) begin
        if (!reset && (valid || fu_reg.valid)) begin
            $display("========================================");
            $display("=== MEM_FU[%0d] STATE (Cycle %0t) ===", FU_ID, $time);
            $display("========================================");
            
            // Input signals
            $display("--- Inputs ---");
            $display("  valid=%0d func=%0d dest_tag=p%0d rob_idx=%0d sq_idx=%0d",
                     valid, func, dest_tag, rob_idx, store_queue_idx);
            $display("  rs1=%h rs2=%h imm=%h -> computed_addr=%h",
                     rs1, rs2, imm, computed_addr);
            $display("  is_load=%0d is_store=%0d", is_load, is_store);
            
            // Cache/forwarding inputs
            $display("--- Cache/Forwarding ---");
            $display("  cache_hit_data.valid=%0d cache_hit_data.data=%h",
                     cache_hit_data.valid, cache_hit_data.data);
            $display("  forward_valid=%0d forward_data=%h",
                     forward_valid, forward_data);
            $display("  data_available=%0d", data_available);
            
            // FU register state
            $display("--- FU Register ---");
            $display("  fu_reg.valid=%0d has_data=%0d dest_tag=p%0d rob_idx=%0d",
                     fu_reg.valid, fu_reg.has_data, fu_reg.dest_tag, fu_reg.rob_idx);
            $display("  fu_reg.addr=%h result_data=%h",
                     fu_reg.full_addr, fu_reg.result_data);
            $display("  waiting_for_data=%0d ready_for_cdb=%0d",
                     waiting_for_data, ready_for_cdb);
            
            // CDB interface
            $display("--- CDB Interface ---");
            $display("  cdb_request=%0d grant=%0d", cdb_request, grant);
            $display("  cdb_result.valid=%0d tag=p%0d data=%h",
                     cdb_result.valid, cdb_result.tag, cdb_result.data);
            
            // Outputs
            $display("--- Outputs ---");
            $display("  rob_idx_out=%0d is_load_request=%0d",
                     rob_idx_out, is_load_request);
            
            $display("");
        end
    end
`endif

endmodule
