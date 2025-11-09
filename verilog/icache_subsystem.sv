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
    input I_ADDR       read_addr,
    output CACHE_DATA  cache_out, // cache hit, if cache_out.valid == 1

    // Fill interface from MSHR (when data returns from memory)
    // Instruction fetch never have to wrtie back
    input logic      write_en,
    input I_ADDR     write_addr,
    input MEM_BLOCK  write_data,

    // Eviction interface to victim cache
    output ADDR      evict_addr,
    output CACHE_DATA evict_data
);

    MEM_BLOCK bank0_data_out, bank1_data_out, cache_in;
    logic [1:0][(`ICACHE_LINES/`ICACHE_ASSOC)-1:0] valids;
    logic [1:0][(`ICACHE_LINES/`ICACHE_ASSOC)-1:0] tags [`ITAG_BITS-1:0];
    
    // Bank 0: 16 lines, fully associative (addr[3] = 0, even lines)
    memDP #(
        .WIDTH     ($bits(MEM_BLOCK)),
        .DEPTH     (`ICACHE_LINES / `ICACHE_ASSOC),
        .READ_PORTS(1),
        .BYPASS_EN (0)
    ) bank0 (
        .clock(clock),
        .reset(reset),
        .re   (1'b1),
        .raddr(read_addr.index),
        .rdata(bank0_data_out),
        .we   (write_en && ~write_addr.bank),
        .waddr(), // fully associative so write can't depend on index
        .wdata(cache_in)
    );

    // Bank 1: 16 lines, fully associative (addr[3] = 1, odd lines)
    memDP #(
        .WIDTH     ($bits(MEM_BLOCK)),
        .DEPTH     (`ICACHE_LINES / `ICACHE_ASSOC),
        .READ_PORTS(1),
        .BYPASS_EN (0)
    ) bank1 (
        .clock(clock),
        .reset(reset),
        .re   (1'b1),
        .raddr(read_addr.index),
        .rdata(bank1_data_out),
        .we   (write_en && write_addr.bank),
        .waddr(), // fully associative so write can't depend on index
        .wdata(cache_in)
    );

    // Read logic
    // Address break down [31:16] 0s, [15:9] tag, [8:4] index, [3] bank, [2:0] one mem_block
    assign cache_out.valid = read_addr.tag == tags[read_addr.bank][read_addr.index] && valids[read_addr.bank][read_addr.index];
    assign cache_out.cache_line = read_addr.bank ? bank1_data_out : bank0_data_out;

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

module LFSR #(parameter NUM_BITS) (
   input clock,
   input reset,

   input [NUM_BITS-1:0] seed_data,
   output [NUM_BITS-1:0] data_out
);
 
    logic [NUM_BITS-1:0] LFSR;
    logic                r_XNOR;
 
    always @(posedge clock) begin
        if (reset)
           LFSR <= seed_data;
        else
           LFSR <= {LFSR[NUM_BITS-1:1], r_XNOR};
    end

    always @(*) begin
        case (NUM_BITS)
            3: begin
                r_XNOR = LFSR[3] ^~ LFSR[2];
            end
            4: begin
                r_XNOR = LFSR[4] ^~ LFSR[3];
            end
            5: begin
                r_XNOR = LFSR[5] ^~ LFSR[3];
            end
            6: begin
                r_XNOR = LFSR[6] ^~ LFSR[5];
            end
            7: begin
                r_XNOR = LFSR[7] ^~ LFSR[6];
            end
            8: begin
                r_XNOR = LFSR[8] ^~ LFSR[6] ^~ LFSR[5] ^~ LFSR[4];
            end
            9: begin
                r_XNOR = LFSR[9] ^~ LFSR[5];
            end
            10: begin
                r_XNOR = LFSR[10] ^~ LFSR[7];
            end
            11: begin
                r_XNOR = LFSR[11] ^~ LFSR[9];
            end
            12: begin
                r_XNOR = LFSR[12] ^~ LFSR[6] ^~ LFSR[4] ^~ LFSR[1];
            end
            13: begin
                r_XNOR = LFSR[13] ^~ LFSR[4] ^~ LFSR[3] ^~ LFSR[1];
            end
            14: begin
                r_XNOR = LFSR[14] ^~ LFSR[5] ^~ LFSR[3] ^~ LFSR[1];
            end
            15: begin
                r_XNOR = LFSR[15] ^~ LFSR[14];
            end
            16: begin
                r_XNOR = LFSR[16] ^~ LFSR[15] ^~ LFSR[13] ^~ LFSR[4];
            end
            17: begin
                r_XNOR = LFSR[17] ^~ LFSR[14];
            end
            18: begin
                r_XNOR = LFSR[18] ^~ LFSR[11];
            end
            19: begin
                r_XNOR = LFSR[19] ^~ LFSR[6] ^~ LFSR[2] ^~ LFSR[1];
            end
            20: begin
                r_XNOR = LFSR[20] ^~ LFSR[17];
            end
            21: begin
                r_XNOR = LFSR[21] ^~ LFSR[19];
            end
            22: begin
                r_XNOR = LFSR[22] ^~ LFSR[21];
            end
            23: begin
                r_XNOR = LFSR[23] ^~ LFSR[18];
            end
            24: begin
                r_XNOR = LFSR[24] ^~ LFSR[23] ^~ LFSR[22] ^~ LFSR[17];
            end
            25: begin
                r_XNOR = LFSR[25] ^~ LFSR[22];
            end
            26: begin
                r_XNOR = LFSR[26] ^~ LFSR[6] ^~ LFSR[2] ^~ LFSR[1];
            end
            27: begin
                r_XNOR = LFSR[27] ^~ LFSR[5] ^~ LFSR[2] ^~ LFSR[1];
            end
            28: begin
                r_XNOR = LFSR[28] ^~ LFSR[25];
            end
            29: begin
                r_XNOR = LFSR[29] ^~ LFSR[27];
            end
            30: begin
                r_XNOR = LFSR[30] ^~ LFSR[6] ^~ LFSR[4] ^~ LFSR[1];
            end
            31: begin
                r_XNOR = LFSR[31] ^~ LFSR[28];
            end
            32: begin
                r_XNOR = LFSR[32] ^~ LFSR[22] ^~ LFSR[2] ^~ LFSR[1];
            end

        endcase
    end

    assign data_out = LFSR;

endmodule