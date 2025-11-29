`include "sys_defs.svh"
`include "ISA.svh"
// TODO add window_valid_count logic to ib or dispatch
module instr_buffer (
    input  logic                               clock,
    input  logic                               reset,

    // Fetch stage IO
    output logic [`IB_IDX_BITS:0]              available_slots,
    input  FETCH_PACKET [`IB_PUSH_WIDTH-1:0]   new_ib_entries,

    // Decode and Dispatch IO
    input  logic [$clog2(`N+1)-1:0]             num_pops,
    output FETCH_PACKET [`N-1:0]                dispatch_window,
    output logic [$clog2(`N+1)-1:0]             window_valid_count
);

    FETCH_PACKET [`IB_SZ-1:0] ib_entries, ib_entries_next;
    logic [`IB_IDX_BITS-1:0] head_ptr, head_ptr_next, tail_ptr, tail_ptr_next;
    logic [`IB_IDX_BITS:0]   available_slots_next;
    logic [$clog2(`IB_PUSH_WIDTH+1)-1:0] num_pushes;

    // dispatch_window
    logic [`N-1:0] dispatch_valid_bits;
    for (genvar i = 0; i < `N; i++) begin
        assign dispatch_window[i] = ib_entries[(head_ptr + i) % `IB_SZ].valid ? ib_entries[(head_ptr + i) % `IB_SZ] : '0;
        assign dispatch_valid_bits[i] = dispatch_window[i].valid;
    end
    assign window_valid_count = $countones(dispatch_valid_bits);

    // available_slots
    assign available_slots_next = available_slots + num_pops - num_pushes;

    // FIFO next state
    always_comb begin
        ib_entries_next = ib_entries;
        head_ptr_next = head_ptr;
        tail_ptr_next = tail_ptr;
        num_pushes = '0;

        // Pop
        for (int i = 0; i < num_pops; i++) begin
            ib_entries_next[(head_ptr + i) % `IB_SZ].valid = 1'b0;
        end
        head_ptr_next = (head_ptr + num_pops) % `IB_SZ;

        // Push
        for (int i = 0; i < `IB_PUSH_WIDTH; i++) begin
            if (new_ib_entries[i].valid) begin
                ib_entries_next[(tail_ptr + num_pushes) % `IB_SZ] = new_ib_entries[i];
                num_pushes = num_pushes + 1;
            end
        end
        tail_ptr_next = (tail_ptr + num_pushes) % `IB_SZ;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            ib_entries <= '0;
            head_ptr <= '0;
            tail_ptr <= '0;
            available_slots <= `IB_SZ;
        end else begin
            ib_entries <= ib_entries_next;
            head_ptr <= head_ptr_next;
            tail_ptr <= tail_ptr_next;
            available_slots <= available_slots_next;
        end 
    end
endmodule