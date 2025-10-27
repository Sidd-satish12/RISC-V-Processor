`include "sys_defs.svh"

module cdb (
    input  logic                  clock,
    input  logic                  reset,

    // CDB arbiter inputs
    input CDB_REQUEST [(`NUM_FU_ALU + `NUM_FU_BRANCH)-1:0] other_requests, // requests from issue stage, TODO: ADD NUM_FU_MEM
    input CDB_REQUEST mult_requests, // 1 mult request from execute stage
    input CDB_ENTRY [`NUM_FU_TOTAL-1:0] fu_outputs, // has to come in order of ALU Branch and Mult

    // Broadcasting to Physical Register File, EX stage (data forwarding), and Map Table
    output CDB_ENTRY [`N-1:0] cdb_output;
);

logic [`N-1:0][`NUM_FU_TOTAL-1:0] gnt_bus, gnt_bus_next;
logic [(`NUM_FU_ALU + `NUM_FU_BRANCH + `NUM_FU_MEM)-1:0] other_req_bus;
always_comb begin
    for (int i = 0; i < `NUM_FU_ALU + `NUM_FU_BRANCH + `NUM_FU_MEM; i++) begin
        other_req_bus[i] = fu_outputs[i].valid;
    end
end

psel_gen #(
    .WIDTH(`NUM_FU_TOTAL),   // 6
    .REQS(`N)                // 2
) cdb_arbiter (
    .req({other_req_bus, mult_requests.valid}),
    .gnt_bus(gnt_bus_next),
);

CDB_ENTRY [`N-1:0] cdb, cdb_next;
always_comb begin
    cdb_next = '0;
    for (int i = 0; i < `N; i++) begin
        for (int j = 0; j < `NUM_FU_TOTAL; j++) begin
            cdb_next[i] |= {$bits(CDB_ENTRY){gnt_bus[i][j]}} & fu_outputs[j];
        end
    end
end

always_ff @(posedge clock) begin
    if (reset) begin
        gnt_bus <='0;
        cdb <= '0;
    end else begin
        gnt_bus <= gnt_bus_next;
        cdb <=cdb_next;
    end
end

assign cdb_output = cdb;

endmodule
