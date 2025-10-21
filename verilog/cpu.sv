/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  cpu.sv                                              //
//                                                                     //
//  Description :  Top-level module of the verisimple processor;       //
//                 This instantiates and connects the 5 stages of the  //
//                 Verisimple pipeline together.                       //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "sys_defs.svh"

module cpu (
    input  clock, // System clock
    input  reset, // System reset

    // Memory return path (used for DATA loads/stores only in fake-fetch mode)
    input  MEM_TAG   mem2proc_transaction_tag,
    input  MEM_BLOCK mem2proc_data,
    input  MEM_TAG   mem2proc_data_tag,

    // Memory request path (D$ only now)
    output MEM_COMMAND proc2mem_command,
    output ADDR        proc2mem_addr,
    output MEM_BLOCK   proc2mem_data,
    output MEM_SIZE    proc2mem_size,

    // Note: assigned at bottom
    output COMMIT_PACKET [`N-1:0] committed_insts,

    // Debug outputs (unchanged for P3)
    output ADDR  if_NPC_dbg,
    output DATA  if_inst_dbg,
    output logic if_valid_dbg,
    output ADDR  if_id_NPC_dbg,
    output DATA  if_id_inst_dbg,
    output logic if_id_valid_dbg,
    output ADDR  id_ex_NPC_dbg,
    output DATA  id_ex_inst_dbg,
    output logic id_ex_valid_dbg,
    output ADDR  ex_mem_NPC_dbg,
    output DATA  ex_mem_inst_dbg,
    output logic ex_mem_valid_dbg,
    output ADDR  mem_wb_NPC_dbg,
    output DATA  mem_wb_inst_dbg,
    output logic mem_wb_valid_dbg,

    // ---------------- Fake-fetch interface (from cpu_test.sv) ----------------
    // Bundle of up to N sequential instructions starting at ff_pc
    input  DATA  [`N-1:0]           ff_instr,
    input  ADDR                      ff_pc,
    input  logic[$clog2(`N+1)-1:0]  ff_nvalid,     // typically 'N'
    output logic[$clog2(`N+1)-1:0]  ff_consumed,   // X = how many we grabbed
    // Export branch redirect to testbench (for PC update there)
    output logic                     branch_taken_o,
    output ADDR                      branch_target_o
);

    //////////////////////////////////////////////////
    //                Pipeline Wires
    //////////////////////////////////////////////////
    // Pipeline register enables
    logic if_id_enable, id_ex_enable, ex_mem_enable, mem_wb_enable;

    // IF/ID
    IF_ID_PACKET if_packet, if_id_reg;

    // ID/EX
    ID_EX_PACKET id_packet, id_ex_reg;

    // EX/MEM
    EX_MEM_PACKET ex_packet, ex_mem_reg;

    // MEM/WB
    MEM_WB_PACKET mem_packet, mem_wb_reg;

    // MEM (data-side only)
    ADDR        Dmem_addr;
    MEM_BLOCK   Dmem_store_data;
    MEM_COMMAND Dmem_command;
    MEM_SIZE    Dmem_size;

    // WB loopback
    COMMIT_PACKET wb_packet;

    // Memory stall machinery from your P3
    logic       load_stall;
    logic       new_load;
    logic       mem_tag_match;
    logic       rd_mem_q;                 // previous load
    MEM_TAG     outstanding_mem_tag;      // tag load is waiting in
    MEM_COMMAND Dmem_command_filtered;    // removes redundant loads

    //////////////////////////////////////////////////
    //                Memory Outputs (D$ only)
    //////////////////////////////////////////////////
    // The IF side no longer issues memory requests; only data ops remain.
    always_comb begin
        proc2mem_command = Dmem_command_filtered;
        proc2mem_size    = Dmem_size;
        proc2mem_addr    = Dmem_addr;
        proc2mem_data    = Dmem_store_data;
    end

    //////////////////////////////////////////////////
    //                        IF (FAKE)
    //////////////////////////////////////////////////
    // We synthesize the IF packet directly from the fake-fetch bundle.
    // Scalar consume today: we take at most the first instruction when not stalled.
    logic if_can_take;
    assign if_can_take = !load_stall;

    always_comb begin
        if_packet          = '0;
        if_packet.valid    = if_can_take && (ff_nvalid != '0);
        if_packet.inst     = ff_instr[0];
        if_packet.PC       = ff_pc;
        if_packet.NPC      = ff_pc + 32'd4;
    end

    // How many did we consume from the bundle this cycle? For the current P3
    // scalar pipe, it's 1 iff we actually latch into IF/ID; else 0.
    assign ff_consumed = (if_packet.valid && if_can_take) ? 'd1 : 'd0;

    // Debug
    assign if_NPC_dbg   = if_packet.NPC;
    assign if_inst_dbg  = if_packet.inst;
    assign if_valid_dbg = if_packet.valid;

    //////////////////////////////////////////////////
    //                 IF/ID Pipeline Register
    //////////////////////////////////////////////////
    assign if_id_enable = !load_stall;

    always_ff @(posedge clock) begin
        if (reset) begin
            if_id_reg.inst  <= `NOP;
            if_id_reg.valid <= `FALSE;
            if_id_reg.NPC   <= '0;
            if_id_reg.PC    <= '0;
        end else if (if_id_enable) begin
            if_id_reg <= if_packet;
        end
    end

    // Debug
    assign if_id_NPC_dbg   = if_id_reg.NPC;
    assign if_id_inst_dbg  = if_id_reg.inst;
    assign if_id_valid_dbg = if_id_reg.valid;

    //////////////////////////////////////////////////
    //                         ID
    //////////////////////////////////////////////////
    stage_id stage_id_0 (
        .clock           (clock),
        .reset           (reset),
        .if_id_reg       (if_id_reg),
        .wb_regfile_en   (wb_packet.valid),
        .wb_regfile_idx  (wb_packet.reg_idx),
        .wb_regfile_data (wb_packet.data),
        .id_packet       (id_packet)
    );

    //////////////////////////////////////////////////
    //                 ID/EX Pipeline Register
    //////////////////////////////////////////////////
    assign id_ex_enable = !load_stall;

    always_ff @(posedge clock) begin
        if (reset) begin
            id_ex_reg <= '{
                `NOP,          // inst
                32'b0,         // PC
                32'b0,         // NPC
                32'b0,         // rs1 value
                32'b0,         // rs2 value
                OPA_IS_RS1,
                OPB_IS_RS2,
                `ZERO_REG,
                ALU_ADD,
                1'b0,          // mult
                1'b0,          // rd_mem
                1'b0,          // wr_mem
                1'b0,          // cond
                1'b0,          // uncond
                1'b0,          // halt
                1'b0,          // illegal
                1'b0,          // csr_op
                1'b0           // valid
            };
        end else if (id_ex_enable) begin
            id_ex_reg <= id_packet;
        end
    end

    // Debug
    assign id_ex_NPC_dbg   = id_ex_reg.NPC;
    assign id_ex_inst_dbg  = id_ex_reg.inst;
    assign id_ex_valid_dbg = id_ex_reg.valid;

    //////////////////////////////////////////////////
    //                          EX
    //////////////////////////////////////////////////
    stage_ex stage_ex_0 (
        .id_ex_reg (id_ex_reg),
        .ex_packet (ex_packet)
    );

    //////////////////////////////////////////////////
    //                 EX/MEM Pipeline Register
    //////////////////////////////////////////////////
    assign ex_mem_enable = !load_stall;

    always_ff @(posedge clock) begin
        if (reset) begin
            ex_mem_inst_dbg <= `NOP;
            ex_mem_reg      <= '0;
        end else if (ex_mem_enable) begin
            ex_mem_inst_dbg <= id_ex_inst_dbg;
            ex_mem_reg      <= ex_packet;
        end
    end

    // Debug
    assign ex_mem_NPC_dbg   = ex_mem_reg.NPC;
    assign ex_mem_valid_dbg = ex_mem_reg.valid;

    //////////////////////////////////////////////////
    //                          MEM
    //////////////////////////////////////////////////
    // New address if:
    // 1) Previous instruction wasn't a load
    // 2) Load address changed
    logic valid_load;
    assign valid_load = ex_mem_reg.valid && ex_mem_reg.rd_mem;
    assign new_load   = valid_load && !rd_mem_q;

    assign mem_tag_match = (outstanding_mem_tag == mem2proc_data_tag);
    assign load_stall    = new_load || (valid_load && !mem_tag_match);

    assign Dmem_command_filtered = (new_load || ex_mem_reg.wr_mem) ? Dmem_command : MEM_NONE;

    always_ff @(posedge clock) begin
        if (reset) begin
            rd_mem_q            <= 1'b0;
            outstanding_mem_tag <= '0;
        end else begin
            rd_mem_q            <= valid_load;
            outstanding_mem_tag <= new_load      ? mem2proc_transaction_tag
                                  : mem_tag_match ? '0
                                  : outstanding_mem_tag;
        end
    end

    stage_mem stage_mem_0 (
        .ex_mem_reg      (ex_mem_reg),
        .Dmem_load_data  (mem2proc_data),
        .mem_packet      (mem_packet),
        .Dmem_command    (Dmem_command),
        .Dmem_size       (Dmem_size),
        .Dmem_addr       (Dmem_addr),
        .Dmem_store_data (Dmem_store_data)
    );

    //////////////////////////////////////////////////
    //                      MEM/WB
    //////////////////////////////////////////////////
    assign mem_wb_enable = 1'b1;

    always_ff @(posedge clock) begin
        if (reset || load_stall) begin
            mem_wb_inst_dbg <= `NOP;
            mem_wb_reg      <= '0;
        end else if (mem_wb_enable) begin
            mem_wb_inst_dbg <= ex_mem_inst_dbg;
            mem_wb_reg      <= mem_packet;
        end
    end

    // Debug
    assign mem_wb_NPC_dbg   = mem_wb_reg.NPC;
    assign mem_wb_valid_dbg = mem_wb_reg.valid;

    //////////////////////////////////////////////////
    //                           WB
    //////////////////////////////////////////////////
    stage_wb stage_wb_0 (
        .mem_wb_reg (mem_wb_reg),
        .wb_packet  (wb_packet)
    );

    //////////////////////////////////////////////////
    //                  Branch export to TB
    //////////////////////////////////////////////////
    assign branch_taken_o  = ex_mem_reg.take_branch;
    assign branch_target_o = ex_mem_reg.alu_result;

    //////////////////////////////////////////////////
    //                 Pipeline Outputs
    //////////////////////////////////////////////////
    assign committed_insts[0] = wb_packet;

endmodule // pipeline
