`include "sys_defs.svh"

// Single test for stage_issue to understand critical path
// Models after rs_test.sv structure

`ifndef __SYS_DEFS_SVH__  // Override if needed for testbench
`define RS_SZ 16
`define N 3
`define CDB_SZ 3

typedef logic [5:0] PHYS_TAG;  // Assuming 64 physical regs, clog2(64)=6
typedef logic [$clog2(`RS_SZ)-1:0] RS_IDX;  // 4 bits for 16

typedef struct packed {
    logic [`CDB_SZ-1:0] valid;
    PHYS_TAG [`CDB_SZ-1:0] tags;
} CDB_PACKET;
`endif

module testbench;

    logic clock, reset;
    logic failed;

    // Inputs to stage_issue
    RS_ENTRY [`RS_SZ-1:0] entries;
    logic mispredict;
    logic [`NUM_FU_ALU-1:0] alu_avail;
    logic [`NUM_FU_MULT-1:0] mult_avail;
    logic [`NUM_FU_BRANCH-1:0] branch_avail;
    logic [`NUM_FU_MEM-1:0] mem_avail;

    // Outputs from stage_issue
    logic [`N-1:0] clear_valid;
    RS_IDX [`N-1:0] clear_idxs;
    logic [`N-1:0] issue_valid;
    RS_ENTRY [`N-1:0] issued_entries;

    stage_issue dut (
        .clock(clock),
        .reset(reset),
        .entries(entries),
        .mispredict(mispredict),
        .alu_avail(alu_avail),
        .mult_avail(mult_avail),
        .branch_avail(branch_avail),
        .mem_avail(mem_avail),
        .clear_valid(clear_valid),
        .clear_idxs(clear_idxs),
        .issue_valid(issue_valid),
        .issued_entries(issued_entries)
    );

    always begin
        #50 clock = ~clock;  // Assume 10ns period, adjustable
    end

    // Helper task to set inputs
    task set_inputs(input RS_ENTRY [`RS_SZ-1:0] rs_entries, input logic mp, input logic [`NUM_FU_ALU-1:0] alu,
                    input logic [`NUM_FU_MULT-1:0] mult, input logic [`NUM_FU_BRANCH-1:0] branch,
                    input logic [`NUM_FU_MEM-1:0] mem);
        entries = rs_entries;
        mispredict = mp;
        alu_avail = alu;
        mult_avail = mult;
        branch_avail = branch;
        mem_avail = mem;
        @(posedge clock);
        #10;  // Small delay to let combinational logic settle
    endtask

    // Helper function to create a default empty entry
    function RS_ENTRY empty_entry;
        empty_entry.valid = 0;
        empty_entry.opa_select = OPA_IS_RS1;
        empty_entry.opb_select = OPB_IS_RS2;
        empty_entry.op_type = OP_ALU_ADD;
        empty_entry.src1_tag = 0;
        empty_entry.src1_ready = 0;
        empty_entry.src1_value = 0;
        empty_entry.src2_tag = 0;
        empty_entry.src2_ready = 0;
        empty_entry.src2_value = 0;
        empty_entry.dest_tag = 0;
        empty_entry.rob_idx = 0;
        empty_entry.PC = 0;
        empty_entry.pred_taken = 0;
        empty_entry.pred_target = 0;
    endfunction

    // Helper function to create a ready ALU entry
    function RS_ENTRY ready_alu_entry(input int age_val, input int rob_idx_val);
        ready_alu_entry = empty_entry();
        ready_alu_entry.valid = 1;
        ready_alu_entry.op_type.category = CAT_ALU;
        ready_alu_entry.src1_ready = 1;
        ready_alu_entry.src2_ready = 1;
        ready_alu_entry.rob_idx = rob_idx_val;
        ready_alu_entry.rob_wrap = 0;  // Assume no wrap for simplicity
    endfunction

    // Helper function to create a ready MULT entry
    function RS_ENTRY ready_mult_entry(input int age_val, input int rob_idx_val);
        ready_mult_entry = empty_entry();
        ready_mult_entry.valid = 1;
        ready_mult_entry.op_type.category = CAT_MULT;
        ready_mult_entry.src1_ready = 1;
        ready_mult_entry.src2_ready = 1;
        ready_mult_entry.rob_idx = rob_idx_val;
        ready_mult_entry.rob_wrap = 0;
    endfunction

    // Helper to print RS state
    task print_rs_state(input RS_ENTRY [`RS_SZ-1:0] rs_entries, input string label);
        $display("\n=== %s ===", label);
        for (int i = 0; i < `RS_SZ; i++) begin
            if (rs_entries[i].valid) begin
                string fu_type;
                case (rs_entries[i].op_type.category)
                    CAT_ALU: fu_type = "ALU";
                    CAT_MULT: fu_type = "MULT";
                    CAT_BRANCH: fu_type = "BRANCH";
                    CAT_MEM: fu_type = "MEM";
                    CAT_CSR: fu_type = "CSR";
                    default: fu_type = "UNKNOWN";
                endcase
                $display("  RS[%2d]: %s, ROB=%d, wrap=%d, ready=%b%b, age=7'b%b", i, fu_type, rs_entries[i].rob_idx,
                         rs_entries[i].rob_wrap, rs_entries[i].src1_ready, rs_entries[i].src2_ready, {rs_entries[i].rob_wrap,
                                                                                                      rs_entries[i].rob_idx});
            end
        end
        $display("");
    endtask

    // Helper to print issue results
    task print_issue_results(input string label);
        $display("=== %s ===", label);
        $display("Issue valid: %b", issue_valid);
        for (int i = 0; i < `N; i++) begin
            if (issue_valid[i]) begin
                string fu_type;
                case (issued_entries[i].op_type.category)
                    CAT_ALU: fu_type = "ALU";
                    CAT_MULT: fu_type = "MULT";
                    CAT_BRANCH: fu_type = "BRANCH";
                    CAT_MEM: fu_type = "MEM";
                    CAT_CSR: fu_type = "CSR";
                    default: fu_type = "UNKNOWN";
                endcase
                $display("  Issue[%d]: RS[%d] (%s), ROB=%d, wrap=%d", i, clear_idxs[i], fu_type, issued_entries[i].rob_idx,
                         issued_entries[i].rob_wrap);
            end
        end
        $display("");
    endtask

    // Helper to check issue results
    task check_issue_results(input logic [`N-1:0] expected_valid, input RS_IDX [`N-1:0] expected_idxs);
        if (issue_valid != expected_valid) begin
            $display("Issue valid mismatch: expected %b, got %b", expected_valid, issue_valid);
            failed = 1;
        end
        for (int i = 0; i < `N; i++) begin
            if (expected_valid[i] && clear_idxs[i] != expected_idxs[i]) begin
                $display("Clear idx %d mismatch: expected %d, got %d", i, expected_idxs[i], clear_idxs[i]);
                failed = 1;
            end
        end
    endtask

    initial begin
        // $dumpfile("../stage_issue.vcd");
        // $dumpvars(0, testbench.dut);

        clock = 0;
        reset = 1;
        failed = 0;

        // Initialize inputs
        entries = '{default: empty_entry()};
        mispredict = 0;
        alu_avail = {`NUM_FU_ALU{1'b1}};  // All ALUs available
        mult_avail = {`NUM_FU_MULT{1'b1}};  // All MULTs available
        branch_avail = {`NUM_FU_BRANCH{1'b1}};  // All BRANCHs available
        mem_avail = {`NUM_FU_MEM{1'b1}};  // All MEMs available

        @(negedge clock);
        @(negedge clock);
        reset = 0;
        @(negedge clock);

        // Single Test: Simple issue selection
        $display("\nSingle Test: Basic issue selection with 4 ready entries");

        // Set up RS with 4 ready entries of different ages and FU types
        // Age = {rob_wrap, rob_idx}, smaller = older
        // ROB indices: 10 (oldest), 20, 25, 30 (newest) - keep within 5-bit range (0-31)
        begin
            RS_ENTRY [`RS_SZ-1:0] test_entries = '{default: empty_entry()};

            // Entry 0: ALU, ROB idx 10 (oldest)
            test_entries[0] = ready_alu_entry(10, 10);

            // Entry 1: MULT, ROB idx 20
            test_entries[1] = ready_mult_entry(20, 20);

            // Entry 2: ALU, ROB idx 25
            test_entries[2] = ready_alu_entry(25, 25);

            // Entry 3: MEM, ROB idx 30 (newest)
            test_entries[3] = empty_entry();
            test_entries[3].valid = 1;
            test_entries[3].op_type.category = CAT_MEM;
            test_entries[3].src1_ready = 1;
            test_entries[3].src2_ready = 1;
            test_entries[3].rob_idx = 30;
            test_entries[3].rob_wrap = 0;

            // DEBUG: Print RS state before issue
            print_rs_state(test_entries, "RS State BEFORE Issue");

            // Apply inputs (all FUs available, no mispredict)
            set_inputs(test_entries, 0, {`NUM_FU_ALU{1'b1}}, {`NUM_FU_MULT{1'b1}}, {`NUM_FU_BRANCH{1'b1}}, {`NUM_FU_MEM{1'b1}});

            // DEBUG: Print issue results
            print_issue_results("Issue Results AFTER Processing");
        end

        // Expected results:
        // Phase 1 (per-FU filtering): All 4 are candidates (ALU:3 avail, MULT:1 avail, MEM:1 avail)
        // Phase 2 (global ranking): Select oldest 3: idx0(ALU,age10), idx1(MULT,age20), idx2(ALU,age25)
        // Note: idx3(MEM,age30) should be 4th but we only issue N=3
        begin
            logic  [`N-1:0] expected_valid = 3'b111;
            RS_IDX [`N-1:0] expected_idxs;
            expected_idxs[0] = 0;
            expected_idxs[1] = 1;
            expected_idxs[2] = 2;  // RS scan order: RS[0], RS[1], RS[2] (which are the 3 oldest)

            $display("Expected to issue entries: %d, %d, %d", expected_idxs[0], expected_idxs[1], expected_idxs[2]);
            $display("Actual issued entries: valid=%b, idxs=%d,%d,%d", issue_valid, clear_idxs[0], clear_idxs[1], clear_idxs[2]);

            check_issue_results(expected_valid, expected_idxs);
        end

        $display("");
        if (failed) $display("@@@ Failed\n");
        else $display("@@@ Passed\n");

        $finish;
    end

endmodule
