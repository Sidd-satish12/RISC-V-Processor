`include "sys_defs.svh"

// Memory Functional Unit: handles load/store address computation and data path
// Two-state design:
//   - pending_load: tracks loads waiting for cache data
//   - pending_result: holds completed result until CDB grant
module mem_fu (
    input clock,
    input reset,
    input logic valid,
    input MEM_FUNC func,
    input DATA rs1,
    input DATA rs2,
    input DATA imm,
    input STOREQ_IDX store_queue_idx,
    input PHYS_TAG dest_tag,
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
    output STOREQ_IDX lookup_sq_tail
);

    // =========================================================================
    // State definitions
    // =========================================================================
    typedef struct packed {
        logic valid;
        PHYS_TAG dest_tag;
        ADDR full_addr;
        STOREQ_IDX sq_tail;
    } PENDING_LOAD;

    PENDING_LOAD pending_load, pending_load_next;
    CDB_ENTRY pending_result, pending_result_next;

    // =========================================================================
    // Combinational signals
    // =========================================================================
    ADDR computed_addr;
    logic is_load, is_store;
    logic data_available;      // Cache hit or forwarding provides data
    logic pending_load_hit;    // Pending load now has data
    logic load_completes;      // Any load completing this cycle

    // Load data extraction
    DATA loaded_word, final_load_data;
    ADDR addr_for_extract;
    logic word_select;
    logic [1:0] byte_offset;
    logic [7:0] byte_val;
    logic [15:0] half_val;

    // =========================================================================
    // Main combinational logic
    // =========================================================================
    always_comb begin
        // Address computation
        computed_addr = rs1 + imm;
        addr = computed_addr;
        data = rs2;

        // Operation type
        is_load = func inside {LOAD_BYTE, LOAD_HALF, LOAD_WORD, LOAD_DOUBLE, LOAD_BYTE_U, LOAD_HALF_U};
        is_store = func inside {STORE_BYTE, STORE_HALF, STORE_WORD, STORE_DOUBLE};

        // Data availability
        data_available = cache_hit_data.valid || forward_valid;
        pending_load_hit = pending_load.valid && data_available;
        load_completes = pending_load_hit || (valid && is_load && data_available);

        // =====================================================================
        // Load data extraction (from cache or forwarding)
        // =====================================================================
        addr_for_extract = pending_load.valid ? pending_load.full_addr : computed_addr;
        word_select = addr_for_extract[2];
        byte_offset = addr_for_extract[1:0];

        // Select word from cache line or use forwarded data
        if (forward_valid) begin
            loaded_word = forward_data;
        end else if (cache_hit_data.valid) begin
            loaded_word = word_select ? cache_hit_data.data.word_level[1]
                                      : cache_hit_data.data.word_level[0];
        end else begin
            loaded_word = '0;
        end

        // Extract byte/half from word
        byte_val = loaded_word >> (8 * byte_offset);
        half_val = byte_offset[1] ? loaded_word[31:16] : loaded_word[15:0];

        // Apply size/sign extension
        case (func)
            LOAD_BYTE:   final_load_data = {{24{byte_val[7]}}, byte_val};
            LOAD_BYTE_U: final_load_data = {24'b0, byte_val};
            LOAD_HALF:   final_load_data = {{16{half_val[15]}}, half_val};
            LOAD_HALF_U: final_load_data = {16'b0, half_val};
            default:     final_load_data = loaded_word;
        endcase

        // =====================================================================
        // Store queue entry (for stores)
        // =====================================================================
        store_queue_entry = (valid && is_store) ? '{
            valid: 1'b1,
            addr: computed_addr,
            data: rs2,
            store_queue_idx: store_queue_idx
        } : '0;
        is_store_op = valid && is_store;

        // =====================================================================
        // Store queue forwarding lookup
        // =====================================================================
        if (valid && is_load) begin
            lookup_valid   = 1'b1;
            lookup_addr    = computed_addr;
            lookup_sq_tail = store_queue_idx;
        end else if (pending_load.valid) begin
            lookup_valid   = 1'b1;
            lookup_addr    = pending_load.full_addr;
            lookup_sq_tail = pending_load.sq_tail;
        end else begin
            lookup_valid   = 1'b0;
            lookup_addr    = '0;
            lookup_sq_tail = '0;
        end

        // =====================================================================
        // Dcache request
        // =====================================================================
        if (valid && is_load && !forward_valid) begin
            is_load_request = 1'b1;
            dcache_addr = '{zeros: 16'b0, tag: computed_addr[31:3], block_offset: computed_addr[2:0]};
        end else if (pending_load.valid && !forward_valid) begin
            is_load_request = 1'b1;
            dcache_addr = '{zeros: 16'b0, tag: pending_load.full_addr[31:3], block_offset: pending_load.full_addr[2:0]};
        end else begin
            is_load_request = 1'b0;
            dcache_addr = '0;
        end

        // =====================================================================
        // CDB result and request (with pending_result holding)
        // =====================================================================
        cdb_result = '0;
        cdb_request = 1'b0;
        pending_result_next = pending_result;

        if (pending_result.valid) begin
            // Already have a result waiting for grant
            cdb_result = pending_result;
            cdb_request = 1'b1;
            if (grant)
                pending_result_next.valid = 1'b0;
        end else if (pending_load_hit) begin
            // Pending load completes
            pending_result_next = '{valid: 1'b1, tag: pending_load.dest_tag, data: final_load_data};
            cdb_result = pending_result_next;
            cdb_request = 1'b1;
        end else if (valid && is_load && data_available) begin
            // New load completes immediately
            pending_result_next = '{valid: 1'b1, tag: dest_tag, data: final_load_data};
            cdb_result = pending_result_next;
            cdb_request = 1'b1;
        end else if (valid && is_store) begin
            // Store completes (no data result, just needs CDB slot)
            pending_result_next = '{valid: 1'b1, tag: '0, data: '0};
            cdb_result = pending_result_next;
            cdb_request = 1'b1;
        end

        // =====================================================================
        // Pending load state
        // =====================================================================
        pending_load_next = pending_load;

        if (pending_load_hit) begin
            pending_load_next.valid = 1'b0;
        end else if (valid && is_load && !data_available && !pending_load.valid) begin
            pending_load_next = '{
                valid: 1'b1,
                dest_tag: dest_tag,
                full_addr: computed_addr,
                sq_tail: store_queue_idx
            };
        end
    end

    // =========================================================================
    // Sequential state update
    // =========================================================================
    always_ff @(posedge clock) begin
        if (reset) begin
            pending_load   <= '0;
            pending_result <= '0;
        end else begin
            pending_load   <= pending_load_next;
            pending_result <= pending_result_next;
        end
    end

endmodule
