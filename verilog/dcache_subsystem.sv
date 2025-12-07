`include "verilog/sys_defs.svh"
`include "verilog/ISA.svh"

module dcache_subsystem (
    input clock,
    input reset,

    // Cache read from loads
    input  D_ADDR_PACKET [1:0]  read_addrs,  // read_addr[0] is older operations
    output CACHE_DATA    [1:0]  cache_outs,

    // Data back from memory
    input MEM_TAG               current_data_back_tag,
    input MEM_BLOCK             mem_data_back,
    input MEM_TAG               mem_data_back_tag,

    // Memory read request
    output D_ADDR_PACKET        mem_read_addr,
    input  logic                mem_read_accepted,
    
    // Dirty writebacks on eviction
    output D_ADDR_PACKET        mem_write_addr, // request always accepted
    output MEM_BLOCK            mem_write_data,
    output logic                mem_write_valid,

    // Store request (from Store Queue)
    input logic                 proc_store_valid,
    input ADDR                  proc_store_addr,
    input DATA                  proc_store_data,
    input MEM_SIZE              proc_store_mem_size,
    input ADDR                  proc_store_PC,
    output logic                proc_store_response,  // 1 = Store Complete, 0 = Stall/Retry
    // debug to expose DCache to testbench
    output D_CACHE_LINE [`DCACHE_LINES-1:0]      cache_lines_debug
);

    // Internal wires
    D_ADDR_PACKET dcache_write_addr, dcache_write_addr_refill;
    logic dcache_full;
    D_MSHR_PACKET new_mshr_entry;
    D_CACHE_LINE evicted_line;
    logic evicted_valid;
    CACHE_DATA [1:0] dcache_outs;
    logic mshr_addr_found;  // MSHR already has this address
    logic prefetcher_addr_found_dcache;  // Prefetcher address found in dcache
    logic prefetcher_addr_found_mshr;    // Prefetcher address found in MSHR

    // Store logic signals
    D_ADDR_PACKET store_req_addr;
    logic     store_hit_dcache;
    
    // Prefetcher signals
    D_ADDR_PACKET prefetcher_snooping_addr;
    D_ADDR_PACKET cache_miss_addr;  // Combined miss from loads and stores

    // D-cache write control signals
    D_ADDR_PACKET dcache_write_addr_refill_local;
    logic         dcache_store_en_local;
    MEM_BLOCK     dcache_store_data_local;
    logic [7:0]   dcache_store_byte_en;  // Byte enable mask for sub-word stores

    dcache dcache_inst (
        .clock        (clock),
        .reset        (reset),
        // Fetch Stage read
        .read_addrs   (read_addrs),
        .cache_outs   (dcache_outs),
        // Snoop for store hits
        .snooping_addr(store_req_addr),
        .addr_found   (store_hit_dcache),
        .full         (dcache_full),
        // Snoop for prefetcher addresses
        .prefetch_snooping_addr(prefetcher_snooping_addr),
        .prefetch_addr_found(prefetcher_addr_found_dcache),
        // Dcache write mem_data_back (refill)
        .write_addr   (dcache_write_addr),
        .write_data   (mem_data_back),
        // Dcache Store Update
        .store_en     (dcache_store_en_local),
        .store_addr   (store_req_addr),
        .store_data   (dcache_store_data_local),
        .store_byte_en(dcache_store_byte_en),
        // Eviction interface (for dirty writeback to memory)
        .evicted_line (evicted_line),
        .evicted_valid(evicted_valid),
        // debug to expose DCache to testbench
        .cache_lines_debug(cache_lines_debug)
    );

    // Direct output from dcache (no victim cache)
    assign cache_outs = dcache_outs;

    // Prefetcher module - handles all memory requests (misses + prefetches)
    d_prefetcher d_prefetcher_inst (
        .clock                   (clock),
        .reset                   (reset),
        // Cache miss inputs (loads and stores)
        .cache_miss_addr         (cache_miss_addr),
        .dcache_full             (dcache_full),
        .mem_read_accepted       (mem_read_accepted),
        .current_data_back_tag   (current_data_back_tag),
        // Snooping for prefetch addresses
        .snooping_addr           (prefetcher_snooping_addr),
        .addr_found_dcache       (prefetcher_addr_found_dcache),
        .addr_found_mshr         (prefetcher_addr_found_mshr),
        // Memory request output
        .mem_read_addr           (mem_read_addr)
    );

    d_mshr d_mshr_inst (
        .clock          (clock),
        .reset          (reset),
        // Snoop for duplicate requests (loads, stores, and prefetches)
        .snooping_addr  (prefetcher_snooping_addr.addr),
        .addr_found     (prefetcher_addr_found_mshr),
        // When mem_read_accepted
        .new_entry      (new_mshr_entry),
        // Mem data back
        .mem_data_back_tag   (mem_data_back_tag),
        .mem_data_back_d_addr(dcache_write_addr_refill)
    );

    assign dcache_write_addr_refill_local = dcache_write_addr_refill;

    // D-cache write mux: Refill takes priority
    assign dcache_write_addr = dcache_write_addr_refill_local.valid ? dcache_write_addr_refill_local : '0;

    // Store Request Processing
    // Convert processor store address to cache address format and generate byte enables
    // NOTE: Address breakdown for 8-byte cache lines:
    //   tag = addr[31:3] (29 bits - uniquely identifies 8-byte aligned block)
    //   block_offset = addr[2:0] (3 bits - byte offset within 8-byte line)
    //   word_offset = addr[2] (1 bit - which word: 0=lower, 1=upper)
    always_comb begin
        store_req_addr = '0;
        dcache_store_data_local = '0;
        dcache_store_byte_en = '0;

        if (proc_store_valid) begin
            store_req_addr.valid = 1'b1;
            store_req_addr.addr.tag = proc_store_addr[31:3];        // Full tag
            store_req_addr.addr.block_offset = proc_store_addr[2:0]; // Byte offset within line
            store_req_addr.addr.zeros = '0;

            case (proc_store_mem_size)
                BYTE: begin
                    if (proc_store_addr[2]) begin
                        // Upper word
                        case (proc_store_addr[1:0])
                            2'b00: begin dcache_store_data_local.word_level[1][7:0]   = proc_store_data[7:0];   dcache_store_byte_en = 8'b0001_0000; end
                            2'b01: begin dcache_store_data_local.word_level[1][15:8]  = proc_store_data[7:0];   dcache_store_byte_en = 8'b0010_0000; end
                            2'b10: begin dcache_store_data_local.word_level[1][23:16] = proc_store_data[7:0];   dcache_store_byte_en = 8'b0100_0000; end
                            2'b11: begin dcache_store_data_local.word_level[1][31:24] = proc_store_data[7:0];   dcache_store_byte_en = 8'b1000_0000; end
                        endcase
                    end else begin
                        // Lower word
                        case (proc_store_addr[1:0])
                            2'b00: begin dcache_store_data_local.word_level[0][7:0]   = proc_store_data[7:0];   dcache_store_byte_en = 8'b0000_0001; end
                            2'b01: begin dcache_store_data_local.word_level[0][15:8]  = proc_store_data[7:0];   dcache_store_byte_en = 8'b0000_0010; end
                            2'b10: begin dcache_store_data_local.word_level[0][23:16] = proc_store_data[7:0];   dcache_store_byte_en = 8'b0000_0100; end
                            2'b11: begin dcache_store_data_local.word_level[0][31:24] = proc_store_data[7:0];   dcache_store_byte_en = 8'b0000_1000; end
                        endcase
                    end
                end

                HALF: begin
                    if (proc_store_addr[2]) begin
                        // Upper word
                        if (!proc_store_addr[1]) begin
                            dcache_store_data_local.word_level[1][15:0] = proc_store_data[15:0];
                            dcache_store_byte_en = 8'b0011_0000;
                        end else begin
                            dcache_store_data_local.word_level[1][31:16] = proc_store_data[15:0];
                            dcache_store_byte_en = 8'b1100_0000;
                        end
                    end else begin
                        // Lower word
                        if (!proc_store_addr[1]) begin
                            dcache_store_data_local.word_level[0][15:0] = proc_store_data[15:0];
                            dcache_store_byte_en = 8'b0000_0011;
                        end else begin
                            dcache_store_data_local.word_level[0][31:16] = proc_store_data[15:0];
                            dcache_store_byte_en = 8'b0000_1100;
                        end
                    end
                end

                WORD: begin
                    if (proc_store_addr[2]) begin
                        dcache_store_data_local.word_level[1] = proc_store_data;
                        dcache_store_byte_en = 8'b1111_0000;
                    end else begin
                        dcache_store_data_local.word_level[0] = proc_store_data;
                        dcache_store_byte_en = 8'b0000_1111;
                    end
                end

                DOUBLE: begin
                    // Treat DOUBLE the same as WORD, since proc_store_data is 32 bits
                    if (proc_store_addr[2]) begin
                        dcache_store_data_local.word_level[1] = proc_store_data;
                        dcache_store_byte_en = 8'b1111_0000;
                    end else begin
                        dcache_store_data_local.word_level[0] = proc_store_data;
                        dcache_store_byte_en = 8'b0000_1111;
                    end
                end

                default: begin
                    // fallback to WORD behavior
                    if (proc_store_addr[2]) begin
                        dcache_store_data_local.word_level[1] = proc_store_data;
                        dcache_store_byte_en = 8'b1111_0000;
                    end else begin
                        dcache_store_data_local.word_level[0] = proc_store_data;
                        dcache_store_byte_en = 8'b0000_1111;
                    end
                end
            endcase
        end
    end



    // Store completion logic
    // A store can only complete if the line is already in the cache (hit)
    // If it misses, we request the line and the store will retry next cycle
    always_comb begin
        dcache_store_en_local = 1'b0;
        proc_store_response = 1'b0;

        // Only process stores if NO refill is active (Refill has priority)
        if (proc_store_valid && !dcache_write_addr_refill_local.valid) begin
            if (store_hit_dcache) begin
                // Hit: write to cache and signal completion
                dcache_store_en_local = 1'b1;
                proc_store_response = 1'b1;
            end
            // Miss: response stays 0 (stall), line will be fetched via MSHR
        end
    end

    // Cache miss address logic - prioritize store misses over load misses
    // This is passed to prefetcher which handles all memory requests
    always_comb begin
        cache_miss_addr = '0;
        
        // If store misses the cache, pass to prefetcher
        if (proc_store_valid && !store_hit_dcache) begin
            cache_miss_addr.valid = 1'b1;
            cache_miss_addr.addr.tag = proc_store_addr[31:3];  // Full tag for 8-byte lines
            cache_miss_addr.addr.block_offset = '0;  // Request full line
            cache_miss_addr.addr.zeros = '0;
            cache_miss_addr.PC = proc_store_PC;
        end
        // Otherwise check for load misses
        else if (read_addrs[0].valid && !dcache_outs[0].valid) begin
            cache_miss_addr.valid = 1'b1;
            cache_miss_addr.addr  = read_addrs[0].addr;
            cache_miss_addr.PC   = read_addrs[0].PC;
        end else if (read_addrs[1].valid && !dcache_outs[1].valid) begin
            cache_miss_addr.valid = 1'b1;
            cache_miss_addr.addr  = read_addrs[1].addr;
            cache_miss_addr.PC   = read_addrs[1].PC;
        end
    end

    // Memory write logic - send dirty evictions to memory
    // NOTE: evicted_line and evicted_valid are now REGISTERED in dcache module
    // to capture eviction data before the refill overwrites the cache line
    always_comb begin
        mem_write_valid = evicted_valid && evicted_line.dirty;
        mem_write_addr = '0;
        mem_write_data = '0;
        
        if (mem_write_valid) begin
            mem_write_addr.valid = 1'b1;
            // Reconstruct D_ADDR from stored tag (matches mem_fu.sv format)
            mem_write_addr.addr = '{zeros: 16'b0,
                                   tag: evicted_line.tag,
                                   block_offset: '0};
            mem_write_data = evicted_line.data;
        end
    end

    // Memory read request is now handled by d_prefetcher
    // mem_read_addr is output from d_prefetcher

    // MSHR entry logic - add when request is accepted
    assign new_mshr_entry = (mem_read_accepted && current_data_back_tag != 0) ?
        '{valid: 1'b1, mem_tag: current_data_back_tag, d_addr: mem_read_addr.addr} : '0;

    // D-Cache Subsystem Display - Mem FU Interface
`ifdef DEBUG
    always_ff @(posedge clock) begin
        if (!reset) begin
            $display("========================================");
            $display("=== D-CACHE SUBSYSTEM (Cycle %0t) ===", $time);
            $display("========================================");
            
            // Mem FU Requests
            $display("--- Mem FU Requests ---");
            for (int i = 0; i < 2; i++) begin
                if (read_addrs[i].valid) begin
                    $display("  Read[%0d]: Valid=1 Addr.tag=%h Addr.block_offset=%0d", 
                             i, read_addrs[i].addr.tag, read_addrs[i].addr.block_offset);
                end else begin
                    $display("  Read[%0d]: Valid=0", i);
                end
            end
            
            // Our Responses
            $display("--- Cache Responses ---");
            for (int i = 0; i < 2; i++) begin
                if (cache_outs[i].valid) begin
                    $display("  Out[%0d]: Valid=1 Data=%h", i, cache_outs[i].data.dbbl_level);
                end else begin
                    $display("  Out[%0d]: Valid=0 (miss)", i);
                end
            end
            
            // Memory Requests We're Making
            $display("--- Memory Requests ---");
            if (mem_read_addr.valid) begin
                $display("  Read Request: Valid=1 Addr.tag=%h Addr.block_offset=%0d Accepted=%0d", 
                         mem_read_addr.addr.tag, mem_read_addr.addr.block_offset, mem_read_accepted);
            end else begin
                $display("  Read Request: Valid=0");
            end
            
            // Memory Writebacks
            if (mem_write_valid) begin
                $display("  Writeback: Valid=1 Addr.tag=%h Data=%h", 
                         mem_write_addr.addr.tag, mem_write_data.dbbl_level);
            end else begin
                $display("  Writeback: Valid=0");
            end
            
            // Memory Data Coming Back
            if (mem_data_back_tag != 0) begin
                $display("  Memory Data Returned: Tag=%0d Data=%h", 
                         mem_data_back_tag, mem_data_back.dbbl_level);
            end
            
            // Store Interface
            $display("--- Store Interface ---");
            if (proc_store_valid) begin
                $display("  Store Request: Valid=1 Addr=%h Data=%h Hit=%0d Response=%0d", 
                         proc_store_addr & 32'hFFFFFFF8, proc_store_data, store_hit_dcache, proc_store_response);
            end else begin
                $display("  Store Request: Valid=0");
            end
            
            // MSHR State
            $display("--- MSHR State ---");
            $display("  Cache Miss Addr: Valid=%0d Tag=%h PC=%h", 
                     cache_miss_addr.valid, cache_miss_addr.addr.tag, cache_miss_addr.PC);
            $display("  Prefetcher Snooping: Valid=%0d Tag=%h", 
                     prefetcher_snooping_addr.valid, prefetcher_snooping_addr.addr.tag);
            $display("  Prefetcher Found in DCache: %0d, Found in MSHR: %0d", 
                     prefetcher_addr_found_dcache, prefetcher_addr_found_mshr);
            $display("  Cache Full: %0d", dcache_full);
            
            // Refill State
            if (dcache_write_addr_refill_local.valid) begin
                $display("  Refill: Valid=1 Addr.tag=%h", dcache_write_addr_refill_local.addr.tag);
            end
            
            // Eviction State
            if (evicted_valid) begin
                $display("  Eviction: Valid=1 Dirty=%0d Tag=%h", 
                         evicted_line.dirty, evicted_line.tag);
            end
            
            $display("");
        end
    end
`endif

endmodule

// D-Cache Prefetcher with PC-hashed stride table
// Handles all memory requests (cache misses + prefetches)
module d_prefetcher #(
    parameter PREFETCH_TABLE_SIZE = 32,
    parameter PREFETCH_DEPTH = 6
) (
    input clock,
    input reset,

    // Cache miss input (from loads and stores)
    input D_ADDR_PACKET cache_miss_addr,
    
    // Cache state
    input logic dcache_full,
    
    // Memory interface
    input  logic         mem_read_accepted,
    input  MEM_TAG       current_data_back_tag,
    
    // Snooping interface (check if prefetch address already cached/requested)
    output D_ADDR_PACKET snooping_addr,
    input  logic         addr_found_dcache,
    input  logic         addr_found_mshr,
    
    // Memory request output (handles both misses and prefetches)
    output D_ADDR_PACKET mem_read_addr
);

    // Stride table entry structure
    typedef struct packed {
        logic valid;
        ADDR last_addr;        // Last data address accessed by this PC
        logic [31:0] last_stride; // Learned stride (signed)
        logic [1:0] state;      // State machine: 00=Init, 01=Transient, 10/11=Steady/Confident
    } PREFETCH_ENTRY;

    localparam TABLE_INDEX_BITS = $clog2(PREFETCH_TABLE_SIZE);
    localparam PREFETCH_COUNT_BITS = $clog2(PREFETCH_DEPTH + 1);
    
    // Stride table
    PREFETCH_ENTRY [PREFETCH_TABLE_SIZE-1:0] stride_table, next_stride_table;
    
    // Prefetch state
    logic [PREFETCH_COUNT_BITS-1:0] prefetch_count, next_prefetch_count;
    D_ADDR_PACKET prefetch_base_addr, next_prefetch_base_addr;
    logic [31:0] prefetch_stride, next_prefetch_stride;
    logic prefetch_active, next_prefetch_active;
    
    // PC hashing function: simple hash of PC bits
    function automatic logic [TABLE_INDEX_BITS-1:0] hash_pc(input ADDR pc);
        // Hash PC[7:2] to table index (simple modulo)
        hash_pc = TABLE_INDEX_BITS'(pc[7:2] % PREFETCH_TABLE_SIZE);
    endfunction
    
    // Convert D_ADDR to full byte address for stride calculation
    function automatic ADDR d_addr_to_byte_addr(input D_ADDR addr);
        d_addr_to_byte_addr = {addr.tag, addr.block_offset};
    endfunction
    
    // Calculate stride from two addresses
    function automatic logic [31:0] calculate_stride(input ADDR addr1, input ADDR addr2);
        calculate_stride = $signed(addr1) - $signed(addr2);
    endfunction
    
    // State machine update logic
    function automatic logic [1:0] update_state(
        input logic [1:0] current_state,
        input logic [31:0] current_stride,
        input logic [31:0] new_stride
    );
        if (current_stride == new_stride) begin
            // Stride matches: increment state (saturate at 11)
            if (current_state < 2'b11) begin
                update_state = current_state + 1'b1;
            end else begin
                update_state = current_state;
            end
        end else begin
            // Stride differs: reset to Init (00)
            update_state = 2'b00;
        end
    endfunction
    
    // Check if state allows prefetching (state >= 10)
    function automatic logic can_prefetch(input logic [1:0] state);
        can_prefetch = (state >= 2'b10);
    endfunction

    always_comb begin
        // Default values
        next_stride_table = stride_table;
        next_prefetch_count = prefetch_count;
        next_prefetch_base_addr = prefetch_base_addr;
        next_prefetch_stride = prefetch_stride;
        next_prefetch_active = prefetch_active;
        snooping_addr = '0;
        mem_read_addr = '0;
        
        // Process cache miss: learn stride and update table
        if (cache_miss_addr.valid) begin
            // Convert cache miss address to byte address for stride calculation
            ADDR miss_byte_addr;
            logic [TABLE_INDEX_BITS-1:0] table_idx;
            PREFETCH_ENTRY table_entry;
            
            miss_byte_addr = d_addr_to_byte_addr(cache_miss_addr.addr);
            table_idx = hash_pc(cache_miss_addr.PC);
            table_entry = stride_table[table_idx];
            // Snoop the miss address to check if already in MSHR
            snooping_addr = cache_miss_addr;
            
            if (table_entry.valid) begin
                // Entry exists: calculate stride and update state
                logic [31:0] calculated_stride;
                logic [1:0] new_state;
                
                calculated_stride = calculate_stride(miss_byte_addr, table_entry.last_addr);
                new_state = update_state(table_entry.state, table_entry.last_stride, calculated_stride);
                
                next_stride_table[table_idx].last_stride = calculated_stride;
                next_stride_table[table_idx].state = new_state;
                next_stride_table[table_idx].last_addr = miss_byte_addr;
                
                // If state allows prefetching, start prefetch sequence
                if (can_prefetch(new_state)) begin
                    next_prefetch_active = 1'b1;
                    next_prefetch_base_addr = cache_miss_addr;
                    next_prefetch_stride = calculated_stride;
                    next_prefetch_count = '0;
                end
            end else begin
                // New entry: initialize
                next_stride_table[table_idx].valid = 1'b1;
                next_stride_table[table_idx].last_addr = miss_byte_addr;
                next_stride_table[table_idx].last_stride = '0;
                next_stride_table[table_idx].state = 2'b00;  // Init state
            end
            
            // Request the miss address only if not already in MSHR
            if (!addr_found_mshr) begin
                mem_read_addr = cache_miss_addr;
            end
        end
        // Prefetch logic: continue prefetching if active and conditions met
        else if (prefetch_active && !dcache_full && (prefetch_count < PREFETCH_DEPTH)) begin
            // Calculate next prefetch address
            ADDR next_prefetch_byte_addr;
            D_ADDR next_prefetch_d_addr;
            
            next_prefetch_byte_addr = d_addr_to_byte_addr(prefetch_base_addr.addr) + prefetch_stride;
            next_prefetch_d_addr.tag = next_prefetch_byte_addr[31:3];
            next_prefetch_d_addr.block_offset = next_prefetch_byte_addr[2:0];
            next_prefetch_d_addr.zeros = '0;
            
            snooping_addr.valid = 1'b1;
            snooping_addr.addr = next_prefetch_d_addr;
            snooping_addr.PC = prefetch_base_addr.PC;
            
            // Only send request if not found in dcache or MSHR
            if (!addr_found_dcache && !addr_found_mshr) begin
                mem_read_addr.valid = 1'b1;
                mem_read_addr.addr = next_prefetch_d_addr;
                mem_read_addr.PC = prefetch_base_addr.PC;
                
                if (mem_read_accepted) begin
                    // Update prefetch state
                    next_prefetch_base_addr.addr = next_prefetch_d_addr;
                    next_prefetch_count = prefetch_count + 1'b1;
                end
            end else if (addr_found_dcache || addr_found_mshr) begin
                // Address already cached/requested, skip and continue
                next_prefetch_base_addr.addr = next_prefetch_d_addr;
                next_prefetch_count = prefetch_count + 1'b1;
            end
        end else if (prefetch_active && (dcache_full || (prefetch_count >= PREFETCH_DEPTH))) begin
            // Prefetch complete or cache full: stop prefetching
            next_prefetch_active = 1'b0;
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            stride_table <= '0;
            prefetch_count <= '0;
            prefetch_base_addr <= '0;
            prefetch_stride <= '0;
            prefetch_active <= 1'b0;
        end else begin
            stride_table <= next_stride_table;
            prefetch_count <= next_prefetch_count;
            prefetch_base_addr <= next_prefetch_base_addr;
            prefetch_stride <= next_prefetch_stride;
            prefetch_active <= next_prefetch_active;
        end
    end

endmodule

// D-Cache MSHR (Miss Status Handling Register)
// Tracks outstanding memory requests
module d_mshr #(
    parameter MSHR_WIDTH = `NUM_MEM_TAGS + `N
) (
    input clock,
    input reset,

    // Duplicate request detection
    input  D_ADDR snooping_addr,
    output logic  addr_found,

    // When mem_read_accepted
    input D_MSHR_PACKET new_entry,

    // Mem data back
    input  MEM_TAG       mem_data_back_tag,
    output D_ADDR_PACKET mem_data_back_d_addr
);

    localparam D_CACHE_INDEX_BITS = $clog2(MSHR_WIDTH);
    D_MSHR_PACKET [MSHR_WIDTH-1:0] mshr_entries, next_mshr_entries;
    logic [D_CACHE_INDEX_BITS-1:0] head, next_head, tail, next_tail;

    // Snooping logic - check if address is already in MSHR
    always_comb begin
        addr_found = 1'b0;
        for (int i = 0; i < MSHR_WIDTH; i++) begin
            if (mshr_entries[i].valid && (mshr_entries[i].d_addr.tag == snooping_addr.tag)) begin
                addr_found = 1'b1;
            end
        end
    end

    // MSHR logic
    logic pop_condition, push_condition;
    logic pop_cond_has_data, pop_cond_head_valid, pop_cond_tag_match;
    
    always_comb begin
        next_head = head;
        next_tail = tail;
        mem_data_back_d_addr = '0;
        next_mshr_entries = mshr_entries;

        // Data returned from Memory, Pop MSHR Entry
        pop_cond_has_data = (mem_data_back_tag != '0);
        pop_cond_head_valid = mshr_entries[head].valid;
        pop_cond_tag_match = (mem_data_back_tag == mshr_entries[head].mem_tag);
        pop_condition = pop_cond_has_data && pop_cond_head_valid && pop_cond_tag_match;
        
        if (pop_condition) begin
            next_head = D_CACHE_INDEX_BITS'((head + 1'b1) % MSHR_WIDTH);
            next_mshr_entries[head].valid = '0;
            mem_data_back_d_addr.valid = 1'b1;
            mem_data_back_d_addr.addr = mshr_entries[head].d_addr;
        end

        // New memory request, push new MSHR Entry
        if (new_entry.valid) begin
            next_mshr_entries[tail] = new_entry;
            next_tail = D_CACHE_INDEX_BITS'((tail + 1'b1) % MSHR_WIDTH);
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            head <= 1'b0;
            tail <= 1'b0;
            mshr_entries <= 1'b0;
        end else begin
            head <= next_head;
            tail <= next_tail;
            mshr_entries <= next_mshr_entries;
        end
    end

    // MSHR Debug Display
`ifdef DEBUG
    always_ff @(posedge clock) begin
        if (!reset) begin
            $display("--- D-Cache MSHR State ---");
            $display("  Head: %0d, Tail: %0d", head, tail);
            $display("  Entries:");
            for (int i = 0; i < MSHR_WIDTH; i++) begin
                if (mshr_entries[i].valid) begin
                    $display("    [%0d] Valid=1, MemTag=%0d, DAddr.tag=%h", 
                             i, mshr_entries[i].mem_tag, mshr_entries[i].d_addr.tag);
                end
            end
            if (mem_data_back_tag != 0) begin
                $display("  Memory Data Returned: Tag=%0d", mem_data_back_tag);
            end
            if (new_entry.valid) begin
                $display("  New Entry Pushed: MemTag=%0d, DAddr.tag=%h", 
                         new_entry.mem_tag, new_entry.d_addr.tag);
            end
            $display("");
        end
    end
`endif

endmodule

// D-Cache module - fully associative cache with byte-enable store support
module dcache #(
    parameter MEM_DEPTH = `DCACHE_LINES,
    parameter D_CACHE_INDEX_BITS = $clog2(MEM_DEPTH),
    parameter MEM_WIDTH = 1 + 1 + `DTAG_BITS + `MEM_BLOCK_BITS  // valid + dirty + tag + data
) (
    input clock,
    input reset,

    // Memory operations read
    input D_ADDR_PACKET [1:0] read_addrs,
    output CACHE_DATA [1:0] cache_outs,

    // Store hit snooping
    input  D_ADDR_PACKET snooping_addr,
    output logic         addr_found,
    output logic         full,
    
    // Prefetch snooping
    input  D_ADDR_PACKET prefetch_snooping_addr,
    output logic         prefetch_addr_found,

    // Dcache write (refill from memory)
    input D_ADDR_PACKET write_addr,
    input MEM_BLOCK     write_data,
    
    // Store update interface (byte-granular)
    input logic         store_en,
    input D_ADDR_PACKET store_addr,
    input MEM_BLOCK     store_data,
    input logic [7:0]   store_byte_en,  // Byte enable mask
    
    // Eviction interface
    output D_CACHE_LINE evicted_line,
    output logic        evicted_valid,
    // debug to expose DCache to testbench
    output D_CACHE_LINE [MEM_DEPTH-1:0]      cache_lines_debug
);

    CACHE_DATA [1:0]                  cache_outs_temp;
    D_CACHE_LINE [MEM_DEPTH-1:0]      cache_lines;
    D_CACHE_LINE                      cache_line_write;
    logic [MEM_DEPTH-1:0]             cache_write_enable_mask;
    logic [MEM_DEPTH-1:0]             cache_write_no_evict_one_hot;
    logic [D_CACHE_INDEX_BITS-1:0]    cache_write_evict_index;
    logic [MEM_DEPTH-1:0]             valid_bits;

    // Hit logic for stores
    logic [D_CACHE_INDEX_BITS-1:0]    hit_index;
    logic                             hit_valid;

    assign cache_lines_debug = cache_lines;
    memDP #(
        .WIDTH(MEM_WIDTH),
        .DEPTH(1'b1)
    ) cache_line[MEM_DEPTH-1:0] (
        .clock(clock),
        .reset(reset),
        .re(1'b1),
        .raddr(1'b0),
        .rdata(cache_lines),
        .we(cache_write_enable_mask),
        .waddr(1'b0),
        .wdata(cache_line_write)
    );

    // Write selection - find free slot
    psel_gen #(
        .WIDTH(MEM_DEPTH),
        .REQS(1'b1)
    ) psel_gen_inst (
        .req(~valid_bits),
        .gnt(cache_write_no_evict_one_hot)
    );

    // Pseudo-LRU for replacement policy (only updates on writes)
    logic [D_CACHE_INDEX_BITS-1:0] lru_index;
    logic [D_CACHE_INDEX_BITS-1:0] prefetch_write_index;
    logic prefetch_write_valid;
    
    pseudo_tree_lru #(
        .CACHE_SIZE(MEM_DEPTH),
        .INDEX_BITS(D_CACHE_INDEX_BITS)
    ) lru_inst (
        .clock(clock),
        .reset(reset),
        .write_index(prefetch_write_index),
        .write_valid(prefetch_write_valid),
        .lru_index(lru_index)
    );
    
    assign cache_write_evict_index = lru_index;

    // Hit detection for store snooping
    always_comb begin
        addr_found = 1'b0;
        hit_index = '0;
        hit_valid = 1'b0;
        for (int i = 0; i < MEM_DEPTH; i++) begin
            if (snooping_addr.valid && cache_lines[i].valid && 
                (snooping_addr.addr.tag == cache_lines[i].tag)) begin
                addr_found = 1'b1;
                hit_index = D_CACHE_INDEX_BITS'(i);
                hit_valid = 1'b1;
            end
        end
    end
    
    // Prefetch snooping - check if prefetch address is already in cache
    always_comb begin
        prefetch_addr_found = 1'b0;
        for (int i = 0; i < MEM_DEPTH; i++) begin
            if (prefetch_snooping_addr.valid && cache_lines[i].valid && 
                (prefetch_snooping_addr.addr.tag == cache_lines[i].tag)) begin
                prefetch_addr_found = 1'b1;
            end
        end
    end

    // Full detection
    always_comb begin
        for (int i = 0; i < MEM_DEPTH; i++) begin
            valid_bits[i] = cache_lines[i].valid;
        end
        full = &valid_bits;
    end

    // Cache write logic with byte-enable support for stores
    MEM_BLOCK merged_data;
    
    // Combinational eviction signals (captured BEFORE posedge overwrites cache)
    D_CACHE_LINE evicted_line_comb;
    logic        evicted_valid_comb;
    
    // Convert one-hot free slot selection to index for LRU update
    logic [D_CACHE_INDEX_BITS-1:0] free_slot_index;
    one_hot_to_index #(
        .INPUT_WIDTH(MEM_DEPTH)
    ) one_hot_to_index_inst (
        .one_hot(cache_write_no_evict_one_hot),
        .index(free_slot_index)
    );
    
    always_comb begin
        cache_write_enable_mask = '0;
        cache_line_write = '0;
        evicted_line_comb = '0;
        evicted_valid_comb = 1'b0;
        merged_data = '0;
        prefetch_write_index = '0;
        prefetch_write_valid = 1'b0;

        // Priority 1: Refill (allocating new line from memory)
        if (write_addr.valid) begin
            cache_line_write = '{valid: 1'b1,
                                dirty: 1'b0,  // Data from memory is clean
                                tag: write_addr.addr.tag,
                                data: write_data};
            
            // Try to find a free slot first
            if (|cache_write_no_evict_one_hot) begin
                cache_write_enable_mask = cache_write_no_evict_one_hot;
                prefetch_write_index = free_slot_index;
                prefetch_write_valid = 1'b1;
            end else begin
                // No free slot, evict using LRU-selected index
                cache_write_enable_mask[cache_write_evict_index] = 1'b1;
                evicted_line_comb = cache_lines[cache_write_evict_index];
                evicted_valid_comb = cache_lines[cache_write_evict_index].valid;
                prefetch_write_index = cache_write_evict_index;
                prefetch_write_valid = 1'b1;
            end
        end
        // Priority 2: Store update (hit only - merge with existing data)
        else if (store_en && hit_valid) begin
            cache_write_enable_mask[hit_index] = 1'b1;
            
            // Byte-granular merge: only update bytes enabled by store_byte_en
            merged_data = cache_lines[hit_index].data;
            for (int b = 0; b < 8; b++) begin
                if (store_byte_en[b]) begin
                    merged_data.byte_level[b] = store_data.byte_level[b];
                end
            end

            cache_line_write = '{valid: 1'b1,
                                dirty: cache_lines[hit_index].dirty || (merged_data != cache_lines[hit_index].data),
                                tag: cache_lines[hit_index].tag,
                                data: merged_data};
        end
    end
    
    // Register eviction signals at posedge to capture data BEFORE refill overwrites cache
    // This is necessary because:
    // 1. Eviction data is read combinationally from cache_lines
    // 2. At posedge, memDP writes the refill data to cache_lines[evict_index]
    // 3. After posedge, cache_lines[evict_index] contains NEW data (dirty=0)
    // 4. Memory samples at negedge, so we need stable registered values
    always_ff @(posedge clock) begin
        if (reset) begin
            evicted_line <= '0;
            evicted_valid <= 1'b0;
        end else begin
            evicted_line <= evicted_line_comb;
            evicted_valid <= evicted_valid_comb;
        end
    end

    // Cache read logic
    always_comb begin
        cache_outs_temp = '0;
        for (int j = 0; j < 2; j++) begin
            for (int i = 0; i < MEM_DEPTH; i++) begin
                if (read_addrs[j].valid && cache_lines[i].valid && 
                    (read_addrs[j].addr.tag == cache_lines[i].tag)) begin
                    cache_outs_temp[j].data = cache_lines[i].data;
                    cache_outs_temp[j].valid = 1'b1;
                end
            end
        end
    end
    assign cache_outs = cache_outs_temp;

    // D-Cache State Display
    // Format matches final memory output: @@@ mem[%5d] = %h : %0d
`ifdef DEBUG
    always_ff @(posedge clock) begin
        if (!reset) begin
            logic [31:0] byte_addr;
            $display("========================================");
            $display("=== D-CACHE STATE (Cycle %0t) ===", $time);
            $display("========================================");
            $display("Cache Lines (Total: %0d):", MEM_DEPTH);
            for (int i = 0; i < MEM_DEPTH; i++) begin
                if (cache_lines[i].valid) begin
                    // Convert tag to byte address: tag is addr[31:3], so byte_addr = tag << 3
                    byte_addr = {cache_lines[i].tag, 3'b0};
                    if (cache_lines[i].dirty) begin
                        $display("  [%2d] @@@ mem[%5d] = %016h : %0d (DIRTY)", 
                                 i, byte_addr, cache_lines[i].data.dbbl_level,
                                 cache_lines[i].data.dbbl_level);
                    end else begin
                        $display("  [%2d] @@@ mem[%5d] = %016h : %0d", 
                                 i, byte_addr, cache_lines[i].data.dbbl_level,
                                 cache_lines[i].data.dbbl_level);
                    end
                end else begin
                    $display("  [%2d] (empty)", i);
                end
            end
            $display("Cache Full: %0d", full);
            $display("");
        end
    end
`endif

endmodule
