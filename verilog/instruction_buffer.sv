module instr_buffer #(
  parameter int unsigned DEPTH = 16,
  parameter int unsigned GH    = 8
)(
  input  logic                 clock,
  input  logic                 reset,

  // Flush whole buffer (e.g., on mispredict)
  input  logic                 flush_i,

  // ---------- Push from FETCH ----------
  input  logic                 push_i,     // write one entry if !full
  input  logic [31:0]          push_pc_i,
  input  logic [31:0]          push_inst_i,   // raw 32-bit instruction

  input  logic                 push_bp_pred_taken_i,
  input  logic [31:0]          push_bp_pred_target_i,
  input  logic [GH-1:0]        push_bp_ghr_snapshot_i,

  output logic                 full_o,

  // ---------- Pop to DECODE ----------
  input  logic                 pop_i,      // consume one entry if !empty

  output logic                 empty_o,
  output logic [31:0]          pop_pc_o,
  output logic [31:0]          pop_inst_o,  // feed this to decoder.inst

  output logic                 pop_bp_pred_taken_o,
  output logic [31:0]          pop_bp_pred_target_o,
  output logic [GH-1:0]        pop_bp_ghr_snapshot_o
);

  typedef struct packed {
    logic [31:0]   pc;
    logic [31:0]   inst;
    logic          bp_pred_taken;
    logic [31:0]   bp_pred_target;
    logic [GH-1:0] bp_ghr_snapshot;
  } ibuf_entry_t;

  localparam int unsigned PTR_W = $clog2(DEPTH);

  ibuf_entry_t      mem   [DEPTH];
  logic [PTR_W-1:0] head, tail;
  logic [PTR_W:0]   count;

  // Flags
  assign empty_o = (count == 0);
  assign full_o  = (count == DEPTH);

  // Outputs from head
  assign pop_pc_o              = mem[head].pc;
  assign pop_inst_o            = mem[head].inst;
  assign pop_bp_pred_taken_o   = mem[head].bp_pred_taken;
  assign pop_bp_pred_target_o  = mem[head].bp_pred_target;
  assign pop_bp_ghr_snapshot_o = mem[head].bp_ghr_snapshot;

  // Sequential logic
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
      // PUSH
      if (push_i && !full_o) begin
        mem[tail].pc              <= push_pc_i;
        mem[tail].inst            <= push_inst_i;
        mem[tail].bp_pred_taken   <= push_bp_pred_taken_i;
        mem[tail].bp_pred_target  <= push_bp_pred_target_i;
        mem[tail].bp_ghr_snapshot <= push_bp_ghr_snapshot_i;

        tail  <= tail + 1'b1;
        count <= count + 1'b1;
      end

      // POP
      if (pop_i && !empty_o) begin
        head  <= head + 1'b1;
        count <= count - 1'b1;
      end
    end
  end

endmodule
