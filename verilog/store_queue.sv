// -----------------------------------------------------------------------------
// Store Queue FIFO (simple, registered I/O)
// - Depth comes from `LSQ_SZ` (set in sys_defs.svh)
// - Payload type: store_queue_entry_t (defined in sys_defs.svh)
// - Enqueue from DISPATCH/ISSUE; Dequeue at RETIRE
// - All acks and outputs are registered (no combinational assigns)
// - Allows same-cycle enqueue+dequeue
// -----------------------------------------------------------------------------

`include "sys_defs.svh"

module store_queue (
    input logic clock,
    input logic reset,

    // ============================================================
    // Dispatch I/O
    // ============================================================
    input  STOREQ_ENTRY [               `N-1:0] sq_dispatch_packet,  // must be contiguous valid
    output logic        [$clog2(`LSQ_SZ+1)-1:0] free_slots,          // number of free SQ slots
    output STOREQ_IDX   [               `N-1:0] sq_alloc_idxs,       // allocation indices

    // ============================================================
    // Retire I/O (May not be needed)
    // ============================================================
    output STOREQ_ENTRY [`N-1:0] sq_head_entries,  // up to N entries to retire
    output STOREQ_IDX   [`N-1:0] sq_head_idxs,
    output logic        [`N-1:0] sq_head_valids
);

    // ============================================================
    // Storage
    // ============================================================
    STOREQ_ENTRY [`LSQ_SZ-1:0] sq_entries, sq_entries_next;

    logic [$clog2(`LSQ_SZ+1)-1:0] free_count, free_count_next;
    logic [$clog2(`LSQ_SZ)-1:0] head_idx, head_idx_next;
    logic [$clog2(`LSQ_SZ)-1:0] tail_idx, tail_idx_next;

    logic [`N-1:0] dispatch_valid_bits;
    logic [$clog2(`N+1)-1:0] retire_count;
    logic [$clog2(`N+1)-1:0] num_retired, num_dispatched;

    // ============================================================
    // Combinational Logic
    // ============================================================
    always_comb begin
        sq_entries_next = sq_entries;
        free_count_next = free_count;
        retire_count    = '0;

        for (int i = 0; i < `N; i++) begin

            // ====================================================
            // Dispatch (enqueue) — contiguous valid bits required
            // ====================================================
            if (sq_dispatch_packet[i].valid) begin
                sq_entries_next[(tail_idx+i)%`LSQ_SZ] = sq_dispatch_packet[i];
            end

            dispatch_valid_bits[i] = sq_dispatch_packet[i].valid;

            // ====================================================
            // Retire (longest in-order prefix of valid entries)
            // ====================================================
            if ((i == retire_count) && sq_entries[(head_idx+i)%`LSQ_SZ].valid) begin
                retire_count = retire_count + 1;
            end
        end

        num_dispatched = $countones(dispatch_valid_bits);
        num_retired    = retire_count;

        // ========================================================
        // Invalidate retired entries
        // ========================================================
        for (int i = 0; i < retire_count; i++) begin
            sq_entries_next[(head_idx+i)%`LSQ_SZ].valid = 1'b0;
        end

        // ========================================================
        // Update free count
        // ========================================================
        free_count_next = free_count + num_retired - num_dispatched;

        // ========================================================
        // Update head/tail
        // ========================================================
        head_idx_next   = (head_idx + retire_count) % `LSQ_SZ;
        tail_idx_next   = (tail_idx + num_dispatched) % `LSQ_SZ;
    end

    // ============================================================
    // Allocation indices (dispatch)
    // ============================================================
    always_comb begin
        for (int i = 0; i < `N; i++) begin
            sq_alloc_idxs[i] = STOREQ_IDX'((tail_idx + i) % `LSQ_SZ);
        end
    end

    // ============================================================
    // Exposure of head window (for retiring stores)
    // ============================================================
    always_comb begin
        for (int i = 0; i < `N; i++) begin
            sq_head_entries[i] = sq_entries[(head_idx + i) % `LSQ_SZ];
            sq_head_idxs[i]    = STOREQ_IDX'((head_idx + i) % `LSQ_SZ);
            sq_head_valids[i]  = sq_entries[(head_idx + i) % `LSQ_SZ].valid;
        end
    end

    assign free_slots = free_count;

    // ============================================================
    // Sequential
    // ============================================================
    always_ff @(posedge clock) begin
        if (reset) begin
            sq_entries <= '0;
            head_idx   <= '0;
            tail_idx   <= '0;
            free_count <= `LSQ_SZ;
        end else begin
            sq_entries <= sq_entries_next;
            head_idx   <= head_idx_next;
            tail_idx   <= tail_idx_next;
            free_count <= free_count_next;
        end
    end

endmodule
