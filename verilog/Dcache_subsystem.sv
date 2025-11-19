`include "verilog/sys_defs.svh"

module Dcache_subsystem (
    input clock,
    input reset,
    
    // one read and write for now
    input D_ADDR_PACKET [`N-1:0]   read_addr, // max 3, when 3 loads in ex
    input D_ADDR_PACKET [`N-1:0]   write_addr, // max 3, when 3 stores retire

    // for reads (Load instructions)
    output CACHE_DATA [`N-1:0]     cache_out,

    // Mem.sv IOs
    input MEM_TAG          current_req_tag,
    input MEM_BLOCK        mem_data,
    input MEM_TAG          mem_data_tag,

    // Arbitor IOs
    output MEM_REQUEST_PACKET   mem_req,
    
    input  logic           mem_req_accepted
);

endmodule

module Dcache (
    input clock,
    input reset,

    input D_ADDR_PACKET [`N-1:0] read_addr,
    input D_ADDR_PACKET [`N-1:0] write_addr,

    output CACHE_DATA [`N-1:0]   cache_out,

    // Dcache write mem_data, when mem_data_tag matches head of MSHR
    input D_ADDR_PACKET [`N-1:0] write_addr,
    input MEM_BLOCK [`N-1:0]    write_data
);

    localparam MEM_WIDTH = 2 + `DTAG_BITS + `MEM_BLOCK_BITS;  // + 2 is for valid bit and dirty bit
    localparam MEM_DEPTH = `DCACHE_LINES;
    localparam D_CACHE_INDEX_BITS = $clog2(MEM_DEPTH);

    D_CACHE_LINE [MEM_DEPTH-1:0]          cache_lines;
    logic [MEM_DEPTH-1:0]                 cache_write_enable_mask;
    D_CACHE_LINE                          cache_line_write;
    logic [MEM_DEPTH-1:0]                 cache_write_no_evict_one_hot;
    logic [D_CACHE_INDEX_BITS-1:0]        cache_write_evict_index;
    logic [MEM_DEPTH-1:0]                 cache_write_evict_one_hot;

    logic [`N-1:0][MEM_DEPTH-1:0]            cache_reads_one_hot;
    logic [`N-1:0][D_CACHE_INDEX_BITS-1:0]   cache_reads_index;


    memDP #(
            .WIDTH(MEM_WIDTH),
            .DEPTH(1),
            .READ_PORTS(1),
            .BYPASS_EN(0)
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

    // Write selection no eviction
    psel_gen #(
        .WIDTH(MEM_DEPTH),
        .REQS(1'b1)
    ) psel_gen_inst (
        .req(valid_bits),
        .gnt(cache_write_no_evict_one_hot)
    );

    // Write selection random eviction
    LFSR #(
        .NUM_BITS (D_CACHE_INDEX_BITS)
    ) LFSR_inst (
        .clock(clock),
        .reset(reset),
        .seed_data(D_CACHE_INDEX_BITS'(`LFSR_SEED)),
        .data_out(cache_write_evict_index)
    );

    // todo ammend below

    // Cache write logic
    for (genvar k = 0; k < MEM_DEPTH; k++) begin
        assign cache_write_evict_one_hot[k] = (cache_write_evict_index == k);
    end
    
    assign cache_write_enable_mask = |cache_write_no_evict_one_hot ? cache_write_no_evict_one_hot : cache_write_evict_one_hot;
    
    assign cache_line_write = '{valid: write_addr.valid,
                                tag: write_addr.addr.tag,
                                data: write_data};

     // Cache read logic
    for (genvar j = 0; j <= 1; j++) begin
        for (genvar i = 0; i < MEM_DEPTH; i++) begin
            assign cache_reads_one_hot[j][i] = (read_addrs[j].addr.tag == cache_lines[i].tag) &
                                                read_addrs[j].valid &
                                                cache_lines[i].valid;

            assign cache_outs_temp[j].data = cache_lines[i].data & {`MEM_BLOCK_BITS{cache_reads_one_hot[j][i]}};
        end
    end
    assign cache_outs = cache_outs_temp;


endmodule

// module d_mshr (


// );