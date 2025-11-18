`include "sys_defs.svh"
module instr_buffer #(
  parameter DEPTH = 32,
  parameter GH    = `GHR_BITS
)(
  input  logic                 clock,
  input  logic                 reset,

  // Global Flush (on mispredict)
  input  logic                 flush,

  // Push (from fetch)
  input  FETCH_PACKET           push_entry_i,
  output logic                  full_o,

  // Decode
  output logic                  empty_o,
  output FETCH_PACKET           pop_entry_o
);

  typedef FETCH_PACKET ibuf_entry_t;

  localparam int PTR_W = $clog2(DEPTH);

  ibuf_entry_t      mem   [DEPTH];
  logic [PTR_W-1:0] head, tail;
  logic [PTR_W:0]   count;

  assign empty_o = (count == 0);
  assign full_o  = (count == DEPTH);

  assign pop_entry_o = mem[head];


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

      // push
      if (push_i && !full_o) begin
        mem[tail] <= push_entry_i;
        tail      <= tail + 1'b1;
        count     <= count + 1'b1;
      end

      // Pop
      if (pop_i && !empty_o) begin
        head  <= head + 1'b1;
        count <= count - 1'b1;
      end
    end
  end

endmodule
