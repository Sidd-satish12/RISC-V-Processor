`include "sys_defs.svh"
module instr_buffer #(
  parameter int unsigned DEPTH = 16,.
  parameter int unsigned GH    = GHR_BITS
)(
  input  logic                 clock,
  input  logic                 reset,
  input  logic                 flush_i,
  input  logic                 push_i,     
  input  logic [31:0]          push_pc_i,
  input  logic [31:0]          push_inst_i,  
  input  logic                 push_bp_pred_taken_i,
  input  logic [31:0]          push_bp_pred_target_i,
  input  logic [GH-1:0]        push_bp_ghr_snapshot_i,
  output logic                 full_o,
  input  logic                 pop_i,    
  output logic                 empty_o,
  output logic [31:0]          pop_pc_o,
  output logic [31:0]          pop_inst_o,
  output logic                 pop_bp_pred_taken_o,
  output logic [31:0]          pop_bp_pred_target_o,
  output logic [GH-1:0]        pop_bp_ghr_snapshot_o
);

  typedef FETCH_ENTRY ibuf_entry_t;
  localparam int unsigned PTR_W = $clog2(DEPTH);
  ibuf_entry_t      mem   [DEPTH];
  logic [PTR_W-1:0] head, tail;
  logic [PTR_W:0]   count;
  assign empty_o = (count == 0);
  assign full_o  = (count == DEPTH);
  assign pop_pc_o              = mem[head].pc;
  assign pop_inst_o            = mem[head].inst;
  assign pop_bp_pred_taken_o   = mem[head].bp_pred_taken;
  assign pop_bp_pred_target_o  = mem[head].bp_pred_target;
  assign pop_bp_ghr_snapshot_o = mem[head].bp_ghr_snapshot;
  always_ff @(posedge clock) begin
    if (reset) begin
      head  <= '0;
      tail  <= '0;
      count <= '0;
    end else if (flush_i) begin
      head  <= '0;
      tail  <= '0;
      count <= '0;
    end else begin
      if (push_i && !full_o) begin
        mem[tail].pc              <= push_pc_i;
        mem[tail].inst            <= push_inst_i;
        mem[tail].bp_pred_taken   <= push_bp_pred_taken_i;
        mem[tail].bp_pred_target  <= push_bp_pred_target_i;
        mem[tail].bp_ghr_snapshot <= push_bp_ghr_snapshot_i;
        tail  <= tail + 1'b1;
        count <= count + 1'b1;
      end
      if (pop_i && !empty_o) begin
        head  <= head + 1'b1;
        count <= count - 1'b1;
      end
    end
  end
endmodule
