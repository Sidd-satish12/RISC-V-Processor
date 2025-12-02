`include "sys_defs.svh"

// Memory module: compute addresses and handle memory operations
// Handles both loads and stores, with store queue interaction and load cache interface
// Purely combinational
module mem_fu (
    input  logic valid,              // Is this FU active?
    input  MEM_FUNC func,            // Memory operation type
    input  DATA rs1,                 // Base register for address
    input  DATA rs2,                 // Data to store (for stores)
    input  DATA imm,                 // Immediate offset from instruction
    input  STOREQ_IDX store_queue_idx, // Store queue index from dispatch (for stores)
    input  PHYS_TAG dest_tag,        // Destination register tag (for loads)
    input  CACHE_DATA cache_hit_data, // Cache hit data from dcache (for loads)

    output DATA addr,                // Effective address (for both loads and stores)
    output DATA data,                // Store data (only meaningful for stores)
    output EXECUTE_STOREQ_ENTRY store_queue_entry,  // Store queue entry
    output CDB_ENTRY cdb_result,      // CDB result for loads that hit cache
    output logic is_load_request,     // Whether this FU needs dcache access for a load
    output D_ADDR dcache_addr         // Dcache address for load requests
);

    always_comb begin
        // Always compute effective address
        addr = rs1 + imm;

        // Store data is always rs2
        data = rs2;

        // Build store queue entry for stores
        if (valid && (func == STORE_BYTE   ||
                      func == STORE_HALF   ||
                      func == STORE_WORD   ||
                      func == STORE_DOUBLE)) begin
            store_queue_entry = '{
                valid: 1'b1,
                addr: addr,                    // effective address
                data: data,                    // store data
                store_queue_idx: store_queue_idx  // index from dispatch
            };
        end else begin
            store_queue_entry = '0;  // Not a store or not valid
        end

        // Build CDB result for loads that hit in cache
        if (valid && cache_hit_data.valid &&
            (func == LOAD_BYTE   || func == LOAD_HALF   || func == LOAD_WORD   ||
             func == LOAD_DOUBLE || func == LOAD_BYTE_U || func == LOAD_HALF_U)) begin
            cdb_result = '{
                valid: 1'b1,
                tag: dest_tag,
                data: cache_hit_data.data
            };
        end else begin
            cdb_result = '0;  // No load hit or not a load
        end

        // Output load request information for dcache
        if (valid && (func == LOAD_BYTE   || func == LOAD_HALF   || func == LOAD_WORD   ||
                      func == LOAD_DOUBLE || func == LOAD_BYTE_U || func == LOAD_HALF_U)) begin
            is_load_request = 1'b1;
            dcache_addr = '{tag: addr[31:12],      // Extract tag from address
                           block_offset: addr[4:3]}; // Extract block offset
        end else begin
            is_load_request = 1'b0;
            dcache_addr = '0;
        end
    end

endmodule  // mem