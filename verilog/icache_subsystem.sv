/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  icache_subsystem.sv                                 //
//                                                                     //
//  Description :  Non-blocking instruction cache subsystem with MSHR, //
//                 prefetcher (with integrated stream buffer), and     //
//                 2-way banked icache.                                //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

// ============================================================================
// Main ICache Subsystem Module
// ============================================================================
module icache_subsystem (
    input clock,
    input reset,

    // From memory (via arbiter)
    input MEM_TAG   Imem2proc_transaction_tag,  // Memory accepted request with this tag (0 = rejected)
    input MEM_BLOCK Imem2proc_data,             // Data returning from memory
    input MEM_TAG   Imem2proc_data_tag,         // Tag for returned data (0 = no data)

    // From arbiter
    input logic arbiter_accept,                 // Arbiter accepted our memory request this cycle

    // From victim cache (external module)
    input logic      victim_cache_hit,
    input MEM_BLOCK  victim_cache_data,

    // From fetch stage
    input ADDR proc2Icache_addr,
    
    // To arbiter (for memory requests)
    output logic        mem_req_valid,          // Request to send to memory
    output ADDR         mem_req_addr,           // Address for memory request
    output MEM_COMMAND  mem_req_command,        // Memory command (MEM_LOAD)

    // To victim cache (for lookup)
    output ADDR victim_cache_lookup_addr,

    // To fetch stage
    output MEM_BLOCK Icache_data_out,           // Instruction data output
    output logic     Icache_valid_out           // Data is valid
);

    // Internal signals between submodules
    // TODO: Wire up connections between icache, prefetcher, MSHR

endmodule


// ============================================================================
// ICache (2-way banked, fully associative per bank)
// ============================================================================
// Two memDP modules for odd/even banking to support 2 simultaneous reads
// Each bank is fully associative (16 lines per bank = 32 total lines)
// Uses LFSR for pseudo-random replacement policy within each bank
module icache (
    input clock,
    input reset,

    // Lookup interface from fetch stage
    input ADDR       lookup_addr,
    output logic     cache_hit,
    output MEM_BLOCK cache_data,

    // Fill interface from MSHR (when data returns from memory)
    input logic      fill_en,
    input ADDR       fill_addr,
    input MEM_BLOCK  fill_data,

    // Eviction interface to victim cache
    output logic     evict_valid,
    output ADDR      evict_addr,
    output MEM_BLOCK evict_data
);

    // Internal: 2 memDP modules (one per bank)
    // Bank 0: 16 lines, fully associative (addr[3] = 0, even lines)
    // Bank 1: 16 lines, fully associative (addr[3] = 1, odd lines)
    // Each bank uses LFSR for replacement
    // TODO: Instantiate memDP modules, tag arrays, and LFSR

endmodule


// ============================================================================
// Miss Status Handling Register (MSHR)
// ============================================================================
// Uses psel_gen for efficient allocation of MSHR entries
module mshr (
    input clock,
    input reset,

    // Allocation requests (from cache miss path and prefetcher)
    input logic [1:0] alloc_req,                // [1]=prefetch, [0]=demand
    input ADDR        alloc_addr_demand,
    input ADDR        alloc_addr_prefetch,

    // From arbiter
    input logic       arbiter_accept,           // Arbiter accepted our request

    // From memory
    input MEM_TAG     Imem2proc_transaction_tag,
    input MEM_TAG     Imem2proc_data_tag,
    input MEM_BLOCK   Imem2proc_data,

    // To arbiter (memory request)
    output logic      mem_req_valid,
    output ADDR       mem_req_addr,

    // MSHR status
    output logic      mshr_full,
    output logic [3:0] mshr_occupancy,

    // Lookup interface (check if address already pending)
    input ADDR        lookup_addr,
    output logic      lookup_hit,               // Address already in MSHR

    // Data output when ready
    output logic      data_valid,
    output ADDR       data_addr,
    output MEM_BLOCK  data_block,
    output logic      data_is_prefetch
);

    // Internal: psel_gen for MSHR entry allocation
    // TODO: Instantiate psel_gen for allocating free MSHR entries

endmodule


// ============================================================================
// Prefetcher (with integrated stream buffer)
// ============================================================================
// Simple next-line sequential prefetcher with 4-entry stream buffer
// Stream buffer holds prefetched data before promotion to main cache
module prefetcher (
    input clock,
    input reset,

    // From fetch stage (monitor access pattern)
    input ADDR  fetch_addr,

    // Lookup interface (checked on cache miss)
    input ADDR       lookup_addr,
    output logic     prefetch_hit,              // Address found in stream buffer
    output MEM_BLOCK prefetch_data,             // Data from stream buffer

    // Fill interface from MSHR (when prefetch data returns)
    input logic      fill_en,
    input ADDR       fill_addr,
    input MEM_BLOCK  fill_data,

    // Prefetch request output (to MSHR)
    output logic     prefetch_req_valid,
    output ADDR      prefetch_req_addr,

    // Status
    output logic     stream_buffer_full
);

    // Internal: 4-entry stream buffer (holds prefetched lines)
    // TODO: Implement stream buffer storage and prefetch generation logic

endmodule


// ============================================================================
// LFSR (Linear Feedback Shift Register for pseudo-random replacement)
// ============================================================================
// Used for replacement policy in fully associative cache banks
// Each bank has 16 lines, so needs 4-bit LFSR to select replacement victim
module lfsr #(
    parameter WIDTH = 4
)(
    input clock,
    input reset,
    input logic shift_en,

    output logic [WIDTH-1:0] lfsr_out
);

    // TODO: Implement LFSR with appropriate feedback polynomial

endmodule

