`include "sys_defs.svh"

module instr_buffer #(
    parameter DEPTH = 32 // make sure it's a multiple of 4
)(
    input  logic                 clock,
    input  logic                 reset,

    // Retire on branch mispredict
    input  logic                 flush,

    // Fetch stage
    input FETCH_PACKET [1:0]     new_ib_entry,
    output logic                 full,

    // Decode and Dispatch IO
    input logic [$clog2(`N)-1:0] num_pops,
    output FETCH_PACKET [1:0]    popped_ib_entry

);

FETCH_PACKET [DEPTH-1:0]  ib_entries;

// We output if its full
//     if not full We get 4 Insts from fetch
//     if full, output full
// We push all of them to FIFO
// receives number of dispatched instruction this cycle
// Pop accordingly
// On a mispredict (we empty the entire buffer), the flush signal comes from Retire Stage.
//

// instruction: IB -> decode -> decode/dispath pipeline register -> dispatch
// dispatch tells IB how many were dispatched, the IB pops accordingly
endmodule
