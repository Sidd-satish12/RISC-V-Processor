`include "verilog/sys_defs.svh"

module Dcache_subsystem (
    input clock,
    input reset,
    
    // one read and write for now
    input D_ADDR_PACKET    read_addr,
    input D_ADDR_PACKET    write_addr,

    // for reads (Load instructions)
    output CACHE_DATA      cache_out,

    // Mem.sv IOs
    input MEM_TAG          current_req_tag,
    input MEM_BLOCK        mem_data,
    input MEM_TAG          mem_data_tag,

    // Arbitor IOs
    output I_ADDR_PACKET   mem_req_addr,
    input  logic           mem_req_accepted
);

endmodule

module Dcache (
    input clock,
    input reset,

    input D_ADDR_PACKET    read_addr,
    input D_ADDR_PACKET    write_addr,

    output CACHE_DATA      cache_out,

    // Dcache write mem_data, when mem_data_tag matches head of MSHR
    // 
    input I_ADDR_PACKET write_addr,
    input MEM_BLOCK     write_data
);

    localparam MEM_WIDTH = 1 + `DTAG_BITS + `MEM_BLOCK_BITS;
    // todo check size to see if it meets specs
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