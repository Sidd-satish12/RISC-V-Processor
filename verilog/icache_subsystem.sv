`include "verilog/sys_defs.svh"

module icache_subsystem (
    input clock,
    input reset,

    // Fetch
    input  ADDR       [1:0]   read_addrs,                 // read_addr[0] is older instructions
    output CACHE_DATA [1:0]   cache_outs,

    // Mem.sv IOs
    input  MEM_TAG            current_req_tag,
    input  MEM_BLOCK          mem_data,
    input  MEM_TAG            mem_data_tag,

    // Arbitor IOs
    output ADDR_PACKET        mem_req_addr,
    input  logic              mem_req_accepted
);

    // Internal wires
    ADDR_PACKET prefetcher_snooping_addr, icache_write_addr, oldest_miss_addr;
    logic       icache_full, snooping_found_icache, snooping_found_mshr;
    MSHR_PACKET new_mshr_entry;

    icache icache_inst (
        .clock             (clock),
        .reset             (reset),
        // Fetch Stage read
        .read_addrs        (read_addrs),
        .cache_outs        (cache_outs),
        // Prefetch snooping
        .snooping_addr     (prefetcher_snooping_addr),
        .addr_found        (snooping_found_icache),
        .full              (icache_full),
        // Icache write mem_data, when mem_data_tag matches head of MSHR
        .write_addr        (icache_write_addr),
        .mem_data          (mem_data)
    );

    prefetcher prefetcher_inst (
        .clock                    (clock),
        .reset                    (reset),
        .icache_miss              (oldest_miss_addr),
        .icache_full              (icache_full),
        .mem_req_accepted         (mem_req_accepted),
        .prefetcher_snooping_addr (prefetcher_snooping_addr)
    );

    i_mshr i_mshr_inst (
        .clock            (clock),
        .reset            (reset),
        // Prefetch snooping
        .snooping_addr    (prefetcher_snooping_addr),
        .addr_found       (snooping_found_mshr),
        // When mem_req_accepted
        .new_entry        (new_mshr_entry),
        // Mem data back
        .mem_data_tag     (mem_data_tag),
        .mem_data_i_addr  (icache_write_addr)
    );

    // Oldest miss address logic
    always_comb begin
        oldest_miss_addr.valid = '0;
        if (read_addrs[0].valid & ~cache_outs[0].valid) begin
            oldest_miss_addr.valid = '1;
            oldest_miss_addr.addr = read_addrs[0].addr;
        end else if (read_addrs[1].valid & ~cache_outs[1].valid) begin
            oldest_miss_addr.valid = '1;
            oldest_miss_addr.addr = read_addrs[1].addr;
        end
    end

    // Mem request address logic
    always_comb begin
        mem_req_addr.valid = '0;
        if (~snooping_found_icache & ~snooping_found_mshr) begin
            mem_req_addr = prefetcher_snooping_addr;
        end
    end

    // New MSHR entry logic
    always_comb begin
        new_mshr_entry.valid = '0;
        if (mem_req_accepted) begin
            new_mshr_entry.valid = '1;
            new_mshr_entry.mem_tag = current_req_tag;
            new_mshr_entry.i_addr = mem_req_addr.addr;
        end
    end

endmodule


module i_mshr #(
    parameter MSHR_WIDTH = `NUM_MEM_TAGS
) (
    input                 clock,
    input                 reset,

    // Prefetch snooping
    input  I_ADDR         snooping_addr,   // to decide whether to send mem request
    output logic          addr_found,

    // When mem_req_accepted
    input  MSHR_PACKET    new_entry,

    // Mem data back
    input  MEM_TAG        mem_data_tag,
    output ADDR_PACKET    mem_data_i_addr  // to write to icache
);

endmodule

module prefetcher (
    input clock,
    input reset,

    input ADDR_PACKET     icache_miss_addr,
    input logic           icache_full,

    input logic           mem_req_accepted,
    output ADDR_PACKET    mem_req
);


endmodule

module icache (
    input clock,
    input reset,

    // Fetch Stage read
    input  I_ADDR       [1:0] read_addrs,
    output CACHE_DATA   [1:0] cache_outs,

    // Prefetch snooping
    input  I_ADDR             snooping_addr,   // to decide whether to send mem request
    output logic              addr_found,
    output logic              full,

    // Icache write mem_data, when mem_data_tag matches head of MSHR
    input  I_ADDR             write_addr,
    input  MEM_BLOCK          write_data    
);

    I_TAG [1:0] read_tags;
    assign read_tags[0] = read_addr[0].tag;
    assign read_tags[1] = read_addr[1].tag;

endmodule

module one_hot_to_index #(
    parameter int INPUT_WIDTH = 1
) (
    input logic [INPUT_WIDTH-1:0] one_hot,
    output wor [((INPUT_WIDTH <= 1) ? 1 : $clog2(INPUT_WIDTH))-1:0] index
);

    localparam INDEX_WIDTH = (INPUT_WIDTH <= 1) ? 1 : $clog2(INPUT_WIDTH);

    assign index = '0;
    for (genvar i = 0; i < INPUT_WIDTH; i++) begin : gen_index_terms
        assign index = {INDEX_WIDTH{one_hot[i]}} & i;
    end

endmodule

module LFSR #(
    parameter NUM_BITS
) (
    input clock,
    input reset,

    input  [NUM_BITS-1:0] seed_data,
    output [NUM_BITS-1:0] data_out
);

    logic [NUM_BITS-1:0] LFSR;
    logic                r_XNOR;

    always @(posedge clock) begin
        if (reset) LFSR <= seed_data;
        else LFSR <= {LFSR[NUM_BITS-1:1], r_XNOR};
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

module index_to_onehot #(
    parameter OUTPUT_WIDTH = 1
) (
    input  logic [$clog2(OUTPUT_WIDTH)-1:0] idx,
    output logic [OUTPUT_WIDTH-1:0] one_hot
);

    integer i;
    always_comb begin
        one_hot = '0;
        for (i = 0; i < OUTPUT_WIDTH; i = i + 1) begin
            if (idx == i[$clog2(OUTPUT_WIDTH)-1:0])
                one_hot[i] = 1'b1;
        end
    end

endmodule
