`include "sys_defs.svh"

module rob_test;

  // -------------------------------------------------------------
  // DUT signals
  // -------------------------------------------------------------
  logic clock, reset;
  logic [`N-1:0] alloc_valid;
  ROB_ENTRY [`N-1:0] rob_entry_packet;
  ROB_IDX [`N-1:0] alloc_idxs;
  logic [$clog2(`ROB_SZ+1)-1:0] free_slots;
  ROB_UPDATE_PACKET rob_update_packet;
  ROB_ENTRY [`N-1:0] head_entries;
  logic [`N-1:0] head_valids;
  logic mispredict;
  ROB_IDX mispred_idx;



  // -------------------------------------------------------------
  // DUT instantiation
  // -------------------------------------------------------------
  rob dut (
      .clock(clock),
      .reset(reset),
      .alloc_valid(alloc_valid),
      .rob_entry_packet(rob_entry_packet),
      .alloc_idxs(alloc_idxs),
      .free_slots(free_slots),
      .rob_update_packet(rob_update_packet),
      .head_entries(head_entries),
      .head_valids(head_valids),
      .mispredict(mispredict),
      .mispred_idx(mispred_idx)
  );

  // -------------------------------------------------------------
  // Clock generation
  // -------------------------------------------------------------
  always #5 clock = ~clock;

  // -------------------------------------------------------------
  // Testbench state and helper variables
  // -------------------------------------------------------------
  bit                            failed = 0;
  ADDR                           pc_val = 32'h1000;
  REG_IDX                        arch_val = 5'd1;
  PHYS_TAG                       phys_val = 6'd10;
  DATA                           data_val = 32'd1000;

  logic    [$clog2(`ROB_SZ)-1:0] start_idx;
  logic    [$clog2(`ROB_SZ)-1:0] i;
  logic    [$clog2(`ROB_SZ)-1:0] rob_idx;

  // -------------------------------------------------------------
  // Helper functions
  // -------------------------------------------------------------
  function automatic ROB_ENTRY make_rob_entry(
      input ADDR pc, input INST inst, input REG_IDX arch_rd, input PHYS_TAG phys_rd,
      input PHYS_TAG prev_phys_rd, input DATA value, input logic branch = 0,
      input ADDR branch_target = '0, input logic branch_taken = 0, input ADDR pred_target = '0,
      input logic pred_taken = 0, input logic halt = 0, input logic illegal = 0);
    ROB_ENTRY entry;
    entry.valid         = 1'b1;
    entry.PC            = pc;
    entry.inst          = inst;
    entry.arch_rd       = arch_rd;
    entry.phys_rd       = phys_rd;
    entry.prev_phys_rd  = prev_phys_rd;
    entry.value         = value;
    entry.complete      = 1'b0;
    entry.exception     = NO_ERROR;
    entry.branch        = branch;
    entry.branch_target = branch_target;
    entry.branch_taken  = branch_taken;
    entry.pred_target   = pred_target;
    entry.pred_taken    = pred_taken;
    entry.halt          = halt;
    entry.illegal       = illegal;
    return entry;
  endfunction

  function automatic void fill_rob_packet(inout ROB_ENTRY [`N-1:0] packet, input ADDR base_pc,
                                          input REG_IDX base_arch, input PHYS_TAG base_phys,
                                          input DATA base_value);
    for (int i = 0; i < `N; i++) begin
      packet[i] = make_rob_entry(
          base_pc + i,  // PC
          `NOP,  // Instruction
          base_arch + i,  // arch_rd
          base_phys + i,  // phys_rd
          base_phys + i - 1,  // prev_phys_rd
          base_value + i  // value
      );
    end
  endfunction

  // -------------------------------------------------------------
  // Main test sequence
  // -------------------------------------------------------------
  initial begin
   
    
    automatic ROB_IDX expected_tail;
    automatic int k;
    automatic int retire_cnt;
    automatic ROB_IDX idx;
    automatic int actual_allocs;
    automatic int ran_num_alloc;
    automatic int ran_num_retire;
    automatic int alloc_counter;
    automatic int complete_counter;
    logic do_alloc, do_complete;
    int hw;
    int free_before_wrap;
    int completed_count;
  

    
    // Initialization & Reset
    // -------------------------------
    clock = 0;
    reset = 1;
    alloc_valid = 0;
    rob_update_packet = '{default: 0};
    mispredict = 0;
    mispred_idx = '0;

    @(negedge clock);
    @(negedge clock);
    reset = 0;
    @(posedge clock);  // allow one cycle after reset

    // use below monitior statement for debugging

    // $monitor("Time %0t | head=%0d tail=%0d free_slots=%0d valid=%0d",
    //           $time, dut.head, dut.tail, dut.free_slots, dut.rob_array[0].valid);

    // -------------------------------
    // Test 1: Check Empty ROB after Reset
    // -------------------------------
    $display("\nTest 1: Checking if ROB is empty after reset...\n");
    if (free_slots !== `ROB_SZ) begin
      $display("FAIL: Incorrect number of free slots as Head and tail may not match or if they do logic to detemrine between full is wrong");
      failed = 1;
    end
    

    if (!failed) $display("PASS: ROB is empty and head == tail after reset.\n");
    else $display("FAIL: ROB initial empty-state check.\n");

    // -------------------------------
    // Test 2: Fill ROB
    // -------------------------------
    $display("Test 2: Filling the ROB and checking if its full\n");
    alloc_valid = '1;
    for (int i = 0; i < (`ROB_SZ / `N); i++) begin
      fill_rob_packet(rob_entry_packet, pc_val + i * `N, arch_val + i * `N, phys_val + i * `N,
                      data_val + i * `N);
      @(posedge clock);
    end

    alloc_valid = '0;
    for (int i = 0; i < 2; i++) begin
      rob_entry_packet[i] = make_rob_entry(pc_val + i, `NOP, arch_val + i, phys_val + i,
                                           phys_val + i - 1, data_val + i);
      alloc_valid[i] = 1'b1;
    end
    @(posedge clock);
    alloc_valid = '0;
    //@(negedge clock);
    @(posedge clock);

    if (free_slots !== 0) begin
      $display("FAIL: Expected free_slots = 0, got %0d", free_slots);
      failed = 1;
    end else $display("PASS: ROB full condition detected.\n");

    // -------------------------------
    // Test 3: Complete and Retire All Instructions
    // -------------------------------
    $display("Test 3: Completing and retiring all instructions...\n");
    for (start_idx = 0; start_idx < `ROB_SZ - 3; start_idx += `N) begin
      for (i = 0; i < `N; i++) begin
        rob_idx                             = (start_idx + i) % `ROB_SZ;
        rob_update_packet.valid[i]          = 1'b1;
        rob_update_packet.idx[i]            = rob_idx;
        rob_update_packet.values[i]         = 0;
        rob_update_packet.branch_taken[i]   = 1'b0;
        rob_update_packet.branch_targets[i] = '0;
      end
      @(posedge clock);
      rob_update_packet.valid = '0;
      @(posedge clock);
      @(posedge clock);
    end

    // Final batch
    for (i = 0; i < `N; i++) begin
      rob_idx                             = (start_idx + i) % `ROB_SZ;
      rob_update_packet.valid[i]          = 1'b1;
      rob_update_packet.idx[i]            = rob_idx;
      rob_update_packet.values[i]         = 0;
      rob_update_packet.branch_taken[i]   = 1'b0;
      rob_update_packet.branch_targets[i] = '0;
    end
    rob_update_packet.valid[2] = 1'b0;
    @(posedge clock);
    rob_update_packet.valid = '0;
    @(posedge clock);
    @(posedge clock);

    if (free_slots !== `ROB_SZ) begin
      $display("FAIL: ROB did not retire all entries, free_slots = %0d", free_slots);
      failed = 1;
    end else $display("PASS: All instructions completed and retired correctly.\n");

    // -------------------------------
    // Test 4: Simultaneous Retirement & Dispatch
    // -------------------------------
    $display("Test 4: Testing simultaneous retirement and dispatch...\n");
    alloc_valid = '1;
    for (int i = 0; i < (`ROB_SZ / `N); i++) begin
      fill_rob_packet(rob_entry_packet, pc_val + i * `N, arch_val + i * `N, phys_val + i * `N,
                      data_val + i * `N);
      @(posedge clock);
    end
    alloc_valid = '0;
    for (int i = 0; i < 2; i++) begin
      rob_entry_packet[i] = make_rob_entry(pc_val + i, `NOP, arch_val + i, phys_val + i,
                                           phys_val + i - 1, data_val + i);
      alloc_valid[i] = 1'b1;
    end
    @(posedge clock);
    @(negedge clock);
    alloc_valid = '0;
    @(negedge clock);

    // Complete first N instructions
    rob_update_packet.valid = '0;
    for (i = 0; i < `N; i++) begin
      rob_update_packet.valid[i]  = 1'b1;
      rob_update_packet.idx[i]    = i;
      rob_update_packet.values[i] = 0;
      rob_update_packet.branch_taken[i] = 1'b0;
      rob_update_packet.branch_targets[i] = '0;
    end
    @(negedge clock);

    // Dispatch new instructions while retiring
    rob_update_packet.valid = '0;
    for (i = 0; i < `N; i++) begin
      rob_entry_packet[i] = make_rob_entry(
          pc_val + `ROB_SZ + i,
          `NOP,
          arch_val + `ROB_SZ + i,
          phys_val + `ROB_SZ + i,
          phys_val + `ROB_SZ + i - 1,
          data_val + `ROB_SZ + i
      );
      alloc_valid[i] = 1'b1;
    end
    @(negedge clock);
    alloc_valid = '0;
    @(negedge clock);
    @(posedge clock);

    if (free_slots !== 0) begin
      $display("FAIL: ROB free_slots incorrect after retire+dispatch, got %0d", free_slots);
      failed = 1;
    end else $display("PASS: Simultaneous retirement and dispatch successful.\n");

    // -------------------------------
    // Test 5: OOO Complete and In Order Retire
    // -------------------------------

    $display("\nTest 5: Out of Order Complete and In Order Retire...\n");
    @(negedge clock);
    reset = 1;
    #3 // delay to let reset take effect (combinational delay)
    @(negedge clock);
    reset = 0;


    //@(posedge clock);

    // 1. Fill the ROB completely
    alloc_valid = '1;
    for (int i = 0; i < (`ROB_SZ / `N); i++) begin
      fill_rob_packet(rob_entry_packet, pc_val + i * `N, arch_val + i * `N, phys_val + i * `N, data_val + i * `N);
      @(posedge clock);
    end
    if (`ROB_SZ % `N != 0) begin
        alloc_valid = '0; for (int i = 0; i < (`ROB_SZ % `N); i++) alloc_valid[i] = 1'b1;
        @(posedge clock);
    end
    alloc_valid = '0;
    @(negedge clock);

    // 2. Complete several instructions out of order (but not the first few)
    $display("Completing entries at indices 5, 2, 8 out of order...");
    rob_update_packet.valid = '0;
    rob_update_packet.valid[0] = 1'b1; rob_update_packet.idx[0] = 5;
    rob_update_packet.valid[1] = 1'b1; rob_update_packet.idx[1] = 2;
    rob_update_packet.valid[2] = 1'b1; rob_update_packet.idx[2] = 4;
    @(posedge clock);
    //#3;
    rob_update_packet.valid = '0;
    
    // 3. Verify that the head has NOT moved, because instruction 0 is not complete
    repeat(3) @(posedge clock);
    if (free_slots !== 0) begin
      $display("FAIL: Head advanced on out-of-order complete.");
      failed = 1;
    end else begin
      $display("PASS: Head correctly stalled while waiting for in-order instruction.\n");
    end

    // 4. Now, complete the first block of instructions to fill the gap
    $display("Completing first block of instructions (0, 1, 3, 4) to un-stall retirement...");
    rob_update_packet.valid = '0;
    rob_update_packet.valid[0] = 1'b1; rob_update_packet.idx[0] = 0;
    rob_update_packet.valid[1] = 1'b1; rob_update_packet.idx[1] = 1;
    rob_update_packet.valid[2] = 1'b1; rob_update_packet.idx[2] = 3;
    @(posedge clock);

    rob_update_packet.valid = '0;
    @(negedge clock);
    // 5. Verify that the head has advanced past the entire contiguous completed block
    @(posedge clock);

    @(posedge clock);

    @(posedge clock);

    // Instructions 0, 1, 2, 3, 4, 5 are all now complete. Head should be at 6.
    if (free_slots !== 6) begin
      $display("FAIL: Head did not correctly batch-retire. free_slots: %0d",free_slots);
      failed = 1;
    end else begin
      $display("PASS: Instructions correctly retired in-order after out-of-order completion.\n");
    end

    // -------------------------------
    // Test 6: Partial Completions
    // -------------------------------

    $display("Test 6: Partial completions");
    @(negedge clock);
    reset = 1;
    #3
    @(negedge clock);
    reset = 0;

    // allocate 2*N entries
    for (int i = 0; i < 2; i++) begin
      alloc_valid='1; 
      fill_rob_packet(rob_entry_packet, pc_val+i*`N, arch_val+i*`N, phys_val+i*`N, data_val+i*`N);
      @(posedge clock);
    end
    alloc_valid='0; @(posedge clock);

    // set first k complete, next one incomplete
    k = (`N >= 3) ? (`N-1) : 1;
    rob_update_packet.valid = '0;
    for (int i = 0; i < k; i++) begin
      rob_update_packet.valid[i] = 1'b1; 
      rob_update_packet.idx[i] = i;
    end
    @(posedge clock); 
    rob_update_packet.valid='0; 
    repeat(2) @(posedge clock);

    // Expect head advanced by k, and exactly those k entries invalidated

    if (free_slots != (`ROB_SZ - (2 * `N)) + k) begin 
      $display("FAIL: free slots is incorrect, head advanced by more than k completed instructions"); 
      failed=1; 
    end
    if (!failed) $display("PASS: Partial block of %0d instructions retired correctly.\n", k);


    // -------------------------------
    // Test 7: Pointer Wrap-Around and Boundary Conditions
    // -------------------------------
    $display("\nTest 7: Pointer Wrap-Around and Boundary Conditions...\n");
    // Reset and fill all but the last N slots
    @(negedge clock);
    reset = 1;
    #3
    @(negedge clock);
    reset = 0;

    alloc_valid = '1;
    for (int i = 0; i < (`ROB_SZ / `N); i++) begin 
      fill_rob_packet(rob_entry_packet, i*`N, i*`N, i*`N, i*`N); 
      @(posedge clock); 
    end
    alloc_valid = '0; @(posedge clock);

    // Complete and retire the first N*2 instructions to move the head up
    for (int i = 0; i < (`N * 2); i++) begin
      rob_update_packet.valid[i % `N] = 1'b1;
      rob_update_packet.idx[i % `N]   = i;
      if ((i % `N) == (`N - 1) || i == (`N*2 - 1) ) begin 
        @(posedge clock); rob_update_packet.valid = '0; 
      end
    end
    repeat (3) 
    @(posedge clock); 
    // Wait for retirement

    // Record free slots before wrap-around allocation
    free_before_wrap = free_slots;


    // At this point, tail is at `ROB_SZ - N`.
    $display("Allocating instructions to wrap tail pointer...");
    alloc_valid = '1;
    fill_rob_packet(rob_entry_packet, pc_val, arch_val, phys_val, data_val);
    @(posedge clock); // Allocates N instructions, tail becomes (`ROB_SZ-N+N)%ROB_SZ = 0
    fill_rob_packet(rob_entry_packet, pc_val, arch_val, phys_val, data_val);
    @(posedge clock); // Allocates N more, tail becomes (0+N)%ROB_SZ = N
    alloc_valid = '0;
    @(posedge clock);

    if (free_before_wrap - free_slots !== 2 * `N) begin
      $display("FAIL: Tail did not wrap correctly.");
      failed = 1;
    end else $display("PASS: Tail pointer wrapped around correctly.\n");

    // -------------------------------
    // Test 8: Partial Allocation and Retirement
    // -------------------------------
    $display("\nTest 8: Partial Allocation and Retirement...\n");
    // -- 8.1: Partial Allocation
    @(negedge clock);
    reset = 1;
    #3
    @(negedge clock);
    reset = 0;


    alloc_valid = '0;
    alloc_valid[0] = 1'b1;
    alloc_valid[2] = 1'b1;
    fill_rob_packet(rob_entry_packet, pc_val, arch_val, phys_val, data_val);
    @(posedge clock);
    alloc_valid = '0;
    @(posedge clock);

    if (free_slots != (`ROB_SZ - 2)) begin
      $display("FAIL: Tail advanced incorrectly on partial alloc.");
      failed = 1;
    end else $display("PASS: Partial allocation handled correctly.");
    

    // -- 8.2: Partial Retirement
    @(negedge clock);
    reset = 1;
    #3
    @(negedge clock);
    reset = 0;

    alloc_valid = '1; // Refill ROB
    for (int i = 0; i < (`ROB_SZ / `N); i++) begin fill_rob_packet(rob_entry_packet, i, i, i, i); @(posedge clock); end
    if (`ROB_SZ % `N != 0) begin alloc_valid = '0; for (int i = 0; i < (`ROB_SZ % `N); i++) alloc_valid[i] = 1'b1; @(posedge clock); end
    alloc_valid = '0; @(posedge clock);

    rob_update_packet.valid[0] = 1'b1;
    rob_update_packet.idx[0] = 0; // Complete only the instruction at the head

    @(posedge clock);
    rob_update_packet.valid = '0;
    repeat(2) @(posedge clock);

    if (free_slots !== 1) begin
      $display("FAIL: Head did not advance by 1 on single retirement. Expected 1, got %0d", free_slots);
      failed = 1;
    end else $display("PASS: Partial retirement of one instruction successful.\n");



    // -------------------------------
    // Test 9: Retire 3 Instructions and Check head_entries
    // -------------------------------
    $display("Test 9: Retiring 3 instructions and checking head_entries...\n");
    //failed = 0;
    hw = 0; 


    // Reset DUT again for a clean state
    @(negedge clock);
    reset = 1;
    #3
    @(negedge clock);
    reset = 0;

    // Step 1: Allocate 3 instructions
    @(posedge clock);   // set inputs before next posedge
    alloc_valid = '0;
    for (int i = 0; i < 3; i++) begin
      rob_entry_packet[i] = make_rob_entry(
        pc_val + i,
        `NOP,
        arch_val + i,
        phys_val + i,
        phys_val + i - 1,
        data_val + i
      );
      alloc_valid[i] = 1'b1;
    end
    @(posedge clock);   // DUT samples alloc_valid + packet
    alloc_valid = '0;
    @(posedge clock);
    //alloc_valid = '0;   // clear after DUT sampled

    // Step 2: Mark all 3 instructions as complete
    @(negedge clock);   // set updates before next posedge
    rob_update_packet = '{default:0};
    for (int i = 0; i < 3; i++) begin
      
      rob_update_packet.valid[i]  = 1'b1;
      rob_update_packet.idx[i]    = i;
      rob_update_packet.values[i] = data_val + i;
    end
    @(posedge clock);   // DUT sees completions
    @(negedge clock);
    rob_update_packet.valid = '0;

    // Step 3: Wait one cycle for completion logic to execute
    repeat (1) @(posedge clock);
    //#3 // small dealy
    // Step 4: Check head_entries (after DUT update)
    for (int i = 0; i < 3; i++) begin
      hw = `N-1 - i; // oldest at N-1
      if (head_valids[hw] !== 1'b1) begin
        $display("FAIL: head_valids[%0d] = %b (expected 1)", hw, head_valids[hw]);
        failed = 1;
      end else if (head_entries[hw].PC !== pc_val + i) begin
        $display("FAIL: head_entries[%0d].PC = 0x%0h (expected 0x%0h)",
                  hw, head_entries[hw].PC, pc_val + i);
        failed = 1;
      end else begin
        $display("PASS: head_entries[%0d] retired instruction PC=0x%0h",
                  hw, head_entries[hw].PC);
      end
    end

    if (!failed)
      $display("\033[1;32mPASS: All 3 retired instructions match expected head_entries.\033[0m\n");
    else
      $display("\033[1;31mFAIL: Retired instructions do not match expected head_entries.\033[0m\n");


    // -------------------------------
    // Test 10: Simplified Out-of-Order Stress Test
    // -------------------------------
    $display("\nTest 10: Simplified Out-of-Order Stress Test...\n");

    // Reset
    reset = 1;
    @(negedge clock); 
    #3
    @(negedge clock);
    reset = 0;
    @(posedge clock);

    // Run 10 cycles of allocation + randomized completions
    for (int cycle = 0; cycle < 10; cycle++) begin
        // Clear signals
        alloc_valid = '0;
        rob_update_packet.valid = '0;

        // Allocate up to N instructions if free slots exist
        for (int i = 0; i < `N; i++) begin
            if (i < free_slots) alloc_valid[i] = 1'b1;
        end
        fill_rob_packet(rob_entry_packet, pc_val, arch_val, phys_val, data_val);
        pc_val += `N;
        arch_val += `N;
        phys_val += `N;

        @(posedge clock);

        // Out-of-order completion: randomly pick some allocated indices
        for (int i = 0; i < `N; i++) begin
            if (alloc_valid[i] && ($urandom_range(0,1) == 1)) begin
                rob_update_packet.valid[i] = 1'b1;
                rob_update_packet.idx[i]   = alloc_idxs[i];
            end
        end

        @(posedge clock);
        alloc_valid = '0;
        rob_update_packet.valid = '0;
    end

    // Final phase: complete any remaining instructions that were not yet marked complete
    for (int i = 0; i < `ROB_SZ; i += `N) begin
        rob_update_packet.valid = '0;
        for (int j = 0; j < `N; j++) begin
            if (i+j < `ROB_SZ) begin
                rob_update_packet.valid[j] = 1'b1;
                rob_update_packet.idx[j]   = i+j;
            end
        end
        @(posedge clock);
    end
    rob_update_packet.valid = '0;

    // Give a few extra cycles for retirement to settle
    repeat(2) @(posedge clock);

    // Check ROB is empty
    if (free_slots == `ROB_SZ) begin
        $display("PASS: ROB is empty after out-of-order stress test.\n");
    end else begin
        $display("FAIL: ROB is not empty. free_slots=%0d", free_slots);
        failed = 1;
    end



    if (!failed)
      $display("\033[1;32mAll tests passed.\033[0m\n");
    else
      $display("\033[1;31mOne or more tests failed.\033[0m\n");



    

    // -------------------------------
    // Test Summary
    // -------------------------------
    if (failed) begin
      $display("\033[1;31m@@@ Failed\033[0m\n");
    end else begin
      $display("\033[1;32m@@@ Passed\033[0m\n");
    end


    $finish;
    //`endif
  end

endmodule

/// Test cases:
// 
// 

// input to check if it's ready to issue
// all the inputs and output signals

// stress test
// one test case




