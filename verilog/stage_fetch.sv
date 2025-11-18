`include "sys_defs.svh"
// Fetch stage fetches a bundle of instructions (4 instructions) from iCache.
// Stall If any of cache_data is invalid | IB has less than 4 empty space | mispredict
//    when done stalling, Check if there is a branch in any of the 4
//        if has branch send BP packet
//        BP responds with prediction, we send that packet to IB
//    Update PC, send new read_addrs
module stage_fetch #(
    parameter GH = `BP_PHT_BITS
) (
    input  logic                     clock,
    input  logic                     reset,

    // Icache_subsystem IOs
    output I_ADDR        [1:0]       read_addrs,
    input  CACHE_DATA    [1:0]       cache_data,

    // Instruction buffer IOs
    input  logic                     stall_fetch,
    output logic                     stall_instruction_buffer,
    output FETCH_PACKET    [1:0]     fetch_stage_packet,

    // Branch Predictor IOs
    output  BP_PREDICT_REQUEST       bp_predict_req_o,
    input   BP_PREDICT_RESPONSE      bp_predict_resp_i,

    // Retire on branch mispredict
    input  logic                     mispredict,
    input  ADDR                      PC_update_addr

);



endmodule
