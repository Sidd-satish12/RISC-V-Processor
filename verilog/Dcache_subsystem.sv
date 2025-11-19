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

    localparam MEM_WIDTH = 1 + `DTAG_BITS + `MEM_BLOCK_BITS;

    memDP #(
            .WIDTH(MEM_WIDTH),
            .DEPTH(1),
            .READ_PORTS(1),
            .BYPASS_EN(0)
        ) cache_line[`DCACHE_LINES-1:0] (
            .clock(clock),
            .reset(reset),
            .re(1'b1),
            .raddr(1'b0),
            .rdata(cache_lines),
            .we(cache_write_enable_mask),
            .waddr(1'b0),
            .wdata(cache_line_write)
        );


endmodule

// module d_mshr (


// );