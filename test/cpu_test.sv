/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  cpu_test.sv                                         //
//                                                                     //
//  Description :  Testbench module for the VeriSimpleV processor.     //
//                 (Fake-Fetch enabled: feeds N insts per cycle)       //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"

// Minimal DPI use (writeback pretty printer)
import "DPI-C" function string decode_inst(int inst);

`define TB_MAX_CYCLES 50000000

module testbench;
    // ----------------------------------------------------------------
    // CLI args & output files
    // ----------------------------------------------------------------
    string program_memory_file, output_name;
    string out_outfile, cpi_outfile, writeback_outfile;
    int    out_fileno, cpi_fileno, wb_fileno;

    // ----------------------------------------------------------------
    // TB state
    // ----------------------------------------------------------------
    logic        clock;
    logic        reset;
    logic [31:0] clock_count;
    logic [31:0] instr_count;

    // Processor <-> Memory (data-side; IF is faked)
    MEM_COMMAND proc2mem_command;
    ADDR        proc2mem_addr;
    MEM_BLOCK   proc2mem_data;
    MEM_TAG     mem2proc_transaction_tag;
    MEM_BLOCK   mem2proc_data;
    MEM_TAG     mem2proc_data_tag;
    MEM_SIZE    proc2mem_size;

    // Retire bundle
    COMMIT_PACKET [`N-1:0] committed_insts;
    EXCEPTION_CODE         error_status = NO_ERROR;

    // Debug taps (unchanged)
    ADDR  if_NPC_dbg;
    DATA  if_inst_dbg;
    logic if_valid_dbg;
    ADDR  if_id_NPC_dbg;
    DATA  if_id_inst_dbg;
    logic if_id_valid_dbg;
    ADDR  id_ex_NPC_dbg;
    DATA  id_ex_inst_dbg;
    logic id_ex_valid_dbg;
    ADDR  ex_mem_NPC_dbg;
    DATA  ex_mem_inst_dbg;
    logic ex_mem_valid_dbg;
    ADDR  mem_wb_NPC_dbg;
    DATA  mem_wb_inst_dbg;
    logic mem_wb_valid_dbg;

    // ----------------------------------------------------------------
    // Fake-Fetch wires (testbench <-> cpu)
    // ----------------------------------------------------------------
    ADDR  fake_pc;
    DATA  fake_instr [`N-1:0];
    logic [$clog2(`N+1)-1:0] fake_nvalid;
    logic [$clog2(`N+1)-1:0] fake_consumed;

    logic ff_branch_taken;
    ADDR  ff_branch_target;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    cpu verisimpleV (
        // Clk/Reset
        .clock (clock),
        .reset (reset),

        // Memory return path (data only)
        .mem2proc_transaction_tag (mem2proc_transaction_tag),
        .mem2proc_data            (mem2proc_data),
        .mem2proc_data_tag        (mem2proc_data_tag),

        // Memory request path (data only)
        .proc2mem_command (proc2mem_command),
        .proc2mem_addr    (proc2mem_addr),
        .proc2mem_data    (proc2mem_data),
`ifndef CACHE_MODE
        .proc2mem_size    (proc2mem_size),
`endif

        // Retire
        .committed_insts (committed_insts),

        // Debug
        .if_NPC_dbg       (if_NPC_dbg),
        .if_inst_dbg      (if_inst_dbg),
        .if_valid_dbg     (if_valid_dbg),
        .if_id_NPC_dbg    (if_id_NPC_dbg),
        .if_id_inst_dbg   (if_id_inst_dbg),
        .if_id_valid_dbg  (if_id_valid_dbg),
        .id_ex_NPC_dbg    (id_ex_NPC_dbg),
        .id_ex_inst_dbg   (id_ex_inst_dbg),
        .id_ex_valid_dbg  (id_ex_valid_dbg),
        .ex_mem_NPC_dbg   (ex_mem_NPC_dbg),
        .ex_mem_inst_dbg  (ex_mem_inst_dbg),
        .ex_mem_valid_dbg (ex_mem_valid_dbg),
        .mem_wb_NPC_dbg   (mem_wb_NPC_dbg),
        .mem_wb_inst_dbg  (mem_wb_inst_dbg),
        .mem_wb_valid_dbg (mem_wb_valid_dbg),

        // ---- Fake-Fetch interface ----
        .ff_instr        (fake_instr),
        .ff_pc           (fake_pc),
        .ff_nvalid       (fake_nvalid),
        .ff_consumed     (fake_consumed),
        .branch_taken_o  (ff_branch_taken),
        .branch_target_o (ff_branch_target)
    );

    // ----------------------------------------------------------------
    // Unified Memory (data-side only; IF is faked here)
    // ----------------------------------------------------------------
    mem memory (
        .clock            (clock),
        .proc2mem_command (proc2mem_command),
        .proc2mem_addr    (proc2mem_addr),
        .proc2mem_data    (proc2mem_data),
`ifndef CACHE_MODE
        .proc2mem_size    (proc2mem_size),
`endif
        .mem2proc_transaction_tag (mem2proc_transaction_tag),
        .mem2proc_data            (mem2proc_data),
        .mem2proc_data_tag        (mem2proc_data_tag)
    );

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end

    // ----------------------------------------------------------------
    // Fake-Fetch: PC register
    // ----------------------------------------------------------------
    always_ff @(posedge clock) begin
        if (reset) begin
            fake_pc <= '0;
        end else begin
            if (ff_branch_taken) begin
                fake_pc <= ff_branch_target;
            end else begin
                // Advance by 4*X where X = fake_consumed from CPU
                fake_pc <= fake_pc + 32'(4 * fake_consumed);
            end
        end
    end

    // ----------------------------------------------------------------
    // Read a 32b instruction from unified memory at byte address 'addr'
    // ----------------------------------------------------------------
    function DATA get_inst32(input ADDR addr);
        MEM_BLOCK blk;
        begin
            blk = memory.unified_memory[addr[31:3]]; // 8B-aligned line
            get_inst32 = blk.word_level[addr[2]];    // 0: low word, 1: high word
        end
    endfunction

    // ----------------------------------------------------------------
    // Build the N-wide bundle every cycle (sequential @ fake_pc + 4*i)
    // ----------------------------------------------------------------
    always_comb begin
        for (int i = 0; i < `N; i++) begin
            fake_instr[i] = get_inst32(fake_pc + 32'(4*i));
        end
        fake_nvalid = `N; // simple model: always provide N; CPU decides how many to take
    end

    // ----------------------------------------------------------------
    // Init / Load / Run
    // ----------------------------------------------------------------
    initial begin
        $display("\n---- Starting CPU Testbench (Fake-Fetch) ----\n");

        if ($value$plusargs("MEMORY=%s", program_memory_file)) begin
            $display("Using memory file  : %s", program_memory_file);
        end else begin
            $display("Did not receive '+MEMORY=' argument. Exiting.\n");
            $finish;
        end
        if ($value$plusargs("OUTPUT=%s", output_name)) begin
            $display("Using output files : %s.{out, cpi, wb}", output_name);
            out_outfile       = {output_name,".out"};
            cpi_outfile       = {output_name,".cpi"};
            writeback_outfile = {output_name,".wb"};
        end else begin
            $display("\nDid not receive '+OUTPUT=' argument. Exiting.\n");
            $finish;
        end

        clock = 1'b0;
        reset = 1'b0;

        $display("\n  %16t : Asserting Reset", $realtime);
        reset = 1'b1;

        @(posedge clock);
        @(posedge clock);

        $display("  %16t : Loading Unified Memory", $realtime);
        $readmemh(program_memory_file, memory.unified_memory);

        @(posedge clock);
        @(posedge clock);
        #1;
        $display("  %16t : Deasserting Reset", $realtime);
        reset = 1'b0;

        wb_fileno = $fopen(writeback_outfile);
        $fdisplay(wb_fileno, "Register writeback output (hexadecimal)");

        out_fileno = $fopen(out_outfile);

        $display("  %16t : Running Processor", $realtime);
    end

    // ----------------------------------------------------------------
    // Progress + retire logging + stop conditions
    // ----------------------------------------------------------------
    always @(negedge clock) begin
        if (reset) begin
            clock_count = 0;
            instr_count = 0;
        end else begin
            #2;
            clock_count = clock_count + 1;

            if ((clock_count % 10000) == 0)
                $display("  %16t : %0d cycles", $realtime, clock_count);

            // Optional: peek at fake-fetch behavior
            // $display("%0t [FF] pc=%h consumed=%0d br=%0d tgt=%h",
            //          $time, fake_pc, fake_consumed, ff_branch_taken, ff_branch_target);

            output_reg_writeback_and_maybe_halt();

            if (error_status != NO_ERROR || clock_count > `TB_MAX_CYCLES) begin
                $display("  %16t : Processor Finished", $realtime);
                $fclose(wb_fileno);
                show_final_mem_and_status(error_status);
                output_cpi_file();
                $display("\n---- Finished CPU Testbench ----\n");
                #100 $finish;
            end
        end
    end

    // ----------------------------------------------------------------
    // Retire printer (unchanged)
    // ----------------------------------------------------------------
    task output_reg_writeback_and_maybe_halt;
        ADDR pc;
        DATA inst;
        MEM_BLOCK block;
        begin
            for (int n = 0; n < `N; ++n) begin
                if (committed_insts[n].valid) begin
                    instr_count = instr_count + 1;

                    pc    = committed_insts[n].NPC - 4;
                    block = memory.unified_memory[pc[31:3]];
                    inst  = block.word_level[pc[2]];

                    if (committed_insts[n].reg_idx == `ZERO_REG) begin
                        $fdisplay(wb_fileno, "PC %4x:%-8s| ---", pc, decode_inst(inst));
                    end else begin
                        $fdisplay(wb_fileno, "PC %4x:%-8s| r%02d=%-8x",
                                  pc, decode_inst(inst),
                                  committed_insts[n].reg_idx,
                                  committed_insts[n].data);
                    end

                    if (committed_insts[n].illegal) begin
                        error_status = ILLEGAL_INST;
                        break;
                    end else if (committed_insts[n].halt) begin
                        error_status = HALTED_ON_WFI;
                        break;
                    end
                end
            end
        end
    endtask

    // ----------------------------------------------------------------
    // CPI file
    // ----------------------------------------------------------------
    task output_cpi_file;
        real cpi;
        begin
            cpi = (instr_count == 0) ? 0.0 : ($itor(clock_count) / instr_count);
            cpi_fileno = $fopen(cpi_outfile);
            $fdisplay(cpi_fileno, "@@@  %0d cycles / %0d instrs = %f CPI",
                      clock_count, instr_count, cpi);
            $fdisplay(cpi_fileno, "@@@  %4.2f ns total time to execute",
                      clock_count * `CLOCK_PERIOD);
            $fclose(cpi_fileno);
        end
    endtask

    // ----------------------------------------------------------------
    // Final memory dump & status
    // ----------------------------------------------------------------
    task show_final_mem_and_status;
        input EXCEPTION_CODE final_status;
        int showing_data;
        begin
            $fdisplay(out_fileno, "\nFinal memory state and exit status:\n");
            $fdisplay(out_fileno, "@@@ Unified Memory contents hex on left, decimal on right: ");
            $fdisplay(out_fileno, "@@@");
            showing_data = 0;
            for (int k = 0; k <= `MEM_64BIT_LINES - 1; k = k+1) begin
                if (memory.unified_memory[k] != 0) begin
                    $fdisplay(out_fileno, "@@@ mem[%5d] = %x : %0d",
                              k*8, memory.unified_memory[k], memory.unified_memory[k]);
                    showing_data = 1;
                end else if (showing_data != 0) begin
                    $fdisplay(out_fileno, "@@@");
                    showing_data = 0;
                end
            end
            $fdisplay(out_fileno, "@@@");

            case (final_status)
                LOAD_ACCESS_FAULT: $fdisplay(out_fileno, "@@@ System halted on memory error");
                HALTED_ON_WFI:     $fdisplay(out_fileno, "@@@ System halted on WFI instruction");
                ILLEGAL_INST:      $fdisplay(out_fileno, "@@@ System halted on illegal instruction");
                default:           $fdisplay(out_fileno, "@@@ System halted on unknown error code %x", final_status);
            endcase
            $fdisplay(out_fileno, "@@@");
            $fclose(out_fileno);
        end
    endtask

    // Optional hook
    task print_custom_data; endtask

endmodule // module testbench
