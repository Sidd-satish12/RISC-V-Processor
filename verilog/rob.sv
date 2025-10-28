/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  rob.sv                                              //
//                                                                     //
//  Description :  Reorder Buffer module; manages up to ROB_SZ         //
//                 in-flight instructions for in-order commit,         //
//                 branch misprediction recovery, and exception        //
//                 handling. Acts as a circular buffer with head       //
//                 (oldest) and tail (next alloc) pointers.            //
//                 Allocates entries from Dispatch, updates from       //
//                 Complete (complete bit, value, branch info),        //
//                 provides head entries to Retire, advances head      //
//                 on retire, and truncates on mispredict flush.       //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"

// Parameters and typedefs are now centrally defined in sys_defs.svh

// ROB entry structure is now defined in sys_defs.svh

// ROB update packet (extended for branch info) now in SYS_DEFS


module rob (
    input clock,  // system clock
    input reset,  // system reset

    // Allocation from Dispatch
    input logic [`N-1:0] alloc_valid,  // Valid allocations this cycle
    input ROB_ENTRY [`N-1:0] rob_entry_packet,  // New entries (partial fields set by Dispatch)
    output ROB_IDX [`N-1:0] alloc_idxs,  // Assigned ROB indices for new entries
    output logic [$clog2(`ROB_SZ+1)-1:0] free_slots,  // Number of free slots (for stall check)

    // Updates from Complete
    input ROB_UPDATE_PACKET rob_update_packet,  // Updates for complete bit, value, and branch info

    // Retire interface
    output ROB_ENTRY [`N-1:0] head_entries,  // Up to N consecutive head entries for Retire
    output logic [`N-1:0] head_valids,  // Valid bits for each head entry

    // to delete
    //input logic [`N:0] retire_count,  // Number of instructions to retire (0 to N) -> the maximum number of instructions that can be retired in a single cycle

    // Flush on mispredict (from Execute or Retire)
    input logic   mispredict,  // Flush signal
    input ROB_IDX mispred_idx  // ROB index of mispredicted branch (truncate after this)
);

  localparam ALLOC_CNT_WIDTH = $clog2(`N+1); 
  
  // Internal storage: circular buffer of entries
  ROB_ENTRY [`ROB_SZ-1:0] rob_array;

  // Head (oldest) and tail (next allocation) pointers
  ROB_IDX head, tail;
  ROB_IDX head_next, tail_next;
  ROB_IDX idx1, idx4;
  ROB_IDX idx_alloc;
  ROB_IDX idx_retire;
  ROB_IDX idx_hw;

  // Signal from rob_update_packet that used to indicate the idx that is ready to complete (EX -> C)
  ROB_IDX rob_complete_update_idx;

  // =========================================================================
  // *** CHANGE: free_slots computed from head/tail (pointer-based).
  //     This makes post-flush accounting correct immediately without
  //     having to clear .valid on every truncated entry.
  // =========================================================================
  logic [$clog2(`ROB_SZ+1)-1:0] inflight;
  always_comb begin
    if (tail >= head) inflight = tail - head;
    else              inflight = `ROB_SZ - (head - tail);
    free_slots = `ROB_SZ - inflight;
  end


  // Combinational OUTPUT (free_slots): compute free slots
  // logic [$clog2(`ROB_SZ):0] valid_count;
  // always_comb begin
  //   valid_count = 0;
  //   for (int i = 0; i < `ROB_SZ; i++) begin
  //     if (rob_array[i].valid) begin
  //       valid_count = valid_count + 1;
  //     end
  //   end

  //   free_slots = `ROB_SZ - valid_count;
  // end


  // Combinational OUTPUT (alloc_idxs): assign allocation indices starting from tail
  always_comb begin
    ROB_IDX current_idx = tail;
    for (int i = 0; i < `N; i++) begin
      alloc_idxs[i] = current_idx;
      if (alloc_valid[i]) begin
        current_idx = (current_idx + 1) % `ROB_SZ;
      end
    end
  end

  // =========================================================================
  // *** CHANGE: Unconditional head window view for Retire.
  //     - Always expose next up to N entries, ordered [N-1]=oldest .. [0]=youngest.
  //     - Valid bit indicates whether that slot lies in [head, tail) window.
  // =========================================================================
  always_comb begin
    for (int i = 0; i < `N; i++) begin         // i=0 is FIFO-oldest
      idx_hw = (head + i) % `ROB_SZ;
      head_entries[`N-1 - i] = rob_array[idx_hw];     // map to requested order
      head_valids [`N-1 - i] = (i < inflight);     // valid if inside head..tail
    end
  end

  // Combinational: output head entries and valids
  // always_comb begin
  //   retire_count = '0;
  //   for (int i = 0; i < `N; i++) begin
  //     idx1 = (head + i) % `ROB_SZ;
  //     head_entries[i] = rob_array[idx1];
  //     // Valid if within committed range and entry is valid
  //     head_valids[i] = ((tail - head) % `ROB_SZ > i) && rob_array[idx1].valid;
  //     retire_count = retire_count + rob_array[idx1].valid;
  //   end
  // end

  // Next state logic (combinational)
  ROB_ENTRY [`ROB_SZ-1:0] rob_next;
  logic [(ALLOC_CNT_WIDTH-1):0] alloc_cnt;
  
  
  always_comb begin
    // default vals
    rob_next  = rob_array;
    head_next = head;
    tail_next = tail;
//   head_valids = 0;

    // Priority: handle mispredict flush (WIP)
    if (mispredict) begin
      tail_next = (mispred_idx + 1) % `ROB_SZ;
      // No need to invalidate entries explicitly; overwriting on future alloc suffices
    end else begin

      // ---------------------------------------------------------------------
      // *** RETIRE ADVANCE (in-order):
      // Walk from head while entries are inside the window AND complete.
      // Invalidate those entries and bump head.
      // NOTE: head_entries/head_valids are NOT driven here; they are the
      //       read-only window above. This block only updates state.
      // ---------------------------------------------------------------------
      for (int i = 0; i < `N; i++) begin
        // Stop if no more in-flight
        if (i >= inflight) break;

        idx_retire = (head_next + i) % `ROB_SZ;
        if (rob_array[idx_retire].valid && rob_array[idx_retire].complete) begin
          rob_next[idx_retire].valid    = 1'b0;   // clear when retiring
          rob_next[idx_retire].complete = 1'b0;   // optional: clear complete bit
          // do not write head_entries here
          head_next = (head_next + 1) % `ROB_SZ;
        end else begin
          // hit first incomplete → stop committing this cycle
          break;
        end
      end

      // Updates from Complete: set complete, value, and branch info
      for (int i = 0; i < `N; i++) begin
        if (rob_update_packet.valid[i]) begin
          rob_complete_update_idx = rob_update_packet.idx[i];
          rob_next[rob_complete_update_idx].complete = 1'b1;
          
          // for debug purposes
          // rob_next[idx].value = rob_update_packet.values[i];

          // Branching WIP
          if (rob_next[rob_complete_update_idx].branch) begin
            rob_next[rob_complete_update_idx].branch_taken  = rob_update_packet.branch_taken[i];
            rob_next[rob_complete_update_idx].branch_target = rob_update_packet.branch_targets[i];
          end
        end
      end


      // ---------------------------------------------------------------------
      // ALLOCATION (Dispatch): write new entries at (tail + i) for valid lanes
      // *** CHANGE: also stamp rob_idx inside each entry so Retire can echo it.
      // ---------------------------------------------------------------------
      for (int i = 0; i < `N; i++) begin
        if (alloc_valid[i]) begin
          idx_alloc = (tail + i) % `ROB_SZ;

          rob_next[idx_alloc]             = rob_entry_packet[i];
          rob_next[idx_alloc].valid       = 1'b1;
          rob_next[idx_alloc].complete    = 1'b0;
          rob_next[idx_alloc].exception   = NO_ERROR;

          // *** CHANGE: record the entry’s own ROB index (used by Retire on mispredict)
          rob_next[idx_alloc].rob_idx     = idx_alloc;
        end
      end
      // ### ADVANCE TAIL: advance tail by number allocated
      alloc_cnt = 0;
      for (int i = 0; i < `N; i++) begin
        alloc_cnt = alloc_cnt + alloc_valid[i];
      end
      tail_next = (tail + alloc_cnt) % `ROB_SZ;
    end
  end

  // Clocked update
  always_ff @(posedge clock) begin
    if (reset) begin
      head <= 0;
      tail <= 0;
      for (int i = 0; i < `ROB_SZ; i++) begin
        rob_array[i].valid <= 1'b0;
        rob_array[i].complete <= 1'b0;
      end
    end else begin
      head <= head_next;
      tail <= tail_next;
      rob_array <= rob_next;
    end
  end

endmodule  // rob
